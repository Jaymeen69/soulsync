import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_service.dart';
import 'auth_provider.dart';

/// Profile data for the current user.
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  if (SupabaseConfig.isConfigured) {
    try {
      final response = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      return response;
    } catch (_) {}
  }

  return {
    'id': user.id,
    'display_name': user.displayName,
    'email': user.email,
    'avatar_url': user.avatarUrl,
    'couple_id': user.coupleId,
  };
});

class ProfileRepository {
  ProfileRepository(this.ref);
  final Ref ref;

  /// Create or update the user's profile.
  Future<void> upsertProfile({
    required String userId,
    required String displayName,
    String? avatarUrl,
    DateTime? dateOfBirth,
    String? country,
    String? timezone,
  }) async {
    if (SupabaseConfig.isConfigured) {
      await supabase.from('profiles').upsert({
        'id': userId,
        'display_name': displayName.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth.toIso8601String(),
        if (country != null) 'country': country,
        if (timezone != null) 'timezone': timezone,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }

    // Always update local reactive state
    await ref.read(authRepositoryProvider).updateProfile(
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  /// Upload avatar image.
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    if (SupabaseConfig.isConfigured) {
      final filePath = '$userId/avatar.$fileExtension';
      await supabase.storage.from('avatars').uploadBinary(
        filePath,
        imageBytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExtension',
          upsert: true,
        ),
      );
      return supabase.storage.from('avatars').getPublicUrl(filePath);
    }

    return '';
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref);
});
