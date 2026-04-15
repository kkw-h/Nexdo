import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexdo/src/core/network/api_client.dart';
import 'package:nexdo/src/features/auth/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('auth/change_password', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('calls PATCH /me/password with bearer token and payload', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'auth.session',
        jsonEncode({
          'user': {
            'id': 'u_1',
            'nickname': 'Nexdo',
            'email': 'user@example.com',
            'created_at': '2026-04-15T10:00:00Z',
          },
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      );

      late http.Request capturedRequest;
      final repository = AuthRepository(
        preferences: preferences,
        apiClient: NexdoApiClient(
          baseUrl: 'https://example.com/api/v1',
          httpClient: MockClient((request) async {
            capturedRequest = request;
            return http.Response(
              jsonEncode({'code': 0, 'message': 'ok', 'data': null}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await repository.changePassword(
        oldPassword: 'old-password',
        newPassword: 'new-password-123',
      );

      expect(capturedRequest.method, 'PATCH');
      expect(capturedRequest.url.path, '/api/v1/me/password');
      expect(capturedRequest.headers['Authorization'], 'Bearer access-token');
      expect(jsonDecode(capturedRequest.body), {
        'old_password': 'old-password',
        'new_password': 'new-password-123',
      });
    });

    test('throws when session is missing', () async {
      final preferences = await SharedPreferences.getInstance();
      final repository = AuthRepository(
        preferences: preferences,
        apiClient: NexdoApiClient(
          baseUrl: 'https://example.com/api/v1',
          httpClient: MockClient((request) async {
            return http.Response('{}', 200);
          }),
        ),
      );

      await expectLater(
        () => repository.changePassword(
          oldPassword: 'old-password',
          newPassword: 'new-password-123',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            '登录已失效，请重新登录',
          ),
        ),
      );
    });

    test('surfaces api error message', () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'auth.session',
        jsonEncode({
          'user': {
            'id': 'u_1',
            'nickname': 'Nexdo',
            'email': 'user@example.com',
            'created_at': '2026-04-15T10:00:00Z',
          },
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      );

      final repository = AuthRepository(
        preferences: preferences,
        apiClient: NexdoApiClient(
          baseUrl: 'https://example.com/api/v1',
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({'code': 40001, 'message': '当前密码错误'}),
              400,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await expectLater(
        () => repository.changePassword(
          oldPassword: 'wrong-password',
          newPassword: 'new-password-123',
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            '当前密码错误',
          ),
        ),
      );
    });
  });
}
