import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/safety_repository.dart';
import '../../domain/models/safety_models.dart';

class DrivingModeScreen extends ConsumerStatefulWidget {
  const DrivingModeScreen({super.key});

  @override
  ConsumerState<DrivingModeScreen> createState() => _DrivingModeScreenState();
}

class _DrivingModeScreenState extends ConsumerState<DrivingModeScreen> {
  final SafetyRepository _repo = SafetyRepository();
  final FlutterTts _tts = FlutterTts();

  SafetyStateModel? _safety;
  StreamSubscription<Position>? _posSub;
  Timer? _syncTimer;

  bool _voiceMuted = false;
  double? _liveSpeedKmh;
  bool _speedAvailable = false;
  double? _cachedAcceptedThreshold;
  TravelMode _travelMode = TravelMode.car;

  // Sustained exceedance state (Section 19):
  // 5s local warning, 15s partner alert, 60s cooldown, 5s stable recovery hysteresis (3 km/h)
  DateTime? _exceedStartedAt;
  DateTime? _recoveryStartedAt;
  DateTime? _lastVoiceWarningAt;
  DateTime? _lastPartnerAlertAt;
  bool _isWarningActive = false;
  bool _partnerAlertSentForEvent = false;
  int _gpsSeq = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    _initTts();
    _loadInitialState();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
    } catch (_) {}
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _syncTimer?.cancel();
    _tts.stop();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || coupleId.isEmpty) return;

    // Load cached accepted threshold for offline evaluation
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getDouble('soulsafe_cached_threshold_${user.id}');
    if (mounted && cached != null) {
      setState(() => _cachedAcceptedThreshold = cached);
    }

    try {
      final st = await _repo.updateConsent(
        userId: user.id,
        coupleId: coupleId,
        action: 'update_consents',
        drivingMode: true,
      );
      if (!mounted) return;
      final agThresh = st.agreementForMe?.activeThresholdKmh;
      if (agThresh != null) {
        await prefs.setDouble('soulsafe_cached_threshold_${user.id}', agThresh);
      } else {
        await prefs.remove('soulsafe_cached_threshold_${user.id}');
      }
      setState(() {
        _safety = st;
        _travelMode = st.myTravelMode;
        _cachedAcceptedThreshold = agThresh;
      });
    } catch (_) {}

    _startGpsMonitoring();
    _syncTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      try {
        final st = await _repo.getState(user.id, coupleId);
        if (!mounted) return;
        final agThresh = st.agreementForMe?.activeThresholdKmh;
        if (agThresh != null) {
          final p = await SharedPreferences.getInstance();
          await p.setDouble('soulsafe_cached_threshold_${user.id}', agThresh);
        }
        setState(() {
          _safety = st;
          _cachedAcceptedThreshold = agThresh;
        });
      } catch (_) {}
    });
  }

  Future<void> _startGpsMonitoring() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen(_onPositionUpdate, onError: (_) {
        if (mounted) {
          setState(() {
            _speedAvailable = false;
            _liveSpeedKmh = null;
          });
        }
      });
    } catch (_) {}
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    final accurate = pos.accuracy >= 0 && pos.accuracy <= 50.0;
    final hasSpeed = pos.speed >= 0 && accurate && pos.speed <= 80.0;
    final speedKmh = hasSpeed ? double.parse((pos.speed * 3.6).toStringAsFixed(1)) : null;

    setState(() {
      _speedAvailable = speedKmh != null;
      _liveSpeedKmh = speedKmh;
    });

    _evaluateSustainedSpeedRule(speedKmh);

    // Publish latest fix if location sharing consent is active
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user != null &&
        coupleId != null &&
        _safety?.myStatus == 'active' &&
        _safety?.myConsents.location == true) {
      _gpsSeq += 1;
      _repo
          .pushLocation(
            userId: user.id,
            coupleId: coupleId,
            sequence: _gpsSeq,
            lat: pos.latitude,
            lng: pos.longitude,
            horizontalAccuracyM: pos.accuracy,
            speedMps: hasSpeed ? pos.speed : null,
            bearing: pos.heading,
            travelMode: _travelMode.id,
          )
          .catchError((_) => <String, dynamic>{});
    }
  }

  void _evaluateSustainedSpeedRule(double? speedKmh) {
    final threshold = _cachedAcceptedThreshold;
    if (threshold == null || speedKmh == null) {
      // Missing or unreliable samples reset confirmation window
      _exceedStartedAt = null;
      return;
    }

    final now = DateTime.now();
    const double hysteresis = 3.0;

    if (speedKmh > threshold) {
      _recoveryStartedAt = null;
      _exceedStartedAt ??= now;
      final sustainedSec = now.difference(_exceedStartedAt!).inSeconds;

      // 5s sustained exceedance -> local hands-free voice warning (60s cooldown)
      if (sustainedSec >= 5) {
        final cooldownOk = _lastVoiceWarningAt == null ||
            now.difference(_lastVoiceWarningAt!).inSeconds >= 60;
        if (cooldownOk) {
          _lastVoiceWarningAt = now;
          if (mounted) setState(() => _isWarningActive = true);
          _speakWarning(
            'Safety alert. Estimated speed ${speedKmh.round()} kilometers per hour. Your agreed alert threshold is ${threshold.round()}. Please slow down safely.',
          );
        }
      }

      // 15s sustained exceedance -> one optional partner notification per event
      if (sustainedSec >= 15 && !_partnerAlertSentForEvent) {
        final partnerCooldownOk = _lastPartnerAlertAt == null ||
            now.difference(_lastPartnerAlertAt!).inSeconds >= 60;
        if (partnerCooldownOk) {
          _partnerAlertSentForEvent = true;
          _lastPartnerAlertAt = now;
          final user = ref.read(currentUserProvider);
          final coupleId = user?.coupleId;
          if (user != null && coupleId != null) {
            _repo
                .triggerAlert(
                  userId: user.id,
                  coupleId: coupleId,
                  speedKmh: speedKmh,
                  thresholdKmh: threshold,
                  sustainedSeconds: sustainedSec,
                )
                .catchError((_) {});
          }
        }
      }
    } else if (speedKmh <= (threshold - hysteresis)) {
      _exceedStartedAt = null;
      _recoveryStartedAt ??= now;
      // 5s stable recovery below threshold - hysteresis
      if (now.difference(_recoveryStartedAt!).inSeconds >= 5) {
        _partnerAlertSentForEvent = false;
        if (_isWarningActive && mounted) {
          setState(() => _isWarningActive = false);
        }
      }
    }
  }

  Future<void> _speakWarning(String text) async {
    if (_voiceMuted) return;
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _exitDrivingMode() async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user != null && coupleId != null) {
      await _repo
          .updateConsent(
            userId: user.id,
            coupleId: coupleId,
            action: 'update_consents',
            drivingMode: false,
          )
          .catchError((_) => _safety!);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _triggerEmergencySos() async {
    HapticFeedback.heavyImpact();
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;
    double? lat, lng;
    try {
      final p = await Geolocator.getLastKnownPosition();
      lat = p?.latitude;
      lng = p?.longitude;
    } catch (_) {}
    await _repo.sendSos(
      userId: user.id,
      coupleId: coupleId,
      message: 'Urgent SOS sent from Driving Mode!',
      lat: lat,
      lng: lng,
      consentOneTimeLocation: lat != null && lng != null,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD32F2F),
          content: Text('🚨 SOS alert sent to your partner. Call local emergency (112/911) if in danger.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final threshold = _cachedAcceptedThreshold;
    final bgColor = _isWarningActive ? const Color(0xFF4A0E17) : const Color(0xFF120B24);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Simplified Status Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_travelMode.emoji} ${_travelMode.label} Mode',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 30,
                    color: Colors.white,
                    tooltip: _voiceMuted ? 'Unmute Voice Alerts' : 'Mute Voice Alerts',
                    icon: Icon(_voiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                    onPressed: () => setState(() => _voiceMuted = !_voiceMuted),
                  ),
                ],
              ),

              // Center Distraction-Free Speed Display
              Column(
                children: [
                  Text(
                    _speedAvailable && _liveSpeedKmh != null
                        ? '${_liveSpeedKmh!.round()}'
                        : '--',
                    style: TextStyle(
                      fontSize: 108,
                      fontWeight: FontWeight.w900,
                      color: _isWarningActive ? const Color(0xFFFF6B81) : Colors.white,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _speedAvailable ? 'km/h (estimated)' : 'Speed unavailable',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isWarningActive ? const Color(0xFFFF6B81) : Colors.white24,
                      ),
                    ),
                    child: Text(
                      threshold != null
                          ? 'Personal Alert Threshold: ${threshold.round()} km/h\n(Not an official legal road speed limit)'
                          : 'No active personal speed threshold set',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_isWarningActive && threshold != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Safety Alert: Estimated ${_liveSpeedKmh?.round() ?? 0} km/h exceeds agreed ${threshold.round()} km/h threshold. Please slow down safely.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Bottom Large Accessible Controls (Touch-friendly)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 2),
                            content: Text('Press & HOLD button to send Emergency SOS (prevents accidental tap).'),
                          ),
                        );
                      },
                      onLongPress: _triggerEmergencySos,
                      icon: const Icon(Icons.sos_rounded),
                      label: const Text(
                        'HOLD TO SEND EMERGENCY SOS',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _exitDrivingMode,
                      child: const Text(
                        'Exit Driving Mode',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
