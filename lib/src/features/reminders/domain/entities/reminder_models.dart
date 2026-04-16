import 'dart:convert';

enum ReminderFilter { all, pending, completed }

class ReminderQuery {
  const ReminderQuery({
    this.completion = ReminderFilter.all,
    this.listIds = const [],
    this.groupIds = const [],
    this.tagIds = const [],
  });

  final ReminderFilter completion;
  final List<String> listIds;
  final List<String> groupIds;
  final List<String> tagIds;

  bool get isEmpty =>
      completion == ReminderFilter.all &&
      listIds.isEmpty &&
      groupIds.isEmpty &&
      tagIds.isEmpty;

  ReminderQuery copyWith({
    ReminderFilter? completion,
    List<String>? listIds,
    List<String>? groupIds,
    List<String>? tagIds,
  }) {
    return ReminderQuery(
      completion: completion ?? this.completion,
      listIds: listIds ?? this.listIds,
      groupIds: groupIds ?? this.groupIds,
      tagIds: tagIds ?? this.tagIds,
    );
  }
}

enum ReminderRepeatRule {
  none,
  daily,
  weekly,
  monthly,
  yearly,
  workday,
  restday,
}

extension ReminderRepeatRuleX on ReminderRepeatRule {
  String get label {
    switch (this) {
      case ReminderRepeatRule.none:
        return '不重复';
      case ReminderRepeatRule.daily:
        return '每天';
      case ReminderRepeatRule.weekly:
        return '每周';
      case ReminderRepeatRule.monthly:
        return '每月';
      case ReminderRepeatRule.yearly:
        return '每年';
      case ReminderRepeatRule.workday:
        return '工作日';
      case ReminderRepeatRule.restday:
        return '休息日';
    }
  }

  DateTime nextDate(DateTime dateTime) {
    switch (this) {
      case ReminderRepeatRule.none:
        return dateTime;
      case ReminderRepeatRule.daily:
        return dateTime.add(const Duration(days: 1));
      case ReminderRepeatRule.weekly:
        return dateTime.add(const Duration(days: 7));
      case ReminderRepeatRule.monthly:
        return DateTime(
          dateTime.year,
          dateTime.month + 1,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
        );
      case ReminderRepeatRule.yearly:
        return DateTime(
          dateTime.year + 1,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
        );
      case ReminderRepeatRule.workday:
        return _nextMatchingDate(dateTime, (value) {
          return value.weekday >= DateTime.monday &&
              value.weekday <= DateTime.friday;
        });
      case ReminderRepeatRule.restday:
        return _nextMatchingDate(dateTime, (value) {
          return value.weekday == DateTime.saturday ||
              value.weekday == DateTime.sunday;
        });
    }
  }

  String get storageValue {
    switch (this) {
      case ReminderRepeatRule.restday:
        return 'restday';
      default:
        return name;
    }
  }

  static ReminderRepeatRule fromStorage(String? value) {
    final normalized = value?.trim().toLowerCase();
    switch (normalized) {
      case 'workday':
      case 'work_day':
      case 'weekday':
      case 'business_day':
        return ReminderRepeatRule.workday;
      case 'restday':
      case 'rest_day':
      case 'weekend':
      case 'holiday':
        return ReminderRepeatRule.restday;
    }
    return ReminderRepeatRule.values.firstWhere(
      (item) => item.name == normalized,
      orElse: () => ReminderRepeatRule.none,
    );
  }

