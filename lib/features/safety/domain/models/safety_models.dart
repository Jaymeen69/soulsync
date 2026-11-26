import 'dart:math' as math;

enum TravelMode {
  car('car', 'Car', '🚗'),
  bike('bike', 'Bike', '🏍️'),
  walking('walking', 'Walking', '🚶'),
  stationary('stationary', 'Stationary', '🛑'),
  cycling('cycling', 'Cycling', '🚲'),
  inVehicle('in_vehicle', 'Vehicle', '🚙'),
  other('other', 'Other', '📍');

  const TravelMode(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;

  static TravelMode fromId(String? val) {
    return TravelMode.values.firstWhere(
      (e) => e.id == val,
      orElse: () => TravelMode.stationary,
    );
  }
}

class HaversineCalculator {
  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000.0;
    final p1 = lat1 * math.pi / 180.0;
    final p2 = lat2 * math.pi / 180.0;
    final dp = (lat2 - lat1) * math.pi / 180.0;
    final dl = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(math.max(0.0, 1.0 - a)));
    return r * c;
  }

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    return distanceMeters(lat1, lng1, lat2, lng2) / 1000.0;
  }
}

class SafetyConsents {
  final bool location;
  final bool speed;
  final bool battery;
  final bool destination;
  final bool history;
  final bool safeZones;

  const SafetyConsents({
    this.location = false,
    this.speed = true,
    this.battery = false,
    this.destination = false,
    this.history = false,
    this.safeZones = false,
  });

  factory SafetyConsents.fromJson(Map<String, dynamic> json) => SafetyConsents(
        location: json['location'] == true,
        speed: json['speed'] != false,
        battery: json['battery'] == true,
        destination: json['destination'] == true,
        history: json['history'] == true,
        safeZones: json['safe_zones'] == true,
      );

  Map<String, dynamic> toJson() => {
        'location': location,
        'speed': speed,
        'battery': battery,
        'destination': destination,
        'history': history,
        'safe_zones': safeZones,
      };
}

class SafetyLocationFix {
  final double lat;
  final double lng;
  final double accuracyM;
  final double? bearing;
  final String? observedAt;
  final String? serverReceivedAt;
  final double ageSeconds;

  const SafetyLocationFix({
    required this.lat,
    required this.lng,
    this.accuracyM = 25.0,
    this.bearing,
    this.observedAt,
    this.serverReceivedAt,
    this.ageSeconds = 0.0,
  });

  factory SafetyLocationFix.fromJson(Map<String, dynamic> json) =>
      SafetyLocationFix(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble() ?? 25.0,
        bearing: (json['bearing'] as num?)?.toDouble(),
        observedAt: json['observed_at']?.toString(),
        serverReceivedAt: json['server_received_at']?.toString(),
        ageSeconds: (json['age_seconds'] as num?)?.toDouble() ?? 0.0,
      );
}

class SafetyPartnerView {
  final String userId;
  final String name;
  final String sharingStatus; // stopped | active | paused | expired
  final bool isLive;
  final String freshness; // live | delayed | stale | paused | stopped | expired | unavailable
  final SafetyLocationFix? location;
  final TravelMode travelMode;
  final bool drivingMode;
  final double? speedKmh;
  final bool speedAvailable;
  final double? accuracyM;
  final String? lastUpdatedAt;
  final String? expiresAt;
  final int? batteryPercent;
  final bool? batteryCharging;
  final Map<String, dynamic>? journey;

  const SafetyPartnerView({
    required this.userId,
    required this.name,
    required this.sharingStatus,
    required this.isLive,
    required this.freshness,
    this.location,
    this.travelMode = TravelMode.stationary,
    this.drivingMode = false,
    this.speedKmh,
    this.speedAvailable = false,
    this.accuracyM,
    this.lastUpdatedAt,
    this.expiresAt,
    this.batteryPercent,
    this.batteryCharging,
    this.journey,
  });

  factory SafetyPartnerView.fromJson(Map<String, dynamic> json) {
    final locJson = json['location'] as Map<String, dynamic>?;
    final batJson = json['battery'] as Map<String, dynamic>?;
    return SafetyPartnerView(
      userId: json['user_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Partner',
      sharingStatus: json['sharing_status']?.toString() ?? 'stopped',
      isLive: json['is_live'] == true,
      freshness: json['freshness']?.toString() ?? 'unavailable',
      location: locJson != null ? SafetyLocationFix.fromJson(locJson) : null,
      travelMode: TravelMode.fromId(json['travel_mode']?.toString()),
      drivingMode: json['driving_mode'] == true,
      speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
      speedAvailable: json['speed_available'] == true,
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      lastUpdatedAt: json['last_updated_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
      batteryPercent: (batJson?['percent'] as num?)?.toInt(),
      batteryCharging: batJson?['charging'] as bool?,
      journey: json['journey'] as Map<String, dynamic>?,
    );
  }
}

class SpeedAgreement {
  final String targetUserId;
  final String? proposedBy;
  final double? activeThresholdKmh;
  final double? pendingThresholdKmh;
  final String status; // none | pending | accepted | rejected | revoked
  final int version;
  final String? acceptedAt;

  const SpeedAgreement({
    required this.targetUserId,
    this.proposedBy,
    this.activeThresholdKmh,
    this.pendingThresholdKmh,
    this.status = 'none',
    this.version = 0,
    this.acceptedAt,
  });

  factory SpeedAgreement.fromJson(Map<String, dynamic> json) => SpeedAgreement(
        targetUserId: json['target_user_id']?.toString() ?? '',
        proposedBy: json['proposed_by']?.toString(),
        activeThresholdKmh:
            (json['active_threshold_kmh'] as num?)?.toDouble(),
        pendingThresholdKmh:
            (json['pending_threshold_kmh'] as num?)?.toDouble(),
        status: json['status']?.toString() ?? 'none',
        version: (json['version'] as num?)?.toInt() ?? 0,
        acceptedAt: json['accepted_at']?.toString(),
      );
}

class SafeZoneModel {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final int radiusM;
  final bool enabled;

  const SafeZoneModel({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.radiusM = 150,
    this.enabled = true,
  });

  factory SafeZoneModel.fromJson(Map<String, dynamic> json) => SafeZoneModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Safe Zone',
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
        radiusM: (json['radius_m'] as num?)?.toInt() ?? 150,
        enabled: json['enabled'] != false,
      );
}

class SafetyStateModel {
  final String coupleId;
  final bool enabled;
  final bool speedAlertsEnabled;
  final bool routingConfigured;
  final List<String> allowedDurations;

