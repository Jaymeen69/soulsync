import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kThemeModePrefKey = 'soulsync_theme_mode';

/// Persists and exposes the user's selected SoulSync theme mode
/// (`light`, `dark`, or `system`).
class SoulSyncThemeNotifier extends StateNotifier<ThemeMode> {
  SoulSyncThemeNotifier() : super(ThemeMode.system) {
    _loadSavedThemeMode();
  }

  Future<void> _loadSavedThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kThemeModePrefKey);
      if (saved == 'light') {
        state = ThemeMode.light;
      } else if (saved == 'dark') {
        state = ThemeMode.dark;
      } else {
        state = ThemeMode.system;
      }
    } catch (_) {
      // Ignore persistence errors and keep system default.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await prefs.setString(_kThemeModePrefKey, value);
    } catch (_) {}
  }
}

final themeModeProvider =
    StateNotifierProvider<SoulSyncThemeNotifier, ThemeMode>(
  (ref) => SoulSyncThemeNotifier(),
);
