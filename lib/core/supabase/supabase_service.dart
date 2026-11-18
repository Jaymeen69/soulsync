import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

/// Global Supabase client accessor.
/// Returns null or throws if not configured.
SupabaseClient? get supabaseClientOrNull =>
    SupabaseConfig.isConfigured ? Supabase.instance.client : null;

SupabaseClient get supabase => Supabase.instance.client;

/// Helper to initialize Supabase if configured.
Future<void> initSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    debugPrint('ℹ️ Supabase not yet configured. Running in secure local offline/demo mode.');
    return;
  }

  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
      storageOptions: const StorageClientOptions(
        retryAttempts: 3,
      ),
    );
  } catch (e) {
    debugPrint('⚠️ Supabase initialize error: $e');
  }
}
