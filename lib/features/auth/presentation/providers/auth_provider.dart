import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_service.dart';

/// User profile model for SoulSync
class SoulSyncUser {
  const SoulSyncUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.coupleId,
    this.partnerName,
    this.relationshipStartDate,
    this.isEmailVerified = true,
  });

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String? coupleId;
  final String? partnerName;
  final DateTime? relationshipStartDate;
  final bool isEmailVerified;

  bool get isConnectedToPartner => coupleId != null && coupleId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'coupleId': coupleId,
        'partnerName': partnerName,
        'relationshipStartDate': relationshipStartDate?.toIso8601String(),
        'isEmailVerified': isEmailVerified,
      };

  factory SoulSyncUser.fromJson(Map<String, dynamic> json) => SoulSyncUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String? ?? 'Partner',
        avatarUrl: json['avatarUrl'] as String?,
        coupleId: json['coupleId'] as String?,
        partnerName: json['partnerName'] as String?,
        relationshipStartDate: json['relationshipStartDate'] != null
            ? DateTime.tryParse(json['relationshipStartDate'] as String)
            : null,
        isEmailVerified: json['isEmailVerified'] as bool? ?? true,
      );

  SoulSyncUser copyWith({
    String? displayName,
    String? avatarUrl,
    String? coupleId,
    String? partnerName,
    DateTime? relationshipStartDate,
    bool? isEmailVerified,
  }) {
    return SoulSyncUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coupleId: coupleId ?? this.coupleId,
      partnerName: partnerName ?? this.partnerName,
      relationshipStartDate: relationshipStartDate ?? this.relationshipStartDate,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    );
  }
}

/// State notifier for reactive authentication state
class AuthNotifier extends StateNotifier<AsyncValue<SoulSyncUser?>> {
  AuthNotifier() : super(const AsyncValue.loading()) {
    _loadInitialUser();
  }

  static const String _userPrefsKey = 'soulsync_current_user';
  static const String _usersDbKey = 'soulsync_registered_users';

  Future<void> _loadInitialUser() async {
    try {
      if (SupabaseConfig.isConfigured && supabaseClientOrNull?.auth.currentUser != null) {
        final sbUser = supabaseClientOrNull!.auth.currentUser!;
        state = AsyncValue.data(SoulSyncUser(
          id: sbUser.id,
          email: sbUser.email ?? '',
          displayName: sbUser.userMetadata?['display_name'] as String? ?? 'Partner',
          isEmailVerified: sbUser.emailConfirmedAt != null,
        ));
        return;
      }

      // Check local session
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString(_userPrefsKey);
      if (userDataStr != null) {
        final map = jsonDecode(userDataStr) as Map<String, dynamic>;
        state = AsyncValue.data(SoulSyncUser.fromJson(map));
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e, st) {
      debugPrint('Error loading initial user: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<SoulSyncUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim();

    if (SupabaseConfig.isConfigured) {
      final res = await supabase.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'display_name': cleanName},
      );
      final u = res.user;
      final user = SoulSyncUser(
        id: u?.id ?? const Uuid().v4(),
        email: cleanEmail,
        displayName: cleanName,
        isEmailVerified: u?.emailConfirmedAt != null,
      );
      state = AsyncValue.data(user);
      return user;
    }

    // Local / Offline mode
    final prefs = await SharedPreferences.getInstance();
    final usersMapStr = prefs.getString(_usersDbKey) ?? '{}';
    final usersMap = jsonDecode(usersMapStr) as Map<String, dynamic>;

    if (usersMap.containsKey(cleanEmail)) {
      throw Exception('This email is already registered. Please sign in.');
    }

    final userId = const Uuid().v4();
    final newUser = SoulSyncUser(
      id: userId,
      email: cleanEmail,
      displayName: cleanName,
      isEmailVerified: true,
    );

    // Save user credentials & profile
    usersMap[cleanEmail] = {
      'password': password,
      'user': newUser.toJson(),
    };
    await prefs.setString(_usersDbKey, jsonEncode(usersMap));
    await prefs.setString(_userPrefsKey, jsonEncode(newUser.toJson()));

    state = AsyncValue.data(newUser);
    return newUser;
  }

  Future<SoulSyncUser> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (SupabaseConfig.isConfigured) {
      final res = await supabase.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );
      final u = res.user;
      final user = SoulSyncUser(
        id: u?.id ?? const Uuid().v4(),
        email: cleanEmail,
        displayName: u?.userMetadata?['display_name'] as String? ?? 'Partner',
        isEmailVerified: u?.emailConfirmedAt != null,
      );
      state = AsyncValue.data(user);
      return user;
    }

    // Local / Offline mode
    final prefs = await SharedPreferences.getInstance();
    final usersMapStr = prefs.getString(_usersDbKey) ?? '{}';
    final usersMap = jsonDecode(usersMapStr) as Map<String, dynamic>;

    if (!usersMap.containsKey(cleanEmail)) {
      throw Exception('Account not found. Please check your email or sign up.');
    }

    final record = usersMap[cleanEmail] as Map<String, dynamic>;
    if (record['password'] != password) {
      throw Exception('Incorrect password. Please try again.');
    }

    final user = SoulSyncUser.fromJson(record['user'] as Map<String, dynamic>);
    await prefs.setString(_userPrefsKey, jsonEncode(user.toJson()));

    state = AsyncValue.data(user);
    return user;
  }

  Future<void> signOut() async {
    if (SupabaseConfig.isConfigured) {
      try {
        await supabase.auth.signOut();
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userPrefsKey);
    state = const AsyncValue.data(null);
  }

  Future<void> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? coupleId,
    String? partnerName,
  }) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return;

    final updated = currentUser.copyWith(
      displayName: displayName,
      avatarUrl: avatarUrl,
      coupleId: coupleId,
      partnerName: partnerName,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userPrefsKey, jsonEncode(updated.toJson()));

    // Update in users registry
    final usersMapStr = prefs.getString(_usersDbKey) ?? '{}';
    final usersMap = jsonDecode(usersMapStr) as Map<String, dynamic>;
    if (usersMap.containsKey(updated.email)) {
      final rec = usersMap[updated.email] as Map<String, dynamic>;
      rec['user'] = updated.toJson();
      usersMap[updated.email] = rec;
      await prefs.setString(_usersDbKey, jsonEncode(usersMap));
    }

    state = AsyncValue.data(updated);
  }

  Future<void> resetPassword(String email) async {
    if (SupabaseConfig.isConfigured) {
      await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase());
    }
  }

  Future<void> resendVerificationEmail(String email) async {
    if (SupabaseConfig.isConfigured) {
      await supabase.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase());
    }
  }

  Future<void> deleteAccount() async {
    await signOut();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<SoulSyncUser?>>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<SoulSyncUser?>((ref) {
  return ref.watch(authProvider).valueOrNull;
});

final authRepositoryProvider = Provider<AuthNotifier>((ref) {
  return ref.watch(authProvider.notifier);
});
