import 'package:nexdo/src/core/network/api_client.dart';
import 'package:nexdo/src/core/network/api_exception.dart';
import 'package:nexdo/src/features/auth/data/auth_repository.dart'
    show AccessTokenProvider, AuthException;
import 'package:nexdo/src/features/reminders/data/datasources/reminder_local_data_source.dart';
import 'package:nexdo/src/features/reminders/domain/entities/reminder_models.dart';
import 'package:nexdo/src/features/reminders/domain/repositories/reminder_workspace_repository.dart';

class RemoteReminderWorkspaceRepository implements ReminderWorkspaceRepository {
  RemoteReminderWorkspaceRepository(
    this._apiClient,
    this._tokenProvider,
    this._localDataSource,
  );

  final NexdoApiClient _apiClient;
  final AccessTokenProvider _tokenProvider;
  final ReminderLocalDataSource _localDataSource;

  ReminderWorkspace? _cache;
  String? _serverTime;

  @override
  Future<ReminderWorkspace> fetchWorkspace() async {
    if (_cache != null) {
      return _cache!;
    }
    final local = await _loadCachedWorkspace();
    if (local != null) {
      return local;
    }
    return seedIfEmpty();
  }

  @override
  Future<ReminderWorkspace> seedIfEmpty() async {
    try {
      return await _refreshWorkspace();
    } on AuthException {
      rethrow;
    } catch (_) {
      final local = await _loadCachedWorkspace();
      if (local != null) {
        return local;
      }
      rethrow;
    }
  }

  @override
  Future<ReminderWorkspace> refreshWorkspace({
    bool forceBootstrap = false,
  }) async {
    return _refreshWorkspace(forceBootstrap: forceBootstrap);
  }

