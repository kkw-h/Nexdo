import '../entities/reminder_models.dart';

class ReminderSaveResult {
  const ReminderSaveResult({required this.workspace, required this.reminder});

  final ReminderWorkspace workspace;
  final ReminderItem reminder;
}

abstract class ReminderWorkspaceRepository {
  Future<ReminderWorkspace> fetchWorkspace();

  Future<ReminderWorkspace> seedIfEmpty();

  Future<ReminderWorkspace> refreshWorkspace({bool forceBootstrap = false});

  Future<List<ReminderItem>> queryReminders(ReminderQuery query);

  Future<List<ReminderCompletionLog>> fetchCompletionLogs(String reminderId);

  Future<ReminderSaveResult> saveReminder(ReminderItem reminder);

  Future<ReminderWorkspace> deleteReminder(String id);

  Future<ReminderWorkspace> saveList(ReminderList list);

  Future<ReminderWorkspace> deleteList(String id);

  Future<ReminderWorkspace> saveGroup(ReminderGroup group);

  Future<ReminderWorkspace> deleteGroup(String id);

  Future<ReminderWorkspace> saveTag(ReminderTag tag);

  Future<ReminderWorkspace> deleteTag(String id);
}
