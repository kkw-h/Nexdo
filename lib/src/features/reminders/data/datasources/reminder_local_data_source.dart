import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/reminder_models.dart';

class ReminderLocalDataSource {
  ReminderLocalDataSource(this._preferences);

  static const _storageKey = 'reminder_workspace.v2';

  final SharedPreferences _preferences;

  Future<ReminderWorkspace?> readWorkspace() async {
    final raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return ReminderWorkspace.decode(raw);
  }

  Future<void> writeWorkspace(ReminderWorkspace workspace) async {
    await _preferences.setString(_storageKey, workspace.encode());
  }
}
