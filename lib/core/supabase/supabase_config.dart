// ⚠️  SECURITY: Never commit real credentials.
// Fill in your project credentials when you have your Supabase project.

abstract final class SupabaseConfig {
  /// Your Supabase project URL
  /// Example: https://xyzcompany.supabase.co
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';

  /// Your Supabase anon (public) key
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  /// Whether Supabase credentials have been configured
  static bool get isConfigured =>
      supabaseUrl != 'YOUR_SUPABASE_URL' &&
      supabaseUrl.startsWith('https://') &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY';

  // ─── Storage bucket names ───────────────────────────────────
  static const String avatarsBucket = 'avatars';
  static const String memoriesBucket = 'memories';
  static const String lettersBucket = 'letters';

  // ─── Realtime channels ──────────────────────────────────────
  static const String couplePulsesChannel = 'couple-pulses';
  static const String coupleActivityChannel = 'couple-activity';

  // ─── Free tier limits ───────────────────────────────────────
  static const int freeMemoryPhotoLimit = 100;
  static const int freeMemoryStorageLimitMb = 500;
}
