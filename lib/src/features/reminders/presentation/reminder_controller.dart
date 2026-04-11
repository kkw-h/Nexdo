import 'package:flutter/foundation.dart';

import '../application/reminder_notification_service.dart';
import '../domain/entities/reminder_models.dart';
import '../domain/repositories/reminder_workspace_repository.dart';

class ReminderController extends ChangeNotifier {
  ReminderController(this._repository, this._notificationService);

  final ReminderWorkspaceRepository _repository;
  final ReminderNotificationService _notificationService;

  ReminderWorkspace _workspace = const ReminderWorkspace(
    reminders: [],
    lists: [],
    groups: [],
    tags: [],
  );

  bool _isLoading = true;

  ReminderWorkspace get workspace => _workspace;
  List<ReminderItem> get reminders => List.unmodifiable(_workspace.reminders);
  List<ReminderList> get lists => List.unmodifiable(_workspace.lists);
  List<ReminderGroup> get groups => List.unmodifiable(_workspace.groups);
  List<ReminderTag> get tags => List.unmodifiable(_workspace.tags);
  bool get isLoading => _isLoading;

  Future<void> bootstrap() async {
    _isLoading = true;
    notifyListeners();
    _workspace = await _repository.seedIfEmpty();
    await _notificationService.syncAll(_workspace.reminders);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _workspace = await _repository.refreshWorkspace();
    await _notificationService.syncAll(_workspace.reminders);
    notifyListeners();
  }

  List<ReminderItem> remindersFor(ReminderFilter filter) {
    switch (filter) {
      case ReminderFilter.today:
        final todays =
            _workspace.reminders.where((item) => item.isDueToday).toList();
        todays.sort((a, b) {
          if (a.isCompleted != b.isCompleted) {
            return a.isCompleted ? 1 : -1;
          }
          return a.dueAt.compareTo(b.dueAt);
        });
        return todays;
      case ReminderFilter.upcoming:
        return _workspace.reminders
            .where((item) => !item.isCompleted && !item.isDueToday)
            .toList();
      case ReminderFilter.completed:
        return _workspace.reminders.where((item) => item.isCompleted).toList();
      case ReminderFilter.all:
        return _workspace.reminders;
    }
  }

  List<ReminderItem> remindersForDate(DateTime date) {
    return _workspace.reminders.where((item) {
      return item.dueAt.year == date.year &&
          item.dueAt.month == date.month &&
          item.dueAt.day == date.day;
    }).toList();
  }

  List<ReminderItem> remindersForList(String listId, ReminderFilter filter) {
    return remindersFor(filter).where((item) => item.listId == listId).toList();
  }

  ReminderList? findList(String id) {
    return _workspace.lists.cast<ReminderList?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
  }

  ReminderGroup? findGroup(String id) {
    return _workspace.groups.cast<ReminderGroup?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
  }

  List<ReminderTag> findTags(List<String> ids) {
    return _workspace.tags.where((tag) => ids.contains(tag.id)).toList();
  }

  Future<void> saveReminder(ReminderItem reminder) async {
    final result = await _repository.saveReminder(reminder);
    _workspace = result.workspace;
    await _notificationService.scheduleForReminder(result.reminder);
    notifyListeners();
  }

  Future<void> toggleCompletion(ReminderItem reminder, bool isCompleted) async {
    if (isCompleted && reminder.repeatRule != ReminderRepeatRule.none) {
      await saveReminder(
        reminder.copyWith(
          dueAt: reminder.repeatRule.nextDate(reminder.dueAt),
          updatedAt: DateTime.now(),
          isCompleted: false,
        ),
      );
      return;
    }

    await saveReminder(
      reminder.copyWith(isCompleted: isCompleted, updatedAt: DateTime.now()),
    );
  }

  Future<void> removeReminder(String id) async {
    _workspace = await _repository.deleteReminder(id);
    await _notificationService.cancelReminder(id);
    notifyListeners();
  }

  Future<void> createList(String name, int colorValue) async {
    _workspace = await _repository.saveList(
      ReminderList(
        id: 'list-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        colorValue: colorValue,
      ),
    );
    notifyListeners();
  }

  Future<void> createGroup(String name, int iconCodePoint) async {
    _workspace = await _repository.saveGroup(
      ReminderGroup(
        id: 'group-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        iconCodePoint: iconCodePoint,
      ),
    );
    notifyListeners();
  }

  Future<void> createTag(String name, int colorValue) async {
    _workspace = await _repository.saveTag(
      ReminderTag(
        id: 'tag-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        colorValue: colorValue,
      ),
    );
    notifyListeners();
  }
}
