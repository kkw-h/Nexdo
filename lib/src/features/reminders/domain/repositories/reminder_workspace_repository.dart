import '../entities/reminder_models.dart';

abstract class ReminderWorkspaceRepository {
  Future<ReminderWorkspace> fetchWorkspace();

  Future<ReminderWorkspace> seedIfEmpty();

  Future<ReminderWorkspace> saveReminder(ReminderItem reminder);

  Future<ReminderWorkspace> deleteReminder(String id);

  Future<ReminderWorkspace> saveList(ReminderList list);

  Future<ReminderWorkspace> saveGroup(ReminderGroup group);

  Future<ReminderWorkspace> saveTag(ReminderTag tag);
}
