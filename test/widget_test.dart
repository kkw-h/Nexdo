import 'package:flutter_test/flutter_test.dart';

import 'package:nexdo/src/features/reminders/domain/entities/reminder_models.dart';

void main() {
  test('workspace encode/decode keeps nested data intact', () {
    final now = DateTime(2026, 4, 11, 9, 0);
    final workspace = ReminderWorkspace(
      lists: const [
        ReminderList(id: 'list-1', name: '工作', colorValue: 0xFF126A5A),
      ],
      groups: const [
        ReminderGroup(id: 'group-1', name: '高优先级', iconCodePoint: 123),
      ],
      tags: const [
        ReminderTag(id: 'tag-1', name: '紧急', colorValue: 0xFFC75C3A),
      ],
      reminders: [
        ReminderItem(
          id: 'r1',
          title: '测试提醒',
          note: '备注',
          dueAt: now,
          isCompleted: false,
          createdAt: now,
          updatedAt: now,
          listId: 'list-1',
          groupId: 'group-1',
          tagIds: const ['tag-1'],
          notificationEnabled: true,
          repeatRule: ReminderRepeatRule.weekly,
        ),
      ],
    );

    final encoded = workspace.encode();
    final decoded = ReminderWorkspace.decode(encoded);

    expect(decoded.lists.single.name, '工作');
    expect(decoded.groups.single.name, '高优先级');
    expect(decoded.tags.single.name, '紧急');
    expect(decoded.reminders.single.tagIds, ['tag-1']);
    expect(decoded.reminders.single.notificationEnabled, isTrue);
    expect(decoded.reminders.single.repeatRule, ReminderRepeatRule.weekly);
  });

  test('repeat rule supports workday and restday aliases', () {
    final friday = DateTime(2026, 4, 17, 19, 0);
    final saturday = DateTime(2026, 4, 18, 19, 0);

    expect(
      ReminderRepeatRuleX.fromStorage('workday'),
      ReminderRepeatRule.workday,
    );
    expect(
      ReminderRepeatRuleX.fromStorage('weekend'),
      ReminderRepeatRule.restday,
    );
    expect(
      ReminderRepeatRule.workday.nextDate(friday),
      DateTime(2026, 4, 20, 19, 0),
    );
    expect(
      ReminderRepeatRule.restday.nextDate(saturday),
      DateTime(2026, 4, 19, 19, 0),
    );
  });

  test('completion log encode/decode keeps reminder timestamps intact', () {
    final log = ReminderCompletionLog(
      id: 'log-1',
      reminderId: 'reminder-1',
      completedAt: DateTime.parse('2026-04-17T09:30:00+08:00'),
      originalDueAt: DateTime.parse('2026-04-17T09:00:00+08:00'),
      nextDueAt: DateTime.parse('2026-04-18T09:00:00+08:00'),
      createdAt: DateTime.parse('2026-04-17T09:30:10+08:00'),
    );

    final decoded = ReminderCompletionLog.fromMap(log.toMap());

    expect(decoded.id, 'log-1');
    expect(decoded.reminderId, 'reminder-1');
    expect(decoded.completedAt, log.completedAt);
    expect(decoded.originalDueAt, log.originalDueAt);
    expect(decoded.nextDueAt, log.nextDueAt);
    expect(decoded.createdAt, log.createdAt);
  });
}
