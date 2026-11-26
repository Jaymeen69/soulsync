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
  List<String> _searchHistory = [];
  MusicLikesState _likes = const MusicLikesState();
  List<MusicDedication> _dedications = [];
  List<MusicMemoryItem> _memories = [];
  MusicRecap _recap = const MusicRecap();

  String? _nextPageToken;
  String _lastQuery = '';
  int _searchEpoch = 0;
  Timer? _searchDebounce;
  String? _searchError;

  bool _isLoadingRoom = true;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _isReconnecting = false;
  bool _hasLeftRoom = false;
  String? _errorMessage;
  String _selectedLobbyMode = 'together';

  // Synchronization & Player Stability State
  String? _loadedVideoId;
  int _lastHandledSeq = -1;
  int _trackLoadEpoch = 0;
  double _displayPosSeconds = 0.0;
  double _driftSeconds = 0.0;
  bool _localBuffering = false;
  bool _isDraggingSlider = false;
  double _sliderDragValue = 0.0;
  bool _endHandledForTrack = false;
  bool _needsManualTap = false;
  String? _playerErrorMsg;
  DateTime _lastSyncPacketAt = DateTime.now();

  // Local audio controls (never affects partner)
  int _localVolume = 85;
  bool _isMuted = false;

  // Live Reactions & Animations
  bool _enableReactionAnimations = true;
  String? _incomingReactionBanner;
  Timer? _reactionClearTimer;

  // Local Individual Sleep Timer (minutes countdown in seconds)
  Timer? _localSleepTimer;
  int? _localSleepRemainingSec;

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

    _bottomTabCtrl = TabController(length: 4, vsync: this);

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

    _initRoomAndExtras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _reactionClearTimer?.cancel();
    _localSleepTimer?.cancel();
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
    if (user == null ||
        coupleId == null ||
        coupleId.isEmpty ||
        _room == null) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _fetchAndResyncRoom(forceResync: true);
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

  Future<void> _initRoomAndExtras() async {
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
      await _refreshSecondaryData(coupleId, user.id);
      if (!mounted) return;
      setState(() {
        _partnerId = resp.partnerId;
        _partnerName = resp.partnerName;
        _isLoadingRoom = false;
      });
      if (resp.room != null) {
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

  Future<void> _refreshSecondaryData(String coupleId, String userId) async {
    try {
      final results = await Future.wait([
        _repo.getPlaylists(coupleId, userId),
        _repo.getSearchHistory(userId),
        _repo.getLikes(coupleId, userId),
        _repo.getDedications(coupleId, userId),
        _repo.getMusicalMemories(coupleId, userId),
        _repo.getRecap(coupleId, userId),
      ]);
      if (!mounted) return;
      setState(() {
        _playlists = results[0] as List<MusicPlaylist>;
        _searchHistory = results[1] as List<String>;
        _likes = results[2] as MusicLikesState;
        _dedications = results[3] as List<MusicDedication>;
        _memories = results[4] as List<MusicMemoryItem>;
        _recap = results[5] as MusicRecap;
      });
    } catch (_) {}
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
                content: Text(
                    '🎵 Invitation sent to $_partnerName to listen together!')),
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

    _syncTickTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final rm = _room;
      if (!mounted || rm == null || _hasLeftRoom) return;
      final pb = rm.playback;
      if (pb.videoId == null) return;

      final elapsedSincePacket =
          DateTime.now().difference(_lastSyncPacketAt).inMilliseconds / 1000.0;
      final expectedPos = pb.isPlaying
          ? (pb.livePositionSeconds + elapsedSincePacket).clamp(
              0.0,
              pb.durationSeconds > 0 ? pb.durationSeconds.toDouble() : 99999.0)
          : pb.livePositionSeconds;

      if (!_isDraggingSlider) {
        setState(() => _displayPosSeconds = expectedPos);
      }

      try {
        final actualPos = await _ytController.currentTime;
        final drift = (actualPos - expectedPos).abs();
        if (mounted) {
          setState(() => _driftSeconds = drift);
        }
        if (drift > 2.2 &&
            !_localBuffering &&
            pb.videoId == _loadedVideoId &&
            !_needsManualTap) {
          await _ytController.seekTo(seconds: expectedPos, allowSeekAhead: true);
        }
      } catch (_) {}
    });

    _pollFallbackTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_hasLeftRoom) {
        _fetchAndResyncRoom(silent: true);
      }
    });

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
            if (parsed['event'] == 'reaction' && parsed['reaction'] is Map) {
              final r = parsed['reaction'] as Map<String, dynamic>;
              final sender = r['sender_name']?.toString() ?? 'Partner';
              final emoji = r['emoji']?.toString() ?? '❤️';
              _showLiveReaction('$sender reacted $emoji');
            }
            if (parsed['room'] is Map<String, dynamic>) {
              final rm = MusicRoom.fromJson(
                  parsed['room'] as Map<String, dynamic>);
              _applyServerRoomState(rm);
            }
          } catch (_) {}
        },
        onError: (_) => _scheduleSseReconnect(),
        onDone: () => _scheduleSseReconnect(),
      );
    }).catchError((_) => _scheduleSseReconnect());
  }

  void _showLiveReaction(String text) {
    if (!mounted) return;
    _reactionClearTimer?.cancel();
    setState(() => _incomingReactionBanner = text);
    _reactionClearTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _incomingReactionBanner = null);
    });
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

  Future<void> _fetchAndResyncRoom({
    bool silent = false,
    bool forceResync = false,
  }) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null || _hasLeftRoom) return;

    try {
      final resp = await _repo.getRoomState(coupleId, user.id);
      if (!silent) {
        await _refreshSecondaryData(coupleId, user.id);
      } else {
        final pls = await _repo.getPlaylists(coupleId, user.id);
        if (mounted) setState(() => _playlists = pls);
      }
      if (!mounted) return;
      if (_isReconnecting) setState(() => _isReconnecting = false);
      if (resp.room != null) {
        await _applyServerRoomState(resp.room!, forceResync: forceResync);
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _isReconnecting = true);
      }
    }
  }

  Future<void> _applyServerRoomState(
    MusicRoom newRoom, {
    bool forceResync = false,
  }) async {
    if (!mounted) return;
    final pb = newRoom.playback;

    // Sequence lock: reject stale / out-of-order packets from poll or laggy network
    if (!forceResync && _lastHandledSeq >= 0 && pb.eventSeq < _lastHandledSeq) {
      return;
    }

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
      _lastHandledSeq = pb.eventSeq;
      _endHandledForTrack = false;
      _playerErrorMsg = null;
      _needsManualTap = false;
      await _loadTrackIntoPlayer(
        videoId: pb.videoId!,
        startSeconds: pb.livePositionSeconds,
        shouldPlay: pb.isPlaying,
      );
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

  Future<void> _loadTrackIntoPlayer({
    required String videoId,
    required double startSeconds,
    required bool shouldPlay,
  }) async {
    final epoch = ++_trackLoadEpoch;
    try {
      // Wait a tiny frame if widget just mounted, then issue command
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted || epoch != _trackLoadEpoch || _loadedVideoId != videoId) {
        return;
      }

      if (shouldPlay) {
        await _ytController.loadVideoById(
          videoId: videoId,
          startSeconds: startSeconds,
        );
      } else {
        await _ytController.cueVideoById(
          videoId: videoId,
          startSeconds: startSeconds,
        );
      }

      if (_isMuted) {
        await _ytController.mute();
      } else {
        await _ytController.setVolume(_localVolume);
      }

      if (!shouldPlay) return;

      // Verify player actually transitioned cleanly; retry once & surface autoplay tap pill if browser blocked autoplay
      Future.delayed(const Duration(milliseconds: 900), () async {
        if (!mounted ||
            epoch != _trackLoadEpoch ||
            _loadedVideoId != videoId) {
          return;
        }
        try {
          final st = await _ytController.playerState;
          if (st == PlayerState.cued ||
              st == PlayerState.unStarted ||
              st == PlayerState.unknown) {
            await _ytController.playVideo();
          }
        } catch (_) {}
      });

      Future.delayed(const Duration(milliseconds: 1900), () async {
        if (!mounted ||
            epoch != _trackLoadEpoch ||
            _loadedVideoId != videoId) {
          return;
        }
        try {
          final st = await _ytController.playerState;
          final stillPlaying = _room?.playback.isPlaying == true;
          if (stillPlaying &&
              (st == PlayerState.cued ||
                  st == PlayerState.unStarted ||
                  st == PlayerState.unknown)) {
            setState(() => _needsManualTap = true);
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _onYouTubePlayerEvent(YoutubePlayerValue val) {
    if (!mounted) return;
    final isBuf = val.playerState == PlayerState.buffering;
    if (isBuf != _localBuffering) {
      setState(() => _localBuffering = isBuf);
    }

    if (val.playerState == PlayerState.playing && _needsManualTap) {
      setState(() => _needsManualTap = false);
    }

    if (val.hasError) {
      setState(() {
        _playerErrorMsg =
            'Playback restricted or unavailable on YouTube (${val.error.name}). Skip to another song or queue next track.';
      });
    }

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
    int? oldIndex,
    int? newIndex,
    String? playlistId,
    String? suggestionId,
    String? videoId,
    int? minutes,
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
        oldIndex: oldIndex,
        newIndex: newIndex,
        playlistId: playlistId,
        suggestionId: suggestionId,
        videoId: videoId,
        minutes: minutes,
      );
      await _applyServerRoomState(updated);
      if (action == 'set_track' ||
          action == 'play_playlist' ||
          action == 'surprise') {
        final r = await _repo.getRecap(coupleId, user.id);
        if (mounted) setState(() => _recap = r);
      }
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

  void _onSearchQueryChanged(String val) {
    _searchDebounce?.cancel();
    final q = val.trim();
    if (q.isEmpty) {
      setState(() {
        _searchError = null;
      });
      return;
    }
    // Automatically run debounced search for full queries or YouTube URLs
    if (q.length >= 3 || q.contains('youtu')) {
      _searchDebounce = Timer(const Duration(milliseconds: 520), () {
        if (mounted && _searchCtrl.text.trim() == q) {
          _runSearch(q);
        }
      });
    }
  }

  Future<void> _runSearch([String? presetQuery]) async {
    _searchDebounce?.cancel();
    final q = (presetQuery ?? _searchCtrl.text).trim();
    if (q.isEmpty) return;
    if (presetQuery != null) _searchCtrl.text = presetQuery;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final epoch = ++_searchEpoch;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _lastQuery = q;
      _nextPageToken = null;
    });

    try {
      final resp = await _repo.searchSongs(q, user.id);
      if (!mounted || epoch != _searchEpoch) return;
      final hist = await _repo.getSearchHistory(user.id);
      if (!mounted || epoch != _searchEpoch) return;
      setState(() {
        _searchResults = resp.results;
        _nextPageToken = resp.nextPageToken;
        _searchHistory = hist;
        _isSearching = false;
      });
    } catch (e) {
      if (mounted && epoch == _searchEpoch) {
        setState(() {
          _isSearching = false;
          _searchError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _loadMoreSearch() async {
    final user = ref.read(currentUserProvider);
    if (user == null ||
        _nextPageToken == null ||
        _lastQuery.isEmpty ||
        _isLoadingMore) {
      return;
    }
    final epoch = _searchEpoch;
    setState(() => _isLoadingMore = true);
    try {
      final resp = await _repo.searchSongs(
        _lastQuery,
        user.id,
        pageToken: _nextPageToken,
      );
      if (!mounted || epoch != _searchEpoch) return;
      final existingIds = _searchResults.map((e) => e.videoId).toSet();
      final deduped = resp.results
          .where((t) => !existingIds.contains(t.videoId))
          .toList();
      setState(() {
        _searchResults = [..._searchResults, ...deduped];
        _nextPageToken = resp.nextPageToken;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _leaveRoom() async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user != null && coupleId != null) {
      await _repo.leaveRoom(coupleId, user.id);
    }
    try {
      await _ytController.pauseVideo();
    } catch (_) {}
    _syncTickTimer?.cancel();
    _pollFallbackTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    if (mounted) {
      setState(() {
        _hasLeftRoom = true;
        _room = null;
        _loadedVideoId = null;
      });
    }
  }

  bool _isTrackLiked(String? videoId) {
    if (videoId == null) return false;
    return _likes.likedSongs.any((t) => t.videoId == videoId);
  }

  Future<void> _toggleLike(MusicTrack track) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;
    final already = _isTrackLiked(track.videoId);
    try {
      final updated = await _repo.likesOp(
        coupleId: coupleId,
        userId: user.id,
        operation: already ? 'unlike' : 'like',
        track: track,
        videoId: track.videoId,
      );
      if (mounted) {
        setState(() => _likes = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(already
                ? 'Removed "${track.title}" from your Likes'
                : '❤️ Saved "${track.title}" to your Likes!'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _addToPlaylistDialog(MusicTrack track) async {
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

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
            Text('Save "${track.title}" to Playlist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleLarge),
            const SizedBox(height: 12),
            ..._playlists.map((pl) => ListTile(
                  leading: Text(pl.artworkEmoji,
                      style: const TextStyle(fontSize: 22)),
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
    String selectedEmoji = '🎶';
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('New Couple Playlist 🎵',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: context.ssTextPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. Late Night Drives 🌙',
                  filled: true,
                  fillColor: context.ssInputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.ssBorder),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['🎶', '💖', '🌙', '🚗', '☕', '🔥'].map((e) {
                  final sel = selectedEmoji == e;
                  return ChoiceChip(
                    label: Text(e, style: const TextStyle(fontSize: 16)),
                    selected: sel,
                    onSelected: (_) => setDlg(() => selectedEmoji = e),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                await _repo.createPlaylist(
                  coupleId,
                  user.id,
                  name,
                  artworkEmoji: selectedEmoji,
                );
                final updatedPls =
                    await _repo.getPlaylists(coupleId, user.id);
                if (mounted) setState(() => _playlists = updatedPls);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPlaylistManageDialog(MusicPlaylist pl) async {
    final nameCtrl = TextEditingController(text: pl.name);
    String chosenEmoji = pl.artworkEmoji;
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: const Text('Edit Playlist 🎨'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: context.ssTextPrimary),
                decoration: const InputDecoration(labelText: 'Playlist Name'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['💖', '🎶', '🌙', '🎧', '🌹', '✨'].map((e) {
                  return ChoiceChip(
                    label: Text(e),
                    selected: chosenEmoji == e,
                    onSelected: (_) => setDlg(() => chosenEmoji = e),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            if (!pl.isOurSongs)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _repo.playlistOp(
                    coupleId: coupleId,
                    userId: user.id,
                    playlistId: pl.id,
                    operation: 'delete',
                  );
                  final updatedPls =
                      await _repo.getPlaylists(coupleId, user.id);
                  if (mounted) setState(() => _playlists = updatedPls);
                },
                child: const Text('Delete'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _repo.playlistOp(
                  coupleId: coupleId,
                  userId: user.id,
                  playlistId: pl.id,
                  operation: 'rename',
                  name: nameCtrl.text.trim(),
                );
                await _repo.playlistOp(
                  coupleId: coupleId,
                  userId: user.id,
                  playlistId: pl.id,
                  operation: 'artwork',
                  artworkEmoji: chosenEmoji,
                );
                final updatedPls =
                    await _repo.getPlaylists(coupleId, user.id);
                if (mounted) setState(() => _playlists = updatedPls);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDedicateDialog(MusicTrack track) async {
    final msgCtrl = TextEditingController();
    String emoji = '💌';
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: Text('Dedicate Song to $_partnerName 💌'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: msgCtrl,
                maxLines: 3,
                style: TextStyle(color: context.ssTextPrimary),
                decoration: InputDecoration(
                  hintText: 'This song reminded me of you...',
                  filled: true,
                  fillColor: context.ssInputFill,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: ['💌', '💖', '🥺', '🌹', '🎵'].map((e) {
                  return ChoiceChip(
                    label: Text(e),
                    selected: emoji == e,
                    onSelected: (_) => setDlg(() => emoji = e),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _repo.sendDedication(
                  coupleId: coupleId,
                  userId: user.id,
                  track: track,
                  message: msgCtrl.text.trim().isEmpty
                      ? 'This song reminded me of you 💖'
                      : msgCtrl.text.trim(),
                  emoji: emoji,
                );
                await _refreshSecondaryData(coupleId, user.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('💌 Song dedicated & $_partnerName notified!')),
                  );
                }
              },
              child: const Text('Send Dedication'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMemoryDialog({
    MusicTrack? track,
    MusicMemoryItem? existing,
  }) async {
    final titleCtrl =
        TextEditingController(text: existing?.title ?? track?.title ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    String occasion = existing?.occasion ?? 'Date Night';
    final user = ref.read(currentUserProvider);
    final coupleId = user?.coupleId;
    if (user == null || coupleId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: Text(
              existing == null ? 'Save Musical Memory 📸' : 'Edit Memory ✏️'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  style: TextStyle(color: context.ssTextPrimary),
                  decoration: const InputDecoration(labelText: 'Memory Title'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  style: TextStyle(color: context.ssTextPrimary),
                  decoration: const InputDecoration(
                      labelText: 'Why is this song special to you two?'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    'Date Night',
                    'First Dance',
                    'Road Trip',
                    'Late Night Call',
                    'Anniversary'
                  ].map((occ) {
                    return ChoiceChip(
                      label: Text(occ, style: const TextStyle(fontSize: 11)),
                      selected: occasion == occ,
                      onSelected: (_) => setDlg(() => occasion = occ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _repo.musicalMemoryOp(
                  coupleId: coupleId,
                  userId: user.id,
                  operation: existing == null ? 'create' : 'edit',
                  memoryId: existing?.id,
                  track: track ?? existing?.track,
                  title: titleCtrl.text.trim(),
                  note: noteCtrl.text.trim(),
                  occasion: occasion,
                );
                await _refreshSecondaryData(coupleId, user.id);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerModal() {
    final user = ref.read(currentUserProvider);
    final rm = _room;
    if (user == null || rm == null) return;

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
            Text('Sleep Timer 🌙', style: AppTypography.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Choose a personal timer (only pauses your device) or propose a shared timer that requires $_partnerName to accept.',
              style: TextStyle(fontSize: 12, color: context.ssTextSecondary),
            ),
            const SizedBox(height: 14),
            Text('Personal Sleep Timer (Only You)',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: context.ssTextPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [10, 20, 30, 45, 60].map((m) {
                return ActionChip(
                  label: Text('$m min'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _startLocalSleepTimer(m);
                  },
                );
              }).toList(),
            ),
            if (_localSleepRemainingSec != null)
              TextButton(
                onPressed: () {
                  _localSleepTimer?.cancel();
                  setState(() => _localSleepRemainingSec = null);
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel Personal Timer'),
              ),
            const Divider(height: 24),
            Text('Propose Shared Room Sleep Timer',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: context.ssTextPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [15, 30, 45].map((m) {
                return ActionChip(
                  label: Text('Propose $m min 🤝'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendPlaybackControl('sleep_timer_propose', minutes: m);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _startLocalSleepTimer(int minutes) {
    _localSleepTimer?.cancel();
    setState(() => _localSleepRemainingSec = minutes * 60);
    _localSleepTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = (_localSleepRemainingSec ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        setState(() => _localSleepRemainingSec = null);
        try {
          await _ytController.pauseVideo();
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('🌙 Personal Sleep Timer paused your playback.')),
          );
        }
      } else {
        setState(() => _localSleepRemainingSec = left);
      }
    });
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
          style: TextStyle(color: ctx.ssTextPrimary),
          decoration: InputDecoration(
            hintText: 'Reason (e.g. broken playback, inappropriate)',
            filled: true,
            fillColor: ctx.ssInputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ctx.ssBorder),
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

  MusicTrack? _currentTrackObj(MusicPlaybackState pb) {
    if (pb.videoId == null || pb.videoId!.isEmpty) return null;
    return MusicTrack(
      videoId: pb.videoId!,
      title: pb.title ?? 'Song',
      artist: pb.artist ?? 'YouTube',
      thumbnail: pb.thumbnail ??
          'https://img.youtube.com/vi/${pb.videoId}/hqdefault.jpg',
      durationSeconds: pb.durationSeconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isConnected = user != null && user.isConnectedToPartner;

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
          'Listen Together 🎵',
          style: TextStyle(
              color: context.ssTextPrimary, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          if (_room != null && !_hasLeftRoom) ...[
            IconButton(
              tooltip: 'Sync Now',
              icon: Icon(Icons.sync_rounded, color: context.ssPrimary),
              onPressed: () async {
                await _fetchAndResyncRoom(forceResync: true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✨ Synced with server timestamp!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Sleep Timer',
              icon: Icon(
                Icons.bedtime_rounded,
                color: (_localSleepRemainingSec != null ||
                        _room?.sleepTimer?.status == 'active')
                    ? context.ssAccent
                    : context.ssTextSecondary,
              ),
              onPressed: _showSleepTimerModal,
            ),
            IconButton(
              tooltip: 'Leave Room',
              icon:
                  const Icon(Icons.exit_to_app_rounded, color: AppColors.error),
              onPressed: _leaveRoom,
            ),
          ],
        ],
      ),
      body: !isConnected
          ? _buildNotPairedView()
          : _isLoadingRoom
              ? Center(
                  child: CircularProgressIndicator(color: context.ssPrimary))
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
            Text(
              'Listen Together rooms are strictly private for connected couples. Pair your account with your partner\'s invitation code on Home to listen together.',
              style: TextStyle(color: context.ssTextSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
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
              onPressed: _initRoomAndExtras,
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
                colors: [Color(0xFF6C3EBC), Color(0xFFD03070)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
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
                      color: Colors.white.withValues(alpha: 0.92), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.ssSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.ssBorder, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose Listening Mode', style: AppTypography.titleLarge),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  value: 'together',
                  groupValue: _selectedLobbyMode,
                  activeColor: context.ssPrimary,
                  title: const Text('Together Mode 💞',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Both you and your partner can Play, Pause, Skip & Seek.',
                      style: TextStyle(
                          fontSize: 12, color: context.ssTextSecondary)),
                  onChanged: (v) => setState(() => _selectedLobbyMode = v!),
                ),
                RadioListTile<String>(
                  value: 'host',
                  groupValue: _selectedLobbyMode,
                  activeColor: context.ssPrimary,
                  title: const Text('Host Mode 👑',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Room host leads playback while partner stays synced and can suggest tracks.',
                      style: TextStyle(
                          fontSize: 12, color: context.ssTextSecondary)),
                  onChanged: (v) => setState(() => _selectedLobbyMode = v!),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.ssInputFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.ssBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: context.ssPrimary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Official YouTube Player: Playback stays synced (~0.5–1.5s) while this screen stays open. Standard YouTube ads or buffering occur independently per device and auto-resync afterward.',
                    style: TextStyle(
                        fontSize: 11, color: context.ssTextSecondary, height: 1.4),
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
    final currentPos =
        (_isDraggingSlider ? _sliderDragValue : _displayPosSeconds)
            .clamp(0.0, maxDur);
    final isHostMode = room.mode == 'host';
    final amHost = !isHostMode || room.hostId == user.id;
    final curTrack = _currentTrackObj(pb);
    final likedCurrent = _isTrackLiked(pb.videoId);
    final disableAnim = MediaQuery.disableAnimationsOf(context);

    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(
          child: Column(
            children: [
              // 1. Partner Presence & Mode Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF23113A), Color(0xFF42195C)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
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
                          status: myPart?.buffering == true
                              ? 'Buffering'
                              : 'Connected',
                          isOnline: true,
                        ),
                        AnimatedBuilder(
                          animation: _heartAnimCtrl,
                          builder: (_, __) {
                            final scale = disableAnim
                                ? 1.0
                                : 0.92 + (_heartAnimCtrl.value * 0.22);
                            return Column(
                              children: [
                                Transform.scale(
                                  scale: scale,
                                  child: Icon(
                                    Icons.favorite_rounded,
                                    color: partnerOnline
                                        ? const Color(0xFFFF4D8D)
                                        : Colors.white54,
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
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        InkWell(
                          onTap: () {
                            final nextMode =
                                room.mode == 'host' ? 'together' : 'host';
                            _sendPlaybackControl('mode', mode: nextMode);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              room.mode == 'host'
                                  ? '👑 Host Mode${amHost ? " (You)" : ""}'
                                  : '💞 Together Mode',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _joinOrCreateRoom(
                              isCreate: false, invitePartner: true),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.notifications_active_rounded,
                                    size: 13, color: Colors.white),
                                const SizedBox(width: 4),
                                Text('Invite $_partnerName',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _sendPlaybackControl('surprise'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text('🎲 Surprise Me',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Sleep timer banner (Personal or Shared)
              if (_localSleepRemainingSec != null ||
                  (room.sleepTimer != null &&
                      room.sleepTimer!.status != 'expired'))
                Container(
                  width: double.infinity,
                  color: context.ssSurfaceVariant,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(
                    children: [
                      if (_localSleepRemainingSec != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '🌙 Personal Sleep Timer: ${_formatDuration(_localSleepRemainingSec!.toDouble())}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.ssTextPrimary),
                            ),
                            TextButton(
                              onPressed: () {
                                _localSleepTimer?.cancel();
                                setState(() => _localSleepRemainingSec = null);
                              },
                              child: const Text('Stop'),
                            ),
                          ],
                        ),
                      if (room.sleepTimer != null &&
                          room.sleepTimer!.status == 'pending')
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                room.sleepTimer!.proposedById == user.id
                                    ? '🌙 Shared timer (${room.sleepTimer!.minutes}m) waiting for $_partnerName'
                                    : '🌙 ${room.sleepTimer!.proposedByName} proposed ${room.sleepTimer!.minutes}m shared sleep timer',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: context.ssTextPrimary),
                              ),
                            ),
                            if (room.sleepTimer!.proposedById != user.id)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 32),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10)),
                                onPressed: () =>
                                    _sendPlaybackControl('sleep_timer_accept'),
                                child: const Text('Accept'),
                              ),
                            TextButton(
                              onPressed: () =>
                                  _sendPlaybackControl('sleep_timer_cancel'),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      if (room.sleepTimer != null &&
                          room.sleepTimer!.status == 'active')
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '🤝 Shared Sleep Timer active (${room.sleepTimer!.minutes}m)',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _sendPlaybackControl('sleep_timer_cancel'),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              // 2. Always-Mounted YouTube Player & Controls
              Container(
                color: context.ssSurface,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 188,
                        width: double.infinity,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: YoutubePlayer(
                                    controller: _ytController,
                                    aspectRatio: 16 / 9,
                                  ),
                                ),
                                if (pb.videoId == null)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFF321754),
                                            Color(0xFF7B2869)
                                          ],
                                        ),
                                      ),
                                      child: const Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.music_note_rounded,
                                                color: Colors.white70,
                                                size: 38),
                                            SizedBox(height: 8),
                                            Padding(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 16),
                                              child: Text(
                                                'Search a song or paste a YouTube URL below to start listening together 🎶',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (_needsManualTap) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              minimumSize: const Size(0, 38)),
                          onPressed: () async {
                            setState(() => _needsManualTap = false);
                            await _ytController.playVideo();
                          },
                          icon: const Icon(Icons.headphones_rounded, size: 18),
                          label: const Text('Tap to Join Playback 🎧'),
                        ),
                      ),
                    ],

                    if (_playerErrorMsg != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_playerErrorMsg!,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: context.ssTextPrimary)),
                            ),
                            TextButton(
                              onPressed: () => _sendPlaybackControl('next'),
                              child: const Text('Next Song'),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Song Metadata + Quick Actions (Like / Dedicate / Save / Report)
                    if (pb.videoId != null && curTrack != null)
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
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: context.ssTextPrimary),
                                ),
                                Text(
                                  '${pb.artist ?? 'YouTube'}${pb.updatedBy != null ? ' • Updated by ${pb.updatedBy}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: context.ssTextSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip:
                                likedCurrent ? 'Unlike Song' : 'Like Song',
                            icon: Icon(
                              likedCurrent
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 20,
                              color: likedCurrent
                                  ? AppColors.accent
                                  : context.ssTextSecondary,
                            ),
                            onPressed: () => _toggleLike(curTrack),
                          ),
                          IconButton(
                            tooltip: 'Dedicate to $_partnerName',
                            icon: Icon(Icons.card_giftcard_rounded,
                                size: 20, color: context.ssPrimary),
                            onPressed: () => _showDedicateDialog(curTrack),
                          ),
                          IconButton(
                            tooltip: 'Save to Playlist',
                            icon: Icon(Icons.playlist_add_rounded,
                                size: 20, color: context.ssPrimary),
                            onPressed: () => _addToPlaylistDialog(curTrack),
                          ),
                          IconButton(
                            tooltip: 'Report Track',
                            icon: Icon(Icons.flag_outlined,
                                size: 18, color: context.ssTextHint),
                            onPressed: () => _showReportSongDialog(pb),
                          ),
                        ],
                      ),

                    // Seek Slider & Timestamps
                    Row(
                      children: [
                        Text(_formatDuration(currentPos),
                            style: TextStyle(
                                fontSize: 11, color: context.ssTextSecondary)),
                        Expanded(
                          child: Slider(
                            value: currentPos,
                            min: 0.0,
                            max: maxDur > 0 ? maxDur : 1.0,
                            activeColor: AppColors.accent,
                            inactiveColor: context.ssBorder,
                            onChangeStart: amHost
                                ? (v) {
                                    setState(() {
                                      _isDraggingSlider = true;
                                      _sliderDragValue = v;
                                    });
                                  }
                                : null,
                            onChanged: amHost
                                ? (v) => setState(() => _sliderDragValue = v)
                                : null,
                            onChangeEnd: amHost
                                ? (v) {
                                    setState(() => _isDraggingSlider = false);
                                    _sendPlaybackControl('seek',
                                        positionSeconds: v);
                                  }
                                : null,
                          ),
                        ),
                        Text(_formatDuration(maxDur),
                            style: TextStyle(
                                fontSize: 11, color: context.ssTextSecondary)),
                      ],
                    ),

                    // Local Individual Volume Slider + Playback Controls
                    Row(
                      children: [
                        IconButton(
                          tooltip: _isMuted ? 'Unmute Local Audio' : 'Mute Local Audio',
                          icon: Icon(
                            _isMuted || _localVolume == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            size: 20,
                            color: context.ssPrimary,
                          ),
                          onPressed: () async {
                            final nextMute = !_isMuted;
                            setState(() => _isMuted = nextMute);
                            try {
                              if (nextMute) {
                                await _ytController.mute();
                              } else {
                                await _ytController.unMute();
                                await _ytController.setVolume(_localVolume);
                              }
                            } catch (_) {}
                          },
                        ),
                        Expanded(
                          child: Slider(
                            value: _isMuted ? 0.0 : _localVolume.toDouble(),
                            min: 0,
                            max: 100,
                            activeColor: context.ssPrimary,
                            inactiveColor: context.ssBorder,
                            onChanged: (v) async {
                              final vol = v.round();
                              setState(() {
                                _localVolume = vol;
                                _isMuted = vol == 0;
                              });
                              try {
                                if (vol == 0) {
                                  await _ytController.mute();
                                } else {
                                  await _ytController.unMute();
                                  await _ytController.setVolume(vol);
                                }
                              } catch (_) {}
                            },
                          ),
                        ),
                        Text('My Vol $_localVolume%',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: context.ssTextSecondary)),
                      ],
                    ),

                    // Playback Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                            pb.repeatMode == 'one'
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            color: pb.repeatMode != 'none'
                                ? context.ssPrimary
                                : context.ssTextHint,
                          ),
                          onPressed: amHost
                              ? () {
                                  final next = pb.repeatMode == 'none'
                                      ? 'all'
                                      : pb.repeatMode == 'all'
                                          ? 'one'
                                          : 'none';
                                  _sendPlaybackControl('repeat',
                                      repeatMode: next);
                                }
                              : null,
                        ),
                        IconButton(
                          icon: Icon(Icons.skip_previous_rounded,
                              size: 30, color: context.ssTextPrimary),
                          onPressed:
                              amHost ? () => _sendPlaybackControl('prev') : null,
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: AppColors.primaryGradient,
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
                            onPressed: (pb.videoId == null || !amHost)
                                ? null
                                : () => _sendPlaybackControl(
                                      pb.isPlaying ? 'pause' : 'resume',
                                      positionSeconds: currentPos,
                                    ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.skip_next_rounded,
                              size: 30, color: context.ssTextPrimary),
                          onPressed:
                              amHost ? () => _sendPlaybackControl('next') : null,
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: pb.shuffle
                                ? context.ssPrimary
                                : context.ssTextHint,
                          ),
                          onPressed: amHost
                              ? () => _sendPlaybackControl('shuffle',
                                  shuffle: !pb.shuffle)
                              : null,
                        ),
                      ],
                    ),

                    // Live Emoji Reactions OUTSIDE Player
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.ssSurfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: ['❤️', '😍', '🔥', '🥺', '🎵', '🫶']
                                    .map((e) => InkWell(
                                          onTap: () async {
                                            try {
                                              await _repo.sendReaction(
                                                coupleId: room.coupleId,
                                                userId: user.id,
                                                emoji: e,
                                              );
                                            } catch (err) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(err
                                                        .toString()
                                                        .replaceFirst(
                                                            'Exception: ', '')),
                                                    duration: const Duration(
                                                        seconds: 1),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 3),
                                            child: Text(e,
                                                style: const TextStyle(
                                                    fontSize: 18)),
                                          ),
                                        ))
                                    .toList(),
                              ),
                              IconButton(
                                tooltip: _enableReactionAnimations
                                    ? 'Reduce reaction animations'
                                    : 'Enable reaction animations',
                                icon: Icon(
                                  _enableReactionAnimations
                                      ? Icons.auto_awesome_rounded
                                      : Icons.motion_photos_off_rounded,
                                  size: 16,
                                  color: context.ssTextSecondary,
                                ),
                                onPressed: () => setState(() =>
                                    _enableReactionAnimations =
                                        !_enableReactionAnimations),
                              ),
                            ],
                          ),
                          if (_incomingReactionBanner != null)
                            AnimatedOpacity(
                              opacity: 1,
                              duration: Duration(
                                  milliseconds:
                                      (!_enableReactionAnimations || disableAnim)
                                          ? 0
                                          : 250),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _incomingReactionBanner!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: context.ssAccent),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Host Mode Incoming Suggestions Banner
                    if (amHost && room.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...room.suggestions.take(2).map((sug) => Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: context.ssInputFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.ssBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '🙋 ${sug.suggestedBy} suggested: ${sug.track.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: context.ssTextPrimary),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _sendPlaybackControl('set_track',
                                        track: sug.track);
                                    _sendPlaybackControl('dismiss_suggestion',
                                        suggestionId: sug.id);
                                  },
                                  child: const Text('Play'),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close,
                                      size: 16, color: context.ssTextHint),
                                  onPressed: () => _sendPlaybackControl(
                                      'dismiss_suggestion',
                                      suggestionId: sug.id),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyTabBarDelegate(
            TabBar(
              controller: _bottomTabCtrl,
              labelColor: context.ssPrimary,
              unselectedLabelColor: context.ssTextSecondary,
              indicatorColor: context.ssPrimary,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              tabs: [
                const Tab(text: 'Search 🔍'),
                Tab(text: 'Queue (${room.queue.length})'),
                Tab(text: 'Playlists (${_playlists.length})'),
                const Tab(text: 'Couple ✨'),
              ],
            ),
            context.ssSurface,
          ),
        ),
      ],
      body: TabBarView(
        controller: _bottomTabCtrl,
        children: [
          _buildSearchTab(user, room, amHost),
          _buildQueueTab(room, amHost),
          _buildPlaylistsTab(user, room, amHost),
          _buildCoupleExtrasTab(user, room, curTrack, amHost),
        ],
      ),
    );
  }

  Widget _buildSearchTab(SoulSyncUser user, MusicRoom room, bool amHost) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(
                    color: context.ssTextPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Search song, artist, or paste YouTube URL...',
                  prefixIcon:
                      Icon(Icons.search_rounded, color: context.ssPrimary),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchError = null);
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: _onSearchQueryChanged,
                onSubmitted: (_) => _runSearch(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(52, 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: _isSearching ? null : () => _runSearch(),
              child: _isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.search_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Discover Moods
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              'Romantic Acoustic',
              'Lo-Fi Love Chill',
              'Late Night Drive',
              'Ed Sheeran Perfect',
              'Arijit Singh Love',
            ]
                .map((tag) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(tag,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.ssPrimary)),
                        backgroundColor: context.ssSurfaceVariant,
                        side: BorderSide(color: context.ssBorder),
                        onPressed: () => _runSearch(tag),
                      ),
                    ))
                .toList(),
          ),
        ),

        // Recent Search History
        if (_searchHistory.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Searches',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: context.ssTextSecondary)),
              TextButton(
                onPressed: () async {
                  await _repo.clearSearchHistory(user.id);
                  if (mounted) setState(() => _searchHistory = []);
                },
                child: const Text('Clear', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _searchHistory
                .take(8)
                .map((q) => ActionChip(
                      label: Text(q, style: const TextStyle(fontSize: 11)),
                      onPressed: () => _runSearch(q),
                    ))
                .toList(),
          ),
        ],

        if (_searchError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Text(_searchError!,
                style: TextStyle(fontSize: 12, color: context.ssTextPrimary)),
          ),
        ],

        const SizedBox(height: 10),
        if (_searchResults.isEmpty && !_isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'Search any song via YouTube Data API v3 or paste a youtube.com / youtu.be URL for instant 1-unit resolution 🎵',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.ssTextSecondary, fontSize: 12.5),
            ),
          )
        else
          ..._searchResults.map((t) {
            final liked = _isTrackLiked(t.videoId);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
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
                  style: TextStyle(fontSize: 11, color: context.ssTextSecondary),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: amHost ? 'Play Now Together' : 'Suggest to Host',
                      icon: Icon(
                        amHost
                            ? Icons.play_circle_fill_rounded
                            : Icons.front_hand_rounded,
                        color: AppColors.accent,
                      ),
                      onPressed: () {
                        if (amHost) {
                          _sendPlaybackControl('set_track', track: t);
                        } else {
                          _sendPlaybackControl('suggest_track', track: t);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    '🙋 Suggested "${t.title}" to $_partnerName!')),
                          );
                        }
                      },
                    ),
                    if (amHost)
                      IconButton(
                        tooltip: 'Add to Queue',
                        icon: Icon(Icons.playlist_add_rounded,
                            color: context.ssPrimary),
                        onPressed: () async {
                          await _sendPlaybackControl('queue_add', track: t);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Added "${t.title}" to queue')),
                            );
                          }
                        },
                      ),
                    IconButton(
                      tooltip: liked ? 'Unlike' : 'Like',
                      icon: Icon(
                        liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 19,
                        color: AppColors.accent,
                      ),
                      onPressed: () => _toggleLike(t),
                    ),
                    IconButton(
                      tooltip: 'Save to Playlist',
                      icon: Icon(Icons.bookmark_add_outlined,
                          size: 19, color: context.ssPrimary),
                      onPressed: () => _addToPlaylistDialog(t),
                    ),
                  ],
                ),
              ),
            );
          }),

        if (_nextPageToken != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: OutlinedButton.icon(
              onPressed: _isLoadingMore ? null : _loadMoreSearch,
              icon: _isLoadingMore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Load More Songs'),
            ),
          ),
      ],
    );
  }

  Widget _buildQueueTab(MusicRoom room, bool amHost) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Up Next (${room.queue.length})${room.playback.shuffle ? " • Shuffle ON" : ""}',
              style: AppTypography.titleMedium,
            ),
            if (room.queue.isNotEmpty && amHost)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear Queue?'),
                      content: const Text(
                          'Remove all upcoming songs from this shared room queue?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Keep')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _sendPlaybackControl('queue_clear');
                          },
                          child: const Text('Clear Queue'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Clear All'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (room.queue.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Queue is empty. Search songs or tap Play All on a playlist!',
              style: TextStyle(color: context.ssTextSecondary, fontSize: 12),
            ),
          )
        else
          ...List.generate(room.queue.length, (i) {
            final t = room.queue[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: amHost
                    ? () => _sendPlaybackControl('queue_play', index: i)
                    : null,
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
                  style:
                      TextStyle(fontSize: 11, color: context.ssTextSecondary),
                ),
                trailing: amHost
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i > 0)
                            IconButton(
                              tooltip: 'Move Up',
                              icon: const Icon(Icons.arrow_upward_rounded,
                                  size: 18),
                              onPressed: () => _sendPlaybackControl(
                                  'queue_reorder',
                                  oldIndex: i,
                                  newIndex: i - 1),
                            ),
                          if (i < room.queue.length - 1)
                            IconButton(
                              tooltip: 'Move Down',
                              icon: const Icon(Icons.arrow_downward_rounded,
                                  size: 18),
                              onPressed: () => _sendPlaybackControl(
                                  'queue_reorder',
                                  oldIndex: i,
                                  newIndex: i + 1),
                            ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: AppColors.error),
                            onPressed: () =>
                                _sendPlaybackControl('queue_remove', index: i),
                          ),
                        ],
                      )
                    : null,
              ),
            );
          }),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recently Played (${room.recentlyPlayed.length})',
                style: AppTypography.titleMedium),
            if (room.recentlyPlayed.isNotEmpty && amHost)
              TextButton(
                onPressed: () => _sendPlaybackControl('clear_recent'),
                child: const Text('Clear History'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (room.recentlyPlayed.isEmpty)
          Text('No recently played songs yet.',
              style: TextStyle(color: context.ssTextSecondary, fontSize: 12))
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
                subtitle: Text(t.artist,
                    style: TextStyle(
                        fontSize: 11, color: context.ssTextSecondary)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (amHost)
                      IconButton(
                        tooltip: 'Replay',
                        icon:
                            Icon(Icons.replay_rounded, color: context.ssPrimary),
                        onPressed: () =>
                            _sendPlaybackControl('set_track', track: t),
                      ),
                    if (amHost)
                      IconButton(
                        tooltip: 'Remove from Recent',
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: context.ssTextHint),
                        onPressed: () => _sendPlaybackControl('delete_recent',
                            videoId: t.videoId),
                      ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildPlaylistsTab(SoulSyncUser user, MusicRoom room, bool amHost) {
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
              child: ExpansionTile(
                initiallyExpanded: pl.isOurSongs,
                leading: Text(pl.artworkEmoji,
                    style: const TextStyle(fontSize: 22)),
                title: Text(pl.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                subtitle: Text('${pl.songs.length} songs',
                    style: TextStyle(
                        fontSize: 11, color: context.ssTextSecondary)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pl.songs.isNotEmpty && amHost)
                      IconButton(
                        tooltip: 'Play All in Sync',
                        icon: const Icon(Icons.play_circle_filled_rounded,
                            color: AppColors.accent),
                        onPressed: () => _sendPlaybackControl('play_playlist',
                            playlistId: pl.id),
                      ),
                    IconButton(
                      tooltip: 'Rename / Artwork / Delete',
                      icon: Icon(Icons.edit_outlined,
                          size: 18, color: context.ssTextSecondary),
                      onPressed: () => _showPlaylistManageDialog(pl),
                    ),
                  ],
                ),
                children: pl.songs.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'No songs saved here yet. Tap Save on any song!',
                            style: TextStyle(
                                color: context.ssTextSecondary, fontSize: 12),
                          ),
                        ),
                      ]
                    : List.generate(pl.songs.length, (idx) {
                        final s = pl.songs[idx];
                        return ListTile(
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
                            style: TextStyle(
                                fontSize: 11, color: context.ssTextSecondary),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (amHost)
                                IconButton(
                                  tooltip: 'Play Together',
                                  icon: const Icon(Icons.play_arrow_rounded,
                                      color: AppColors.accent),
                                  onPressed: () => _sendPlaybackControl(
                                      'set_track',
                                      track: s),
                                ),
                              if (idx > 0)
                                IconButton(
                                  tooltip: 'Move Up',
                                  icon: const Icon(Icons.arrow_upward_rounded,
                                      size: 16),
                                  onPressed: () async {
                                    await _repo.playlistSongOperation(
                                      coupleId: coupleId,
                                      userId: user.id,
                                      playlistId: pl.id,
                                      operation: 'reorder',
                                      oldIndex: idx,
                                      newIndex: idx - 1,
                                    );
                                    final updated = await _repo.getPlaylists(
                                        coupleId, user.id);
                                    if (mounted) {
                                      setState(() => _playlists = updated);
                                    }
                                  },
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
                                tooltip: 'Remove',
                                icon: Icon(Icons.delete_outline_rounded,
                                    size: 18, color: context.ssTextHint),
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
                        );
                      }),
              ),
            )),
      ],
    );
  }

  Widget _buildCoupleExtrasTab(
    SoulSyncUser user,
    MusicRoom room,
    MusicTrack? curTrack,
    bool amHost,
  ) {
    final coupleId = user.coupleId ?? '';
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 1. Music Recap
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.ssSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.ssBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Our Music Recap 📊', style: AppTypography.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RecapChip(label: 'Sessions', value: '${_recap.sharedSessions}'),
                  _RecapChip(label: 'My Likes', value: '${_recap.likedSongsCount}'),
                  _RecapChip(label: 'Playlists', value: '${_recap.playlistsCount}'),
                  _RecapChip(label: 'Dedications', value: '${_recap.dedicationsCount}'),
                  _RecapChip(label: 'Memories', value: '${_recap.musicalMemoriesCount}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Liked Songs & Opt-in "Our Favourites" Mutual Intersection
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.ssSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.ssBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Liked Songs ❤️ (${_likes.likedSongs.length})',
                            style: AppTypography.titleLarge),
                        Text(
                          'Private by default. Enable sharing to find mutual favourites.',
                          style: TextStyle(
                              fontSize: 11, color: context.ssTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _likes.shareConsent,
                    onChanged: (v) async {
                      final updated = await _repo.likesOp(
                        coupleId: coupleId,
                        userId: user.id,
                        operation: 'toggle_consent',
                        consent: v,
                      );
                      if (mounted) setState(() => _likes = updated);
                    },
                  ),
                ],
              ),
              if (_likes.shareConsent && _likes.partnerShared) ...[
                const SizedBox(height: 8),
                Text(
                  'Our Favourites 💖 ("You both love this song": ${_likes.mutualFavourites.length})',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: context.ssAccent),
                ),
                ..._likes.mutualFavourites.map((m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Text('💖', style: TextStyle(fontSize: 18)),
                      title: Text(m.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: const Text('You both love this song 💖'),
                      trailing: amHost
                          ? IconButton(
                              icon: const Icon(Icons.play_arrow_rounded),
                              onPressed: () =>
                                  _sendPlaybackControl('set_track', track: m),
                            )
                          : null,
                    )),
              ],
              ..._likes.likedSongs.map((s) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(s.thumbnail,
                          width: 40, height: 30, fit: BoxFit.cover),
                    ),
                    title: Text(s.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.artist,
                        style: TextStyle(
                            fontSize: 11, color: context.ssTextSecondary)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (amHost)
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded),
                            onPressed: () =>
                                _sendPlaybackControl('set_track', track: s),
                          ),
                        IconButton(
                          icon: const Icon(Icons.favorite_rounded,
                              size: 18, color: AppColors.accent),
                          onPressed: () => _toggleLike(s),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Song Dedications
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.ssSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.ssBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Song Dedications 💌', style: AppTypography.titleLarge),
                  if (curTrack != null)
                    TextButton.icon(
                      onPressed: () => _showDedicateDialog(curTrack),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Dedicate Current'),
                    ),
                ],
              ),
              if (_dedications.isEmpty)
                Text('No dedications yet. Dedicate the song playing right now!',
                    style:
                        TextStyle(fontSize: 12, color: context.ssTextSecondary))
              else
                ..._dedications.map((d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          Text(d.emoji, style: const TextStyle(fontSize: 22)),
                      title: Text('${d.senderName}: ${d.track.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Text('"${d.message}"',
                          style: TextStyle(
                              fontSize: 12, color: context.ssTextSecondary)),
                      trailing: amHost
                          ? IconButton(
                              icon: const Icon(Icons.play_arrow_rounded,
                                  color: AppColors.accent),
                              onPressed: () => _sendPlaybackControl('set_track',
                                  track: d.track),
                            )
                          : null,
                    )),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Musical Memories CRUD
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.ssSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.ssBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Musical Memories 📸', style: AppTypography.titleLarge),
                  TextButton.icon(
                    onPressed: () => _showMemoryDialog(track: curTrack),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Memory'),
                  ),
                ],
              ),
              if (_memories.isEmpty)
                Text('Pin a meaningful song + story to remember special moments.',
                    style:
                        TextStyle(fontSize: 12, color: context.ssTextSecondary))
              else
                ..._memories.map((m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${m.title} (${m.occasion})',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Text('${m.note}\n${m.date}',
                          style: TextStyle(
                              fontSize: 11.5, color: context.ssTextSecondary)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m.track.videoId.isNotEmpty && amHost)
                            IconButton(
                              icon: const Icon(Icons.play_arrow_rounded,
                                  color: AppColors.accent),
                              onPressed: () => _sendPlaybackControl('set_track',
                                  track: m.track),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _showMemoryDialog(existing: m),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18, color: AppColors.error),
                            onPressed: () async {
                              await _repo.musicalMemoryOp(
                                coupleId: coupleId,
                                userId: user.id,
                                operation: 'delete',
                                memoryId: m.id,
                              );
                              await _refreshSecondaryData(coupleId, user.id);
                            },
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color bgColor;

  _StickyTabBarDelegate(this._tabBar, this.bgColor);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: bgColor, child: _tabBar);
  }

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) =>
      bgColor != oldDelegate.bgColor;
}

class _RecapChip extends StatelessWidget {
  final String label;
  final String value;

  const _RecapChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.ssSurfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: context.ssPrimary)),
          Text(label,
              style:
                  TextStyle(fontSize: 10.5, color: context.ssTextSecondary)),
        ],
      ),
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
              isOnline ? AppColors.accent : Colors.white24,
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
                  color: isOnline ? const Color(0xFF80E27E) : Colors.white60,
                  fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
