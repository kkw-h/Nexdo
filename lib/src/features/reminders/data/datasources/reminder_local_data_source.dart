import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/reminder_models.dart';

class CachedReminderWorkspace {
  const CachedReminderWorkspace({
    required this.workspace,
    this.serverTime,
  });

  final ReminderWorkspace workspace;
  final String? serverTime;
}

class ReminderLocalDataSource {
  ReminderLocalDataSource(this._preferences);

  static const _storageKey = 'reminder_workspace.v2';

  final SharedPreferences _preferences;

  Future<CachedReminderWorkspace?> readCache() async {
    final raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('workspace')) {
          final workspace =
              ReminderWorkspace.fromMap(decoded['workspace'] as Map<String, dynamic>);
          final serverTime = decoded['server_time'] as String?;
          return CachedReminderWorkspace(
            workspace: workspace,
            serverTime: serverTime,
          );
        }
        return CachedReminderWorkspace(
          workspace: ReminderWorkspace.fromMap(decoded),
          serverTime: null,
        );
      }
    } catch (_) {
      // ignore decode errors and treat as missing cache
    }
    return null;
  }

  Future<ReminderWorkspace?> readWorkspace() async {
    final cached = await readCache();
    return cached?.workspace;
  }

  Future<void> writeCache(
    ReminderWorkspace workspace, {
    String? serverTime,
  }) async {
    final extra = serverTime == null ? null : {'server_time': serverTime};
    final payload = jsonEncode({
      'workspace': workspace.toMap(),
      ...?extra,
    });
    await _preferences.setString(_storageKey, payload);
  }

  Future<void> writeWorkspace(ReminderWorkspace workspace) {
    return writeCache(workspace);
  }
}
