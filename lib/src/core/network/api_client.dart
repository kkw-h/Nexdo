import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

class NexdoApiClient {
  NexdoApiClient({
    String? baseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
  }) : baseUrl = baseUrl ?? _resolveDefaultBaseUrl(),
       _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  final http.Client _httpClient;
  final Duration _timeout;
  final String baseUrl;

  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    Object? body,
    Map<String, String>? headers,
    String? accessToken,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $accessToken';
    }
    if (headers != null) {
      requestHeaders.addAll(headers);
    }

    final normalizedMethod = method.toUpperCase().trim();
    final encodedBody = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      switch (normalizedMethod) {
        case 'GET':
          response = await _httpClient
              .get(uri, headers: requestHeaders)
              .timeout(_timeout);
          break;
        case 'POST':
          response = await _httpClient
              .post(uri, headers: requestHeaders, body: encodedBody)
              .timeout(_timeout);
          break;
        case 'PATCH':
          response = await _httpClient
              .patch(uri, headers: requestHeaders, body: encodedBody)
              .timeout(_timeout);
          break;
        case 'DELETE':
          response = await _httpClient
              .delete(uri, headers: requestHeaders, body: encodedBody)
              .timeout(_timeout);
          break;
        default:
          throw ApiException(
            statusCode: -1,
            message: 'Unsupported method $method',
          );
      }
    } on SocketException catch (error, stackTrace) {
      developer.log(
        '[NexdoApiClient] 网络不可用: ${error.message}',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApiException(
        statusCode: -1,
        message: '网络不可用，请检查连接: ${error.message}',
      );
    } on http.ClientException catch (error) {
      throw ApiException(statusCode: -1, message: '请求失败: ${error.message}');
    } on TimeoutException {
      throw const ApiException(statusCode: -1, message: '请求超时，请稍后再试');
    }

    if (response.body.isEmpty) {
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }

    if (response.statusCode >= 400) {
      if (decoded is Map<String, dynamic>) {
        throw ApiException(
          statusCode: response.statusCode,
          code: decoded['code'] as int?,
          message: decoded['message'] as String? ?? '请求失败',
          details: decoded['error'],
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        message: '请求失败(${response.statusCode})',
        details: decoded,
      );
    }

    if (decoded is Map<String, dynamic> && decoded.containsKey('code')) {
      final code = decoded['code'] as int?;
      if (code != null && code != 0) {
        throw ApiException(
          statusCode: response.statusCode,
          code: code,
          message: decoded['message'] as String? ?? '请求失败',
          details: decoded['error'],
        );
      }
      return decoded['data'];
    }

    return decoded;
  }

  Uri _buildUri(String path, Map<String, dynamic>? queryParameters) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBase$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    final qp = queryParameters.map((key, value) {
      return MapEntry(key, value?.toString() ?? '');
    });
    return uri.replace(queryParameters: qp);
  }

  static String _resolveDefaultBaseUrl() {
    const envBase = String.fromEnvironment(
      'NEXDO_API_BASE_URL',
      defaultValue: '',
    );
    if (envBase.isNotEmpty) {
      return envBase;
    }
    return 'https://nexdo.kkw-cloud.cc/api/v1';
  }
}
