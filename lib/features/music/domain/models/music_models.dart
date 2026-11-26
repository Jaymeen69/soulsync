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

class MusicSearchResponse {
  final List<MusicTrack> results;
  final String? nextPageToken;
  final bool resolvedUrl;
  final bool cached;
  final int quotaUsedToday;

  const MusicSearchResponse({
    required this.results,
    this.nextPageToken,
    this.resolvedUrl = false,
    this.cached = false,
    this.quotaUsedToday = 0,
  });
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

class MusicSuggestion {
  final String id;
  final String suggestedBy;
  final MusicTrack track;
  final String createdAt;

  const MusicSuggestion({
    required this.id,
    required this.suggestedBy,
    required this.track,
    required this.createdAt,
  });

  factory MusicSuggestion.fromJson(Map<String, dynamic> json) =>
      MusicSuggestion(
        id: json['id']?.toString() ?? '',
        suggestedBy: json['suggested_by']?.toString() ?? 'Partner',
        track: MusicTrack.fromJson(
            json['track'] as Map<String, dynamic>? ?? const {}),
        createdAt: json['created_at']?.toString() ?? '',
      );
}

class MusicSleepTimer {
  final int minutes;
  final String proposedById;
  final String proposedByName;
  final String status; // 'pending' | 'active' | 'expired'
  final int? expiresAtMs;
  final String? acceptedBy;

  const MusicSleepTimer({
    required this.minutes,
    required this.proposedById,
    required this.proposedByName,
    required this.status,
    this.expiresAtMs,
    this.acceptedBy,
  });

  factory MusicSleepTimer.fromJson(Map<String, dynamic> json) =>
      MusicSleepTimer(
        minutes: (json['minutes'] as num?)?.toInt() ?? 30,
        proposedById: json['proposed_by_id']?.toString() ?? '',
        proposedByName: json['proposed_by_name']?.toString() ?? 'Partner',
        status: json['status']?.toString() ?? 'pending',
        expiresAtMs: (json['expires_at_ms'] as num?)?.toInt(),
        acceptedBy: json['accepted_by']?.toString(),
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
  final List<MusicSuggestion> suggestions;
  final MusicSleepTimer? sleepTimer;
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
    this.suggestions = const [],
    this.sleepTimer,
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
    final rawSuggestions = json['suggestions'] as List<dynamic>? ?? [];
    final rawTimer = json['sleep_timer'];

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
      suggestions: rawSuggestions
          .whereType<Map<String, dynamic>>()
          .map(MusicSuggestion.fromJson)
          .toList(),
      sleepTimer: rawTimer is Map<String, dynamic>
          ? MusicSleepTimer.fromJson(rawTimer)
          : null,
      serverNowMs: (json['server_now_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class MusicPlaylist {
  final String id;
  final String coupleId;
  final String name;
  final String artworkEmoji;
  final String artworkColor;
  final bool isOurSongs;
  final String createdBy;
  final List<MusicTrack> songs;

  const MusicPlaylist({
    required this.id,
    required this.coupleId,
    required this.name,
    this.artworkEmoji = '🎶',
    this.artworkColor = '#6C3EBC',
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
      artworkEmoji: json['artwork_emoji']?.toString() ?? '🎶',
      artworkColor: json['artwork_color']?.toString() ?? '#6C3EBC',
      isOurSongs: json['is_our_songs'] == true,
      createdBy: json['created_by']?.toString() ?? 'Partner',
      songs: rawSongs
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
    );
  }
}

class MusicLikesState {
  final List<MusicTrack> likedSongs;
  final bool shareConsent;
  final bool partnerShared;
  final List<MusicTrack> mutualFavourites;

  const MusicLikesState({
    this.likedSongs = const [],
    this.shareConsent = false,
    this.partnerShared = false,
    this.mutualFavourites = const [],
  });

  factory MusicLikesState.fromJson(Map<String, dynamic> json) {
    final rawLikes = json['liked_songs'] as List<dynamic>? ?? [];
    final rawMutual = json['mutual_favourites'] as List<dynamic>? ?? [];
    return MusicLikesState(
      likedSongs: rawLikes
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
      shareConsent: json['share_consent'] == true,
      partnerShared: json['partner_shared'] == true,
      mutualFavourites: rawMutual
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
    );
  }
}

class MusicDedication {
  final String id;
  final String senderId;
  final String senderName;
  final MusicTrack track;
  final String message;
  final String emoji;
  final String createdAt;

  const MusicDedication({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.track,
    required this.message,
    required this.emoji,
    required this.createdAt,
  });

  factory MusicDedication.fromJson(Map<String, dynamic> json) =>
      MusicDedication(
        id: json['id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        senderName: json['sender_name']?.toString() ?? 'Partner',
        track: MusicTrack.fromJson(
            json['track'] as Map<String, dynamic>? ?? const {}),
        message: json['message']?.toString() ?? '',
        emoji: json['emoji']?.toString() ?? '💌',
        createdAt: json['created_at']?.toString() ?? '',
      );
}

class MusicMemoryItem {
  final String id;
  final String creatorName;
  final MusicTrack track;
  final String title;
  final String note;
  final String occasion;
  final String date;

  const MusicMemoryItem({
    required this.id,
    required this.creatorName,
    required this.track,
    required this.title,
    required this.note,
    required this.occasion,
    required this.date,
  });

  factory MusicMemoryItem.fromJson(Map<String, dynamic> json) =>
      MusicMemoryItem(
        id: json['id']?.toString() ?? '',
        creatorName: json['creator_name']?.toString() ?? 'Partner',
        track: MusicTrack.fromJson(
            json['track'] as Map<String, dynamic>? ?? const {}),
        title: json['title']?.toString() ?? 'Musical Memory',
        note: json['note']?.toString() ?? '',
        occasion: json['occasion']?.toString() ?? 'Special Moment',
        date: json['date']?.toString() ?? '',
      );
}

class MusicRecap {
  final int sharedSessions;
  final int likedSongsCount;
  final int playlistsCount;
  final int dedicationsCount;
  final int musicalMemoriesCount;
  final int recentlyPlayedCount;

  const MusicRecap({
    this.sharedSessions = 0,
    this.likedSongsCount = 0,
    this.playlistsCount = 0,
    this.dedicationsCount = 0,
    this.musicalMemoriesCount = 0,
    this.recentlyPlayedCount = 0,
  });

  factory MusicRecap.fromJson(Map<String, dynamic> json) => MusicRecap(
        sharedSessions: (json['shared_sessions'] as num?)?.toInt() ?? 0,
        likedSongsCount: (json['liked_songs_count'] as num?)?.toInt() ?? 0,
        playlistsCount: (json['playlists_count'] as num?)?.toInt() ?? 0,
        dedicationsCount: (json['dedications_count'] as num?)?.toInt() ?? 0,
        musicalMemoriesCount:
            (json['musical_memories_count'] as num?)?.toInt() ?? 0,
        recentlyPlayedCount:
            (json['recently_played_count'] as num?)?.toInt() ?? 0,
      );
}