  DateTime _nextMatchingDate(
    DateTime dateTime,
    bool Function(DateTime value) matcher,
  ) {
    var candidate = dateTime.add(const Duration(days: 1));
    while (!matcher(candidate)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}

class ReminderList {
  const ReminderList({
    required this.id,
    required this.name,
    required this.colorValue,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int colorValue;
  final int sortOrder;

  ReminderList copyWith({
    String? id,
    String? name,
    int? colorValue,
    int? sortOrder,
  }) {
    return ReminderList(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'colorValue': colorValue,
      'sortOrder': sortOrder,
    };
  }

  factory ReminderList.fromMap(Map<String, dynamic> map) {
    return ReminderList(
      id: map['id'] as String,
      name: map['name'] as String,
      colorValue: map['colorValue'] as int,
      sortOrder: map['sortOrder'] as int? ?? 0,
    );
  }
}

class ReminderGroup {
  const ReminderGroup({
    required this.id,
    required this.name,
    required this.iconCodePoint,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int iconCodePoint;
  final int sortOrder;

  ReminderGroup copyWith({
    String? id,
    String? name,
    int? iconCodePoint,
    int? sortOrder,
  }) {
    return ReminderGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'iconCodePoint': iconCodePoint,
      'sortOrder': sortOrder,
    };
  }

  factory ReminderGroup.fromMap(Map<String, dynamic> map) {
    return ReminderGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      iconCodePoint: map['iconCodePoint'] as int,
      sortOrder: map['sortOrder'] as int? ?? 0,
    );
  }
}

class ReminderTag {
  const ReminderTag({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  final String name;
  final int colorValue;

  ReminderTag copyWith({String? id, String? name, int? colorValue}) {
    return ReminderTag(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'colorValue': colorValue};
  }

  factory ReminderTag.fromMap(Map<String, dynamic> map) {
    return ReminderTag(
      id: map['id'] as String,
      name: map['name'] as String,
      colorValue: map['colorValue'] as int,
    );
  }
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
    required this.listId,
    required this.groupId,
    required this.tagIds,
    required this.notificationEnabled,
    required this.repeatRule,
    this.note,
  });

  final String id;
  final String title;
  final String? note;
  final DateTime dueAt;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String listId;
  final String groupId;
  final List<String> tagIds;
  final bool notificationEnabled;
  final ReminderRepeatRule repeatRule;

  ReminderItem copyWith({
    String? id,
    String? title,
    String? note,
    DateTime? dueAt,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? listId,
    String? groupId,
    List<String>? tagIds,
    bool? notificationEnabled,
    ReminderRepeatRule? repeatRule,
    bool clearNote = false,
  }) {
    return ReminderItem(
      id: id ?? this.id,
      title: title ?? this.title,
      note: clearNote ? null : (note ?? this.note),
      dueAt: dueAt ?? this.dueAt,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      listId: listId ?? this.listId,
      groupId: groupId ?? this.groupId,
      tagIds: tagIds ?? this.tagIds,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      repeatRule: repeatRule ?? this.repeatRule,
    );
  }

  bool get isOverdue => !isCompleted && dueAt.isBefore(DateTime.now());

  bool get hasSpecificTime =>
      dueAt.hour != 0 ||
      dueAt.minute != 0 ||
      dueAt.second != 0 ||
      dueAt.millisecond != 0 ||
      dueAt.microsecond != 0;

  bool get isDueToday {
    final now = DateTime.now();
    return dueAt.year == now.year &&
        dueAt.month == now.month &&
        dueAt.day == now.day;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'note': note,
      'dueAt': dueAt.toIso8601String(),
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'listId': listId,
      'groupId': groupId,
      'tagIds': tagIds,
      'notificationEnabled': notificationEnabled,
      'repeatRule': repeatRule.storageValue,
    };
  }

  factory ReminderItem.fromMap(Map<String, dynamic> map) {
    return ReminderItem(
      id: map['id'] as String,
      title: map['title'] as String,
      note: map['note'] as String?,
      dueAt: DateTime.parse(map['dueAt'] as String),
      isCompleted: map['isCompleted'] as bool? ?? false,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      listId: map['listId'] as String,
      groupId: map['groupId'] as String,
      tagIds: (map['tagIds'] as List<dynamic>? ?? []).cast<String>(),
      notificationEnabled: map['notificationEnabled'] as bool? ?? true,
      repeatRule: ReminderRepeatRuleX.fromStorage(map['repeatRule'] as String?),
    );
  }
}

class ReminderWorkspace {
  const ReminderWorkspace({
    required this.reminders,
    required this.lists,
    required this.groups,
    required this.tags,
  });

  final List<ReminderItem> reminders;
  final List<ReminderList> lists;
  final List<ReminderGroup> groups;
  final List<ReminderTag> tags;

  ReminderWorkspace copyWith({
    List<ReminderItem>? reminders,
    List<ReminderList>? lists,
    List<ReminderGroup>? groups,
    List<ReminderTag>? tags,
  }) {
    return ReminderWorkspace(
      reminders: reminders ?? this.reminders,
      lists: lists ?? this.lists,
      groups: groups ?? this.groups,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reminders': reminders.map((item) => item.toMap()).toList(),
      'lists': lists.map((item) => item.toMap()).toList(),
      'groups': groups.map((item) => item.toMap()).toList(),
      'tags': tags.map((item) => item.toMap()).toList(),
    };
  }

  String encode() => jsonEncode(toMap());

  factory ReminderWorkspace.fromMap(Map<String, dynamic> map) {
    return ReminderWorkspace(
      reminders: (map['reminders'] as List<dynamic>? ?? [])
          .map((item) => ReminderItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      lists: (map['lists'] as List<dynamic>? ?? [])
          .map((item) => ReminderList.fromMap(item as Map<String, dynamic>))
          .toList(),
      groups: (map['groups'] as List<dynamic>? ?? [])
          .map((item) => ReminderGroup.fromMap(item as Map<String, dynamic>))
          .toList(),
      tags: (map['tags'] as List<dynamic>? ?? [])
          .map((item) => ReminderTag.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }

  factory ReminderWorkspace.decode(String source) {
    return ReminderWorkspace.fromMap(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }
}