  final String myStatus;
  final String myDurationKey;
  final bool myDailySharing;
  final String? myExpiresAt;
  final TravelMode myTravelMode;
  final bool myDrivingMode;
  final SafetyConsents myConsents;
  final int myHistoryRetentionDays;
  final SafetyLocationFix? myLocation;

  final SafetyPartnerView? partner;
  final double? straightLineKm;
  final bool distanceIsLive;
  final SpeedAgreement? agreementForMe;
  final SpeedAgreement? agreementForPartner;
  final List<SafeZoneModel> mySafeZones;
  final Map<String, dynamic>? myJourney;
  final Map<String, bool> notificationPrefs;
  final List<Map<String, dynamic>> recentSos;
  final List<Map<String, dynamic>> recentAlerts;

  const SafetyStateModel({
    required this.coupleId,
    this.enabled = true,
    this.speedAlertsEnabled = true,
    this.routingConfigured = false,
    this.allowedDurations = const ['1h', '8h', '12h', 'manual'],
    this.myStatus = 'stopped',
    this.myDurationKey = '8h',
    this.myDailySharing = false,
    this.myExpiresAt,
    this.myTravelMode = TravelMode.stationary,
    this.myDrivingMode = false,
    this.myConsents = const SafetyConsents(),
    this.myHistoryRetentionDays = 7,
    this.myLocation,
    this.partner,
    this.straightLineKm,
    this.distanceIsLive = false,
    this.agreementForMe,
    this.agreementForPartner,
    this.mySafeZones = const [],
    this.myJourney,
    this.notificationPrefs = const {},
    this.recentSos = const [],
    this.recentAlerts = const [],
  });

  factory SafetyStateModel.fromJson(Map<String, dynamic> json) {
    final cfg = json['config'] as Map<String, dynamic>? ?? {};
    final mySess = json['my_session'] as Map<String, dynamic>? ?? {};
    final dist = json['distance'] as Map<String, dynamic>? ?? {};
    final ags = json['agreements'] as Map<String, dynamic>? ?? {};
    final myLocJson = json['my_location'] as Map<String, dynamic>?;
    final partnerJson = json['partner'] as Map<String, dynamic>?;
    final zonesJson = json['my_safe_zones'] as List<dynamic>? ?? [];
    final rawPrefs = json['notification_prefs'] as Map<String, dynamic>? ?? {};
    final parsedPrefs = <String, bool>{};
    rawPrefs.forEach((k, v) => parsedPrefs[k] = v == true);

    return SafetyStateModel(
      coupleId: json['couple_id']?.toString() ?? '',
      enabled: cfg['enabled'] != false,
      speedAlertsEnabled: cfg['speed_alerts_enabled'] != false,
      routingConfigured: cfg['routing_configured'] == true,
      allowedDurations: (cfg['allowed_durations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['1h', '8h', '12h', 'manual'],
      myStatus: mySess['status']?.toString() ?? 'stopped',
      myDurationKey: mySess['duration_key']?.toString() ?? '8h',
      myDailySharing: mySess['daily_sharing'] == true,
      myExpiresAt: mySess['expires_at']?.toString(),
      myTravelMode: TravelMode.fromId(mySess['travel_mode']?.toString()),
      myDrivingMode: mySess['driving_mode'] == true,
      myConsents: SafetyConsents.fromJson(
          mySess['consents'] as Map<String, dynamic>? ?? {}),
      myHistoryRetentionDays:
          (mySess['history_retention_days'] as num?)?.toInt() ?? 7,
      myLocation:
          myLocJson != null ? SafetyLocationFix.fromJson(myLocJson) : null,
      partner:
          partnerJson != null ? SafetyPartnerView.fromJson(partnerJson) : null,
      straightLineKm: (dist['straight_line_km'] as num?)?.toDouble(),
      distanceIsLive: dist['is_live'] == true,
      agreementForMe: ags['for_me'] is Map<String, dynamic>
          ? SpeedAgreement.fromJson(ags['for_me'] as Map<String, dynamic>)
          : null,
      agreementForPartner: ags['for_partner'] is Map<String, dynamic>
          ? SpeedAgreement.fromJson(
              ags['for_partner'] as Map<String, dynamic>)
          : null,
      mySafeZones: zonesJson
          .whereType<Map<String, dynamic>>()
          .map(SafeZoneModel.fromJson)
          .toList(),
      myJourney: json['my_journey'] as Map<String, dynamic>?,
      notificationPrefs: parsedPrefs,
      recentSos: (json['recent_sos'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
      recentAlerts: (json['recent_alerts'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
    );
  }
}
