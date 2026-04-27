import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../device/device_identity.dart';
import 'api_exception.dart';

class NexdoApiClient {
  NexdoApiClient({
    String? baseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
    DeviceIdentityProvider? deviceIdentityProvider,
  }) : baseUrl = baseUrl ?? _resolveDefaultBaseUrl(),
       _httpClient = httpClient ?? http.Client(),
       _timeout = timeout,
       _deviceIdentityProvider =
           deviceIdentityProvider ?? DeviceIdentityProvider.instance;

  final http.Client _httpClient;
  final Duration _timeout;
  final String baseUrl;
  final DeviceIdentityProvider _deviceIdentityProvider;

  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    Object? body,
    Map<String, String>? headers,
    String? accessToken,
    Duration? timeout,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final requestHeaders = await _buildHeaders(
      accessToken: accessToken,
      headers: headers,
      hasJsonBody: body != null,
    );
    final effectiveTimeout = timeout ?? _timeout;

    final normalizedMethod = method.toUpperCase().trim();
    final encodedBody = body == null ? null : jsonEncode(body);
    final startedAt = DateTime.now();
    developer.log(
      '[NexdoApiClient] request start method=$normalizedMethod path=$path uri=$uri hasBody=${body != null}',
    );

    http.Response response;
    try {
      switch (normalizedMethod) {
        case 'GET':
          response = await _httpClient
              .get(uri, headers: requestHeaders)
              .timeout(effectiveTimeout);
          break;
        case 'POST':
          response = await _httpClient
              .post(uri, headers: requestHeaders, body: encodedBody)
              .timeout(effectiveTimeout);
          break;
        case 'PATCH':
          response = await _httpClient
              .patch(uri, headers: requestHeaders, body: encodedBody)
              .timeout(effectiveTimeout);
          break;
        case 'DELETE':
          response = await _httpClient
              .delete(uri, headers: requestHeaders, body: encodedBody)
              .timeout(effectiveTimeout);
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

    developer.log(
      '[NexdoApiClient] request done method=$normalizedMethod path=$path status=${response.statusCode} elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}',
    );

    return _decodeResponse(response);
  }

  Future<dynamic> requestMultipart({
    required String method,
    required String path,
    Map<String, String>? fields,
    String? fileFieldName,
    String? filePath,
    MediaType? fileContentType,
    Map<String, String>? headers,
    String? accessToken,
  }) async {
    final uri = _buildUri(path, null);
    final request = http.MultipartRequest(method.toUpperCase().trim(), uri);
    request.headers.addAll(
      await _buildHeaders(accessToken: accessToken, headers: headers),
    );
    if (fields != null && fields.isNotEmpty) {
      request.fields.addAll(fields);
    }
    if (fileFieldName != null && filePath != null && filePath.isNotEmpty) {
      final normalizedPath = _normalizeLocalPath(filePath);
      final file = File(normalizedPath);
      if (!file.existsSync()) {
        throw ApiException(
          statusCode: -1,
          message: '本地录音文件不存在，无法上传',
          details: normalizedPath,
        );
      }
      request.files.add(
        await http.MultipartFile.fromPath(
          fileFieldName,
          normalizedPath,
          contentType: fileContentType,
        ),
      );
    }

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _httpClient.send(request).timeout(_timeout);
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

    final response = await http.Response.fromStream(streamedResponse);
    return _decodeResponse(response);
  }

  Future<Stream<Map<String, dynamic>>> requestSse({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    Object? body,
    Map<String, String>? headers,
    String? accessToken,
    Duration? timeout,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final requestHeaders = await _buildHeaders(
      accessToken: accessToken,
      headers: headers,
      hasJsonBody: body != null,
    );
    final effectiveTimeout = timeout ?? _timeout;
    final startedAt = DateTime.now();
    final request = http.Request(method.toUpperCase().trim(), uri);
    request.headers.addAll(requestHeaders);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(effectiveTimeout);
    } on SocketException catch (error, stackTrace) {
      developer.log(
        '[NexdoApiClient] SSE 网络不可用: ${error.message}',
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

    developer.log(
      '[NexdoApiClient] sse connected method=${request.method} path=$path status=${response.statusCode} elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}',
    );

    if (response.statusCode >= 400) {
      final bodyText = await response.stream.bytesToString();
      dynamic decoded;
      try {
        decoded = jsonDecode(bodyText);
      } catch (_) {
        decoded = bodyText;
      }
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

    return _parseSseResponse(response);
  }

  String _normalizeLocalPath(String path) {
    if (path.startsWith('file://')) {
      return Uri.parse(path).toFilePath();
    }
    return path;
  }

  Future<Uint8List> downloadBytes({
    String? path,
    Uri? uri,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    String? accessToken,
  }) async {
    final targetUri = uri ?? _buildUri(path ?? '', queryParameters);
    final requestHeaders = await _buildHeaders(
      accessToken: accessToken,
      headers: headers,
    );
    http.Response response;
    try {
      response = await _httpClient
          .get(targetUri, headers: requestHeaders)
          .timeout(_timeout);
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

    if (response.statusCode >= 400) {
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
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

    return response.bodyBytes;
  }

  Future<Map<String, String>> _buildHeaders({
    Map<String, String>? headers,
    String? accessToken,
    bool hasJsonBody = false,
  }) async {
    final identity = await _deviceIdentityProvider.ensureIdentity();
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'User-Agent': identity.userAgent,
      'X-Nexdo-Device-ID': _sanitizeHeaderValue(identity.deviceId),
      'X-Nexdo-Device-Name': _sanitizeHeaderValue(identity.deviceName),
      'X-Nexdo-Device-Platform': _sanitizeHeaderValue(identity.platform),
      if (hasJsonBody) 'Content-Type': 'application/json; charset=utf-8',
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $accessToken';
    }
    if (headers != null) {
      requestHeaders.addAll(headers);
    }
    return requestHeaders.map(
      (key, value) => MapEntry(key, _sanitizeHeaderValue(value)),
    );
  }

  String _sanitizeHeaderValue(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.codeUnits) {
      if (codeUnit >= 32 && codeUnit <= 126) {
        buffer.writeCharCode(codeUnit);
      } else {
        buffer.write('?');
      }
    }
    return buffer.toString();
  }

  dynamic _decodeResponse(http.Response response) {
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

  Stream<Map<String, dynamic>> _parseSseResponse(
    http.StreamedResponse response,
  ) async* {
    String eventName = 'message';
    final dataLines = <String>[];

    Future<Map<String, dynamic>?> emit() async {
      if (dataLines.isEmpty) {
        eventName = 'message';
        return null;
      }
      final rawData = dataLines.join('\n');
      dataLines.clear();
      dynamic decoded;
      try {
        decoded = jsonDecode(rawData);
      } catch (_) {
        decoded = rawData;
      }
      final payload = <String, dynamic>{'event': eventName, 'data': decoded};
      eventName = 'message';
      return payload;
    }

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) {
        final payload = await emit();
        if (payload != null) {
          developer.log('[NexdoApiClient] sse event event=${payload['event']}');
          yield payload;
        }
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    final payload = await emit();
    if (payload != null) {
      developer.log('[NexdoApiClient] sse event event=${payload['event']}');
      yield payload;
    }
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
    return 'https://nexdo.kkworld.top/api/v1';
  }
}
