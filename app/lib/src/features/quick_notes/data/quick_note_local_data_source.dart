import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/quick_note.dart';

class QuickNoteLocalDataSource {
  QuickNoteLocalDataSource(this._preferences, {required String userId})
    : _storageKey = 'quick_notes.$userId.v1';

  final SharedPreferences _preferences;
  final String _storageKey;

  Future<List<QuickNote>> readNotes() async {
    final raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => QuickNote.fromMap(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeNotes(List<QuickNote> notes) async {
    final payload = jsonEncode(notes.map((item) => item.toMap()).toList());
    await _preferences.setString(_storageKey, payload);
  }

  Future<List<QuickNote>> saveNote(QuickNote note) async {
    final notes = await readNotes();
    final updated = [note, ...notes.where((item) => item.id != note.id)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await writeNotes(updated);
    return updated;
  }

  Future<List<QuickNote>> deleteNote(String id) async {
    final notes = await readNotes();
    QuickNote? target;
    for (final item in notes) {
      if (item.id == id) {
        target = item;
        break;
      }
    }
    final path = target?.audioPath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    final updated = notes.where((item) => item.id != id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await writeNotes(updated);
    return updated;
  }

  Future<Directory> ensureAudioDirectory() async {
    final baseDirectory = await getApplicationSupportDirectory();
    final directory = Directory('${baseDirectory.path}/quick_notes');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
