import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/music_repository.dart';
import '../../domain/models/music_models.dart';

class ListenTogetherScreen extends ConsumerStatefulWidget {
  const ListenTogetherScreen({super.key});

  @override
  ConsumerState<ListenTogetherScreen> createState() =>
      _ListenTogetherScreenState();
}

class _ListenTogetherScreenState extends ConsumerState<ListenTogetherScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final MusicRepository _repo = MusicRepository();
  final TextEditingController _searchCtrl = TextEditingController();

  late final YoutubePlayerController _ytController;
  late final AnimationController _heartAnimCtrl;
  late final TabController _bottomTabCtrl;

  MusicRoom? _room;
  String _partnerName = 'Partner';
  String? _partnerId;
  List<MusicPlaylist> _playlists = [];
  List<MusicTrack> _searchResults = [];

  bool _isLoadingRoom = true;
  bool _isSearching = false;
  bool _isReconnecting = false;
  bool _hasLeftRoom = false;
  String? _errorMessage;
  String _selectedLobbyMode = 'together';

  // Synchronization state
  String? _loadedVideoId;
  int _lastHandledSeq = -1;
  double _displayPosSeconds = 0.0;
  double _driftSeconds = 0.0;
  bool _localBuffering = false;
  bool _isDraggingSlider = false;
  double _sliderDragValue = 0.0;
  bool _endHandledForTrack = false;
  DateTime _lastSyncPacketAt = DateTime.now();

  StreamSubscription<YoutubePlayerValue>? _ytSub;
  Timer? _syncTickTimer;
  Timer? _pollFallbackTimer;
  Timer? _heartbeatTimer;
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _heartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);

    _bottomTabCtrl = TabController(length: 3, vsync: this);

    _ytController = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        mute: false,
        enableJavaScript: true,
        strictRelatedVideos: true,
      ),
    );

    _ytSub = _ytController.stream.listen(_onYouTubePlayerEvent);
    WakelockPlus.enable().catchError((_) {});

    _initRoomAndPlaylists();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTickTimer?.cancel();
    _pollFallbackTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    _ytSub?.cancel();
    _ytController.close();
    _heartAnimCtrl.dispose();
    _bottomTabCtrl.dispose();
    _searchCtrl.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || coupleId.isEmpty || _room == null) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Foreground recovery: fetch authoritative server timestamp & resync
      _fetchAndResyncRoom();
      _connectSseStream();
    } else if (state == AppLifecycleState.paused) {
      _repo
          .sendControl(
            coupleId: coupleId,
            userId: user.id,
            action: 'heartbeat',
            playerState: 'background',
          )
          .catchError((_) => _room!);
    }
  }

  Future<void> _initRoomAndPlaylists() async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || coupleId.isEmpty) {
      if (mounted) setState(() => _isLoadingRoom = false);
      return;
    }

    setState(() {
      _isLoadingRoom = true;
      _errorMessage = null;
    });

    try {
      final resp = await _repo.getRoomState(coupleId, user.id);
      final pls = await _repo.getPlaylists(coupleId, user.id);
      if (!mounted) return;
      setState(() {
        _partnerId = resp.partnerId;
        _partnerName = resp.partnerName;
        _playlists = pls;
        _isLoadingRoom = false;
      });
      if (resp.room != null) {
        // Automatically rejoin existing couple room on open
        await _joinOrCreateRoom(isCreate: false, invitePartner: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoadingRoom = false;
        });
      }
    }
  }

  Future<void> _joinOrCreateRoom({
    required bool isCreate,
    required bool invitePartner,
  }) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || coupleId.isEmpty) return;

    setState(() {
      _isLoadingRoom = true;
      _hasLeftRoom = false;
      _errorMessage = null;
    });

    try {
      final resp = await _repo.createOrJoinRoom(
        coupleId: coupleId,
        userId: user.id,
        mode: _selectedLobbyMode,
        invitePartner: invitePartner,
        isCreate: isCreate,
      );
      if (!mounted) return;
      setState(() {
        _partnerId = resp.partnerId;
        _partnerName = resp.partnerName;
        _isLoadingRoom = false;
      });
      if (resp.room != null) {
        await _applyServerRoomState(resp.room!, forceResync: true);
        _startSyncTimers();
        _connectSseStream();
        if (invitePartner && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('🎵 Invitation sent to $_partnerName to listen together!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoadingRoom = false;
        });
      }
    }
  }

  void _startSyncTimers() {
    _syncTickTimer?.cancel();
    _pollFallbackTimer?.cancel();
    _heartbeatTimer?.cancel();

    // Update UI clock & check drift against server anchor every 1s
    _syncTickTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final rm = _room;
      if (!mounted || rm == null || _hasLeftRoom) return;
      final pb = rm.playback;
      if (pb.videoId == null) return;

      final elapsedSincePacket =
          DateTime.now().difference(_lastSyncPacketAt).inMilliseconds / 1000.0;
      final expectedPos = pb.isPlaying
          ? (pb.livePositionSeconds + elapsedSincePacket)
              .clamp(0.0, pb.durationSeconds > 0 ? pb.durationSeconds.toDouble() : 99999.0)
          : pb.livePositionSeconds;

      if (!_isDraggingSlider) {
        setState(() => _displayPosSeconds = expectedPos);
      }

      // Check actual player timestamp drift
      try {
        final actualPos = await _ytController.currentTime;
        final drift = (actualPos - expectedPos).abs();
        if (mounted) {
          setState(() => _driftSeconds = drift);
        }
        // Only resync if drift > 2.2s and not actively buffering
        if (drift > 2.2 && !_localBuffering && pb.videoId == _loadedVideoId) {
          await _ytController.seekTo(seconds: expectedPos, allowSeekAhead: true);
        }
      } catch (_) {}
    });

    // Fallback state poll every 4s in case SSE drops silently
    _pollFallbackTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_hasLeftRoom) {
        _fetchAndResyncRoom(silent: true);
      }
    });

    // Heartbeat every 10s so partner knows connection/buffering status
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final user = ref.read(currentUserProvider);
      final coupleId = user?.coupleId;
      if (user == null || coupleId == null || _hasLeftRoom) return;
      try {
        await _repo.sendControl(
          coupleId: coupleId,
          userId: user.id,
          action: 'heartbeat',
          buffering: _localBuffering,
          playerState: _localBuffering ? 'buffering' : 'listening',
        );
      } catch (_) {}
    });
  }

  void _connectSseStream() {
    _sseSub?.cancel();
    _sseClient?.close();

    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || coupleId.isEmpty || _hasLeftRoom) {
      return;
    }

    final client = http.Client();
    _sseClient = client;

    final req = http.Request(
      'GET',
      Uri.parse(
          '${AuthNotifier.apiBaseUrl}/api/music/room/stream?couple_id=${Uri.encodeComponent(coupleId)}&user_id=${Uri.encodeComponent(user.id)}'),
    );
    req.headers['Accept'] = 'text/event-stream';

    client.send(req).then((streamed) {
      if (!mounted) return;
      setState(() => _isReconnecting = false);
      _sseSub = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!line.startsWith('data: ')) return;
          final rawJson = line.substring(6).trim();
          if (rawJson.isEmpty) return;
          try {
            final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
            if (parsed['room'] is Map<String, dynamic>) {
              final rm = MusicRoom.fromJson(parsed['room'] as Map<String, dynamic>);
              _applyServerRoomState(rm);
            }
          } catch (_) {}
        },
        onError: (_) => _scheduleSseReconnect(),
        onDone: () => _scheduleSseReconnect(),
      );
    }).catchError((_) => _scheduleSseReconnect());
  }

  void _scheduleSseReconnect() {
    if (!mounted || _hasLeftRoom) return;
    setState(() => _isReconnecting = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_hasLeftRoom) {
        _fetchAndResyncRoom(silent: true);
        _connectSseStream();
      }
    });
  }

  Future<void> _fetchAndResyncRoom({bool silent = false}) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || _hasLeftRoom) return;

    try {
      final resp = await _repo.getRoomState(coupleId, user.id);
      final pls = await _repo.getPlaylists(coupleId, user.id);
      if (!mounted) return;
      if (_isReconnecting) setState(() => _isReconnecting = false);
      setState(() => _playlists = pls);
      if (resp.room != null) {
        await _applyServerRoomState(resp.room!, forceResync: !silent);
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isReconnecting = true);
      }
    }
  }

  Future<void> _applyServerRoomState(MusicRoom newRoom,
      {bool forceResync = false}) async {
    if (!mounted) return;
    final pb = newRoom.playback;
    final seqChanged = pb.eventSeq != _lastHandledSeq;

    setState(() {
      _room = newRoom;
      _lastSyncPacketAt = DateTime.now();
      if (!_isDraggingSlider) {
        _displayPosSeconds = pb.livePositionSeconds;
      }
    });

    if (pb.videoId == null || pb.videoId!.isEmpty) return;

    final trackChanged = pb.videoId != _loadedVideoId;
    if (trackChanged) {
      _loadedVideoId = pb.videoId;
      _endHandledForTrack = false;
      _lastHandledSeq = pb.eventSeq;
      if (pb.isPlaying) {
        await _ytController.loadVideoById(
          videoId: pb.videoId!,
          startSeconds: pb.livePositionSeconds,
        );
      } else {
        await _ytController.cueVideoById(
          videoId: pb.videoId!,
          startSeconds: pb.livePositionSeconds,
        );
      }
      return;
    }

    if (seqChanged || forceResync) {
      _lastHandledSeq = pb.eventSeq;
      final currentState = await _ytController.playerState;
      final localTime = await _ytController.currentTime;

      if ((localTime - pb.livePositionSeconds).abs() > 1.8) {
        await _ytController.seekTo(
            seconds: pb.livePositionSeconds, allowSeekAhead: true);
      }

      if (pb.isPlaying && currentState != PlayerState.playing) {
        await _ytController.playVideo();
      } else if (!pb.isPlaying && currentState == PlayerState.playing) {
        await _ytController.pauseVideo();
      }
    }
  }

  void _onYouTubePlayerEvent(YoutubePlayerValue val) {
    if (!mounted) return;
    final isBuf = val.playerState == PlayerState.buffering;
    if (isBuf != _localBuffering) {
      setState(() => _localBuffering = isBuf);
    }

    // Track end auto-advance (single handler per track seq to avoid double skips)
    if (val.playerState == PlayerState.ended && !_endHandledForTrack) {
      _endHandledForTrack = true;
      final rm = _room;
      final user = ref.read(currentUserProvider);
      if (rm != null && user != null) {
        final isHostOrTogether =
            rm.mode == 'together' || rm.hostId == user.id;
        if (isHostOrTogether) {
          if (rm.playback.repeatMode == 'one') {
            _sendPlaybackControl('seek', positionSeconds: 0.0);
            _sendPlaybackControl('play', positionSeconds: 0.0);
          } else if (rm.queue.isNotEmpty ||
              rm.playback.repeatMode == 'all') {
            _sendPlaybackControl('next');
          }
        }
      }
    }
  }

  Future<void> _sendPlaybackControl(
    String action, {
    MusicTrack? track,
    double? positionSeconds,
    String? mode,
    String? repeatMode,
    bool? shuffle,
    int? index,
  }) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    HapticFeedback.selectionClick();
    try {
      final updated = await _repo.sendControl(
        coupleId: coupleId,
        userId: user.id,
        action: action,
        track: track,
        positionSeconds: positionSeconds,
        mode: mode,
        repeatMode: repeatMode,
        shuffle: shuffle,
        index: index,
      );
      await _applyServerRoomState(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _runSearch([String? presetQuery]) async {
    final q = (presetQuery ?? _searchCtrl.text).trim();
    if (q.isEmpty) return;
    if (presetQuery != null) _searchCtrl.text = presetQuery;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isSearching = true);
    try {
      final results = await _repo.searchSongs(q, user.id);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _leaveRoom() async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user != null && coupleId != null) {
      await _repo.leaveRoom(coupleId, user.id);
    }
    await _ytController.pauseVideo();
    _syncTickTimer?.cancel();
    _pollFallbackTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    if (mounted) {
      setState(() {
        _hasLeftRoom = true;
        _room = null;
      });
    }
  }

  Future<void> _addToPlaylistDialog(MusicTrack track) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Save "${track.title}" to Playlist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleLarge),
            const SizedBox(height: 12),
            ..._playlists.map((pl) => ListTile(
                  leading: Icon(
                    pl.isOurSongs
                        ? Icons.favorite_rounded
                        : Icons.queue_music_rounded,
                    color: pl.isOurSongs ? AppColors.accent : AppColors.primary,
                  ),
                  title: Text(pl.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${pl.songs.length} songs'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _repo.playlistSongOperation(
                      coupleId: coupleId,
                      userId: user.id,
                      playlistId: pl.id,
                      operation: 'add',
                      track: track,
                      isOurSong: pl.isOurSongs,
                    );
                    final updatedPls =
                        await _repo.getPlaylists(coupleId, user.id);
                    if (mounted) setState(() => _playlists = updatedPls);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('💖 Added to ${pl.name}!')),
                      );
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreatePlaylistDialog() async {
    final nameCtrl = TextEditingController();
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Couple Playlist 🎵',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            hintText: 'e.g. Late Night Drives 🌙',
            filled: true,
            fillColor: const Color(0xFFFAF7FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDACDF2)),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _repo.createPlaylist(coupleId, user.id, name);
              final updatedPls = await _repo.getPlaylists(coupleId, user.id);
              if (mounted) setState(() => _playlists = updatedPls);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportSongDialog(MusicPlaybackState pb) async {
    final reasonCtrl = TextEditingController();
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || pb.videoId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Report Track 🚩',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: reasonCtrl,
          decoration: InputDecoration(
            hintText: 'Reason (e.g. broken playback, inappropriate)',
            filled: true,
            fillColor: const Color(0xFFFAF7FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDACDF2)),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _repo.reportTrack(
                coupleId: coupleId,
                userId: user.id,
                videoId: pb.videoId!,
                title: pb.title ?? 'Song',
                reason: reasonCtrl.text.trim().isEmpty
                    ? 'Reported by user'
                    : reasonCtrl.text.trim(),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Report sent to Admin Music Moderation.')),
                );
              }
            },
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final total = seconds.isNaN || seconds < 0 ? 0 : seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isConnected = user != null && user.isConnectedToPartner;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Listen Together 🎵',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          if (_room != null && !_hasLeftRoom)
            IconButton(
              tooltip: 'Leave Listening Room',
              icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.error),
              onPressed: _leaveRoom,
            ),
        ],
      ),
      body: !isConnected
          ? _buildNotPairedView()
          : _isLoadingRoom
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _errorMessage != null
                  ? _buildErrorView()
                  : (_room == null || _hasLeftRoom)
                      ? _buildLobbyView(user!)
                      : _buildActiveRoomView(user!),
    );
  }

  Widget _buildNotPairedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎧💔', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text('Connect With Your Partner First',
                style: AppTypography.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text(
              'Listen Together rooms are strictly private for connected couples. Pair your account with your partner\'s invitation code on Home to listen to music together.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Go Connect Partner'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 54, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_errorMessage ?? 'Unable to open Listen Together',
                style: AppTypography.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: _initRoomAndPlaylists,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobbyView(SoulSyncUser user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C3EBC), Color(0xFFE94057)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                const Text('🎶💖', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 10),
                const Text(
                  'Two Hearts. One Song. Zero Distance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a private room with $_partnerName and enjoy synchronized YouTube music playback across any distance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.9), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Listening Mode Selector
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDACDF2), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose Listening Mode', style: AppTypography.titleLarge),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  value: 'together',
                  groupValue: _selectedLobbyMode,
                  activeColor: AppColors.primary,
                  title: const Text('Together Mode 💞',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'Both you and your partner can Play, Pause, Skip & Seek.',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() => _selectedLobbyMode = v!),
                ),
                RadioListTile<String>(
                  value: 'host',
                  groupValue: _selectedLobbyMode,
                  activeColor: AppColors.primary,
                  title: const Text('Host Mode 👑',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'Room host leads playback while partner stays synced.',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() => _selectedLobbyMode = v!),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94057),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () =>
                        _joinOrCreateRoom(isCreate: true, invitePartner: true),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: Text('Create Room & Invite $_partnerName',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // YouTube Policy / Transparency Note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF7FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDACDF2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Official YouTube Player: Playback stays synced (~0.5–1.5s) while this screen stays open. Standard YouTube ads or buffering occur independently per device and auto-resync afterward.',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRoomView(SoulSyncUser user) {
    final room = _room!;
    final pb = room.playback;
    final myPart = room.participants[user.id];
    final partnerPart = _partnerId != null
        ? room.participants[_partnerId!]
        : room.participants.values
            .where((p) => p.userId != user.id)
            .cast<MusicParticipant?>()
            .firstOrNull;
    final partnerOnline = partnerPart != null && partnerPart.online;
    final partnerStateLabel = partnerPart == null
        ? 'Not joined yet'
        : partnerPart.buffering
            ? 'Buffering... ⏳'
            : partnerOnline
                ? 'Listening 🎧'
                : partnerPart.state == 'background'
                    ? 'In background 📱'
                    : 'Disconnected';

    final maxDur = pb.durationSeconds > 0 ? pb.durationSeconds.toDouble() : 240.0;
    final currentPos = (_isDraggingSlider ? _sliderDragValue : _displayPosSeconds)
        .clamp(0.0, maxDur);

    return Column(
      children: [
        // 1. Partner Presence & Mode Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF23113A), Color(0xFF42195C)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PartnerAvatarChip(
                    name: user.displayName,
                    status: myPart?.buffering == true ? 'Buffering' : 'Connected',
                    isOnline: true,
                  ),
                  AnimatedBuilder(
                    animation: _heartAnimCtrl,
                    builder: (_, __) {
                      final scale = 0.92 + (_heartAnimCtrl.value * 0.22);
                      return Column(
                        children: [
                          Transform.scale(
                            scale: scale,
                            child: Icon(
                              Icons.favorite_rounded,
                              color: partnerOnline
                                  ? const Color(0xFFFF4D8D)
                                  : Colors.white38,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isReconnecting
                                ? 'Reconnecting...'
                                : _localBuffering
                                    ? 'Buffering...'
                                    : partnerOnline
                                        ? 'Synced ±${_driftSeconds.toStringAsFixed(1)}s'
                                        : 'Waiting for $_partnerName',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      );
                    },
                  ),
                  _PartnerAvatarChip(
                    name: partnerPart?.name ?? _partnerName,
                    status: partnerStateLabel,
                    isOnline: partnerOnline,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text(
                      room.mode == 'host' ? '👑 Host Mode' : '💞 Together Mode',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    selected: true,
                    selectedColor: Colors.white.withOpacity(0.2),
                    backgroundColor: Colors.white.withOpacity(0.1),
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    onSelected: (_) {
                      final nextMode =
                          room.mode == 'host' ? 'together' : 'host';
                      _sendPlaybackControl('mode', mode: nextMode);
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.notifications_active_rounded,
                        size: 14, color: Colors.white),
                    label: Text('Invite $_partnerName',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    backgroundColor: const Color(0xFFE94057),
                    side: BorderSide.none,
                    onPressed: () =>
                        _joinOrCreateRoom(isCreate: false, invitePartner: true),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Embedded YouTube Player + Playback Controls
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 195,
                  width: double.infinity,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: pb.videoId == null
                          ? Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFF321754), Color(0xFF7B2869)],
                                ),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.music_note_rounded,
                                        color: Colors.white70, size: 38),
                                    SizedBox(height: 8),
                                    Text(
                                      'Search & pick a song below to start listening together 🎶',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : YoutubePlayer(
                              controller: _ytController,
                              aspectRatio: 16 / 9,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Song Metadata & Report
              if (pb.videoId != null)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pb.title ?? 'Loading track...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          ),
                          Text(
                            '${pb.artist ?? 'YouTube'} • ${pb.updatedBy != null ? 'Updated by ${pb.updatedBy}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Report Track',
                      icon: const Icon(Icons.flag_outlined,
                          size: 18, color: AppColors.textHint),
                      onPressed: () => _showReportSongDialog(pb),
                    ),
                  ],
                ),

              // Seek Slider & Timestamps
              Row(
                children: [
                  Text(_formatDuration(currentPos),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  Expanded(
                    child: Slider(
                      value: currentPos,
                      min: 0.0,
                      max: maxDur > 0 ? maxDur : 1.0,
                      activeColor: const Color(0xFFE94057),
                      inactiveColor: const Color(0xFFDACDF2),
                      onChangeStart: (v) {
                        setState(() {
                          _isDraggingSlider = true;
                          _sliderDragValue = v;
                        });
                      },
                      onChanged: (v) => setState(() => _sliderDragValue = v),
                      onChangeEnd: (v) {
                        setState(() => _isDraggingSlider = false);
                        _sendPlaybackControl('seek', positionSeconds: v);
                      },
                    ),
                  ),
                  Text(_formatDuration(maxDur),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),

              // Control Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      pb.repeatMode == 'one'
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: pb.repeatMode != 'none'
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                    onPressed: () {
                      final next = pb.repeatMode == 'none'
                          ? 'all'
                          : pb.repeatMode == 'all'
                              ? 'one'
                              : 'none';
                      _sendPlaybackControl('repeat', repeatMode: next);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded,
                        size: 30, color: AppColors.textPrimary),
                    onPressed: () => _sendPlaybackControl('prev'),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE94057), Color(0xFF6C3EBC)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        pb.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: pb.videoId == null
                          ? null
                          : () => _sendPlaybackControl(
                                pb.isPlaying ? 'pause' : 'resume',
                                positionSeconds: currentPos,
                              ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        size: 30, color: AppColors.textPrimary),
                    onPressed: () => _sendPlaybackControl('next'),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color:
                          pb.shuffle ? AppColors.primary : AppColors.textHint,
                    ),
                    onPressed: () =>
                        _sendPlaybackControl('shuffle', shuffle: !pb.shuffle),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 3. Search / Queue / Couple Playlists Tabs
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _bottomTabCtrl,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textHint,
            indicatorColor: AppColors.primary,
            tabs: [
              const Tab(text: 'Search 🔍'),
              Tab(text: 'Queue (${room.queue.length})'),
              Tab(text: 'Playlists (${_playlists.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _bottomTabCtrl,
            children: [
              _buildSearchTab(user, room),
              _buildQueueTab(room),
              _buildPlaylistsTab(user, room),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchTab(SoulSyncUser user, MusicRoom room) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: const Color(0xFFDACDF2), width: 1.2),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(
                        color: Color(0xFF2D1F3D),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: 'Search YouTube songs or artists...',
                      hintStyle:
                          TextStyle(color: Color(0xFF7E7399), fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                onPressed: _isSearching ? null : () => _runSearch(),
                child: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.search_rounded, size: 20),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              'Romantic Acoustic',
              'Lo-Fi Love Chill',
              'Ed Sheeran Perfect',
              'Arijit Singh Love',
            ]
                .map((tag) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        backgroundColor: const Color(0xFFF3ECFF),
                        side: const BorderSide(color: Color(0xFFDACDF2)),
                        onPressed: () => _runSearch(tag),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _searchResults.isEmpty
              ? const Center(
                  child: Text(
                    'Search any song via YouTube Data API v3\nto play together in sync 🎵',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textHint, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _searchResults.length,
                  itemBuilder: (ctx, i) {
                    final t = _searchResults[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFFEDE5FA)),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(t.thumbnail,
                              width: 52, height: 40, fit: BoxFit.cover),
                        ),
                        title: Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${t.artist}${t.durationSeconds > 0 ? ' • ${_formatDuration(t.durationSeconds.toDouble())}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Play Now Together',
                              icon: const Icon(Icons.play_circle_fill_rounded,
                                  color: Color(0xFFE94057)),
                              onPressed: () =>
                                  _sendPlaybackControl('set_track', track: t),
                            ),
                            IconButton(
                              tooltip: 'Add to Queue',
                              icon: const Icon(Icons.playlist_add_rounded,
                                  color: AppColors.primary),
                              onPressed: () async {
                                await _sendPlaybackControl('queue_add',
                                    track: t);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Added "${t.title}" to queue')),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Save to Playlist',
                              icon: const Icon(Icons.favorite_border_rounded,
                                  color: AppColors.accent),
                              onPressed: () => _addToPlaylistDialog(t),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQueueTab(MusicRoom room) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('Up Next Queue (${room.queue.length})',
            style: AppTypography.titleMedium),
        const SizedBox(height: 8),
        if (room.queue.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Queue is empty. Search songs or play from your Couple Playlists!',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          )
        else
          ...List.generate(room.queue.length, (i) {
            final t = room.queue[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(t.thumbnail,
                      width: 48, height: 36, fit: BoxFit.cover),
                ),
                title: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${t.artist}${t.addedBy != null ? ' • Added by ${t.addedBy}' : ''}',
                    style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.error),
                  onPressed: () =>
                      _sendPlaybackControl('queue_remove', index: i),
                ),
              ),
            );
          }),
        const SizedBox(height: 18),
        Text('Recently Played (${room.recentlyPlayed.length})',
            style: AppTypography.titleMedium),
        const SizedBox(height: 8),
        if (room.recentlyPlayed.isEmpty)
          const Text('No recently played songs yet.',
              style: TextStyle(color: AppColors.textHint, fontSize: 12))
        else
          ...room.recentlyPlayed.map((t) => ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(t.thumbnail,
                      width: 44, height: 34, fit: BoxFit.cover),
                ),
                title: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(t.artist, style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.replay_rounded,
                      color: AppColors.primary),
                  onPressed: () =>
                      _sendPlaybackControl('set_track', track: t),
                ),
              )),
      ],
    );
  }

  Widget _buildPlaylistsTab(SoulSyncUser user, MusicRoom room) {
    final coupleId = user.coupleId ?? '';
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Shared Couple Playlists', style: AppTypography.titleMedium),
            TextButton.icon(
              onPressed: _showCreatePlaylistDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Playlist'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._playlists.map((pl) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFDACDF2)),
              ),
              child: ExpansionTile(
                initiallyExpanded: pl.isOurSongs,
                leading: Icon(
                  pl.isOurSongs
                      ? Icons.favorite_rounded
                      : Icons.library_music_rounded,
                  color: pl.isOurSongs ? AppColors.accent : AppColors.primary,
                ),
                title: Text(pl.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                subtitle: Text('${pl.songs.length} songs',
                    style: const TextStyle(fontSize: 11)),
                children: pl.songs.isEmpty
                    ? [
                        const Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            'No songs saved here yet. Tap ❤️ on any search result to add it!',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 12),
                          ),
                        ),
                      ]
                    : pl.songs
                        .map((s) => ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(s.thumbnail,
                                    width: 44, height: 34, fit: BoxFit.cover),
                              ),
                              title: Row(
                                children: [
                                  if (s.isOurSong)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 4),
                                      child: Text('💖',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  Expanded(
                                    child: Text(s.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                  '${s.artist}${s.isOurSong ? ' • Our Song' : ''}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Play Together',
                                    icon: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Color(0xFFE94057)),
                                    onPressed: () => _sendPlaybackControl(
                                        'set_track',
                                        track: s),
                                  ),
                                  IconButton(
                                    tooltip: 'Toggle "Our Song"',
                                    icon: Icon(
                                      s.isOurSong
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      size: 18,
                                      color: AppColors.accent,
                                    ),
                                    onPressed: () async {
                                      await _repo.playlistSongOperation(
                                        coupleId: coupleId,
                                        userId: user.id,
                                        playlistId: pl.id,
                                        operation: 'toggle_our_song',
                                        videoId: s.videoId,
                                      );
                                      final updated = await _repo.getPlaylists(
                                          coupleId, user.id);
                                      if (mounted) {
                                        setState(() => _playlists = updated);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Remove from Playlist',
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: AppColors.textHint),
                                    onPressed: () async {
                                      await _repo.playlistSongOperation(
                                        coupleId: coupleId,
                                        userId: user.id,
                                        playlistId: pl.id,
                                        operation: 'remove',
                                        videoId: s.videoId,
                                      );
                                      final updated = await _repo.getPlaylists(
                                          coupleId, user.id);
                                      if (mounted) {
                                        setState(() => _playlists = updated);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
              ),
            )),
      ],
    );
  }
}

class _PartnerAvatarChip extends StatelessWidget {
  final String name;
  final String status;
  final bool isOnline;

  const _PartnerAvatarChip({
    required this.name,
    required this.status,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor:
              isOnline ? const Color(0xFFE94057) : Colors.white24,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'P',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
            Text(
              status,
              style: TextStyle(
                  color: isOnline ? const Color(0xFF80E27E) : Colors.white54,
                  fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
