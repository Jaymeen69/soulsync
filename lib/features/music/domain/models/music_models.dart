class MusicTrack {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnail;
  final int durationSeconds;
  final String? addedBy;
  final bool isOurSong;
  final String? playedAt;

  const MusicTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    this.durationSeconds = 0,
    this.addedBy,
    this.isOurSong = false,
    this.playedAt,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
        videoId: json['video_id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Untitled Track',
        artist: json['artist']?.toString() ?? 'YouTube',
        thumbnail: json['thumbnail']?.toString() ??
            'https://img.youtube.com/vi/${json['video_id'] ?? ''}/hqdefault.jpg',
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        addedBy: json['added_by']?.toString(),
        isOurSong: json['is_our_song'] == true,
        playedAt: json['played_at']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'video_id': videoId,
        'title': title,
        'artist': artist,
        'thumbnail': thumbnail,
        'duration_seconds': durationSeconds,
        if (addedBy != null) 'added_by': addedBy,
        'is_our_song': isOurSong,
      };
}

class MusicParticipant {
  final String userId;
  final String name;
  final String? avatarUrl;
  final bool online;
  final bool buffering;
  final String state;

  const MusicParticipant({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.online = false,
    this.buffering = false,
    this.state = 'listening',
  });

  factory MusicParticipant.fromJson(Map<String, dynamic> json) =>
      MusicParticipant(
        userId: json['user_id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Partner',
        avatarUrl: json['avatar_url']?.toString(),
        online: json['online'] == true,
        buffering: json['buffering'] == true,
        state: json['state']?.toString() ?? 'offline',
      );
}

class MusicPlaybackState {
  final String? videoId;
  final String? title;
  final String? artist;
  final String? thumbnail;
  final int durationSeconds;
  final bool isPlaying;
  final double positionSeconds;
  final double livePositionSeconds;
  final double playbackRate;
  final int anchorTimestampMs;
  final int serverNowMs;
  final String repeatMode;
  final bool shuffle;
  final int eventSeq;
  final String? updatedBy;

  const MusicPlaybackState({
    this.videoId,
    this.title,
    this.artist,
    this.thumbnail,
    this.durationSeconds = 0,
    this.isPlaying = false,
    this.positionSeconds = 0.0,
    this.livePositionSeconds = 0.0,
    this.playbackRate = 1.0,
    this.anchorTimestampMs = 0,
    this.serverNowMs = 0,
    this.repeatMode = 'none',
    this.shuffle = false,
    this.eventSeq = 0,
    this.updatedBy,
  });

  factory MusicPlaybackState.fromJson(Map<String, dynamic> json) =>
      MusicPlaybackState(
        videoId: json['video_id']?.toString(),
        title: json['title']?.toString(),
        artist: json['artist']?.toString(),
        thumbnail: json['thumbnail']?.toString(),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        isPlaying: json['is_playing'] == true,
        positionSeconds: (json['position_seconds'] as num?)?.toDouble() ?? 0.0,
        livePositionSeconds:
            (json['live_position_seconds'] as num?)?.toDouble() ??
                (json['position_seconds'] as num?)?.toDouble() ??
                0.0,
        playbackRate: (json['playback_rate'] as num?)?.toDouble() ?? 1.0,
        anchorTimestampMs:
            (json['anchor_timestamp_ms'] as num?)?.toInt() ?? 0,
        serverNowMs: (json['server_now_ms'] as num?)?.toInt() ?? 0,
        repeatMode: json['repeat_mode']?.toString() ?? 'none',
        shuffle: json['shuffle'] == true,
        eventSeq: (json['event_seq'] as num?)?.toInt() ?? 0,
        updatedBy: json['updated_by']?.toString(),
      );
}

class MusicRoom {
  final String id;
  final String coupleId;
  final String creatorId;
  final String hostId;
  final String mode; // 'host' | 'together'
  final Map<String, MusicParticipant> participants;
  final MusicPlaybackState playback;
  final List<MusicTrack> queue;
  final List<MusicTrack> recentlyPlayed;
  final int serverNowMs;

  const MusicRoom({
    required this.id,
    required this.coupleId,
    required this.creatorId,
    required this.hostId,
    required this.mode,
    required this.participants,
    required this.playback,
    required this.queue,
    required this.recentlyPlayed,
    required this.serverNowMs,
  });

  factory MusicRoom.fromJson(Map<String, dynamic> json) {
    final rawParts = json['participants'] as Map<String, dynamic>? ?? {};
    final parsedParts = <String, MusicParticipant>{};
    rawParts.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        parsedParts[k] = MusicParticipant.fromJson(v);
      }
    });

    final rawQueue = json['queue'] as List<dynamic>? ?? [];
    final rawRecent = json['recently_played'] as List<dynamic>? ?? [];

    return MusicRoom(
      id: json['id']?.toString() ?? '',
      coupleId: json['couple_id']?.toString() ?? '',
      creatorId: json['creator_id']?.toString() ?? '',
      hostId: json['host_id']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'together',
      participants: parsedParts,
      playback: MusicPlaybackState.fromJson(
          json['playback'] as Map<String, dynamic>? ?? {}),
      queue: rawQueue
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
      recentlyPlayed: rawRecent
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
      serverNowMs: (json['server_now_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class MusicPlaylist {
  final String id;
  final String coupleId;
  final String name;
  final bool isOurSongs;
  final String createdBy;
  final List<MusicTrack> songs;

  const MusicPlaylist({
    required this.id,
    required this.coupleId,
    required this.name,
    this.isOurSongs = false,
    required this.createdBy,
    required this.songs,
  });

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'] as List<dynamic>? ?? [];
    return MusicPlaylist(
      id: json['id']?.toString() ?? '',
      coupleId: json['couple_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Playlist',
      isOurSongs: json['is_our_songs'] == true,
      createdBy: json['created_by']?.toString() ?? 'Partner',
      songs: rawSongs
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
    );
  }
}
