import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralized error sanitizer and retry helper for SoulSync network calls.
/// Ensures raw technical exceptions, IPs, ports, and endpoints are never shown to users.
class ApiErrorHandler {
  ApiErrorHandler._();

  /// Safely decodes a JSON object response; throws a clean user-friendly error on HTML/plain-text errors.
  static Map<String, dynamic> decodeJsonMap(http.Response res) {
    final trimmed = res.body.trim();
    if (trimmed.isEmpty) {
      if (res.statusCode >= 500 || res.statusCode == 401 || res.statusCode == 404) {
        throw Exception(serverUnavailableMsg);
      }
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw Exception(serverUnavailableMsg);
    } on FormatException {
      if (kDebugMode) {
        debugPrint('[SoulSync API] Non-JSON HTTP ${res.statusCode} response received.');
      }
      if (res.statusCode == 408 || res.statusCode == 504) {
        throw Exception(timeoutMsg);
      }
      throw Exception(serverUnavailableMsg);
    }
  }

  static const String noInternetMsg =
      'No internet connection. Please check your network.';
  static const String serverUnavailableMsg =
      'SoulSync is temporarily unavailable. Please try again.';
  static const String databaseUnavailableMsg =
      'We are experiencing a temporary service issue. Please try again later.';
  static const String sessionExpiredMsg =
      'Your session has expired. Please sign in again.';
  static const String timeoutMsg =
      'The connection is taking longer than expected. Please try again.';
  static const String otpSendFailedMsg =
      "We couldn't send your verification code. Please try again.";
  static const String invalidOtpMsg =
      'The verification code is incorrect.';
  static const String expiredOtpMsg =
      'Your verification code has expired. Please request a new code.';

  /// Converts any exception or raw error string into a safe, user-friendly message.
  static String friendlyMessage(Object error, {String? fallback}) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = raw.toLowerCase();

    if (kDebugMode) {
      debugPrint('[SoulSync API Error] ${raw.replaceAll(RegExp(r'https?://[^\s]+'), '[REDACTED_URL]')}');
    }

    if (error is TimeoutException || lower.contains('timeoutexception') || lower.contains('timed out')) {
      return timeoutMsg;
    }

    if (lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('software caused connection abort')) {
      return noInternetMsg;
    }

    if (error is SocketException ||
        error is http.ClientException ||
        error is HandshakeException ||
        lower.contains('clientexception') ||
        lower.contains('socketexception') ||
        lower.contains('no route to host') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('errno =')) {
      return serverUnavailableMsg;
    }

    if (lower.contains('expired') && (lower.contains('otp') || lower.contains('code'))) {
      return expiredOtpMsg;
    }

    if ((lower.contains('incorrect') || lower.contains('invalid')) &&
        (lower.contains('otp') || lower.contains('verification code'))) {
      return invalidOtpMsg;
    }

    if (lower.contains('unable to send') ||
        lower.contains('failed to send') ||
        lower.contains('smtp') ||
        lower.contains('mailer')) {
      return otpSendFailedMsg;
    }

    // Strip any accidental URLs, IPs, or ports from backend/unknown messages.
    if (RegExp(r'(https?://|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|:\d{4,5})').hasMatch(raw)) {
      return fallback ?? serverUnavailableMsg;
    }

    return raw.isEmpty ? (fallback ?? serverUnavailableMsg) : raw;
  }

  /// Retries idempotent GET requests on transient network/5xx errors without duplicating writes.
  static Future<http.Response> getWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
    int maxAttempts = 2,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final res = await http.get(uri, headers: headers).timeout(timeout);
        if (res.statusCode >= 500 && attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        return res;
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    throw Exception(friendlyMessage(lastError ?? serverUnavailableMsg));
  }
}
