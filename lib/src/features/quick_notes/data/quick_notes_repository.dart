import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';
import 'package:nexdo/src/core/network/api_client.dart';
import 'package:nexdo/src/core/network/api_exception.dart';
import 'package:nexdo/src/features/auth/data/auth_repository.dart'
    show AccessTokenProvider, AuthException;

import '../domain/entities/quick_note.dart';
import 'quick_note_local_data_source.dart';

class QuickNotesRepository {
  QuickNotesRepository(
    this._apiClient,
    this._tokenProvider,
    this._localDataSource,
  );

  final NexdoApiClient _apiClient;
  final AccessTokenProvider _tokenProvider;
  final QuickNoteLocalDataSource _localDataSource;

  List<QuickNote>? _cache;

  Future<List<QuickNote>> fetchNotes({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) {
      return _cache!;
    }
    if (!forceRefresh) {
      final local = await _localDataSource.readNotes();
      if (local.isNotEmpty) {
        _cache = local;
        return local;
      }
    }
    return refreshNotes();
  }

  Future<List<QuickNote>> refreshNotes() async {
    final data = await _authorizedRequest(method: 'GET', path: '/quick-notes');
    final notes = ((data as List<dynamic>? ?? const <dynamic>[])
        .map((item) => QuickNote.fromMap(item as Map<String, dynamic>))
        .toList());
    return _replaceCache(notes);
  }

  Future<List<QuickNote>> createNote({
    required String content,
    String? audioPath,
    int? audioDurationMillis,
    List<double>? waveformSamples,
  }) async {
    final trimmedContent = content.trim();
    final hasAudio = audioPath != null && audioPath.isNotEmpty;
    if (trimmedContent.isEmpty && !hasAudio) {
      throw const AuthException('请先输入内容或录制语音');
    }

    final dynamic data;
    if (hasAudio) {
      data = await _authorizedMultipartRequest(
        path: '/quick-notes',
        fields: {
          if (trimmedContent.isNotEmpty) 'content': trimmedContent,
          if (audioDurationMillis != null)
            'audio_duration_ms': audioDurationMillis.toString(),
          if (waveformSamples != null && waveformSamples.isNotEmpty)
            'waveform_samples': jsonEncode(waveformSamples),
        },
        fileFieldName: 'audio',
        filePath: audioPath,
        fileContentType: _audioMediaType(audioPath),
      );
    } else {
      data = await _authorizedRequest(
        method: 'POST',
        path: '/quick-notes',
        body: {'content': trimmedContent},
      );
    }

    final saved = QuickNote.fromMap(
      data as Map<String, dynamic>,
    ).copyWith(
      audioPath: hasAudio ? audioPath : null,
      waveformSamples: waveformSamples,
    );
    final notes = [...(_cache ?? await _localDataSource.readNotes())]
      ..removeWhere((item) => item.id == saved.id)
      ..insert(0, saved);
    return _replaceCache(notes);
  }

  Future<List<QuickNote>> deleteNote(String id) async {
    await _authorizedRequest(method: 'DELETE', path: '/quick-notes/$id');
    final notes = [...(_cache ?? await _localDataSource.readNotes())]
      ..removeWhere((item) => item.id == id);
    return _replaceCache(notes);
  }

  Future<String> ensurePlayableAudioPath(QuickNote note) async {
    final localPath = note.audioPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        return localPath;
      }
    }

    if (note.audioUrl == null || note.audioUrl!.isEmpty) {
      throw const AuthException('当前闪念没有可播放的录音');
    }

    final bytes = await _authorizedDownload(note.audioUrl!, note.id);
    final directory = await _localDataSource.ensureAudioDirectory();
    final ext = _fileExtension(note.audioFilename, note.audioMimeType);
    final path = '${directory.path}/${note.id}.$ext';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final updated = note.copyWith(audioPath: path);
    final notes = [...(_cache ?? await _localDataSource.readNotes())];
    final index = notes.indexWhere((item) => item.id == updated.id);
    if (index != -1) {
      notes[index] = updated;
    } else {
      notes.insert(0, updated);
    }
    await _replaceCache(notes);
    return path;
  }

  Future<Directory> ensureAudioDirectory() {
    return _localDataSource.ensureAudioDirectory();
  }

  Future<List<QuickNote>> _replaceCache(List<QuickNote> notes) async {
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _cache = notes;
    await _localDataSource.writeNotes(notes);
    return notes;
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
      );
    }

    final token = await _tokenProvider.requireAccessToken();
    try {
      return await send(token);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        final refreshedToken = await _tokenProvider.refreshAccessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          return await send(refreshedToken);
        }
        throw const AuthException('登录已失效，请重新登录', shouldLogout: true);
      }
      throw AuthException(error.message ?? '闪念接口调用失败');
    }
  }

  Future<dynamic> _authorizedMultipartRequest({
    required String path,
    required Map<String, String> fields,
    required String fileFieldName,
    required String? filePath,
    MediaType? fileContentType,
  }) async {
    Future<dynamic> send(String token) {
      return _apiClient.requestMultipart(
        method: 'POST',
        path: path,
        fields: fields,
        fileFieldName: fileFieldName,
        filePath: filePath,
        fileContentType: fileContentType,
        accessToken: token,
      );
    }

    final token = await _tokenProvider.requireAccessToken();
    try {
      return await send(token);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        final refreshedToken = await _tokenProvider.refreshAccessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          return await send(refreshedToken);
        }
        throw const AuthException('登录已失效，请重新登录', shouldLogout: true);
      }
      throw AuthException(error.message ?? '上传闪念录音失败');
    }
  }

  Future<Uint8List> _authorizedDownload(String audioUrl, String id) async {
    Future<Uint8List> send(String token) {
      return _apiClient.downloadBytes(
        uri: Uri.parse(audioUrl),
        accessToken: token,
      );
    }

    final token = await _tokenProvider.requireAccessToken();
    try {
      return await send(token);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        final refreshedToken = await _tokenProvider.refreshAccessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          return await send(refreshedToken);
        }
        throw const AuthException('登录已失效，请重新登录', shouldLogout: true);
      }
      throw AuthException(error.message ?? '下载录音失败: $id');
    }
  }

  MediaType _audioMediaType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.m4a')) {
      return MediaType('audio', 'mp4');
    }
    if (lower.endsWith('.wav')) {
      return MediaType('audio', 'wav');
    }
    if (lower.endsWith('.mp3')) {
      return MediaType('audio', 'mpeg');
    }
    return MediaType('audio', 'aac');
  }

  String _fileExtension(String? filename, String? mimeType) {
    final name = filename?.trim() ?? '';
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < name.length - 1) {
      return name.substring(dotIndex + 1);
    }
    if (mimeType == 'audio/mpeg') {
      return 'mp3';
    }
    if (mimeType == 'audio/wav') {
      return 'wav';
    }
    return 'm4a';
  }
}
