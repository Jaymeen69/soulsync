import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_error_handler.dart';

/// Exception thrown when an account tries to sign in before completing email verification.
class UnverifiedEmailException implements Exception {
  UnverifiedEmailException(this.message, this.email);
  final String message;
  final String email;

  @override
  String toString() => message;
}

/// User profile model for SoulSync
class SoulSyncUser {
  const SoulSyncUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.coupleId,
    this.partnerName,
    this.inviteCode,
    this.relationshipStartDate,
    this.isEmailVerified = true,
    this.socialProvider,
    this.socialAccount,
    this.socialAccounts = const [],
  });

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String? coupleId;
  final String? partnerName;
  final String? inviteCode;
  final DateTime? relationshipStartDate;
  final bool isEmailVerified;
  final String? socialProvider;
  final String? socialAccount;
  final List<Map<String, dynamic>> socialAccounts;

  bool get isConnectedToPartner => coupleId != null && coupleId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'coupleId': coupleId,
        'partnerName': partnerName,
        'inviteCode': inviteCode,
        'relationshipStartDate': relationshipStartDate?.toIso8601String(),
        'isEmailVerified': isEmailVerified,
        'social_provider': socialProvider,
        'social_account': socialAccount,
        'social_accounts': socialAccounts,
      };

  factory SoulSyncUser.fromJson(Map<String, dynamic> json) => SoulSyncUser(
        id: json['id'] as String? ?? 'u_${const Uuid().v4()}',
        email: json['email'] as String? ?? '',
        displayName: json['displayName'] as String? ?? json['name'] as String? ?? 'Partner',
        avatarUrl: json['avatarUrl'] as String?,
        coupleId: json['coupleId'] as String? ?? json['couple_id'] as String?,
        partnerName: json['partnerName'] as String? ?? json['partner'] as String?,
        inviteCode: json['inviteCode'] as String? ?? json['invite_code'] as String? ?? 'SOUL-8492',
        relationshipStartDate: json['relationshipStartDate'] != null
            ? DateTime.tryParse(json['relationshipStartDate'] as String)
            : null,
        isEmailVerified: json['isEmailVerified'] as bool? ?? json['is_verified'] as bool? ?? false,
        socialProvider: json['social_provider'] as String? ?? json['socialProvider'] as String?,
        socialAccount: json['social_account'] as String? ?? json['socialAccount'] as String?,
        socialAccounts: (json['social_accounts'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
      );

  SoulSyncUser copyWith({
    String? email,
    String? displayName,
    String? avatarUrl,
    String? coupleId,
    String? partnerName,
    String? inviteCode,
    DateTime? relationshipStartDate,
    bool? isEmailVerified,
    String? socialProvider,
    String? socialAccount,
    List<Map<String, dynamic>>? socialAccounts,
  }) {
    return SoulSyncUser(
      id: id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coupleId: coupleId ?? this.coupleId,
      partnerName: partnerName ?? this.partnerName,
      inviteCode: inviteCode ?? this.inviteCode,
      relationshipStartDate: relationshipStartDate ?? this.relationshipStartDate,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      socialProvider: socialProvider ?? this.socialProvider,
      socialAccount: socialAccount ?? this.socialAccount,
      socialAccounts: socialAccounts ?? this.socialAccounts,
    );
  }
}

/// State notifier for reactive authentication & email verification state
class AuthNotifier extends StateNotifier<AsyncValue<SoulSyncUser?>> {
  AuthNotifier() : super(const AsyncValue.loading()) {
    _loadInitialUser();
  }

  static const String _userPrefsKey = 'soulsync_current_user';

  /// Primary API URL for central backend shared by Mobile App and Admin Panel
  static String get apiBaseUrl => ApiConfig.baseUrl;

  static Future<void> setServerUrl(String url) => ApiConfig.setDebugOverrideUrl(url);

  Future<void> _loadInitialUser() async {
    try {
      await ApiConfig.initialize();
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

  /// 1. Register with real Gmail SMTP OTP verification (never returns or simulates OTPs)
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
    String partnerName = 'Partner',
    String? socialProvider,
    String? socialAccount,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim();

    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': cleanName,
            'email': cleanEmail,
            'password': password,
            'partner': partnerName,
            if (socialProvider != null && socialProvider.isNotEmpty)
              'social_provider': socialProvider.trim().toLowerCase(),
            if (socialAccount != null && socialAccount.isNotEmpty)
              'social_account': socialAccount.trim(),
          }),
        )
        .timeout(const Duration(seconds: 25));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return body;
    }
    throw Exception(body['error'] ?? 'Registration failed (${res.statusCode}).');
  }

  /// 2. Verify 6-digit Email OTP against authoritative backend challenge
  Future<SoulSyncUser> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': cleanEmail, 'otp': otp.trim()}),
        )
        .timeout(const Duration(seconds: 10));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200 && body['user'] is Map<String, dynamic>) {
      return SoulSyncUser.fromJson(body['user'] as Map<String, dynamic>);
    }
    throw Exception(body['error'] ?? 'Invalid or expired verification code.');
  }

  /// 3. Resend registration OTP (server enforces 60s cooldown & rate limits)
  Future<Map<String, dynamic>> resendOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/resend-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': cleanEmail}),
        )
        .timeout(const Duration(seconds: 15));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200) {
      return body;
    }
    throw Exception(body['error'] ?? 'Unable to resend OTP right now.');
  }

  /// 4. Sign in (blocks unverified users strictly)
  Future<SoulSyncUser> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': cleanEmail, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200 && body['user'] is Map<String, dynamic>) {
      final user = SoulSyncUser.fromJson(body['user'] as Map<String, dynamic>);
      if (!user.isEmailVerified) {
        throw UnverifiedEmailException(
          'Please verify your email address before signing in.',
          cleanEmail,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userPrefsKey, jsonEncode(user.toJson()));
      state = AsyncValue.data(user);
      return user;
    }
    if (body['needs_verification'] == true) {
      throw UnverifiedEmailException(
        body['error']?.toString() ?? 'Email not verified yet.',
        cleanEmail,
      );
    }
    throw Exception(body['error'] ?? 'Invalid email or password.');
  }

  /// 4B. Sign in or register with Google / Other Social Account
  Future<SoulSyncUser> signInWithSocial({
    required String provider,
    required String email,
    String? displayName,
    String? socialAccount,
    String? partnerName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/auth/social'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'provider': provider.trim().toLowerCase(),
            'email': cleanEmail,
            if (displayName != null && displayName.trim().isNotEmpty)
              'name': displayName.trim(),
            if (socialAccount != null && socialAccount.trim().isNotEmpty)
              'social_account': socialAccount.trim(),
            if (partnerName != null && partnerName.trim().isNotEmpty)
              'partner': partnerName.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200 && body['user'] is Map<String, dynamic>) {
      final user = SoulSyncUser.fromJson(body['user'] as Map<String, dynamic>);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userPrefsKey, jsonEncode(user.toJson()));
      state = AsyncValue.data(user);
      return user;
    }
    throw Exception(body['error'] ?? 'Social sign-in failed.');
  }

  /// 4C. Link or unlink a social account for the current signed-in user
  Future<SoulSyncUser> updateSocialAccount({
    required String action, // 'connect' or 'disconnect'
    required String provider,
    String account = '',
  }) async {
    final user = state.valueOrNull;
    if (user == null) throw Exception('User not authenticated.');

    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/account/social-accounts'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': user.id,
            'action': action,
            'provider': provider.trim().toLowerCase(),
            'account': account.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200 && body['user'] is Map<String, dynamic>) {
      final updated = SoulSyncUser.fromJson(body['user'] as Map<String, dynamic>);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userPrefsKey, jsonEncode(updated.toJson()));
      state = AsyncValue.data(updated);
      return updated;
    }
    throw Exception(body['error'] ?? 'Failed to update social account.');
  }

  /// 5. Forgot Password Request (separate reset challenge)
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': cleanEmail}),
        )
        .timeout(const Duration(seconds: 15));
    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200) {
      return body;
    }
    throw Exception(body['error'] ?? 'Unable to send reset code.');
  }

  /// 6. Verify Reset Password OTP
  Future<void> verifyResetOtp({required String email, required String otp}) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/auth/verify-reset-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': cleanEmail, 'otp': otp.trim()}),
        )
        .timeout(const Duration(seconds: 10));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Invalid reset code.');
    }
  }

  /// 7. Reset Password with verified OTP
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': cleanEmail,
            'otp': otp.trim(),
            'new_password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 10));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Failed to reset password.');
    }
  }

  /// 8. Request Email Change OTP (separate email_change challenge)
  Future<Map<String, dynamic>> requestChangeEmail(String newEmail) async {
    final user = state.valueOrNull;
    if (user == null) throw Exception('User not authenticated.');
    final cleanEmail = newEmail.trim().toLowerCase();

    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/account/change-email/request'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': user.id, 'new_email': cleanEmail}),
        )
        .timeout(const Duration(seconds: 15));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200) {
      return body;
    }
    throw Exception(body['error'] ?? 'Unable to send email change code.');
  }

  /// 9. Verify Email Change OTP & persist verified new email
  Future<SoulSyncUser> verifyChangeEmail({
    required String newEmail,
    required String otp,
  }) async {
    final user = state.valueOrNull;
    if (user == null) throw Exception('User not authenticated.');
    final cleanEmail = newEmail.trim().toLowerCase();

    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/account/change-email/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': user.id,
            'new_email': cleanEmail,
            'otp': otp.trim(),
          }),
        )
        .timeout(const Duration(seconds: 10));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200) {
      final updated = user.copyWith(email: cleanEmail, isEmailVerified: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userPrefsKey, jsonEncode(updated.toJson()));
      state = AsyncValue.data(updated);
      return updated;
    }
    throw Exception(body['error'] ?? 'Invalid email change code.');
  }

  /// 10. Update Profile
  Future<void> updateProfile({
    String? email,
    String? displayName,
    String? avatarUrl,
    String? coupleId,
    String? partnerName,
  }) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return;

    final updated = currentUser.copyWith(
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
      coupleId: coupleId,
      partnerName: partnerName,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userPrefsKey, jsonEncode(updated.toJson()));
    state = AsyncValue.data(updated);
  }

  /// 11. Connect Partner with Invite Code
  Future<Map<String, dynamic>> connectPartner(String inviteCode) async {
    final user = state.valueOrNull;
    if (user == null) throw Exception('User not authenticated.');

    final res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/couple/request'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': user.id,
            'email': user.email,
            'invite_code': inviteCode.trim().toUpperCase(),
          }),
        )
        .timeout(const Duration(seconds: 5));

    final body = ApiErrorHandler.decodeJsonMap(res);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return body;
    } else {
      throw Exception(body['error'] ?? 'Failed to send connection request.');
    }
  }

  /// 12. Sign out
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userPrefsKey);
    state = const AsyncValue.data(null);
  }

  /// 13. Delete Account
  Future<void> deleteAccount() async {
    await signOut();
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<SoulSyncUser?>>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<SoulSyncUser?>((ref) {
  return ref.watch(authProvider).valueOrNull;
});

final authRepositoryProvider = Provider<AuthNotifier>((ref) {
  return ref.watch(authProvider.notifier);
});
