import 'package:flutter/material.dart';

/// SoulSync brand colours.
/// Privacy note: these are UI-only constants, no user data here.
abstract final class AppColors {
  // Brand primaries
  static const Color primary = Color(0xFF6C3EBC);       // Deep purple
  static const Color primaryLight = Color(0xFF9C6FE4);
  static const Color primaryDark = Color(0xFF4A1E9E);

  // Accent / love tones
  static const Color accent = Color(0xFFE8498A);         // Rose pink
  static const Color accentLight = Color(0xFFF078AD);
  static const Color accentDark = Color(0xFFC0245E);

  // Neutrals
  static const Color background = Color(0xFFFAF8FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF3EEFF);

  // Text
  static const Color textPrimary = Color(0xFF1A1033);
  static const Color textSecondary = Color(0xFF6B6480);
  static const Color textHint = Color(0xFFB0A8C8);

  // Status
  static const Color success = Color(0xFF34C759);
  static const Color error = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFF9500);
  static const Color info = Color(0xFF007AFF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient romanticGradient = LinearGradient(
    colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient loveGlowGradient = LinearGradient(
    colors: [Color(0xFFFF5286), Color(0xFF9044FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient softRomanceGradient = LinearGradient(
    colors: [Color(0xFFFFF5F8), Color(0xFFF7F1FF), Color(0xFFF5F8FF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGlassGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFDFBFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Color romanticRose = Color(0xFFFF4B72);
  static const Color romanticGlow = Color(0xFFFF8DA1);
  static const Color romanticBlush = Color(0xFFFFF0F5);

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF3D1A78), Color(0xFF6C3EBC), Color(0xFFE8498A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Pulse type colours
  static const Color pulseLove = Color(0xFFFF3B6B);
  static const Color pulseHug = Color(0xFFFF9B4E);
  static const Color pulseKiss = Color(0xFFFF5EBE);
  static const Color pulseMissing = Color(0xFF7B61FF);
  static const Color pulseThinking = Color(0xFF34AADC);

  // Dark mode equivalents
  static const Color darkBackground = Color(0xFF0F0A1E);
  static const Color darkSurface = Color(0xFF1A1033);
  static const Color darkSurfaceVariant = Color(0xFF251842);
}
