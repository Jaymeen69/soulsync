import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soulsync/core/config/api_config.dart';
import 'package:soulsync/core/network/api_error_handler.dart';

void main() {
  group('ApiConfig security & environment validation', () {
    test('detects private and local URLs accurately', () {
      expect(ApiConfig.isPrivateOrLocalUrl('http://192.168.1.13:8089'), isTrue);
      expect(ApiConfig.isPrivateOrLocalUrl('http://127.0.0.1:8089'), isTrue);
      expect(ApiConfig.isPrivateOrLocalUrl('http://localhost:8089'), isTrue);
      expect(ApiConfig.isPrivateOrLocalUrl('http://10.0.2.2:8089'), isTrue);
      expect(ApiConfig.isPrivateOrLocalUrl('http://172.16.0.5:8089'), isTrue);
      expect(ApiConfig.isPrivateOrLocalUrl('https://soulsync-api.onrender.com'), isFalse);
    });

    test('validates production URLs require HTTPS and public host', () {
      expect(ApiConfig.isValidProductionUrl('https://soulsync-api.onrender.com'), isTrue);
      expect(ApiConfig.isValidProductionUrl('http://soulsync-api.onrender.com'), isFalse);
      expect(ApiConfig.isValidProductionUrl('https://192.168.1.13:8089'), isFalse);
      expect(ApiConfig.isValidProductionUrl('http://127.0.0.1:8089'), isFalse);
    });
  });

  group('ApiErrorHandler user-friendly sanitization', () {
    test('sanitizes SocketException / No route to host without leaking IP or port', () {
      final err = http.ClientException(
        'SocketException: No route to host (OS Error: No route to host, errno = 113)',
        Uri.parse('http://192.168.1.13:8089/api/register'),
      );
      final msg = ApiErrorHandler.friendlyMessage(err);
      expect(msg, ApiErrorHandler.serverUnavailableMsg);
      expect(msg.contains('192.168'), isFalse);
      expect(msg.contains('8089'), isFalse);
      expect(msg.contains('SocketException'), isFalse);
      expect(msg.contains('ClientException'), isFalse);
    });

    test('maps TimeoutException, DNS failure, and OTP errors cleanly', () {
      expect(
        ApiErrorHandler.friendlyMessage(TimeoutException('timed out')),
        ApiErrorHandler.timeoutMsg,
      );
      expect(
        ApiErrorHandler.friendlyMessage(const SocketException('Failed host lookup')),
        ApiErrorHandler.noInternetMsg,
      );
      expect(
        ApiErrorHandler.friendlyMessage(Exception('Incorrect verification code. 4 attempt(s) remaining.')),
        ApiErrorHandler.invalidOtpMsg,
      );
      expect(
        ApiErrorHandler.friendlyMessage(Exception('Verification code has expired.')),
        ApiErrorHandler.expiredOtpMsg,
      );
      expect(
        ApiErrorHandler.friendlyMessage(Exception('SMTP authentication error')),
        ApiErrorHandler.otpSendFailedMsg,
      );
    });

    test('decodeJsonMap handles non-JSON 401 Unauthorized without FormatException', () {
      final res = http.Response('Unauthorized', 401);
      expect(
        () => ApiErrorHandler.decodeJsonMap(res),
        throwsA(predicate((e) => e.toString().contains(ApiErrorHandler.serverUnavailableMsg))),
      );
      final ok = ApiErrorHandler.decodeJsonMap(http.Response('{"status":"ok"}', 200));
      expect(ok['status'], 'ok');
    });
  });
}
