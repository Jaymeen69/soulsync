import 'package:flutter/material.dart';

/// SoulSync brand colours and semantic Light/Dark theme helpers.
/// Privacy note: these are UI-only constants, no user data here.
abstract final class AppColors {
  // Brand primaries
  static const Color primary = Color(0xFF6C3EBC); // Deep purple
  static const Color primaryLight = Color(0xFFB388FF); // High-contrast dark-mode primary
  static const Color primaryDark = Color(0xFF4A1E9E);

  // Accent / love tones
  static const Color accent = Color(0xFFD03070); // Accessible WCAG-AA rose pink
  static const Color accentLight = Color(0xFFF48FB1);
  static const Color accentDark = Color(0xFFAD1457);

  // Light neutrals
  static const Color background = Color(0xFFFAF8FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF3EEFF);
  static const Color borderLight = Color(0xFFDACDF2);

  // Light text (WCAG AA compliant on white & #F9F6FE)
  static const Color textPrimary = Color(0xFF1A1033);
  static const Color textSecondary = Color(0xFF564D70);
  static const Color textHint = Color(0xFF6E658C);

  // Status
  static const Color success = Color(0xFF1F9D45);
  static const Color error = Color(0xFFD92D20);
  static const Color warning = Color(0xFFC26A00);
  static const Color info = Color(0xFF0066CC);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFFE03E80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient romanticGradient = LinearGradient(
    colors: [Color(0xFF8A2387), Color(0xFFD9305C), Color(0xFFEB5E28)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient loveGlowGradient = LinearGradient(
    colors: [Color(0xFFD9366E), Color(0xFF7B3FE4)],
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

  static const Color romanticRose = Color(0xFFE03862);
  static const Color romanticGlow = Color(0xFFFF8DA1);
  static const Color romanticBlush = Color(0xFFFFF0F5);

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF3D1A78), Color(0xFF6C3EBC), Color(0xFFE8498A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Pulse type colours
  static const Color pulseLove = Color(0xFFE02B5B);
  static const Color pulseHug = Color(0xFFD97218);
  static const Color pulseKiss = Color(0xFFD83B9B);
  static const Color pulseMissing = Color(0xFF6D52F5);
  static const Color pulseThinking = Color(0xFF1482B8);

  // Dark mode palette (WCAG AA compliant)
  static const Color darkBackground = Color(0xFF0F0A1E);
  static const Color darkSurface = Color(0xFF1A1033);
  static const Color darkSurfaceVariant = Color(0xFF261948);
  static const Color darkInputFill = Color(0xFF221640);
  static const Color darkBorder = Color(0xFF47317A);
  static const Color darkTextPrimary = Color(0xFFF7F3FF);
  static const Color darkTextSecondary = Color(0xFFCEC3E8);
  static const Color darkTextHint = Color(0xFFA799CC);
}

/// Semantic theme color accessors so every screen works identically well
/// in Light Mode and Dark Mode with zero white-on-white or dark-on-dark traps.
extension SoulSyncThemeColors on BuildContext {
  bool get ssIsDark => Theme.of(this).brightness == Brightness.dark;
  Color get ssBg => ssIsDark ? AppColors.darkBackground : AppColors.background;
  Color get ssSurface => ssIsDark ? AppColors.darkSurface : AppColors.surface;
  Color get ssSurfaceVariant =>
      ssIsDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant;
  Color get ssInputFill =>
      ssIsDark ? AppColors.darkInputFill : const Color(0xFFF9F6FE);
  Color get ssBorder =>
      ssIsDark ? AppColors.darkBorder : AppColors.borderLight;
  Color get ssTextPrimary =>
      ssIsDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get ssTextSecondary =>
      ssIsDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get ssTextHint =>
      ssIsDark ? AppColors.darkTextHint : AppColors.textHint;
  Color get ssPrimary => ssIsDark ? AppColors.primaryLight : AppColors.primary;
  Color get ssAccent => ssIsDark ? AppColors.accentLight : AppColors.accent;
}
