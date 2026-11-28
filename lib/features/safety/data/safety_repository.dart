import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../domain/models/safety_models.dart';

class SafetyRepository {
  static const _uuid = Uuid();
  String get _base => AuthNotifier.apiBaseUrl;

  Future<SafetyStateModel> getState(String userId, String coupleId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/safety/state?user_id=${Uri.encodeComponent(userId)}&couple_id=${Uri.encodeComponent(coupleId)}'))
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Unable to load SoulSafe status');
    }
    return SafetyStateModel.fromJson(body['safety'] as Map<String, dynamic>);
  }

  Future<SafetyStateModel> updateConsent({
    required String userId,
    required String coupleId,
    required String action,
    String? durationKey,
    String? travelMode,
    bool? drivingMode,
    bool? dailySharing,
    int? historyRetentionDays,
    Map<String, bool>? consents,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/safety/consent'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'action': action,
            if (durationKey != null) 'duration_key': durationKey,
            if (travelMode != null) 'travel_mode': travelMode,
            if (drivingMode != null) 'driving_mode': drivingMode,
            if (dailySharing != null) 'daily_sharing': dailySharing,
            if (historyRetentionDays != null)
              'history_retention_days': historyRetentionDays,
            if (consents != null) 'consents': consents,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Failed to update sharing consent');
    }
    return SafetyStateModel.fromJson(body['safety'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> pushLocation({
    required String userId,
    required String coupleId,
    required int sequence,
    required double lat,
    required double lng,
    required double horizontalAccuracyM,
    double? speedMps,
    double? bearing,
    String? travelMode,
    int? batteryPct,
    bool? batteryCharging,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/safety/location'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'sequence': sequence,
            'lat': lat,
            'lng': lng,
            'horizontal_accuracy_m': horizontalAccuracyM,
            if (speedMps != null && speedMps >= 0) 'speed_mps': speedMps,
            if (bearing != null) 'bearing': bearing,
            if (travelMode != null) 'travel_mode': travelMode,
            if (batteryPct != null) 'battery_pct': batteryPct,
            if (batteryCharging != null) 'battery_charging': batteryCharging,
            'observed_at_ms': DateTime.now().millisecondsSinceEpoch,
            'observed_at': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Location push rejected');
    }
    return body;
  }

  Future<SafetyStateModel> agreementOp({
    required String userId,
    required String coupleId,
    required String operation, // propose | accept | reject | counter | revoke
    String? targetUserId,
    double? thresholdKmh,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/safety/agreement'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'operation': operation,
            if (targetUserId != null) 'target_user_id': targetUserId,
            if (thresholdKmh != null) 'threshold_kmh': thresholdKmh,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Agreement update failed');
    }
    return SafetyStateModel.fromJson(body['safety'] as Map<String, dynamic>);
  }

  Future<void> triggerAlert({
    required String userId,
    required String coupleId,
    required double speedKmh,
    required double thresholdKmh,
    int sustainedSeconds = 15,
    bool notifyPartner = true,
  }) async {
    await http
        .post(
          Uri.parse('$_base/api/safety/alert'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'event_id': 'alt_${_uuid.v4()}',
            'speed_kmh': speedKmh,
            'threshold_kmh': thresholdKmh,
            'sustained_seconds': sustainedSeconds,
            'notify_partner': notifyPartner,
          }),
        )
        .timeout(const Duration(seconds: 25));
  }

  Future<SafetyStateModel> safeZoneOp({
    required String userId,
    required String coupleId,
    required String operation, // create | delete | event
    String? name,
    double? lat,
    double? lng,
    int? radiusM,
    String? zoneId,
    String? zoneName,
    String? eventType,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/safety/safe-zones'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'owner_id': userId,
            'operation': operation,
            if (name != null) 'name': name,
            if (lat != null) 'lat': lat,
            if (lng != null) 'lng': lng,
            if (radiusM != null) 'radius_m': radiusM,
            if (zoneId != null) 'zone_id': zoneId,
            if (zoneName != null) 'zone_name': zoneName,
            if (eventType != null) 'event_type': eventType,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Safe zone update failed');
    }
    return SafetyStateModel.fromJson(body['safety'] as Map<String, dynamic>);
  }

  Future<SafetyStateModel> journeyOp({
    required String userId,
    required String coupleId,
    required String operation, // start | end | reached_safely
    String? travelMode,
    Map<String, dynamic>? destination,
    String? message,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/safety/journey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'operation': operation,
            if (travelMode != null) 'travel_mode': travelMode,
            if (destination != null) 'destination': destination,
            if (message != null) 'message': message,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Journey update failed');
    }
    return SafetyStateModel.fromJson(body['safety'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getRouteEstimate({
    required String userId,
    required String coupleId,
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String travelMode = 'car',
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/safety/route'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'origin_lat': originLat,
            'origin_lng': originLng,
            'dest_lat': destLat,
            'dest_lng': destLng,
            'travel_mode': travelMode,
          }),
        )
        .timeout(const Duration(seconds: 25));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendSos({
    required String userId,
    required String coupleId,
    required String message,
    double? lat,
    double? lng,
    bool consentOneTimeLocation = true,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_base/api/safety/sos'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'event_id': 'sos_${_uuid.v4()}',
            'message': message,
            if (lat != null) 'lat': lat,
            if (lng != null) 'lng': lng,
            'consent_one_time_location': consentOneTimeLocation,
          }),
        )
        .timeout(const Duration(seconds: 25));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    final res = await http
        .get(Uri.parse(
            '$_base/api/safety/history?user_id=${Uri.encodeComponent(userId)}'))
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['history'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
  }

  Future<void> clearHistory(String userId, String coupleId) async {
    await http
        .post(
          Uri.parse('$_base/api/safety/history/clear'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId, 'couple_id': coupleId}),
        )
        .timeout(const Duration(seconds: 25));
  }

  Future<void> updateNotifPrefs(
      String userId, String coupleId, Map<String, bool> prefs) async {
    await http
        .post(
          Uri.parse('$_base/api/safety/notif-prefs'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'couple_id': coupleId,
            'prefs': prefs,
          }),
        )
        .timeout(const Duration(seconds: 25));
  }
}
