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

  Future<List<MusicTrack>> searchSongs(String query, String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/music/search?q=${Uri.encodeComponent(query)}&user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Search failed (${res.statusCode})');
    }
    final list = body['results'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MusicTrack.fromJson)
        .toList();
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
    final endpoint = isCreate ? '/api/music/room/create' : '/api/music/room/join';
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
      String coupleId, String userId, String name) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/music/playlists'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'couple_id': coupleId,
            'user_id': userId,
            'name': name,
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Failed to create playlist');
    }
    return MusicPlaylist.fromJson(body['playlist'] as Map<String, dynamic>);
  }

  Future<MusicPlaylist> playlistSongOperation({
    required String coupleId,
    required String userId,
    String? playlistId,
    required String operation, // 'add' | 'remove' | 'toggle_our_song'
    MusicTrack? track,
    String? videoId,
    bool isOurSong = false,
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
          }),
        )
        .timeout(const Duration(seconds: 5));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Playlist update failed');
    }
    return MusicPlaylist.fromJson(body['playlist'] as Map<String, dynamic>);
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
