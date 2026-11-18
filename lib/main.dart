import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/supabase/supabase_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode (can be unlocked per-screen)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // Initialize Supabase (credentials loaded from supabase_config.dart)
  await initSupabase();

  // Initialize Firebase for push notifications
  // google-services.json must be placed in android/app/ (not committed to git)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Firebase init may fail in development without google-services.json
    debugPrint('Firebase init failed: $e');
  }

  runApp(
    // ProviderScope is required for Riverpod
    const ProviderScope(
      child: SoulSyncApp(),
    ),
  );
}
