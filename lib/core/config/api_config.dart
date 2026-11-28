import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AppEnvironment { development, staging, production }

/// Centralized API configuration for SoulSync across development, staging, and production.
/// Production builds strictly enforce HTTPS public URLs and never fall back to private IPs.
class ApiConfig {
  ApiConfig._();

  static const String _serverUrlPrefsKey = 'soulsync_server_url';

  static const String _envName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: kReleaseMode ? 'production' : 'development',
  );

  static const String _compiledApiUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String defaultProductionUrl = 'https://soulsync-api-8h06.onrender.com';
  static const String defaultStagingUrl = 'https://soulsync-api-8h06.onrender.com';
  static const String defaultDevUrl = 'http://127.0.0.1:8089';

  static String? _debugOverrideUrl;

  static AppEnvironment get environment {
    switch (_envName.trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      default:
        return kReleaseMode ? AppEnvironment.production : AppEnvironment.development;
    }
  }

  static bool get isProduction => environment == AppEnvironment.production || kReleaseMode;

  /// Returns true if [url] points to localhost, loopback, or a private LAN IPv4 range.
  static bool isPrivateOrLocalUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return true;
    final uri = Uri.tryParse(lower);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return true;
    final host = uri.host;
    if (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2' || host == '0.0.0.0') {
      return true;
    }
    if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
    final match172 = RegExp(r'^172\.(\d+)\.').firstMatch(host);
    if (match172 != null) {
      final second = int.tryParse(match172.group(1) ?? '') ?? 0;
      if (second >= 16 && second <= 31) return true;
    }
    return false;
  }

  /// Validates that a URL is safe for production (HTTPS and non-private).
  static bool isValidProductionUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return !isPrivateOrLocalUrl(url);
  }

  /// Active backend base URL used by every SoulSync module.
  static String get baseUrl {
    if (isProduction) {
      if (_compiledApiUrl.isNotEmpty && isValidProductionUrl(_compiledApiUrl)) {
        return _compiledApiUrl.replaceAll(RegExp(r'/+$'), '');
      }
      return defaultProductionUrl;
    }

    if (_debugOverrideUrl != null && _debugOverrideUrl!.isNotEmpty) {
      return _debugOverrideUrl!;
    }
    if (_compiledApiUrl.isNotEmpty) {
      return _compiledApiUrl.replaceAll(RegExp(r'/+$'), '');
    }
    if (environment == AppEnvironment.staging) {
      return defaultStagingUrl;
    }
    return defaultDevUrl;
  }

  /// Initializes config on app startup and purges outdated local/private URLs in production.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_serverUrlPrefsKey);
      if (isProduction) {
        // Always migrate older APKs away from any previously saved local IP/localhost URL.
        if (saved != null) {
          await prefs.remove(_serverUrlPrefsKey);
        }
        _debugOverrideUrl = null;
        return;
      }
      if (saved != null && saved.isNotEmpty) {
        _debugOverrideUrl = saved;
      }
    } catch (_) {}
  }

  /// Non-blocking health ping on app startup to wake Render Free Tier before user submits a form.
  static void warmUpBackend() {
    Future<void>(() async {
      try {
        await http
            .get(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(seconds: 55));
      } catch (_) {}
    });
  }

  /// Developer-only override (no-op in release/production builds).
  static Future<void> setDebugOverrideUrl(String url) async {
    if (isProduction) return;
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    if (clean.isEmpty) {
      _debugOverrideUrl = null;
      await prefs.remove(_serverUrlPrefsKey);
    } else {
      _debugOverrideUrl = clean;
      await prefs.setString(_serverUrlPrefsKey, clean);
    }
  }
}
