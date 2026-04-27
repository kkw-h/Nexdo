import 'dart:developer' as developer;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/data/auth_repository.dart'
    show AccessTokenProvider, AuthException;
import '../domain/ai_command_models.dart';

class AiCommandRepository {
  static const Duration _aiRequestTimeout = Duration(seconds: 60);

  AiCommandRepository(this._apiClient, this._tokenProvider);

  final NexdoApiClient _apiClient;
  final AccessTokenProvider _tokenProvider;

  Future<AiCommandResolveResponse> resolve(String input) async {
    developer.log(
      '[AiCommandRepository] resolve start inputLength=${input.trim().length}',
    );
    final data = await _authorizedRequest(
      method: 'POST',
      path: '/ai/commands/resolve',
      body: {'input': input.trim()},
    );
    developer.log('[AiCommandRepository] resolve success');
    return AiCommandResolveResponse.fromMap(_asMap(data));
  }

  Stream<AiCommandStreamEvent> resolveStream(String input) async* {
    developer.log(
      '[AiCommandRepository] resolveStream start inputLength=${input.trim().length}',
    );
    final stream = await _authorizedSseRequest(
      method: 'POST',
      path: '/ai/commands/resolve/stream',
      body: {'input': input.trim()},
    );
    await for (final payload in stream) {
      final event = AiCommandStreamEvent.fromMap(payload);
      developer.log(
        '[AiCommandRepository] resolveStream event=${event.event} stage=${event.stage} code=${event.code}',
      );
      if (event.event == 'error') {
        if (event.code == 40100) {
          throw const AuthException('登录已失效，请重新登录', shouldLogout: true);
        }
        throw AuthException(event.message ?? 'AI 指令调用失败');
      }
      yield event;
    }
  }

  Future<AiCommandVerifyResponse> verify(String token) async {
    developer.log(
      '[AiCommandRepository] verify start tokenLength=${token.length}',
    );
    final data = await _authorizedRequest(
      method: 'POST',
      path: '/ai/commands/confirmations/verify',
      body: {'token': token},
    );
    developer.log('[AiCommandRepository] verify success');
    return AiCommandVerifyResponse.fromMap(_asMap(data));
  }

  Future<AiCommandExecuteResponse> execute(String token) async {
    developer.log(
      '[AiCommandRepository] execute start tokenLength=${token.length}',
    );
    final data = await _authorizedRequest(
      method: 'POST',
      path: '/ai/commands/confirmations/execute',
      body: {'token': token},
    );
    developer.log('[AiCommandRepository] execute success');
    return AiCommandExecuteResponse.fromMap(_asMap(data));
  }

  Future<dynamic> _authorizedRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    Future<dynamic> send(String token) {
      return _apiClient.request(
        method: method,
        path: path,
        body: body,
        accessToken: token,
        timeout: _aiRequestTimeout,
      );
    }

    final token = await _tokenProvider.requireAccessToken();
    try {
      return await send(token);
    } on ApiException catch (error) {
      developer.log(
        '[AiCommandRepository] request failed method=$method path=$path status=${error.statusCode} code=${error.code} message=${error.message} details=${error.details}',
      );
      if (error.isUnauthorized) {
        final refreshedToken = await _tokenProvider.refreshAccessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          developer.log(
            '[AiCommandRepository] request retry with refreshed token path=$path',
          );
          return await send(refreshedToken);
        }
        throw const AuthException('登录已失效，请重新登录', shouldLogout: true);
      }
      throw AuthException(error.message ?? 'AI 指令调用失败');
    }
  }

  Future<Stream<Map<String, dynamic>>> _authorizedSseRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    Future<Stream<Map<String, dynamic>>> send(String token) {
      return _apiClient.requestSse(
        method: method,
        path: path,
        body: body,
        accessToken: token,
        timeout: _aiRequestTimeout,
      );
    }

    final token = await _tokenProvider.requireAccessToken();
    try {
      return await send(token);
    } on ApiException catch (error) {
      developer.log(
        '[AiCommandRepository] sse failed method=$method path=$path status=${error.statusCode} code=${error.code} message=${error.message} details=${error.details}',
      );
      if (error.isUnauthorized) {
        final refreshedToken = await _tokenProvider.refreshAccessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          developer.log(
            '[AiCommandRepository] sse retry with refreshed token path=$path',
          );
          return await send(refreshedToken);
        }
        throw const AuthException('登录已失效，请重新登录', shouldLogout: true);
      }
      throw AuthException(error.message ?? 'AI 指令调用失败');
    }
  }

  Map<String, dynamic> _asMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    throw const AuthException('AI 服务返回格式异常');
  }
}
