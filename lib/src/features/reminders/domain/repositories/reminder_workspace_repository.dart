import '../entities/reminder_models.dart';

class ReminderSaveResult {
  const ReminderSaveResult({required this.workspace, required this.reminder});

  final ReminderWorkspace workspace;
  final ReminderItem reminder;
}

abstract class ReminderWorkspaceRepository {
  Future<ReminderWorkspace> fetchWorkspace();

  Future<ReminderWorkspace> seedIfEmpty();

  Future<ReminderWorkspace> refreshWorkspace();

  Future<ReminderSaveResult> saveReminder(ReminderItem reminder);

  Future<ReminderWorkspace> deleteReminder(String id);

  Future<ReminderWorkspace> saveList(ReminderList list);

  Future<ReminderWorkspace> saveGroup(ReminderGroup group);

  Future<ReminderWorkspace> saveTag(ReminderTag tag);
}
