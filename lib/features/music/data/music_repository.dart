import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../domain/models/music_models.dart';

class MusicRoomResponse {
  final MusicRoom? room;
  final String? partnerId;
  final String partnerName;
  final String? partnerAvatar;

  const MusicRoomResponse({
    this.room,
    this.partnerId,
    required this.partnerName,
    this.partnerAvatar,
  });
}

class MusicRepository {
  static const _uuid = Uuid();
  String get _base => AuthNotifier.apiBaseUrl;

  Future<MusicSearchResponse> searchSongs(
    String query,
    String userId, {
    String? pageToken,
  }) async {
    final pt = pageToken != null && pageToken.isNotEmpty
        ? '&page_token=${Uri.encodeComponent(pageToken)}'
        : '';
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/search?q=${Uri.encodeComponent(query)}&user_id=${Uri.encodeComponent(userId)}$pt'))
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Search failed (${res.statusCode})');
    }
    final list = body['results'] as List<dynamic>? ?? [];
    return MusicSearchResponse(
      results: list
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
      nextPageToken: body['next_page_token']?.toString(),
      resolvedUrl: body['resolved_url'] == true,
      cached: body['cached'] == true,
      quotaUsedToday: (body['quota_used_today'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<String>> getSearchHistory(String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/search-history?user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['history'] as List<dynamic>? ?? [];
    return list.map((e) => e.toString()).toList();
  }

  Future<void> clearSearchHistory(String userId) async {
    await http
        .post(
          Uri.parse('$_base/api/music/search-history/clear'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId}),
        )
        .timeout(const Duration(seconds: 5));
  }

  Future<MusicRoomResponse> getRoomState(String coupleId, String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/room/state?couple_id=${Uri.encodeComponent(coupleId)}&user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Unable to load room');
    }
    final partner = body['partner'] as Map<String, dynamic>? ?? {};
    final roomJson = body['room'] as Map<String, dynamic>?;
    return MusicRoomResponse(
      room: roomJson != null ? MusicRoom.fromJson(roomJson) : null,
      partnerId: partner['id']?.toString(),
      partnerName: partner['name']?.toString() ?? 'Partner',
      partnerAvatar: partner['avatar_url']?.toString(),
    );
  }

  Future<MusicRoomResponse> createOrJoinRoom({
    required String coupleId,
    required String userId,
    String mode = 'together',
    bool invitePartner = false,
    bool isCreate = false,
  }) async {
    final endpoint =
        isCreate ? '/api/music/room/create' : '/api/music/room/join';
    final res = await http
        .post(
          Uri.parse('$_base$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'mode': mode,
            'invite_partner': invitePartner,
          }),
        )
        .timeout(const Duration(seconds: 6));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Unable to join room');
    }
    final partner = body['partner'] as Map<String, dynamic>? ?? {};
    return MusicRoomResponse(
      room: MusicRoom.fromJson(body['room'] as Map<String, dynamic>),
      partnerId: partner['id']?.toString(),
      partnerName: partner['name']?.toString() ?? 'Partner',
      partnerAvatar: partner['avatar_url']?.toString(),
    );
  }

  Future<void> leaveRoom(String coupleId, String userId) async {
    try {
      await http
          .post(
            Uri.parse('$_base/api/music/room/leave'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'couple_id': coupleId, 'user_id': userId}),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> sendReaction({
    required String coupleId,
    required String userId,
    required String emoji,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/room/reaction'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'emoji': emoji,
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Reaction failed');
    }
  }

  Future<MusicRoom> sendControl({
    required String coupleId,
    required String userId,
    required String action,
    MusicTrack? track,
    double? positionSeconds,
    String? mode,
    String? repeatMode,
    bool? shuffle,
    bool? autoPlay,
    bool? buffering,
    String? playerState,
    int? index,
    int? oldIndex,
    int? newIndex,
    String? playlistId,
    String? suggestionId,
    String? videoId,
    int? minutes,
  }) async {
    final payload = <String, dynamic>{
      'couple_id': coupleId,
      'user_id': userId,
      'action': action,
      'command_id': _uuid.v4(),
      if (track != null) 'track': track.toJson(),
      if (positionSeconds != null) 'position_seconds': positionSeconds,
      if (mode != null) 'mode': mode,
      if (repeatMode != null) 'repeat_mode': repeatMode,
      if (shuffle != null) 'shuffle': shuffle,
      if (autoPlay != null) 'auto_play': autoPlay,
      if (buffering != null) 'buffering': buffering,
      if (playerState != null) 'player_state': playerState,
      if (index != null) 'index': index,
      if (oldIndex != null) 'old_index': oldIndex,
      if (newIndex != null) 'new_index': newIndex,
      if (playlistId != null) 'playlist_id': playlistId,
      if (suggestionId != null) 'suggestion_id': suggestionId,
      if (videoId != null) 'video_id': videoId,
      if (minutes != null) 'minutes': minutes,
    };

    final res = await http
        .post(
          Uri.parse('$_base/api/music/room/control'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 6));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Control rejected');
    }
    return MusicRoom.fromJson(body['room'] as Map<String, dynamic>);
  }

  Future<List<MusicPlaylist>> getPlaylists(String coupleId, String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/playlists?couple_id=${Uri.encodeComponent(coupleId)}&user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Failed to load playlists');
    }
    final list = body['playlists'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MusicPlaylist.fromJson)
        .toList();
  }

  Future<MusicPlaylist> createPlaylist(
    String coupleId,
    String userId,
    String name, {
    String artworkEmoji = '🎶',
    String artworkColor = '#6C3EBC',
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/playlists'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'operation': 'create',
            'name': name,
            'artwork_emoji': artworkEmoji,
            'artwork_color': artworkColor,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Failed to create playlist');
    }
    return MusicPlaylist.fromJson(body['playlist'] as Map<String, dynamic>);
  }

  Future<void> playlistOp({
    required String coupleId,
    required String userId,
    required String playlistId,
    required String operation, // 'rename' | 'delete' | 'artwork'
    String? name,
    String? artworkEmoji,
    String? artworkColor,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/playlists'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'playlist_id': playlistId,
            'operation': operation,
            if (name != null) 'name': name,
            if (artworkEmoji != null) 'artwork_emoji': artworkEmoji,
            if (artworkColor != null) 'artwork_color': artworkColor,
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Playlist action failed');
    }
  }

  Future<MusicPlaylist> playlistSongOperation({
    required String coupleId,
    required String userId,
    String? playlistId,
    required String operation, // 'add' | 'remove' | 'toggle_our_song' | 'reorder'
    MusicTrack? track,
    String? videoId,
    bool isOurSong = false,
    int? oldIndex,
    int? newIndex,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/playlists/song'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            if (playlistId != null) 'playlist_id': playlistId,
            'operation': operation,
            if (track != null) 'track': track.toJson(),
            if (videoId != null) 'video_id': videoId,
            'is_our_song': isOurSong,
            if (oldIndex != null) 'old_index': oldIndex,
            if (newIndex != null) 'new_index': newIndex,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Playlist update failed');
    }
    return MusicPlaylist.fromJson(body['playlist'] as Map<String, dynamic>);
  }

  Future<MusicLikesState> getLikes(String coupleId, String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/likes?couple_id=${Uri.encodeComponent(coupleId)}&user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Failed to load liked songs');
    }
    return MusicLikesState.fromJson(body);
  }

  Future<MusicLikesState> likesOp({
    required String coupleId,
    required String userId,
    required String operation, // 'like' | 'unlike' | 'toggle_consent'
    MusicTrack? track,
    String? videoId,
    bool? consent,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/likes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'operation': operation,
            if (track != null) 'track': track.toJson(),
            if (videoId != null) 'video_id': videoId,
            if (consent != null) 'consent': consent,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Failed to update likes');
    }
    return MusicLikesState.fromJson(body);
  }

  Future<List<MusicDedication>> getDedications(
      String coupleId, String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/dedications?couple_id=${Uri.encodeComponent(coupleId)}&user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['dedications'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MusicDedication.fromJson)
        .toList();
  }

  Future<void> sendDedication({
    required String coupleId,
    required String userId,
    required MusicTrack track,
    required String message,
    String emoji = '💌',
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/dedications'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'track': track.toJson(),
            'message': message,
            'emoji': emoji,
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 201 && res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to send dedication');
    }
  }

  Future<List<MusicMemoryItem>> getMusicalMemories(
      String coupleId, String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/memories?couple_id=${Uri.encodeComponent(coupleId)}&user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['memories'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MusicMemoryItem.fromJson)
        .toList();
  }

  Future<void> musicalMemoryOp({
    required String coupleId,
    required String userId,
    required String operation, // 'create' | 'edit' | 'delete'
    String? memoryId,
    MusicTrack? track,
    String? title,
    String? note,
    String? occasion,
    String? date,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/memories'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'operation': operation,
            if (memoryId != null) 'memory_id': memoryId,
            if (track != null) 'track': track.toJson(),
            if (title != null) 'title': title,
            if (note != null) 'note': note,
            if (occasion != null) 'occasion': occasion,
            if (date != null) 'date': date,
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200 && res.statusCode != 201) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Memory update failed');
    }
  }

  Future<MusicRecap> getRecap(String coupleId, String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/recap?couple_id=${Uri.encodeComponent(coupleId)}&user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return const MusicRecap();
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return MusicRecap.fromJson(body['recap'] as Map<String, dynamic>? ?? {});
  }

  Future<void> reportTrack({
    required String coupleId,
    required String userId,
    required String videoId,
    required String title,
    required String reason,
  }) async {
    await http
        .post(
          Uri.parse('$_base/api/music/report'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'video_id': videoId,
            'title': title,
            'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 5));
  }
}
