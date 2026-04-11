import '../../domain/entities/reminder_models.dart';
import '../../domain/repositories/reminder_workspace_repository.dart';
import '../datasources/reminder_local_data_source.dart';

class LocalFirstReminderWorkspaceRepository
    implements ReminderWorkspaceRepository {
  LocalFirstReminderWorkspaceRepository(this._localDataSource);

  final ReminderLocalDataSource _localDataSource;

  @override
  Future<ReminderWorkspace> fetchWorkspace() async {
    final workspace = await _localDataSource.readWorkspace();
    return _sortWorkspace(workspace ?? _emptyWorkspace());
  }

  @override
  Future<ReminderWorkspace> seedIfEmpty() async {
    final existing = await _localDataSource.readWorkspace();
    if (existing != null) {
      return _sortWorkspace(existing);
    }

    final now = DateTime.now();
    final workspace = ReminderWorkspace(
      lists: const [
        ReminderList(id: 'list-work', name: '工作', colorValue: 0xFF126A5A),
        ReminderList(id: 'list-life', name: '生活', colorValue: 0xFFB85C38),
        ReminderList(id: 'list-study', name: '学习', colorValue: 0xFF4E6D7A),
      ],
      groups: const [
        ReminderGroup(id: 'group-focus', name: '高优先级', iconCodePoint: 0xe318),
        ReminderGroup(id: 'group-routine', name: '日常', iconCodePoint: 0xe3c9),
        ReminderGroup(id: 'group-review', name: '复盘', iconCodePoint: 0xf04f4),
      ],
      tags: const [
        ReminderTag(id: 'tag-urgent', name: '紧急', colorValue: 0xFFC75C3A),
        ReminderTag(id: 'tag-deep', name: '深度工作', colorValue: 0xFF2B6F77),
        ReminderTag(id: 'tag-team', name: '协作', colorValue: 0xFF6B5FB3),
      ],
      reminders: [
        ReminderItem(
          id: 'seed-1',
          title: '确认本周最重要的 3 件事',
          note: '把优先级和截止时间整理清楚，避免提醒越来越碎片化。',
          dueAt: DateTime(now.year, now.month, now.day, 9, 30),
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
          listId: 'list-work',
          groupId: 'group-focus',
          tagIds: const ['tag-urgent', 'tag-deep'],
          notificationEnabled: true,
          repeatRule: ReminderRepeatRule.weekly,
        ),
        ReminderItem(
          id: 'seed-2',
          title: '晚上复盘今天完成情况',
          note: '完成后补一下明天的提醒安排。',
          dueAt: DateTime(now.year, now.month, now.day, 20, 0),
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
          listId: 'list-life',
          groupId: 'group-review',
          tagIds: const ['tag-team'],
          notificationEnabled: true,
          repeatRule: ReminderRepeatRule.daily,
        ),
        ReminderItem(
          id: 'seed-3',
          title: '准备下周需求评审材料',
          note: '列出待办、风险和依赖项。',
          dueAt: DateTime(now.year, now.month, now.day + 2, 14, 0),
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
          listId: 'list-work',
          groupId: 'group-routine',
          tagIds: const ['tag-team'],
          notificationEnabled: true,
          repeatRule: ReminderRepeatRule.none,
        ),
      ],
    );

    final sorted = _sortWorkspace(workspace);
    await _localDataSource.writeWorkspace(sorted);
    return sorted;
  }

  @override
  Future<ReminderWorkspace> refreshWorkspace() async {
    return fetchWorkspace();
  }

  @override
  Future<ReminderSaveResult> saveReminder(ReminderItem reminder) async {
    final workspace = await fetchWorkspace();
    final reminders = [...workspace.reminders];
    final index = reminders.indexWhere((item) => item.id == reminder.id);
    if (index == -1) {
      reminders.add(reminder);
    } else {
      reminders[index] = reminder;
    }
    final updated = _sortWorkspace(workspace.copyWith(reminders: reminders));
    await _localDataSource.writeWorkspace(updated);
    return ReminderSaveResult(workspace: updated, reminder: reminder);
  }

  @override
  Future<ReminderWorkspace> deleteReminder(String id) async {
    final workspace = await fetchWorkspace();
    final updated = _sortWorkspace(
      workspace.copyWith(
        reminders: workspace.reminders.where((item) => item.id != id).toList(),
      ),
    );
    await _localDataSource.writeWorkspace(updated);
    return updated;
  }

  @override
  Future<ReminderWorkspace> saveList(ReminderList list) async {
    final workspace = await fetchWorkspace();
    final lists = [...workspace.lists];
    final index = lists.indexWhere((item) => item.id == list.id);
    if (index == -1) {
      lists.add(list);
    } else {
      lists[index] = list;
    }
    final updated = workspace.copyWith(
      lists: [...lists]..sort((a, b) => a.name.compareTo(b.name)),
    );
    await _localDataSource.writeWorkspace(updated);
    return updated;
  }

  @override
  Future<ReminderWorkspace> saveGroup(ReminderGroup group) async {
    final workspace = await fetchWorkspace();
    final groups = [...workspace.groups];
    final index = groups.indexWhere((item) => item.id == group.id);
    if (index == -1) {
      groups.add(group);
    } else {
      groups[index] = group;
    }
    final updated = workspace.copyWith(
      groups: [...groups]..sort((a, b) => a.name.compareTo(b.name)),
    );
    await _localDataSource.writeWorkspace(updated);
    return updated;
  }

  @override
  Future<ReminderWorkspace> saveTag(ReminderTag tag) async {
    final workspace = await fetchWorkspace();
    final tags = [...workspace.tags];
    final index = tags.indexWhere((item) => item.id == tag.id);
    if (index == -1) {
      tags.add(tag);
    } else {
      tags[index] = tag;
    }
    final updated = workspace.copyWith(
      tags: [...tags]..sort((a, b) => a.name.compareTo(b.name)),
    );
    await _localDataSource.writeWorkspace(updated);
    return updated;
  }

  ReminderWorkspace _emptyWorkspace() {
    return const ReminderWorkspace(
      reminders: [],
      lists: [],
      groups: [],
      tags: [],
    );
  }

  ReminderWorkspace _sortWorkspace(ReminderWorkspace workspace) {
    final reminders = [...workspace.reminders]
      ..sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        return a.dueAt.compareTo(b.dueAt);
      });

    return workspace.copyWith(reminders: reminders);
  }
}