  @override
  Future<List<ReminderItem>> queryReminders(ReminderQuery query) async {
    final data =
        await _authorizedRequest(
              method: 'GET',
              path: '/reminders',
              queryParameters: {
                if (query.completion == ReminderFilter.pending)
                  'is_completed': false,
                if (query.completion == ReminderFilter.completed)
                  'is_completed': true,
                if (query.listIds.isNotEmpty)
                  'list_ids': query.listIds.join(','),
                if (query.groupIds.isNotEmpty)
                  'group_ids': query.groupIds.join(','),
                if (query.tagIds.isNotEmpty) 'tag_ids': query.tagIds.join(','),
              },
            )
            as List<dynamic>?;
    return (data ?? const <dynamic>[])
        .map((item) => _mapReminder(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ReminderCompletionLog>> fetchCompletionLogs(
    String reminderId,
  ) async {
    final data =
        await _authorizedRequest(
              method: 'GET',
              path: '/reminders/$reminderId/completion-logs',
            )
            as List<dynamic>?;
    return (data ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(_mapCompletionLog)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  @override
  Future<ReminderSaveResult> saveReminder(ReminderItem reminder) async {
    final workspace = await _ensureWorkspace();
    final exists = workspace.reminders.any((item) => item.id == reminder.id);
    final path = exists ? '/reminders/${reminder.id}' : '/reminders';
    final method = exists ? 'PATCH' : 'POST';
    final data =
        await _authorizedRequest(
              method: method,
              path: path,
              body: _reminderPayload(reminder),
            )
            as Map<String, dynamic>?;
    if (data == null) {
      throw const AuthException('保存提醒失败');
    }
    return _persistReminderMutation(
      workspace: workspace,
      reminderId: reminder.id,
      data: data,
      fallback: reminder,
      exists: exists,
    );
  }

  @override
  Future<ReminderWorkspace> deleteReminder(String id) async {
    await _authorizedRequest(method: 'DELETE', path: '/reminders/$id');
    final workspace = await _ensureWorkspace();
    final updated = workspace.copyWith(
      reminders: workspace.reminders.where((item) => item.id != id).toList(),
    );
    return _updateWorkspace(updated);
  }

  @override
  Future<ReminderWorkspace> saveList(ReminderList list) async {
    final workspace = await _ensureWorkspace();
    final exists = workspace.lists.any((item) => item.id == list.id);
    final data =
        await _authorizedRequest(
              method: exists ? 'PATCH' : 'POST',
              path: exists ? '/lists/${list.id}' : '/lists',
              body: _listPayload(list),
            )
            as Map<String, dynamic>?;
    if (data == null) {
      throw const AuthException('保存清单失败');
    }
    final saved = _mapList(data);
    final lists = [...workspace.lists];
    if (exists) {
      final index = lists.indexWhere((item) => item.id == saved.id);
      if (index != -1) {
        lists[index] = saved;
      }
    } else {
      lists.removeWhere((item) => item.id == list.id);
      lists.add(saved);
    }
    final updatedWorkspace = workspace.copyWith(lists: _sortLists(lists));
    return _updateWorkspace(updatedWorkspace);
  }

  @override
  Future<ReminderWorkspace> deleteList(String id) async {
    await _authorizedRequest(method: 'DELETE', path: '/lists/$id');
    final workspace = await _ensureWorkspace();
    final updated = workspace.copyWith(
      lists: _sortLists(
        workspace.lists.where((item) => item.id != id).toList(),
      ),
    );
    return _updateWorkspace(updated);
  }

  @override
  Future<ReminderWorkspace> saveGroup(ReminderGroup group) async {
    final workspace = await _ensureWorkspace();
    final exists = workspace.groups.any((item) => item.id == group.id);
    final data =
        await _authorizedRequest(
              method: exists ? 'PATCH' : 'POST',
              path: exists ? '/groups/${group.id}' : '/groups',
              body: _groupPayload(group),
            )
            as Map<String, dynamic>?;
    if (data == null) {
      throw const AuthException('保存分组失败');
    }
    final saved = _mapGroup(data);
    final groups = [...workspace.groups];
    if (exists) {
      final index = groups.indexWhere((item) => item.id == saved.id);
      if (index != -1) {
        groups[index] = saved;
      }
    } else {
      groups.removeWhere((item) => item.id == group.id);
      groups.add(saved);
    }
    final updatedWorkspace = workspace.copyWith(groups: _sortGroups(groups));
    return _updateWorkspace(updatedWorkspace);
  }

  @override
  Future<ReminderWorkspace> deleteGroup(String id) async {
    await _authorizedRequest(method: 'DELETE', path: '/groups/$id');
    final workspace = await _ensureWorkspace();
    final updated = workspace.copyWith(
      groups: _sortGroups(
        workspace.groups.where((item) => item.id != id).toList(),
      ),
    );
    return _updateWorkspace(updated);
  }

  @override
  Future<ReminderWorkspace> saveTag(ReminderTag tag) async {
    final workspace = await _ensureWorkspace();
    final exists = workspace.tags.any((item) => item.id == tag.id);
    final data =
        await _authorizedRequest(
              method: exists ? 'PATCH' : 'POST',
              path: exists ? '/tags/${tag.id}' : '/tags',
              body: _tagPayload(tag),
            )
            as Map<String, dynamic>?;
    if (data == null) {
      throw const AuthException('保存标签失败');
    }
    final saved = _mapTag(data);
    final tags = [...workspace.tags];
    if (exists) {
      final index = tags.indexWhere((item) => item.id == saved.id);
      if (index != -1) {
        tags[index] = saved;
      }
    } else {
      tags.removeWhere((item) => item.id == tag.id);
      tags.add(saved);
    }
    final updatedWorkspace = workspace.copyWith(tags: _sortTags(tags));
    return _updateWorkspace(updatedWorkspace);
  }

  @override
  Future<ReminderWorkspace> deleteTag(String id) async {
    await _authorizedRequest(method: 'DELETE', path: '/tags/$id');
    final workspace = await _ensureWorkspace();
    final updated = workspace.copyWith(
      tags: _sortTags(workspace.tags.where((item) => item.id != id).toList()),
    );
    return _updateWorkspace(updated);
  }

  Future<ReminderWorkspace> _ensureWorkspace() async {
    if (_cache != null) {
      return _cache!;
    }
    final local = await _loadCachedWorkspace();
    if (local != null) {
      return local;
    }
    return _refreshWorkspace(forceBootstrap: true);
  }

  Future<ReminderWorkspace> _refreshWorkspace({
    bool forceBootstrap = false,
  }) async {
    final shouldBootstrap =
        forceBootstrap || _serverTime == null || _cache == null;
    final path = shouldBootstrap ? '/sync/bootstrap' : '/sync/changes';
    final data =
        await _authorizedRequest(
              method: 'GET',
              path: path,
              queryParameters: shouldBootstrap ? null : {'since': _serverTime},
            )
            as Map<String, dynamic>?;
    if (data == null) {
      throw const AuthException('获取提醒数据失败');
    }

    final serverTime = data['server_time'] as String?;
    ReminderWorkspace workspace;
    if (shouldBootstrap) {
      workspace = _mapWorkspace(data);
    } else {
      workspace = _mergeWorkspace(_cache!, data);
    }

    _serverTime = serverTime ?? _serverTime;
    _cache = _sortWorkspace(workspace);
    await _localDataSource.writeCache(_cache!, serverTime: _serverTime);
    return _cache!;
  }

  Future<dynamic> _authorizedRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
  }) async {
    Future<dynamic> send(String token) {
      return _apiClient.request(
        method: method,
        path: path,
        body: body,
        queryParameters: queryParameters,
        accessToken: token,
      );
    }

    final token = await _tokenProvider.requireAccessToken();
    try {
      return await send(token);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        final refreshedToken = await _tokenProvider.refreshAccessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          return await send(refreshedToken);
        }
        throw const AuthException('登录已失效，请重新登录', shouldLogout: true);
      }
      throw AuthException(error.message ?? '接口调用失败');
    }
  }

  Future<ReminderWorkspace> _updateWorkspace(
    ReminderWorkspace workspace,
  ) async {
    _cache = _sortWorkspace(workspace);
    await _localDataSource.writeCache(_cache!, serverTime: _serverTime);
    return _cache!;
  }

  ReminderWorkspace _mapWorkspace(Map<String, dynamic> data) {
    final lists = (data['lists'] as List<dynamic>? ?? [])
        .map((item) => _mapList(item as Map<String, dynamic>))
        .toList();
    final groups = (data['groups'] as List<dynamic>? ?? [])
        .map((item) => _mapGroup(item as Map<String, dynamic>))
        .toList();
    final tags = (data['tags'] as List<dynamic>? ?? [])
        .map((item) => _mapTag(item as Map<String, dynamic>))
        .toList();
    final reminders = (data['reminders'] as List<dynamic>? ?? [])
        .map((item) => _mapReminder(item as Map<String, dynamic>))
        .toList();
    return ReminderWorkspace(
      reminders: reminders,
      lists: lists,
      groups: groups,
      tags: tags,
    );
  }

  ReminderWorkspace _mergeWorkspace(
    ReminderWorkspace workspace,
    Map<String, dynamic> delta,
  ) {
    final lists = _mergeEntities<ReminderList>(
      workspace.lists,
      delta['lists'] as List<dynamic>?,
      delta['deleted_list_ids'] as List<dynamic>?,
      _mapList,
      (item) => item.id,
    );
    final groups = _mergeEntities<ReminderGroup>(
      workspace.groups,
      delta['groups'] as List<dynamic>?,
      delta['deleted_group_ids'] as List<dynamic>?,
      _mapGroup,
      (item) => item.id,
    );
    final tags = _mergeEntities<ReminderTag>(
      workspace.tags,
      delta['tags'] as List<dynamic>?,
      delta['deleted_tag_ids'] as List<dynamic>?,
      _mapTag,
      (item) => item.id,
    );
    final reminders = _mergeEntities<ReminderItem>(
      workspace.reminders,
      delta['reminders'] as List<dynamic>?,
      delta['deleted_reminder_ids'] as List<dynamic>?,
      _mapReminder,
      (item) => item.id,
    );
    return ReminderWorkspace(
      reminders: reminders,
      lists: lists,
      groups: groups,
      tags: tags,
    );
  }

  List<T> _mergeEntities<T>(
    List<T> current,
    List<dynamic>? updates,
    List<dynamic>? deletedIds,
    T Function(Map<String, dynamic>) mapper,
    String Function(T) idSelector,
  ) {
    final map = <String, T>{for (final item in current) idSelector(item): item};
    if (updates != null) {
      for (final raw in updates) {
        if (raw is Map<String, dynamic>) {
          final entity = mapper(raw);
          map[idSelector(entity)] = entity;
        }
      }
    }
    if (deletedIds != null) {
      for (final rawId in deletedIds) {
        final id = rawId?.toString();
        if (id != null) {
          map.remove(id);
        }
      }
    }
    return map.values.toList();
  }

  Future<ReminderWorkspace?> _loadCachedWorkspace() async {
    final cached = await _localDataSource.readCache();
    if (cached == null) {
      return null;
    }
    _serverTime = cached.serverTime;
    _cache = _sortWorkspace(cached.workspace);
    return _cache!;
  }

  ReminderList _mapList(Map<String, dynamic> map) {
    return ReminderList(
      id: map['id'] as String,
      name: map['name'] as String,
      colorValue: (map['color_value'] as num?)?.toInt() ?? 0,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  ReminderGroup _mapGroup(Map<String, dynamic> map) {
    return ReminderGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      iconCodePoint: (map['icon_code_point'] as num?)?.toInt() ?? 0,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  ReminderTag _mapTag(Map<String, dynamic> map) {
    return ReminderTag(
      id: map['id'] as String,
      name: map['name'] as String,
      colorValue: (map['color_value'] as num?)?.toInt() ?? 0,
    );
  }

  ReminderItem _mapReminder(Map<String, dynamic> map) {
    DateTime parseDate(String key) {
      final value = map[key] as String;
      final normalized = value.replaceFirst(
        RegExp(r'(Z|[+-]\d{2}:\d{2})$'),
        '',
      );
      return DateTime.parse(normalized);
    }

    DateTime? parseNullableDate(List<String> keys) {
      for (final key in keys) {
        final value = map[key] as String?;
        if (value == null || value.isEmpty) {
          continue;
        }
        final normalized = value.replaceFirst(
          RegExp(r'(Z|[+-]\d{2}:\d{2})$'),
          '',
        );
        return DateTime.parse(normalized);
      }
      return null;
    }

    int? parseNullableInt(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value is num) {
          return value.toInt();
        }
      }
      return null;
    }

    return ReminderItem(
      id: map['id'] as String,
      title: map['title'] as String,
      note: map['note'] as String?,
      dueAt: parseDate('due_at'),
      isCompleted: map['is_completed'] as bool? ?? false,
      createdAt: parseDate('created_at'),
      updatedAt: parseDate('updated_at'),
      listId: map['list_id'] as String,
      groupId: map['group_id'] as String,
      tagIds: (map['tag_ids'] as List<dynamic>? ?? []).cast<String>(),
      notificationEnabled: map['notification_enabled'] as bool? ?? true,
      repeatRule: ReminderRepeatRuleX.fromStorage(
        map['repeat_rule'] as String?,
      ),
      repeatEndAt: parseNullableDate(const [
        'repeat_end_at',
        'repeat_until_at',
        'repeat_until',
      ]),
      remindBeforeMinutes: parseNullableInt(const [
        'remind_before_minutes',
        'notification_before_minutes',
        'notify_before_minutes',
      ]),
    );
  }

  ReminderCompletionLog _mapCompletionLog(Map<String, dynamic> map) {
    DateTime? parseNullable(Iterable<String> keys) {
      for (final key in keys) {
        final value = map[key] as String?;
        if (value != null && value.isNotEmpty) {
          return DateTime.parse(value);
        }
      }
      return null;
    }

    final completedAt =
        parseNullable(const ['completed_at']) ??
        parseNullable(const ['created_at']) ??
        DateTime.now();

    return ReminderCompletionLog(
      id: (map['id'] ?? '').toString(),
      reminderId: (map['reminder_id'] ?? '').toString(),
      completedAt: completedAt,
      originalDueAt: parseNullable(const ['original_due_at']),
      nextDueAt: parseNullable(const ['next_due_at']),
      createdAt: parseNullable(const ['created_at']),
    );
  }

  Future<ReminderSaveResult> _persistReminderMutation({
    required ReminderWorkspace workspace,
    required String reminderId,
    required Map<String, dynamic> data,
    required ReminderItem fallback,
    required bool exists,
  }) async {
    final saved = _extractReminderFromMutation(data) ?? fallback;
    final updatedReminders = [...workspace.reminders];
    if (exists) {
      final index = updatedReminders.indexWhere(
        (item) => item.id == reminderId,
      );
      if (index != -1) {
        updatedReminders[index] = saved;
      } else {
        updatedReminders.add(saved);
      }
    } else {
      updatedReminders.removeWhere((item) => item.id == reminderId);
      updatedReminders.add(saved);
    }
    final updatedWorkspace = workspace.copyWith(reminders: updatedReminders);
    final persisted = await _updateWorkspace(updatedWorkspace);
    return ReminderSaveResult(workspace: persisted, reminder: saved);
  }

  ReminderItem? _extractReminderFromMutation(Map<String, dynamic> data) {
    if (data.containsKey('id')) {
      return _mapReminder(data);
    }
    final nested = data['reminder'];
    if (nested is Map<String, dynamic>) {
      return _mapReminder(nested);
    }
    final entity = data['data'];
    if (entity is Map<String, dynamic> && entity.containsKey('id')) {
      return _mapReminder(entity);
    }
    return null;
  }

  Map<String, dynamic> _reminderPayload(ReminderItem reminder) {
    String formatDate(DateTime dateTime) {
      final local = dateTime.toLocal();
      final offset = local.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final totalMinutes = offset.inMinutes.abs();
      final offsetHours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
      final offsetMinutes = (totalMinutes % 60).toString().padLeft(2, '0');
      final year = local.year.toString().padLeft(4, '0');
      final month = local.month.toString().padLeft(2, '0');
      final day = local.day.toString().padLeft(2, '0');
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      final second = local.second.toString().padLeft(2, '0');
      return '$year-$month-$day'
          'T$hour:$minute:$second'
          '$sign$offsetHours:$offsetMinutes';
    }

    return {
      'title': reminder.title,
      'note': reminder.note ?? '',
      'due_at': formatDate(reminder.dueAt),
      'list_id': reminder.listId,
      'group_id': reminder.groupId,
      'tag_ids': reminder.tagIds,
      'notification_enabled': reminder.notificationEnabled,
      'repeat_rule': reminder.repeatRule.storageValue,
      'repeat_end_at': reminder.repeatEndAt == null
          ? null
          : formatDate(reminder.repeatEndAt!),
      'remind_before_minutes': reminder.remindBeforeMinutes,
      'is_completed': reminder.isCompleted,
    };
  }

  Map<String, dynamic> _listPayload(ReminderList list) {
    return {
      'name': list.name,
      'color_value': list.colorValue,
      'sort_order': list.sortOrder,
    };
  }

  Map<String, dynamic> _groupPayload(ReminderGroup group) {
    return {
      'name': group.name,
      'icon_code_point': group.iconCodePoint,
      'sort_order': group.sortOrder,
    };
  }

  Map<String, dynamic> _tagPayload(ReminderTag tag) {
    return {'name': tag.name, 'color_value': tag.colorValue};
  }

  ReminderWorkspace _sortWorkspace(ReminderWorkspace workspace) {
    final reminders = [...workspace.reminders]
      ..sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        return a.dueAt.compareTo(b.dueAt);
      });
    return workspace.copyWith(
      reminders: reminders,
      lists: _sortLists(workspace.lists),
      groups: _sortGroups(workspace.groups),
      tags: _sortTags(workspace.tags),
    );
  }

  List<ReminderList> _sortLists(List<ReminderList> items) {
    return [...items]..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) {
        return order;
      }
      return a.name.compareTo(b.name);
    });
  }

  List<ReminderGroup> _sortGroups(List<ReminderGroup> items) {
    return [...items]..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) {
        return order;
      }
      return a.name.compareTo(b.name);
    });
  }

  List<ReminderTag> _sortTags(List<ReminderTag> items) {
    return [...items]..sort((a, b) => a.name.compareTo(b.name));
  }
}
