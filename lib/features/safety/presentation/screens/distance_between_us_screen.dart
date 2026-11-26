import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/safety_repository.dart';
import '../../domain/models/safety_models.dart';

class DistanceBetweenUsScreen extends ConsumerStatefulWidget {
  const DistanceBetweenUsScreen({super.key});

  @override
  ConsumerState<DistanceBetweenUsScreen> createState() =>
      _DistanceBetweenUsScreenState();
}

class _DistanceBetweenUsScreenState
    extends ConsumerState<DistanceBetweenUsScreen>
    with WidgetsBindingObserver {
  static const String _openFreeMapStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';

  final SafetyRepository _repo = SafetyRepository();
  final Battery _battery = Battery();

  SafetyStateModel? _safety;
  bool _isLoading = true;
  String? _error;
  bool _mapReady = false;
  bool _showStraightLine = false;
  MapLibreMapController? _mapCtrl;

  // Live GPS publisher state
  StreamSubscription<Position>? _posSub;
  Timer? _pollTimer;
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  int _sequence = 0;
  DateTime? _lastPublishAt;
  String? _routeSummaryText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSafetyState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _pollTimer?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSafetyState(silent: true);
      _connectSse();
    }
  }

  Future<void> _loadSafetyState({bool silent = false}) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || coupleId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final st = await _repo.getState(user.id, coupleId);
      if (!mounted) return;
      setState(() {
        _safety = st;
        _isLoading = false;
      });
      _refreshMapAnnotations();
      _ensureTimersAndStreams(st);
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _ensureTimersAndStreams(SafetyStateModel st) {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 6), (_) {
      _loadSafetyState(silent: true);
    });
    if (_sseClient == null) {
      _connectSse();
    }
    if (st.myStatus == 'active' && st.myConsents.location && _posSub == null) {
      _startLocationStream();
    } else if (st.myStatus != 'active' && _posSub != null) {
      _posSub?.cancel();
      _posSub = null;
    }
  }

  void _connectSse() {
    _sseSub?.cancel();
    _sseClient?.close();

    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || coupleId.isEmpty) return;

    final client = http.Client();
    _sseClient = client;
    final req = http.Request(
      'GET',
      Uri.parse(
          '${AuthNotifier.apiBaseUrl}/api/safety/stream?user_id=${Uri.encodeComponent(user.id)}&couple_id=${Uri.encodeComponent(coupleId)}'),
    );
    req.headers['Accept'] = 'text/event-stream';

    client.send(req).then((streamed) {
      if (!mounted) return;
      _sseSub = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!line.startsWith('data: ')) return;
        _loadSafetyState(silent: true);
      }, onError: (_) {}, onDone: () {});
    }).catchError((_) {});
  }

  Future<void> _startLocationStream() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final mode = _safety?.myTravelMode ?? TravelMode.stationary;
      final distFilter =
          (mode == TravelMode.car || mode == TravelMode.bike) ? 8 : 15;
      _posSub = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distFilter,
        ),
      ).listen(_onNewLocalPosition, onError: (_) {});

      // Push one immediate fix on start
      final cur = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _onNewLocalPosition(cur);
    } catch (_) {}
  }

  Future<void> _onNewLocalPosition(Position pos) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    final st = _safety;
    if (user == null ||
        coupleId == null ||
        st == null ||
        st.myStatus != 'active') {
      return;
    }

    // Cadence throttle: moving 3s, walking 10s, stationary 30s
    final mode = st.myTravelMode;
    final minGapSec = (mode == TravelMode.car || mode == TravelMode.bike)
        ? 3
        : (mode == TravelMode.walking || mode == TravelMode.cycling)
            ? 10
            : 30;
    if (_lastPublishAt != null &&
        DateTime.now().difference(_lastPublishAt!).inSeconds < minGapSec) {
      return;
    }
    _lastPublishAt = DateTime.now();
    _sequence += 1;

    int? batPct;
    bool? batCharging;
    if (st.myConsents.battery) {
      try {
        batPct = await _battery.batteryLevel;
        final bState = await _battery.batteryState;
        batCharging = bState == BatteryState.charging ||
            bState == BatteryState.full;
      } catch (_) {}
    }

    try {
      await _repo.pushLocation(
        userId: user.id,
        coupleId: coupleId,
        sequence: _sequence,
        lat: pos.latitude,
        lng: pos.longitude,
        horizontalAccuracyM: pos.accuracy,
        speedMps: pos.speed >= 0 ? pos.speed : null,
        bearing: pos.heading,
        travelMode: mode.id,
        batteryPct: batPct,
        batteryCharging: batCharging,
      );
      _loadSafetyState(silent: true);
    } catch (_) {}
  }

  Future<void> _refreshMapAnnotations() async {
    final ctrl = _mapCtrl;
    final st = _safety;
    if (ctrl == null || !_mapReady || st == null) return;

    try {
      await ctrl.clearCircles();
      await ctrl.clearLines();

      final myLoc = st.myLocation;
      final pLoc = st.partner?.location;

      if (myLoc != null && st.myStatus == 'active') {
        await ctrl.addCircle(CircleOptions(
          geometry: LatLng(myLoc.lat, myLoc.lng),
          circleRadius: 11,
          circleColor: '#6C3EBC',
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ));
      }
      if (pLoc != null) {
        await ctrl.addCircle(CircleOptions(
          geometry: LatLng(pLoc.lat, pLoc.lng),
          circleRadius: 12,
          circleColor: '#E94057',
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ));
      }
      if (_showStraightLine &&
          myLoc != null &&
          pLoc != null &&
          st.myStatus == 'active') {
        await ctrl.addLine(LineOptions(
          geometry: [
            LatLng(myLoc.lat, myLoc.lng),
            LatLng(pLoc.lat, pLoc.lng),
          ],
          lineColor: '#E94057',
          lineWidth: 2.5,
          lineOpacity: 0.65,
        ));
      }
    } catch (_) {}
  }

  void _fitBothMarkers() {
    final ctrl = _mapCtrl;
    final myLoc = _safety?.myLocation;
    final pLoc = _safety?.partner?.location;
    if (ctrl == null) return;
    if (myLoc != null && pLoc != null) {
      final sw = LatLng(
        math.min(myLoc.lat, pLoc.lat),
        math.min(myLoc.lng, pLoc.lng),
      );
      final ne = LatLng(
        math.max(myLoc.lat, pLoc.lat),
        math.max(myLoc.lng, pLoc.lng),
      );
      ctrl.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: sw, northeast: ne),
          left: 48,
          top: 48,
          right: 48,
          bottom: 48,
        ),
      );
    } else if (pLoc != null) {
      ctrl.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pLoc.lat, pLoc.lng), 13));
    } else if (myLoc != null) {
      ctrl.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(myLoc.lat, myLoc.lng), 13));
    }
  }

  Future<void> _requestAndStartSharing(String durationKey) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    // Explain permissions clearly BEFORE requesting OS prompt (Section 12 & 20)
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.location_on_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text('Share Location Consent',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ],
        ),
        content: const Text(
          'SoulSync only shares your location while you actively enable it.\n\n'
          '• Precise GPS allows accurate km/h speed & safety alerts.\n'
          '• Approximate location hides exact street coordinates if chosen in Android settings.\n'
          '• You can pause or stop sharing anytime with one tap.\n'
          '• Your partner never needs location permission just to view your shared location.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not Now')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Grant & Start Sharing'),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permission denied. You can still view your partner\'s shared location.'),
            ),
          );
        }
        return;
      }
    } catch (_) {}

    final updated = await _repo.updateConsent(
      userId: user.id,
      coupleId: coupleId,
      action: 'start',
      durationKey: durationKey,
    );
    if (!mounted) return;
    setState(() => _safety = updated);
    _startLocationStream();
    _refreshMapAnnotations();
  }

  Future<void> _handleConsentAction(String action,
      {String? travelMode, Map<String, bool>? consents, bool? dailySharing, int? retentionDays}) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;
    HapticFeedback.selectionClick();
    try {
      final updated = await _repo.updateConsent(
        userId: user.id,
        coupleId: coupleId,
        action: action,
        travelMode: travelMode,
        consents: consents,
        dailySharing: dailySharing,
        historyRetentionDays: retentionDays,
      );
      if (!mounted) return;
      setState(() => _safety = updated);
      if (action == 'stop' || action == 'pause') {
        _posSub?.cancel();
        _posSub = null;
      } else if (action == 'resume') {
        _startLocationStream();
      }
      _refreshMapAnnotations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  void _showDurationPicker() {
    final durations = _safety?.allowedDurations ?? ['1h', '8h', '12h', 'manual'];
    final labels = {
      '1h': '1 Hour',
      '8h': '8 Hours (Daytime)',
      '12h': '12 Hours',
      'manual': 'Until Manually Stopped',
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: context.ssSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Sharing Duration ⏱️', style: AppTypography.titleLarge),
            const SizedBox(height: 12),
            ...durations.map((d) => ListTile(
                  leading: const Icon(Icons.timer_outlined, color: AppColors.primary),
                  title: Text(labels[d] ?? d,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _requestAndStartSharing(d);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showSpeedAgreementsModal() {
    final user = ref.read(currentUserProvider);
    final st = _safety;
    if (user == null || st == null) return;
    final proposeCtrl = TextEditingController(
      text: st.agreementForPartner?.activeThresholdKmh?.round().toString() ?? '60',
    );
    final counterCtrl = TextEditingController(
      text: st.agreementForMe?.pendingThresholdKmh?.round().toString() ?? '70',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ssSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mutually Agreed Speed Alerts 🛡️',
                  style: AppTypography.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Personal safety alert thresholds require acceptance by the travelling partner. They are personal reminders, not legal road speed limits.',
                style: TextStyle(fontSize: 12, color: context.ssTextSecondary),
              ),
              const SizedBox(height: 16),

              // Incoming Proposal for Me
              if (st.agreementForMe?.status == 'pending' &&
                  st.agreementForMe?.pendingThresholdKmh != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.ssIsDark
                        ? const Color(0xFF3B2A14)
                        : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${st.partner?.name ?? 'Partner'} proposed ${st.agreementForMe!.pendingThresholdKmh!.round()} km/h for you',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final u = await _repo.agreementOp(
                                userId: user.id,
                                coupleId: st.coupleId,
                                operation: 'accept',
                                targetUserId: user.id,
                              );
                              if (mounted) setState(() => _safety = u);
                            },
                            child: const Text('Accept'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final u = await _repo.agreementOp(
                                userId: user.id,
                                coupleId: st.coupleId,
                                operation: 'reject',
                                targetUserId: user.id,
                              );
                              if (mounted) setState(() => _safety = u);
                            },
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: counterCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Counter value (km/h)',
                                isDense: true,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final v = double.tryParse(counterCtrl.text.trim());
                              if (v == null) return;
                              Navigator.pop(ctx);
                              final u = await _repo.agreementOp(
                                userId: user.id,
                                coupleId: st.coupleId,
                                operation: 'counter',
                                targetUserId: user.id,
                                thresholdKmh: v,
                              );
                              if (mounted) setState(() => _safety = u);
                            },
                            child: const Text('Send Counter'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // My Active Threshold Status
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active Threshold for Your Travel',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(
                  st.agreementForMe?.activeThresholdKmh != null
                      ? '${st.agreementForMe!.activeThresholdKmh!.round()} km/h (v${st.agreementForMe!.version})'
                      : 'None active',
                ),
                trailing: st.agreementForMe?.activeThresholdKmh != null
                    ? TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final u = await _repo.agreementOp(
                            userId: user.id,
                            coupleId: st.coupleId,
                            operation: 'revoke',
                            targetUserId: user.id,
                          );
                          if (mounted) setState(() => _safety = u);
                        },
                        child: const Text('Disable',
                            style: TextStyle(color: AppColors.error)),
                      )
                    : null,
              ),
              const Divider(),

              // Propose Threshold for Partner
              Text('Propose Threshold for ${st.partner?.name ?? 'Partner'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: proposeCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: ctx.ssTextPrimary),
                      decoration: InputDecoration(
                        labelText: 'Alert threshold (10–200 km/h)',
                        filled: true,
                        fillColor: ctx.ssInputFill,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    onPressed: () async {
                      final val = double.tryParse(proposeCtrl.text.trim());
                      if (val == null || st.partner == null) return;
                      Navigator.pop(ctx);
                      try {
                        final u = await _repo.agreementOp(
                          userId: user.id,
                          coupleId: st.coupleId,
                          operation: 'propose',
                          targetUserId: st.partner!.userId,
                          thresholdKmh: val,
                        );
                        if (mounted) {
                          setState(() => _safety = u);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Proposed ${val.round()} km/h for ${st.partner!.name} (awaits their acceptance).')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        }
                      }
                    },
                    child: const Text('Propose'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSafeZonesAndJourneyModal() {
    final user = ref.read(currentUserProvider);
    final st = _safety;
    if (user == null || st == null) return;
    final zoneNameCtrl = TextEditingController(text: 'Home');
    final destLatCtrl = TextEditingController();
    final destLngCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ssSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Safe Zones & Safe Arrival 💚',
                  style: AppTypography.headlineSmall),
              const SizedBox(height: 12),

              // One-tap I Reached Safely
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final u = await _repo.journeyOp(
                      userId: user.id,
                      coupleId: st.coupleId,
                      operation: 'reached_safely',
                      message: 'I reached safely 💚 Thinking of you!',
                    );
                    if (mounted) {
                      setState(() => _safety = u);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('💚 Safe arrival sent to partner!')),
                      );
                    }
                  },
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text('I Reached Safely (Manual Check-In)',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 16),

              // Route Estimate & Journey Tracker
              Text('Journey & Route Estimate (HeiGIT)',
                  style: AppTypography.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: destLatCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Dest Lat', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: destLngCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Dest Lng', isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    onPressed: () async {
                      final dlat = double.tryParse(destLatCtrl.text.trim()) ??
                          ((st.partner?.location?.lat) ?? 28.6139);
                      final dlng = double.tryParse(destLngCtrl.text.trim()) ??
                          ((st.partner?.location?.lng) ?? 77.2090);
                      final olat = st.myLocation?.lat ?? 28.5355;
                      final olng = st.myLocation?.lng ?? 77.3910;
                      Navigator.pop(ctx);
                      final route = await _repo.getRouteEstimate(
                        userId: user.id,
                        coupleId: st.coupleId,
                        originLat: olat,
                        originLng: olng,
                        destLat: dlat,
                        destLng: dlng,
                        travelMode: st.myTravelMode.id,
                      );
                      final updated = await _repo.journeyOp(
                        userId: user.id,
                        coupleId: st.coupleId,
                        operation: 'start',
                        travelMode: st.myTravelMode.id,
                        destination: {'lat': dlat, 'lng': dlng},
                      );
                      if (mounted) {
                        setState(() {
                          _safety = updated;
                          _routeSummaryText = route['routing_available'] == true
                              ? 'Road: ${route['road_distance_km']} km • ETA ~${route['eta_minutes']} min'
                              : route['message']?.toString();
                        });
                      }
                    },
                    child: Text(st.myJourney?['active'] == true
                        ? 'Update Journey'
                        : 'Start Journey'),
                  ),
                  if (st.myJourney?['active'] == true) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final u = await _repo.journeyOp(
                          userId: user.id,
                          coupleId: st.coupleId,
                          operation: 'end',
                        );
                        if (mounted) setState(() => _safety = u);
                      },
                      child: const Text('End Journey'),
                    ),
                  ],
                ],
              ),
              const Divider(height: 24),

              // Opt-in Safe Zones (Owner-only!)
              Text('Your Own Safe Zones (${st.mySafeZones.length})',
                  style: AppTypography.titleMedium),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: zoneNameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Zone Name (Home, Office...)',
                          isDense: true),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final lat = st.myLocation?.lat ?? 28.6139;
                      final lng = st.myLocation?.lng ?? 77.2090;
                      Navigator.pop(ctx);
                      final u = await _repo.safeZoneOp(
                        userId: user.id,
                        coupleId: st.coupleId,
                        operation: 'create',
                        name: zoneNameCtrl.text.trim(),
                        lat: lat,
                        lng: lng,
                        radiusM: 200,
                      );
                      if (mounted) setState(() => _safety = u);
                    },
                    child: const Text('+ Add Here'),
                  ),
                ],
              ),
              ...st.mySafeZones.map((z) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_moon_outlined,
                        color: AppColors.primary),
                    title: Text('${z.name} (${z.radiusM}m)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error, size: 18),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final u = await _repo.safeZoneOp(
                          userId: user.id,
                          coupleId: st.coupleId,
                          operation: 'delete',
                          zoneId: z.id,
                        );
                        if (mounted) setState(() => _safety = u);
                      },
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacyAndHistoryModal() async {
    final user = ref.read(currentUserProvider);
    final st = _safety;
    if (user == null || st == null) return;
    final history = await _repo.getHistory(user.id).catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;

    var consents = st.myConsents.toJson();
    var prefs = Map<String, bool>.from(st.notificationPrefs);
    var retention = st.myHistoryRetentionDays;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.ssSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => DraggableScrollableSheet(
          initialChildSize: 0.78,
          maxChildSize: 0.92,
          minChildSize: 0.5,
          expand: false,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Privacy, History & Alerts 🔐',
                  style: AppTypography.headlineSmall),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Share Estimated Speed',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                value: consents['speed'] == true,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setDlg(() => consents['speed'] = v);
                  _handleConsentAction('update_consents', consents: {'speed': v});
                },
              ),
              SwitchListTile(
                title: const Text('Share Battery Level (Opt-In)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                value: consents['battery'] == true,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setDlg(() => consents['battery'] = v);
                  _handleConsentAction('update_consents', consents: {'battery': v});
                },
              ),
              SwitchListTile(
                title: const Text('Daily Location Sharing Schedule',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                value: st.myDailySharing,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  Navigator.pop(ctx);
                  _handleConsentAction('update_consents', dailySharing: v);
                },
              ),
              SwitchListTile(
                title: const Text('Session History Logging (OFF by default)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text('Auto-delete retention: $retention days',
                    style: const TextStyle(fontSize: 11)),
                value: consents['history'] == true,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setDlg(() => consents['history'] = v);
                  _handleConsentAction('update_consents',
                      consents: {'history': v}, retentionDays: retention);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Saved Summaries (${history.length})',
                      style: AppTypography.titleMedium),
                  TextButton.icon(
                    onPressed: () async {
                      await _repo.clearHistory(user.id, st.coupleId);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Location history permanently deleted.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.delete_forever_rounded,
                        color: AppColors.error, size: 18),
                    label: const Text('Delete History',
                        style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
              const Divider(height: 20),
              Text('Safety Notification Preferences',
                  style: AppTypography.titleMedium),
              ...[
                ('sharing_started', 'Partner started sharing'),
                ('sharing_stopped', 'Partner stopped sharing'),
                ('driving_mode', 'Partner started Driving Mode'),
                ('vehicle_changed', 'Partner changed vehicle type'),
                ('speed_exceeded', 'Speed threshold exceeded'),
                ('safe_zone', 'Safe zone arrival & check-ins'),
                ('low_battery', 'Partner low battery alert'),
              ].map((item) => SwitchListTile(
                    title: Text(item.$2, style: const TextStyle(fontSize: 13)),
                    value: prefs[item.$1] ?? true,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setDlg(() => prefs[item.$1] = v);
                      _repo.updateNotifPrefs(user.id, st.coupleId, prefs);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showSosDialog() {
    final user = ref.read(currentUserProvider);
    final st = _safety;
    if (user == null || st == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.sos_rounded, color: AppColors.error, size: 28),
            SizedBox(width: 8),
            Text('Emergency SOS 🚨', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Press & send an urgent alert with your timestamp and latest authorized location to your partner. For immediate danger, also call local emergency services.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse('tel:112');
              if (await launcher.canLaunchUrl(uri)) {
                await launcher.launchUrl(uri);
              }
            },
            icon: const Icon(Icons.phone_rounded, color: AppColors.error),
            label: const Text('Call 112',
                style: TextStyle(color: AppColors.error)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              double? lat = st.myLocation?.lat;
              double? lng = st.myLocation?.lng;
              try {
                final res = await _repo.sendSos(
                  userId: user.id,
                  coupleId: st.coupleId,
                  message: 'Urgent SOS alert! Please call or check on me now.',
                  lat: lat,
                  lng: lng,
                  consentOneTimeLocation: lat != null && lng != null,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.error,
                      content: Text(res['status'] == 'sent'
                          ? '🚨 SOS dispatched to ${st.partner?.name ?? "partner"}. Use Call 112 if urgent.'
                          : 'SOS failed while offline — call local emergency directly.'),
                    ),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.error,
                      content: Text(
                          'Offline: SOS could not be delivered. Tap Call 112 directly.'),
                    ),
                  );
                }
              }
            },
            child: const Text('Send SOS Alert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isPaired = user != null && user.isConnectedToPartner;

    return Scaffold(
      backgroundColor: context.ssBg,
      appBar: AppBar(
        backgroundColor: context.ssSurface,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.ssTextPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Distance Between Us 🛡️',
          style: TextStyle(
              color: context.ssTextPrimary, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Privacy & Notifications',
            icon: Icon(Icons.tune_rounded, color: context.ssPrimary),
            onPressed: _safety != null ? _showPrivacyAndHistoryModal : null,
          ),
        ],
      ),
      body: !isPaired
          ? _buildUnpairedView()
          : _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? _buildErrorView()
                  : _buildMainView(user!),
    );
  }

  Widget _buildUnpairedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📍💔', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 14),
            Text('Connect With Your Partner First',
                style: AppTypography.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'SoulSafe location sharing works strictly between connected partners with explicit consent.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.ssTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 10),
          Text(_error ?? 'Unable to load SoulSafe',
              style: AppTypography.titleMedium),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => _loadSafetyState(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainView(SoulSyncUser user) {
    final st = _safety!;
    final partner = st.partner;
    final pName = partner?.name ?? user.partnerName ?? 'Partner';
    final distText = st.straightLineKm != null
        ? 'Distance Between Us: ${st.straightLineKm!.toStringAsFixed(st.straightLineKm! >= 10 ? 0 : 2)} KM ❤️'
        : 'Distance Unavailable';

    final initTarget = st.partner?.location != null
        ? LatLng(st.partner!.location!.lat, st.partner!.location!.lng)
        : (st.myLocation != null
            ? LatLng(st.myLocation!.lat, st.myLocation!.lng)
            : const LatLng(28.6139, 77.2090));

    return RefreshIndicator(
      onRefresh: () => _loadSafetyState(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Hero Distance Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C3EBC), Color(0xFFE94057)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Miles Apart, Always Connected. Always Caring.',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  distText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  st.straightLineKm != null
                      ? (st.distanceIsLive
                          ? 'Live straight-line Haversine distance'
                          : 'Calculated using last authorized location (not live)')
                      : 'Both partners must share an active fix to calculate straight-line distance',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (_routeSummaryText != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_routeSummaryText!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Interactive MapLibre + OpenFreeMap Card
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 230,
              decoration: BoxDecoration(
                color: const Color(0xFFEFE9FA),
                border: Border.all(color: const Color(0xFFDACDF2), width: 1.2),
              ),
              child: Stack(
                children: [
                  MapLibreMap(
                    initialCameraPosition:
                        CameraPosition(target: initTarget, zoom: 11),
                    styleString: _openFreeMapStyleUrl,
                    onMapCreated: (ctrl) => _mapCtrl = ctrl,
                    onStyleLoadedCallback: () {
                      if (mounted) setState(() => _mapReady = true);
                      _refreshMapAnnotations();
                      _fitBothMarkers();
                    },
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Column(
                      children: [
                        _MapControlFab(
                          icon: Icons.fit_screen_rounded,
                          tooltip: 'Fit Both',
                          onTap: _fitBothMarkers,
                        ),
                        const SizedBox(height: 6),
                        _MapControlFab(
                          icon: Icons.person_pin_circle_rounded,
                          tooltip: 'Follow Partner',
                          onTap: () {
                            final p = st.partner?.location;
                            if (p != null) {
                              _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(
                                  LatLng(p.lat, p.lng), 14));
                            }
                          },
                        ),
                        const SizedBox(height: 6),
                        _MapControlFab(
                          icon: _showStraightLine
                              ? Icons.linear_scale_rounded
                              : Icons.timeline_rounded,
                          tooltip: 'Toggle Straight-Line',
                          onTap: () {
                            setState(
                                () => _showStraightLine = !_showStraightLine);
                            _refreshMapAnnotations();
                          },
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '🟣 You (${st.myTravelMode.emoji}) • 🔴 $pName (${partner?.travelMode.emoji ?? '🛑'})',
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '© OpenStreetMap • OpenFreeMap',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 3. Sharing Consent Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.ssSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.ssBorder, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Sharing: ${st.myStatus.toUpperCase()}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: st.myStatus == 'active'
                            ? AppColors.success
                            : context.ssTextSecondary,
                      ),
                    ),
                    if (st.myExpiresAt != null && st.myStatus == 'active')
                      Text(
                        'Auto-expires: ${st.myExpiresAt!.substring(11, 16)} UTC',
                        style: TextStyle(
                            fontSize: 10.5, color: context.ssTextHint),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (st.myStatus != 'active' && st.myStatus != 'paused')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white),
                        onPressed: _showDurationPicker,
                        icon: const Icon(Icons.share_location_rounded, size: 18),
                        label: const Text('Share My Location'),
                      ),
                    if (st.myStatus == 'active')
                      OutlinedButton.icon(
                        onPressed: () => _handleConsentAction('pause'),
                        icon: const Icon(Icons.pause_rounded, size: 18),
                        label: const Text('Pause'),
                      ),
                    if (st.myStatus == 'paused')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white),
                        onPressed: () => _handleConsentAction('resume'),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Resume'),
                      ),
                    if (st.myStatus == 'active' || st.myStatus == 'paused')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white),
                        onPressed: () => _handleConsentAction('stop'),
                        icon: const Icon(Icons.stop_circle_rounded, size: 18),
                        label: const Text('Stop Sharing'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Partner Live Card (Vehicle, Speed, Accuracy, Battery)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.ssSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.ssBorder, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFE94057).withValues(alpha: 0.14),
                      child: Text(
                        partner?.travelMode.emoji ?? '🛑',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$pName — ${partner?.travelMode.label ?? 'Stationary'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          Text(
                            'Status: ${partner?.freshness ?? 'unavailable'}'
                            '${partner?.accuracyM != null ? ' • ±${partner!.accuracyM!.round()}m' : ''}',
                            style: TextStyle(
                                fontSize: 11, color: context.ssTextSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (partner?.batteryPercent != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.ssInputFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.ssBorder),
                        ),
                        child: Text(
                          '🔋 ${partner!.batteryPercent}%${partner.batteryCharging == true ? '⚡' : ''}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.ssSurfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    partner?.speedAvailable == true &&
                            partner?.speedKmh != null
                        ? 'Current Speed: ${partner!.speedKmh!.round()} km/h${partner.drivingMode ? ' (Driving Mode Active)' : ''}'
                        : 'Speed unavailable (stationary, paused, or low GPS accuracy)',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: context.ssPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 5. Select Your Travel Mode
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.ssSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.ssBorder, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Travel Mode (Pre-Trip Selection)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TravelMode.car,
                    TravelMode.bike,
                    TravelMode.walking,
                    TravelMode.stationary,
                    TravelMode.other,
                  ].map((m) {
                    final sel = st.myTravelMode == m;
                    return ChoiceChip(
                      label: Text('${m.emoji} ${m.label}',
                          style: TextStyle(
                              fontSize: 12,
                              color: sel ? Colors.white : context.ssTextPrimary)),
                      selected: sel,
                      selectedColor: AppColors.primary,
                      backgroundColor: context.ssSurfaceVariant,
                      onSelected: (_) =>
                          _handleConsentAction('update_consents', travelMode: m.id),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 6. Safety Feature Grid (Driving Mode, Speed Limits, Safe Zones & Journey, SOS)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              _SafetyTile(
                icon: Icons.directions_car_rounded,
                title: 'Driving Mode',
                subtitle: 'Simplified voice-first HUD',
                color: const Color(0xFF6C3EBC),
                onTap: () => context.push(RouteNames.drivingMode),
              ),
              _SafetyTile(
                icon: Icons.speed_rounded,
                title: 'Speed Alerts',
                subtitle: st.agreementForMe?.activeThresholdKmh != null
                    ? 'Active: ${st.agreementForMe!.activeThresholdKmh!.round()} km/h'
                    : 'Propose / Accept limit',
                color: const Color(0xFFE94057),
                onTap: _showSpeedAgreementsModal,
              ),
              _SafetyTile(
                icon: Icons.verified_user_rounded,
                title: 'Safe Arrival & Zones',
                subtitle: 'Check-in & Journey ETA',
                color: const Color(0xFF00A86B),
                onTap: _showSafeZonesAndJourneyModal,
              ),
              _SafetyTile(
                icon: Icons.sos_rounded,
                title: 'Emergency SOS',
                subtitle: 'Urgent partner alert & 112',
                color: const Color(0xFFD32F2F),
                onTap: _showSosDialog,
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _MapControlFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapControlFab({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.ssSurface,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: context.ssPrimary),
          ),
        ),
      ),
    );
  }
}

class _SafetyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SafetyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.ssSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.ssBorder, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 11, color: context.ssTextSecondary)),
          ],
        ),
      ),
    );
  }
}
