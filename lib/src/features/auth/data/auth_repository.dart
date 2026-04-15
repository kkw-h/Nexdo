import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/auth_user.dart';
import 'auth_session.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

abstract class AccessTokenProvider {
  Future<String> requireAccessToken();

  Future<String?> refreshAccessToken();
}

class AuthRepository implements AccessTokenProvider {
  AuthRepository({
    required SharedPreferences preferences,
    required NexdoApiClient apiClient,
  }) : _preferences = preferences,
       _apiClient = apiClient;

  static const _sessionKey = 'auth.session';

  final SharedPreferences _preferences;
  final NexdoApiClient _apiClient;

  Future<AuthUser?> getCurrentUser() async {
    final session = await _ensureValidSession();
    if (session == null) {
      return null;
    }
    try {
      final remote = await _fetchProfile(session.accessToken);
      final updated = session.copyWith(user: remote);
      await _saveSession(updated);
      return remote;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        return null;
      }
      return session.user;
    }
  }

  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
    required String locale,
    required String timezone,
  }) async {
    final payload = {
      'email': email.trim().toLowerCase(),
      'password': password,
      'nickname': name.trim(),
      'timezone': timezone,
      'locale': locale,
    };
    final data = await _safeRequest(
      () => _apiClient.request(
        method: 'POST',
        path: '/auth/register',
        body: payload,
      ),
      defaultMessage: '注册失败，请稍后再试',
    );
    return _persistSessionFromPayload(data);
  }

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final payload = {'email': email.trim().toLowerCase(), 'password': password};
    final data = await _safeRequest(
      () => _apiClient.request(
        method: 'POST',
        path: '/auth/login',
        body: payload,
      ),
      defaultMessage: '登录失败，请重试',
    );
    return _persistSessionFromPayload(data);
  }

  Future<void> logout() async {
    final session = await _readSession();
    await _clearSession();
    if (session == null) {
      return;
    }
    try {
      await _apiClient.request(
        method: 'POST',
        path: '/auth/logout',
        accessToken: session.accessToken,
      );
    } catch (_) {
      // 静默忽略
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final session = await _ensureValidSession();
    if (session == null) {
      throw const AuthException('登录已失效，请重新登录');
    }
    await _safeRequest(
      () => _apiClient.request(
        method: 'PATCH',
        path: '/me/password',
        accessToken: session.accessToken,
        body: {'old_password': oldPassword, 'new_password': newPassword},
      ),
      defaultMessage: '修改密码失败，请稍后再试',
    );
  }

  @override
  Future<String> requireAccessToken() async {
    final session = await _ensureValidSession();
    if (session == null) {
      throw const AuthException('登录已失效，请重新登录');
    }
    return session.accessToken;
  }

  @override
  Future<String?> refreshAccessToken() async {
    final existing = await _readSession();
    if (existing == null) {
      return null;
    }
    final refreshed = await _refreshSession(existing);
    await _saveSession(refreshed);
    return refreshed.accessToken;
  }

  Future<AuthUser?> cachedUser() async {
    final session = await _readSession();
    return session?.user;
  }

  Future<AuthSession?> _ensureValidSession() async {
    final existing = await _readSession();
    if (existing == null) {
      return null;
    }
    if (!existing.isAccessTokenExpired) {
      return existing;
    }
    try {
      final refreshed = await _refreshSession(existing);
      await _saveSession(refreshed);
      return refreshed;
    } on AuthException {
      rethrow;
    } catch (error) {
      await _clearSession();
      if (error is ApiException && error.statusCode == 401) {
        return null;
      }
      rethrow;
    }
  }

  Future<AuthSession> _refreshSession(AuthSession session) async {
    final data = await _safeRequest(
      () => _apiClient.request(
        method: 'POST',
        path: '/auth/refresh',
        body: {'refresh_token': session.refreshToken},
      ),
      defaultMessage: '登录状态已失效，请重新登录',
    );
    return _mapPayloadToSession(data, fallbackUser: session.user);
  }

  Future<AuthUser?> refreshSessionOnAppLaunch() async {
    final session = await _readSession();
    if (session == null) {
      return null;
    }
    try {
      final data = await _apiClient.request(
        method: 'POST',
        path: '/auth/refresh',
        body: {'refresh_token': session.refreshToken},
      );
      final refreshed = _mapPayloadToSession(data, fallbackUser: session.user);
      await _saveSession(refreshed);
      return refreshed.user;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        return null;
      }
      return session.user;
    } on AuthException {
      rethrow;
    } catch (_) {
      return session.user;
    }
  }

  Future<AuthUser> _persistSessionFromPayload(dynamic payload) async {
    final session = _mapPayloadToSession(payload, fallbackUser: null);
    await _saveSession(session);
    return session.user;
  }

  AuthSession _mapPayloadToSession(dynamic payload, {AuthUser? fallbackUser}) {
    if (payload is! Map<String, dynamic>) {
      throw const AuthException('服务端返回异常，请稍后再试');
    }
    final tokens = payload['tokens'] as Map<String, dynamic>?;
    final userMap = payload['user'] as Map<String, dynamic>?;
    if (tokens == null) {
      throw const AuthException('未获取到登录令牌');
    }
    final expiresIn = (tokens['expires_in'] as num?)?.toInt() ?? 900;
    if (userMap == null && fallbackUser == null) {
      throw const AuthException('未获取到用户信息');
    }
    final user = userMap != null ? AuthUser.fromMap(userMap) : fallbackUser!;
    return AuthSession(
      user: user,
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Future<AuthUser> _fetchProfile(String accessToken) async {
    final data = await _safeRequest(
      () => _apiClient.request(
        method: 'GET',
        path: '/me',
        accessToken: accessToken,
      ),
      defaultMessage: '获取用户信息失败',
    );
    if (data is Map<String, dynamic>) {
      return AuthUser.fromMap(data);
    }
    throw const AuthException('用户信息格式错误');
  }

  Future<List<Map<String, dynamic>>> getDevices() async {
    final session = await _ensureValidSession();
    if (session == null) {
      throw const AuthException('登录已失效，请重新登录');
    }
    final data = await _safeRequest(
      () => _apiClient.request(
        method: 'GET',
        path: '/me/devices',
        accessToken: session.accessToken,
      ),
      defaultMessage: '获取设备列表失败',
    );
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    return [];
  }

  Future<void> logoutDevice(String deviceId) async {
    final session = await _ensureValidSession();
    if (session == null) {
      throw const AuthException('登录已失效，请重新登录');
    }
    await _safeRequest(
      () => _apiClient.request(
        method: 'DELETE',
        path: '/me/devices/$deviceId',
        accessToken: session.accessToken,
      ),
      defaultMessage: '下线设备失败',
    );
  }

  Future<dynamic> _safeRequest(
    Future<dynamic> Function() task, {
    required String defaultMessage,
  }) async {
    try {
      return await task();
    } on ApiException catch (error) {
      throw AuthException(error.message ?? defaultMessage);
    }
  }

  Future<AuthSession?> _readSession() async {
    final raw = _preferences.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return AuthSession.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(AuthSession session) async {
    await _preferences.setString(_sessionKey, jsonEncode(session.toMap()));
  }

  Future<void> _clearSession() async {
    await _preferences.remove(_sessionKey);
  }
}
