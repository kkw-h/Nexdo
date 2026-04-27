import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:nexdo/src/features/quick_notes/data/quick_note_local_data_source.dart';
import 'package:nexdo/src/features/quick_notes/data/quick_notes_repository.dart';
import 'package:nexdo/src/features/quick_notes/presentation/quick_notes_page.dart';
import 'package:nexdo/src/features/ai_commands/data/ai_command_repository.dart';
import 'package:nexdo/src/features/ai_commands/presentation/ai_command_page.dart';

import '../../../core/device/device_identity.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_ui_primitives.dart';
import '../../auth/data/auth_repository.dart'
    show AuthRepository, AuthException;
import '../../auth/domain/auth_device.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/api_debug_page.dart';
import '../../auth/presentation/change_password_page.dart';
import '../../auth/presentation/device_management_page.dart';
import 'package:nexdo/src/core/network/api_client.dart';
import '../application/reminder_notification_service.dart';
import '../data/datasources/reminder_local_data_source.dart';
import '../data/repositories/remote_reminder_workspace_repository.dart';
import '../domain/entities/reminder_models.dart';
import 'reminder_controller.dart';
import 'reminder_form_page.dart';
import 'reminder_notification_settings_page.dart';

const _kCardShadowColor = Color(0x0A0F172A);
const _kCardShadowColorSoft = Color(0x080F172A);

class ReminderAppShell extends StatefulWidget {
  const ReminderAppShell({
    super.key,
    required this.currentUser,
    required this.authRepository,
    required this.apiClient,
    required this.onLogout,
  });

  final AuthUser currentUser;
  final AuthRepository authRepository;
  final NexdoApiClient apiClient;
  final Future<void> Function() onLogout;

  @override
  State<ReminderAppShell> createState() => _ReminderAppShellState();
}

enum ReminderSortMode { dueDate, createdAt, title }

enum InboxStatusFilter { all, pending, completed, overdue }

class _ReminderAppShellState extends State<ReminderAppShell> {
  static const _permissionPromptKey = 'permission_prompt.shown';
  static const _defaultInboxQuery = ReminderQuery();
  final GlobalKey<QuickNotesPageState> _quickNotesPageKey =
      GlobalKey<QuickNotesPageState>();
  ReminderController? _controller;
  ReminderNotificationService? _notificationService;
  QuickNoteLocalDataSource? _quickNoteDataSource;
  QuickNotesRepository? _quickNotesRepository;
  QuickNotesDiagnostics? _quickNotesDiagnostics;
  AiCommandRepository? _aiCommandRepository;
  Future<List<AuthDevice>>? _profileDevicesFuture;
  ReminderQuery _inboxQuery = _defaultInboxQuery;
  InboxStatusFilter _inboxStatusFilter = InboxStatusFilter.all;
  List<ReminderItem>? _inboxQueryResults;
  bool _inboxQueryLoading = false;
  ReminderSortMode _sortMode = ReminderSortMode.dueDate;
  int _selectedNavIndex = 0;
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  String? _error;
  Timer? _countdownTimer;
  int _refreshCountdown = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    _countdownTimer?.cancel();
    setState(() {
      _error = null;
      _controller = null;
      _notificationService = null;
      _aiCommandRepository = null;
      _refreshCountdown = 0;
    });
    await initializeDateFormatting('zh_CN');
    try {
      final preferences = await SharedPreferences.getInstance();
      final repository = RemoteReminderWorkspaceRepository(
        widget.apiClient,
        widget.authRepository,
        ReminderLocalDataSource(preferences),
      );
      final notificationService = ReminderNotificationService(
        FlutterLocalNotificationsPlugin(),
      );
      await notificationService.initialize();
      final controller = ReminderController(repository, notificationService);
      await controller.bootstrap();

      if (!mounted) {
        return;
      }

      setState(() {
        _controller = controller;
        _notificationService = notificationService;
        _quickNoteDataSource = QuickNoteLocalDataSource(
          preferences,
          userId: widget.currentUser.id,
        );
        _quickNotesRepository = QuickNotesRepository(
          widget.apiClient,
          widget.authRepository,
          _quickNoteDataSource!,
        );
        _aiCommandRepository = AiCommandRepository(
          widget.apiClient,
          widget.authRepository,
        );
        _profileDevicesFuture = _loadProfileDevices();
      });
      await _runInboxQuery(controller, query: _defaultInboxQuery);
      _startCountdownTicker();
      await _maybeShowPermissionPrompt(preferences);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
      if (error.shouldLogout) {
        await widget.onLogout();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '加载提醒数据失败，请检查网络后重试。';
      });
    }
  }

  Future<void> _maybeShowPermissionPrompt(SharedPreferences preferences) async {
    final alreadyShown = preferences.getBool(_permissionPromptKey) ?? false;
    if (alreadyShown || !mounted) {
      return;
    }
    await preferences.setBool(_permissionPromptKey, true);
    if (!mounted) {
      return;
    }
    await Future.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('开启网络与通知权限'),
          content: const Text(
            'Nexdo 需要联网同步提醒数据，并使用通知权限在到期时提醒。'
            '\n\n请在系统设置中确保已允许联网与通知，否则将无法正常收取提醒。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我已了解'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final quickNoteDataSource = _quickNoteDataSource;
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _ErrorPanel(
              title: '加载提醒数据失败',
              message: _error!,
              actionLabel: '重试加载',
              onPressed: _initialize,
            ),
          ),
        ),
      );
    }
    if (controller == null ||
        controller.isLoading ||
        quickNoteDataSource == null ||
        _quickNotesRepository == null ||
        _aiCommandRepository == null) {
      return const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: _ReminderListLoadingSkeleton(),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayItems = controller.remindersForDate(now);
        final visibleIds = todayItems.map((item) => item.id).toSet();
        todayItems.addAll(
          controller.reminders.where((item) {
            return !visibleIds.contains(item.id) &&
                !item.isCompleted &&
                item.dueAt.isBefore(todayStart);
          }),
        );
        final pages = [
          _buildTodayView(
            controller,
            todayItems,
            onRefresh: () => _refreshData(controller),
            onPullRefresh: () => _refreshData(controller, forceBootstrap: true),
            onOpenCalendar: () => _openCalendarPage(controller),
          ),
          _buildInboxView(
            controller,
            onOpenCalendar: () => _openCalendarPage(controller),
          ),
          _buildQuickNotesView(_quickNotesRepository!),
          AiCommandPage(
            repository: _aiCommandRepository!,
            embedded: true,
            onExecuted: () async {
              await controller.refresh();
              await _refreshInboxQueryIfNeeded(controller);
            },
            onSessionExpired: widget.onLogout,
          ),
          _buildProfileView(controller),
        ];
        final fabIcon = _selectedNavIndex == 2
            ? Icons.bolt_rounded
            : Icons.add_rounded;
        final fab = FloatingActionButton(
          onPressed: () {
            if (_selectedNavIndex == 2) {
              _quickNotesPageKey.currentState?.openTextComposer();
              return;
            }
            _openForm(controller);
          },
          backgroundColor: AppThemeScope.of(context).palette.primary,
          foregroundColor: AppThemeScope.of(context).palette.onPrimary,
          elevation: 10,
          shape: const CircleBorder(),
          child: Icon(fabIcon, size: 30),
        );
        final compactFab = SizedBox(width: 56, height: 56, child: fab);

        return Scaffold(
          backgroundColor: AppThemeScope.of(context).palette.background,
          floatingActionButton: _selectedNavIndex >= 3
              ? null
              : (_selectedNavIndex == 2
                    ? GestureDetector(
                        onLongPress: () => _quickNotesPageKey.currentState
                            ?.openVoiceComposer(),
                        child: compactFab,
                      )
                    : compactFab),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              color: AppThemeScope.of(context).palette.surface,
              border: Border(
                top: BorderSide(
                  color: AppThemeScope.of(context).palette.outline,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: NavigationBar(
                selectedIndex: _selectedNavIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _selectedNavIndex = index;
                  });
                  unawaited(_refreshForNavIndex(index, controller));
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.today_outlined),
                    selectedIcon: Icon(Icons.today_rounded),
                    label: '今日',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.view_list_outlined),
                    selectedIcon: Icon(Icons.view_list_rounded),
                    label: '清单',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bolt_outlined),
                    selectedIcon: Icon(Icons.bolt_rounded),
                    label: '闪念',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.smart_toy_outlined),
                    selectedIcon: Icon(Icons.smart_toy_rounded),
                    label: 'AI',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: '我的',
                  ),
                ],
              ),
            ),
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppThemeScope.of(context).palette.chipBackground,
                  AppThemeScope.of(context).palette.background,
                ],
              ),
            ),
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: IndexedStack(
                            index: _selectedNavIndex,
                            children: pages,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _refreshData(
    ReminderController controller, {
    bool forceBootstrap = false,
  }) async {
    try {
      await controller.refresh(forceBootstrap: forceBootstrap);
      await _refreshInboxQueryIfNeeded(controller);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(forceBootstrap ? '已完整刷新整个列表' : '已刷新最新数据')),
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      if (error.shouldLogout) {
        await widget.onLogout();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('刷新失败，请稍后再试')));
    }
  }

  Future<void> _refreshForNavIndex(
    int index,
    ReminderController controller,
  ) async {
    try {
      switch (index) {
        case 0:
        case 1:
          await controller.refresh();
          if (index == 1) {
            await _refreshInboxQueryIfNeeded(controller);
          }
          break;
        case 2:
          await _quickNotesPageKey.currentState?.refreshNotes();
          break;
        default:
          break;
      }
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      if (error.shouldLogout) {
        await widget.onLogout();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('刷新最新数据失败，请稍后再试')));
    }
  }

  Future<void> _handleReminderAction(
    Future<void> Function() action, {
    String fallbackMessage = '操作失败，请稍后再试',
  }) async {
    try {
      await action();
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      if (error.shouldLogout) {
        await widget.onLogout();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(fallbackMessage)));
    }
  }

  Future<void> _toggleCompletion(
    ReminderController controller,
    ReminderItem reminder,
    bool isCompleted,
  ) async {
    await _handleReminderAction(
      () => controller.toggleCompletion(reminder, isCompleted),
      fallbackMessage: '更新提醒状态失败，请稍后再试',
    );
    await _refreshInboxQueryIfNeeded(controller);
  }

  Future<void> _deleteReminder(
    ReminderController controller,
    ReminderItem reminder,
  ) async {
    await _confirmReminderDelete(
      message: '确认删除提醒“${reminder.title}”吗？',
      onConfirm: () async {
        await _handleReminderAction(
          () => controller.removeReminder(reminder.id),
          fallbackMessage: '删除提醒失败，请稍后再试',
        );
        await _refreshInboxQueryIfNeeded(controller);
      },
    );
  }

  Future<void> _confirmReminderDelete({
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppThemeScope.of(context).palette.error,
                foregroundColor: AppThemeScope.of(
                  context,
                ).palette.onErrorContainer,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await onConfirm();
    }
  }

  Future<void> _runInboxQuery(
    ReminderController controller, {
    ReminderQuery? query,
  }) async {
    final nextQuery = query ?? _inboxQuery;
    if (nextQuery.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inboxQuery = nextQuery;
        _inboxStatusFilter = _statusFilterFromReminderFilter(
          nextQuery.completion,
        );
        _inboxQueryLoading = false;
        _inboxQueryResults = null;
      });
      return;
    }

    setState(() {
      _inboxQuery = nextQuery;
      _inboxStatusFilter = _statusFilterFromReminderFilter(
        nextQuery.completion,
      );
      _inboxQueryLoading = true;
    });

    try {
      final reminders = await controller.queryReminders(nextQuery);
      if (!mounted) {
        return;
      }
      setState(() {
        _inboxQueryResults = reminders;
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      if (error.shouldLogout) {
        await widget.onLogout();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('查询提醒失败，请稍后再试')));
    } finally {
      if (mounted) {
        setState(() {
          _inboxQueryLoading = false;
        });
      }
    }
  }

  Future<void> _refreshInboxQueryIfNeeded(ReminderController controller) async {
    if (_inboxQuery.isEmpty) {
      return;
    }
    await _runInboxQuery(controller);
  }

  Future<List<AuthDevice>> _loadProfileDevices() async {
    final identity = await DeviceIdentityProvider.instance.ensureIdentity();
    final result = await widget.authRepository.getDevices();
    final devices = result.devices.map((e) {
      final backendCurrentId = result.currentDeviceId;
      final mapDeviceId = e['device_id']?.toString();
      final inferredCurrent = backendCurrentId != null
          ? mapDeviceId != null && mapDeviceId == backendCurrentId
          : mapDeviceId != null && mapDeviceId == identity.deviceId;
      return AuthDevice.fromMap(e, isCurrent: inferredCurrent);
    }).toList();
    devices.sort((a, b) {
      if (a.isCurrent != b.isCurrent) {
        return a.isCurrent ? -1 : 1;
      }
      return b.lastActiveAt.compareTo(a.lastActiveAt);
    });
    return devices;
  }

  Widget _buildInboxView(
    ReminderController controller, {
    required VoidCallback onOpenCalendar,
  }) {
    Future<void> openInboxFilter() async {
      final query = await showModalBottomSheet<ReminderQuery>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _ReminderQuerySheet(
          initialQuery: _inboxQuery,
          lists: controller.lists,
          groups: controller.groups,
          tags: controller.tags,
        ),
      );
      if (query == null) {
        return;
      }
      await _runInboxQuery(controller, query: query);
    }

    final baseReminders = _inboxQuery.isEmpty
        ? controller.reminders
        : (_inboxQueryResults ?? const <ReminderItem>[]);
    final reminders = _sortReminders(_filterInboxReminders(baseReminders));
    final querySummary = _buildInboxQuerySummary(controller);
    final sortLabel = _SortButton.labels[_sortMode]!;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text(
          '清单',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: AppThemeScope.of(context).palette.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              flex: 7,
              child: _InboxSearchButton(
                active: !_inboxQuery.isEmpty,
                onTap: openInboxFilter,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: _InboxFilterButton(
                active: false,
                onTap: () => _showTodaySortMenu(context),
                icon: Icons.swap_vert_rounded,
                label: sortLabel,
                showLabel: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _InboxTopButton(
                icon: Icons.calendar_month_rounded,
                label: '日历',
                onTap: onOpenCalendar,
                showLabel: false,
              ),
            ),
          ],
        ),
        if (_inboxQueryLoading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 3),
        ],
        if (querySummary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...querySummary.map(
                  (label) => _InfoChip(icon: Icons.tune_rounded, label: label),
                ),
                _CompactActionChip(
                  icon: Icons.close_rounded,
                  label: '清空查询',
                  onTap: () =>
                      _runInboxQuery(controller, query: const ReminderQuery()),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              '共 ${reminders.length} 条',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppThemeScope.of(context).palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$sortLabel（从近到远）',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppThemeScope.of(context).palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (reminders.isEmpty)
          _inboxQuery.isEmpty
              ? const _EmptyPanel(
                  title: '当前没有提醒',
                  subtitle: '先创建提醒，列表会按时间自动排列。',
                )
              : _InboxQueryEmptyState(
                  summaryLabels: querySummary,
                  onAdjustQuery: () async {
                    final query = await showModalBottomSheet<ReminderQuery>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (context) => _ReminderQuerySheet(
                        initialQuery: _inboxQuery,
                        lists: controller.lists,
                        groups: controller.groups,
                        tags: controller.tags,
                      ),
                    );
                    if (query == null) {
                      return;
                    }
                    await _runInboxQuery(controller, query: query);
                  },
                  onClearQuery: () =>
                      _runInboxQuery(controller, query: const ReminderQuery()),
                )
        else
          ...reminders.map(
            (reminder) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReminderSwipeAction(
                reminderId: reminder.id,
                onDelete: () => _deleteReminder(controller, reminder),
                child: _ReminderCard(
                  reminder: reminder,
                  controller: controller,
                  onTap: () => _openForm(controller, reminder: reminder),
                  onToggleCompletion: (value) =>
                      _toggleCompletion(controller, reminder, value),
                ),
              ),
            ),
          ),
        const SizedBox(height: 96),
      ],
    );
  }

  List<String> _buildInboxQuerySummary(ReminderController controller) {
    final labels = <String>[];
    switch (_inboxQuery.completion) {
      case ReminderFilter.all:
        break;
      case ReminderFilter.pending:
        labels.add('未完成');
      case ReminderFilter.completed:
        labels.add('已完成');
    }
    for (final id in _inboxQuery.listIds) {
      final list = controller.findList(id);
      if (list != null) {
        labels.add('清单·${list.name}');
      }
    }
    for (final id in _inboxQuery.groupIds) {
      final group = controller.findGroup(id);
      if (group != null) {
        labels.add('分组·${group.name}');
      }
    }
    for (final tag in controller.findTags(_inboxQuery.tagIds)) {
      labels.add('标签·${tag.name}');
    }
    return labels;
  }

  List<ReminderItem> _filterInboxReminders(List<ReminderItem> reminders) {
    return reminders.where((item) {
      return switch (_inboxStatusFilter) {
        InboxStatusFilter.all => true,
        InboxStatusFilter.pending => !item.isCompleted,
        InboxStatusFilter.completed => item.isCompleted,
        InboxStatusFilter.overdue => _isOverdueByDate(item),
      };
    }).toList();
  }

  InboxStatusFilter _statusFilterFromReminderFilter(ReminderFilter filter) {
    return switch (filter) {
      ReminderFilter.all => InboxStatusFilter.all,
      ReminderFilter.pending => InboxStatusFilter.pending,
      ReminderFilter.completed => InboxStatusFilter.completed,
    };
  }

  bool _isOverdueByDate(ReminderItem reminder) {
    if (reminder.isCompleted) {
      return false;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      reminder.dueAt.year,
      reminder.dueAt.month,
      reminder.dueAt.day,
    );
    return dueDate.isBefore(today);
  }

  Widget _buildTodayView(
    ReminderController controller,
    List<ReminderItem> todayItems, {
    required Future<void> Function() onRefresh,
    required Future<void> Function() onPullRefresh,
    required VoidCallback onOpenCalendar,
  }) {
    final orderedItems = _sortReminders(todayItems);
    final pendingCount = orderedItems.where((item) => !item.isCompleted).length;
    final completedCount = orderedItems
        .where((item) => item.isCompleted)
        .length;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final overdueCount = orderedItems.where((item) {
      final dueDate = DateTime(
        item.dueAt.year,
        item.dueAt.month,
        item.dueAt.day,
      );
      return !item.isCompleted && dueDate.isBefore(todayDate);
    }).length;
    final recurringCount = orderedItems
        .where((item) => item.repeatRule != ReminderRepeatRule.none)
        .length;
    final palette = AppThemeScope.of(context).palette;
    final countdownLabel = _countdownLabel();

    return RefreshIndicator(
      onRefresh: onPullRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _TodaySummaryCard(
            pendingCount: pendingCount,
            completedCount: completedCount,
            overdueCount: overdueCount,
            recurringCount: recurringCount,
            countdownLabel: countdownLabel,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _TodayActionButton(
                  icon: Icons.swap_vert_rounded,
                  label: _SortButton.labels[_sortMode]!,
                  onTap: () => _showTodaySortMenu(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TodayActionButton(
                  icon: Icons.calendar_month_rounded,
                  label: '日历',
                  onTap: onOpenCalendar,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            DateFormat('今日 · M 月 d 日 EEEE', 'zh_CN').format(DateTime.now()),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (orderedItems.isEmpty)
            const _EmptyPanel(title: '今天还没有排程', subtitle: '加一条提醒，时间线就会按顺序展示出来。')
          else
            ...orderedItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ReminderSwipeAction(
                  reminderId: item.id,
                  onDelete: () => _deleteReminder(controller, item),
                  child: _TodayReminderRow(
                    reminder: item,
                    controller: controller,
                    onOpenReminder: () => _openForm(controller, reminder: item),
                    onToggleCompletion: (value) =>
                        _toggleCompletion(controller, item, value),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  Widget _buildQuickNotesView(QuickNotesRepository repository) {
    return QuickNotesPage(
      key: _quickNotesPageKey,
      repository: repository,
      diagnostics: _quickNotesDiagnostics,
      onDiagnosticsPressed: _quickNotesPageKey.currentState?.refreshDiagnostics,
      onDiagnosticsChanged: (diagnostics) {
        if (!mounted) {
          return;
        }
        setState(() {
          _quickNotesDiagnostics = diagnostics;
        });
      },
    );
  }

  Widget _buildProfileView(ReminderController controller) {
    final palette = AppThemeScope.of(context).palette;
    final reminders = controller.reminders;
    final totalCount = reminders.length;
    final pendingCount = reminders.where((item) => !item.isCompleted).length;
    final completedCount = reminders.where((item) => item.isCompleted).length;
    final overdueCount = reminders
        .where((item) => _isOverdueByDate(item))
        .length;

    return ListView(
      children: [
        Text(
          '我的',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        AppSurfaceCard(
          padding: EdgeInsets.zero,
          borderRadius: 18,
          child: Column(
            children: [
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: palette.primaryContainer.withValues(
                            alpha: 0.65,
                          ),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.currentUser.name.trim().isEmpty
                              ? 'N'
                              : widget.currentUser.name.trim()[0].toUpperCase(),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: palette.secondary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.currentUser.name.isEmpty
                                        ? 'Nexdo 用户'
                                        : widget.currentUser.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: palette.onSurface,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.primaryContainer.withValues(
                                      alpha: 0.45,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.verified_rounded,
                                        size: 14,
                                        color: palette.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Pro',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: palette.primary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '专注让每一天更有序',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: palette.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: palette.outline),
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
                onTap: () async => widget.onLogout(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, color: palette.error),
                      const SizedBox(width: 10),
                      Text(
                        '退出登录',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: palette.error,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AppSurfaceCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          borderRadius: 18,
          child: Column(
            children: [
              InkWell(
                onTap: () => _openDataOverview(controller),
                child: Row(
                  children: [
                    Text(
                      '数据概览',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: palette.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '查看统计',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: palette.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ProfileMetricCard(
                      icon: Icons.calendar_month_rounded,
                      label: '全部提醒',
                      value: '$totalCount',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProfileMetricCard(
                      icon: Icons.timelapse_rounded,
                      label: '待办',
                      value: '$pendingCount',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProfileMetricCard(
                      icon: Icons.check_circle_rounded,
                      label: '已完成',
                      value: '$completedCount',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProfileMetricCard(
                      icon: Icons.warning_amber_rounded,
                      label: '逾期',
                      value: '$overdueCount',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ProfileSettingsCard(
          items: [
            _ProfileSettingsItem(
              icon: Icons.lock_reset_rounded,
              title: '修改密码',
              subtitle: '保护账号安全',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        ChangePasswordPage(repository: widget.authRepository),
                  ),
                );
              },
            ),
            _ProfileSettingsItem(
              icon: Icons.tune_rounded,
              title: '任务清单与设置',
              subtitle: '清单、分组、标签管理',
              onTap: () => _openWorkspaceManager(controller),
            ),
            _ProfileSettingsItem(
              icon: Icons.notifications_none_rounded,
              title: '通知与提醒设置',
              subtitle: '声音、震动、通知开关',
              onTap: _openNotificationSettingsInfo,
            ),
            _ProfileSettingsItem(
              icon: Icons.cloud_sync_rounded,
              title: '数据与同步',
              subtitle: '同步、备份、恢复',
              onTap: () => _syncProfileData(controller),
            ),
            _ProfileSettingsItem(
              icon: Icons.code_rounded,
              title: '接口调试',
              subtitle: 'API 地址、网络调试',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ApiDebugPage(apiClient: widget.apiClient),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 18),
        AppSurfaceCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          borderRadius: 18,
          child: Column(
            children: [
              InkWell(
                onTap: _openDeviceManagement,
                child: Row(
                  children: [
                    Text(
                      '设备管理',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: palette.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '查看全部',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: palette.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<AuthDevice>>(
                future: _profileDevicesFuture ?? _loadProfileDevices(),
                builder: (context, snapshot) {
                  final devices = snapshot.data ?? const <AuthDevice>[];
                  if (devices.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final previewDevices = devices.take(2).toList();
                  return Column(
                    children: previewDevices
                        .map(
                          (device) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ProfileDevicePreviewTile(
                              device: device,
                              onTap: _openDeviceManagement,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 96),
      ],
    );
  }

  Future<void> _openDeviceManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            DeviceManagementPage(repository: widget.authRepository),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _profileDevicesFuture = _loadProfileDevices();
    });
  }

  Future<void> _syncProfileData(ReminderController controller) async {
    await _refreshData(controller, forceBootstrap: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _profileDevicesFuture = _loadProfileDevices();
    });
  }

  Future<void> _openNotificationSettingsInfo() async {
    final controller = _controller;
    final notificationService = _notificationService;
    if (!mounted || controller == null || notificationService == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReminderNotificationSettingsPage(
          controller: controller,
          notificationService: notificationService,
        ),
      ),
    );
  }

  Future<void> _openForm(
    ReminderController controller, {
    ReminderItem? reminder,
  }) async {
    final result = await Navigator.of(context).push<ReminderFormResult>(
      MaterialPageRoute(
        builder: (_) => ReminderFormPage(
          initialReminder: reminder,
          availableLists: controller.lists,
          availableGroups: controller.groups,
          availableTags: controller.tags,
          existingReminders: controller.reminders,
          loadCompletionLogs: controller.fetchCompletionLogs,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    if (result.action == ReminderFormAction.delete) {
      await _deleteReminder(controller, result.reminder);
    } else {
      await _handleReminderAction(
        () => controller.saveReminder(result.reminder),
        fallbackMessage: '保存提醒失败，请稍后再试',
      );
    }
    await _refreshInboxQueryIfNeeded(controller);
  }

  Future<void> _openDataOverview(ReminderController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DataOverviewPage(controller: controller),
      ),
    );
  }

  Future<void> _openWorkspaceManager(ReminderController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WorkspaceManagerPage(controller: controller),
      ),
    );
  }

  Future<void> _openCalendarPage(ReminderController controller) async {
    final selectedDate = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => _CalendarPage(
          controller: controller,
          initialSelectedDate: _selectedDate,
          initialFocusedDate: _focusedDate,
          onOpenReminder: (reminder) =>
              _openForm(controller, reminder: reminder),
          onDeleteReminder: (reminder) => _deleteReminder(controller, reminder),
          onToggleCompletion: (reminder, value) =>
              _toggleCompletion(controller, reminder, value),
        ),
      ),
    );
    if (selectedDate != null) {
      setState(() {
        _selectedDate = selectedDate;
        _focusedDate = selectedDate;
      });
    }
  }

  void _startCountdownTicker() {
    void tick() {
      if (!mounted) {
        return;
      }
      final controller = _controller;
      if (controller == null) {
        return;
      }
      final nextTime = controller.nextSyncTime;
      final diff = nextTime?.difference(DateTime.now()).inSeconds ?? 0;
      final seconds = diff.clamp(0, 9999).toInt();
      if (seconds != _refreshCountdown) {
        setState(() {
          _refreshCountdown = seconds;
        });
      }
    }

    tick();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String? _countdownLabel() {
    final controller = _controller;
    if (controller == null || controller.nextSyncTime == null) {
      return null;
    }
    final seconds = _refreshCountdown;
    if (seconds <= 0) {
      return '即将刷新';
    }
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _showTodaySortMenu(BuildContext context) async {
    final palette = AppThemeScope.of(context).palette;
    final textTheme = Theme.of(context).textTheme;
    final selected = await showMenu<ReminderSortMode>(
      context: context,
      position: const RelativeRect.fromLTRB(24, 180, 24, 0),
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      constraints: const BoxConstraints(minWidth: 196),
      items: ReminderSortMode.values
          .map(
            (item) => PopupMenuItem<ReminderSortMode>(
              value: item,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: item == _sortMode
                      ? palette.primary.withValues(alpha: 0.07)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (item == _sortMode)
                      Positioned(
                        left: -12,
                        child: Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Icon(
                          _sortMenuIcon(item),
                          size: 18,
                          color: item == _sortMode
                              ? palette.primary
                              : palette.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _SortButton.labels[item]!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: item == _sortMode
                                  ? palette.primary
                                  : palette.onSurface,
                              fontWeight: item == _sortMode
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (item == _sortMode)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: palette.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: palette.onPrimary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
    if (selected == null || selected == _sortMode) {
      return;
    }
    setState(() {
      _sortMode = selected;
    });
  }

  IconData _sortMenuIcon(ReminderSortMode mode) {
    switch (mode) {
      case ReminderSortMode.dueDate:
        return Icons.schedule_rounded;
      case ReminderSortMode.createdAt:
        return Icons.history_rounded;
      case ReminderSortMode.title:
        return Icons.sort_by_alpha_rounded;
    }
  }

  List<ReminderItem> _sortReminders(List<ReminderItem> items) {
    final sorted = [...items];
    switch (_sortMode) {
      case ReminderSortMode.dueDate:
        sorted.sort((a, b) {
          if (a.isCompleted != b.isCompleted) {
            return a.isCompleted ? 1 : -1;
          }
          return a.dueAt.compareTo(b.dueAt);
        });
        break;
      case ReminderSortMode.createdAt:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case ReminderSortMode.title:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
    }
    return sorted;
  }
}

class _ProfileMetricCard extends StatelessWidget {
  const _ProfileMetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      height: 112,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      decoration: BoxDecoration(
        color: palette.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: palette.primaryContainer.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: palette.primary, size: 24),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  '条',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSettingsItem {
  const _ProfileSettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ProfileSettingsCard extends StatelessWidget {
  const _ProfileSettingsCard({required this.items});

  final List<_ProfileSettingsItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _ProfileSettingsTile(item: items[i]),
            if (i != items.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 56, right: 18),
                child: Divider(height: 1, color: palette.outline),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileSettingsTile extends StatelessWidget {
  const _ProfileSettingsTile({required this.item});

  final _ProfileSettingsItem item;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
        child: Row(
          children: [
            Icon(item.icon, size: 24, color: palette.onSurface),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: palette.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ProfileDevicePreviewTile extends StatelessWidget {
  const _ProfileDevicePreviewTile({required this.device, required this.onTap});

  final AuthDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final current = device.isCurrent;
    return Material(
      color: current
          ? palette.primaryContainer.withValues(alpha: 0.18)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Row(
            children: [
              Icon(
                _profileDeviceIcon(device),
                size: 30,
                color: current ? palette.onSurface : palette.textMuted,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: palette.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        if (current)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.primaryContainer.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '当前在线',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: palette.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          )
                        else
                          Text(
                            _profileRelativeTime(device.lastActiveAt),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: palette.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${device.ipAddress} · ${device.platform} · ID: ${_shortDeviceId(device)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _profileDeviceIcon(AuthDevice device) {
    final value = '${device.platform} ${device.userAgent}'.toLowerCase();
    if (value.contains('iphone') || value.contains('ios')) {
      return Icons.phone_iphone_rounded;
    }
    if (value.contains('android')) {
      return Icons.android_rounded;
    }
    if (value.contains('mac')) {
      return Icons.desktop_mac_rounded;
    }
    if (value.contains('windows')) {
      return Icons.desktop_windows_rounded;
    }
    return Icons.devices_rounded;
  }

  static String _shortDeviceId(AuthDevice device) {
    final value = (device.deviceFingerprint ?? device.id).replaceAll('-', '');
    if (value.length <= 8) {
      return value;
    }
    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }

  static String _profileRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inDays >= 1) {
      return '${diff.inDays} 天前';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours} 小时前';
    }
    if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} 分钟前';
    }
    return '刚刚';
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({
    required this.pendingCount,
    required this.completedCount,
    required this.overdueCount,
    required this.recurringCount,
    required this.countdownLabel,
    required this.onRefresh,
  });

  final int pendingCount;
  final int completedCount;
  final int overdueCount;
  final int recurringCount;
  final String? countdownLabel;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: palette.surfaceBright,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.primaryContainer.withValues(alpha: 0.45),
        ),
        boxShadow: const [
          BoxShadow(
            color: _kCardShadowColor,
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.primaryContainer.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wb_sunny_outlined,
                  size: 20,
                  color: palette.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '${_greeting()}，开始高效的一天吧',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: palette.onSurface,
                  ),
                ),
              ),
              Icon(Icons.eco_rounded, size: 18, color: palette.primary),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _TodayMetric(
                  value: '$pendingCount',
                  label: '个待处理',
                  valueColor: palette.primary,
                  showArrow: true,
                ),
              ),
              _MetricDivider(color: palette.outline),
              Expanded(
                child: _TodayMetric(value: '$completedCount', label: '已完成'),
              ),
              Expanded(
                child: _TodayMetric(value: '$overdueCount', label: '逾期'),
              ),
              Expanded(
                child: _TodayMetric(value: '$recurringCount', label: '循环提醒'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onRefresh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: palette.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '最后同步 · 刷新',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '下次自动刷新 ${countdownLabel ?? '--'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onRefresh,
                child: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: palette.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) {
      return '夜深了';
    }
    if (hour < 12) {
      return '早上好';
    }
    if (hour < 18) {
      return '下午好';
    }
    return '晚上好';
  }
}

class _TodayMetric extends StatelessWidget {
  const _TodayMetric({
    required this.value,
    required this.label,
    this.valueColor,
    this.showArrow = false,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                height: 1,
                fontWeight: FontWeight.w800,
                color: valueColor ?? palette.onSurface,
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_downward_rounded,
                size: 16,
                color: palette.primary,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: color);
  }
}

class _TodayActionButton extends StatelessWidget {
  const _TodayActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: _kCardShadowColorSoft,
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: palette.secondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (label.startsWith('按')) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: palette.onSurface,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.mode, required this.onChanged});

  final ReminderSortMode mode;
  final ValueChanged<ReminderSortMode> onChanged;

  static const labels = {
    ReminderSortMode.dueDate: '按时间排序',
    ReminderSortMode.createdAt: '按创建排序',
    ReminderSortMode.title: '按标题排序',
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return PopupMenuButton<ReminderSortMode>(
      tooltip: '排序方式',
      onSelected: onChanged,
      itemBuilder: (context) {
        return ReminderSortMode.values
            .map(
              (item) => CheckedPopupMenuItem<ReminderSortMode>(
                value: item,
                checked: item == mode,
                child: Text(labels[item]!),
              ),
            )
            .toList();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 16, color: palette.secondary),
            const SizedBox(width: 6),
            Text(
              labels[mode]!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricMini extends StatelessWidget {
  const _MetricMini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.outline),
        boxShadow: const [
          BoxShadow(
            color: _kCardShadowColorSoft,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: palette.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: palette.textMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }
}

class _InboxSearchButton extends StatelessWidget {
  const _InboxSearchButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  active ? '查询条件已生效' : '搜索提醒、清单、标签',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxTopButton extends StatelessWidget {
  const _InboxTopButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 0),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: palette.secondary),
              if (showLabel) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxFilterButton extends StatelessWidget {
  const _InboxFilterButton({
    required this.active,
    required this.onTap,
    this.icon = Icons.filter_list_rounded,
    this.label = '筛选',
    this.showLabel = true,
  });

  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: active
          ? palette.primaryContainer.withValues(alpha: 0.35)
          : palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 14 : 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: palette.secondary),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderQuerySheet extends StatefulWidget {
  const _ReminderQuerySheet({
    required this.initialQuery,
    required this.lists,
    required this.groups,
    required this.tags,
  });

  final ReminderQuery initialQuery;
  final List<ReminderList> lists;
  final List<ReminderGroup> groups;
  final List<ReminderTag> tags;

  @override
  State<_ReminderQuerySheet> createState() => _ReminderQuerySheetState();
}

class _ReminderQuerySheetState extends State<_ReminderQuerySheet> {
  late ReminderFilter _completion;
  late Set<String> _selectedListIds;
  late Set<String> _selectedGroupIds;
  late Set<String> _selectedTagIds;

  @override
  void initState() {
    super.initState();
    _completion = widget.initialQuery.completion;
    _selectedListIds = {...widget.initialQuery.listIds};
    _selectedGroupIds = {...widget.initialQuery.groupIds};
    _selectedTagIds = {...widget.initialQuery.tagIds};
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '查询提醒',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          _QuerySection(
            title: '完成状态',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _queryChip(
                  label: '全部',
                  selected: _completion == ReminderFilter.all,
                  onTap: () => setState(() {
                    _completion = ReminderFilter.all;
                  }),
                ),
                _queryChip(
                  label: '未完成',
                  selected: _completion == ReminderFilter.pending,
                  onTap: () => setState(() {
                    _completion = ReminderFilter.pending;
                  }),
                ),
                _queryChip(
                  label: '已完成',
                  selected: _completion == ReminderFilter.completed,
                  onTap: () => setState(() {
                    _completion = ReminderFilter.completed;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _QuerySection(
            title: '任务清单',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.lists
                  .map(
                    (item) => _queryChip(
                      label: item.name,
                      selected: _selectedListIds.contains(item.id),
                      onTap: () => setState(() {
                        if (!_selectedListIds.add(item.id)) {
                          _selectedListIds.remove(item.id);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          _QuerySection(
            title: '分组',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.groups
                  .map(
                    (item) => _queryChip(
                      label: item.name,
                      selected: _selectedGroupIds.contains(item.id),
                      onTap: () => setState(() {
                        if (!_selectedGroupIds.add(item.id)) {
                          _selectedGroupIds.remove(item.id);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          _QuerySection(
            title: '标签',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.tags
                  .map(
                    (item) => _queryChip(
                      label: item.name,
                      selected: _selectedTagIds.contains(item.id),
                      onTap: () => setState(() {
                        if (!_selectedTagIds.add(item.id)) {
                          _selectedTagIds.remove(item.id);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(const ReminderQuery());
                },
                child: const Text('清空'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    ReminderQuery(
                      completion: _completion,
                      listIds: _selectedListIds.toList(),
                      groupIds: _selectedGroupIds.toList(),
                      tagIds: _selectedTagIds.toList(),
                    ),
                  );
                },
                child: const Text('应用查询'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _queryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = AppThemeScope.of(context).palette;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      side: BorderSide.none,
      selectedColor: palette.outlineSoft,
      checkmarkColor: palette.primary,
      labelStyle: TextStyle(
        color: selected ? palette.primary : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _QuerySection extends StatelessWidget {
  const _QuerySection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.controller,
    required this.onTap,
    required this.onToggleCompletion,
  });

  final ReminderItem reminder;
  final ReminderController controller;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleCompletion;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final list = controller.findList(reminder.listId);
    final tags = controller.findTags(reminder.tagIds);
    final status = _InboxReminderStatus.fromReminder(reminder, palette);
    final dateLabel = _inboxDateLabel(reminder.dueAt);
    final weekdayLabel = _inboxWeekdayLabel(reminder.dueAt);
    final timeLabel = reminder.hasSpecificTime
        ? DateFormat('HH:mm', 'zh_CN').format(reminder.dueAt)
        : '全天';

    return Material(
      color: status.cardColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.fromLTRB(0, 0, 14, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: status.borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 132,
                height: 104,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              dateLabel,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: status.mutedColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              timeLabel,
                              maxLines: 1,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: status.timeColor,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: double.infinity,
                      child: ColoredBox(
                        color: status.borderColor,
                        child: const SizedBox(width: 1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            reminder.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  decoration: reminder.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: reminder.isCompleted
                                      ? palette.textMuted.withValues(
                                          alpha: 0.78,
                                        )
                                      : null,
                                ),
                          ),
                        ),
                        if (reminder.repeatRule != ReminderRepeatRule.none) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.sync_rounded,
                            size: 17,
                            color: palette.textMuted,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          list?.name ?? '默认清单',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (tags.isNotEmpty)
                          _TodayTinyChip(
                            label: tags.first.name,
                            color: status.timeColor,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onToggleCompletion(!reminder.isCompleted),
                child: SizedBox(
                  width: 76,
                  height: 104,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _InboxStatusLabel(status: status),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            weekdayLabel,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: status.mutedColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: status.mutedColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _inboxDateLabel(DateTime dueAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(dueAt.year, dueAt.month, dueAt.day);
    final diff = dueDate.difference(today).inDays;
    if (diff == 0) {
      return '今天';
    }
    if (diff == 1) {
      return '明天';
    }
    return DateFormat('M 月 d 日', 'zh_CN').format(dueAt);
  }

  static String _inboxWeekdayLabel(DateTime dueAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(dueAt.year, dueAt.month, dueAt.day);
    final diff = dueDate.difference(today).inDays;
    if (diff == 0) {
      return '今天';
    }
    if (diff == 1) {
      return '明天';
    }
    return DateFormat('E', 'zh_CN').format(dueAt);
  }
}

class _InboxStatusLabel extends StatelessWidget {
  const _InboxStatusLabel({required this.status});

  final _InboxReminderStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.filled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: status.badgeBackground,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: status.labelColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Text(
      status.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: status.labelColor,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _InboxReminderStatus {
  const _InboxReminderStatus({
    required this.label,
    required this.timeColor,
    required this.labelColor,
    required this.mutedColor,
    required this.cardColor,
    required this.borderColor,
    required this.badgeBackground,
    this.filled = false,
  });

  final String label;
  final Color timeColor;
  final Color labelColor;
  final Color mutedColor;
  final Color cardColor;
  final Color borderColor;
  final Color badgeBackground;
  final bool filled;

  factory _InboxReminderStatus.fromReminder(
    ReminderItem reminder,
    AppThemePalette palette,
  ) {
    final green = palette.success;
    final orange = palette.warning;
    final red = palette.error;
    final gray = palette.textMuted;
    final muted = palette.textMuted;
    final border = palette.outline;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(
      reminder.dueAt.year,
      reminder.dueAt.month,
      reminder.dueAt.day,
    );
    final diff = dueDate.difference(today).inDays;

    if (reminder.isCompleted) {
      return _InboxReminderStatus(
        label: '已完成',
        timeColor: gray,
        labelColor: gray,
        mutedColor: gray,
        cardColor: palette.surface,
        borderColor: border,
        badgeBackground: palette.surfaceContainerLow,
      );
    }

    if (diff < 0) {
      return _InboxReminderStatus(
        label: '逾期 ${diff.abs()} 天',
        timeColor: red,
        labelColor: red,
        mutedColor: muted,
        cardColor: palette.errorContainer.withValues(alpha: 0.3),
        borderColor: palette.errorContainer,
        badgeBackground: palette.errorContainer,
      );
    }

    if (diff == 0 && reminder.hasSpecificTime && reminder.dueAt.isBefore(now)) {
      return _InboxReminderStatus(
        label: '进行中',
        timeColor: green,
        labelColor: palette.success,
        mutedColor: muted,
        cardColor: palette.surface,
        borderColor: border,
        badgeBackground: palette.successContainer,
        filled: true,
      );
    }

    if (diff == 0) {
      return _InboxReminderStatus(
        label: '待办',
        timeColor: green,
        labelColor: green,
        mutedColor: muted,
        cardColor: palette.surface,
        borderColor: border,
        badgeBackground: palette.successContainer,
      );
    }

    return _InboxReminderStatus(
      label: '剩余 $diff 天',
      timeColor: diff <= 1 ? green : palette.onSurface,
      labelColor: diff <= 1 ? green : orange,
      mutedColor: muted,
      cardColor: palette.surface,
      borderColor: border,
      badgeBackground: palette.warningContainer,
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.chipBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActionChip extends StatelessWidget {
  const _CompactActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: palette.outlineSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: palette.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderListLoadingSkeleton extends StatelessWidget {
  const _ReminderListLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        _LoadingBar(widthFactor: 0.36, height: 30),
        SizedBox(height: 16),
        _LoadingBar(widthFactor: 0.22),
        SizedBox(height: 14),
        _LoadingCard(height: 108),
        SizedBox(height: 12),
        _LoadingCard(height: 108),
        SizedBox(height: 12),
        _LoadingCard(height: 108),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: palette.chipBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LoadingBar(widthFactor: 0.28),
            SizedBox(height: 12),
            _LoadingBar(widthFactor: 0.72),
            SizedBox(height: 10),
            _LoadingBar(widthFactor: 0.52),
          ],
        ),
      ),
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.widthFactor, this.height = 14});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonBar(widthFactor: widthFactor, height: height);
  }
}

class _ReminderSwipeAction extends StatelessWidget {
  const _ReminderSwipeAction({
    required this.reminderId,
    required this.onDelete,
    required this.child,
  });

  final String reminderId;
  final Future<void> Function() onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Slidable(
      key: ValueKey('reminder-swipe-$reminderId'),
      closeOnScroll: true,
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.24,
        openThreshold: 0.2,
        closeThreshold: 0.1,
        dragDismissible: false,
        children: [
          CustomSlidableAction(
            onPressed: (_) async {
              await onDelete();
            },
            backgroundColor: palette.background,
            padding: EdgeInsets.zero,
            child: Container(
              decoration: BoxDecoration(
                color: palette.error,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: palette.onErrorContainer,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '删除',
                    style: TextStyle(
                      color: palette.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.reminder,
    required this.controller,
    required this.onOpenReminder,
    required this.onToggleCompletion,
  });

  final ReminderItem reminder;
  final ReminderController controller;
  final VoidCallback onOpenReminder;
  final ValueChanged<bool> onToggleCompletion;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final list = controller.findList(reminder.listId);
    final isOverdue = reminder.isOverdue;
    final isCompleted = reminder.isCompleted;
    final baseTextColor = isCompleted
        ? palette.textMuted.withValues(alpha: 0.72)
        : null;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      decoration: isCompleted
          ? TextDecoration.lineThrough
          : TextDecoration.none,
      color: baseTextColor,
    );

    return Card(
      color: isOverdue
          ? palette.errorContainer.withValues(alpha: 0.3)
          : (isCompleted ? palette.chipBackground : null),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onOpenReminder,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 78,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        reminder.hasSpecificTime
                            ? DateFormat('HH:mm').format(reminder.dueAt)
                            : '全天',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isOverdue
                              ? palette.error
                              : (baseTextColor ??
                                    Theme.of(
                                      context,
                                    ).textTheme.titleLarge?.color),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: isOverdue ? palette.errorContainer : palette.outline,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reminder.title, style: titleStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            list?.name ?? '未分类清单',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isCompleted
                                      ? palette.textMuted.withValues(
                                          alpha: 0.72,
                                        )
                                      : palette.textMuted,
                                ),
                          ),
                          if (isOverdue)
                            _Pill(
                              label: '超时未完成',
                              color: palette.errorContainer,
                              foreground: palette.error,
                            ),
                          if (isCompleted)
                            _Pill(
                              label: '已完成',
                              color: palette.outline,
                              foreground: palette.primary,
                            ),
                        ],
                      ),
                      if (reminder.note?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text(
                          reminder.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: baseTextColor),
                        ),
                      ],
                    ],
                  ),
                ),
                Checkbox(
                  value: reminder.isCompleted,
                  onChanged: (value) => onToggleCompletion(value ?? false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayReminderRow extends StatelessWidget {
  const _TodayReminderRow({
    required this.reminder,
    required this.controller,
    required this.onOpenReminder,
    required this.onToggleCompletion,
  });

  final ReminderItem reminder;
  final ReminderController controller;
  final VoidCallback onOpenReminder;
  final ValueChanged<bool> onToggleCompletion;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final list = controller.findList(reminder.listId);
    final tags = controller.findTags(reminder.tagIds);
    final isCompleted = reminder.isCompleted;
    final status = _TodayReminderStatus.fromReminder(reminder, palette);
    final titleColor = isCompleted ? palette.textMuted : palette.onSurface;
    final subtitleColor = isCompleted ? palette.textMuted : palette.textMuted;
    final primaryTag = tags.isNotEmpty ? tags.first.name : null;

    return Material(
      color: status.cardColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpenReminder,
        child: Container(
          constraints: const BoxConstraints(minHeight: 86),
          padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: status.borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 86,
                width: 122,
                child: Row(
                  children: [
                    SizedBox(
                      height: double.infinity,
                      width: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                width: 1,
                                color: status.dotColor.withValues(alpha: 0.16),
                              ),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? status.cardColor
                                  : status.dotColor,
                              shape: BoxShape.circle,
                              border: isCompleted
                                  ? Border.all(
                                      color: status.dotColor,
                                      width: 1.4,
                                    )
                                  : null,
                            ),
                            child: isCompleted
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 10,
                                    color: status.dotColor,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        reminder.hasSpecificTime
                            ? DateFormat('HH:mm').format(reminder.dueAt)
                            : '全天',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: status.timeColor,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: double.infinity,
                      child: ColoredBox(
                        color: status.borderColor,
                        child: const SizedBox(width: 1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              reminder.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    decoration: isCompleted
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                    color: titleColor,
                                  ),
                            ),
                          ),
                          if (reminder.repeatRule !=
                              ReminderRepeatRule.none) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.sync_rounded,
                              size: 16,
                              color: subtitleColor,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            list?.name ?? '默认清单',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: subtitleColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          if (primaryTag != null)
                            _TodayTinyChip(
                              label: primaryTag,
                              color: status.dotColor,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onToggleCompletion(!isCompleted),
                child: SizedBox(
                  width: 86,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (status.filled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: status.labelBackground,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.label,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: status.labelColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status.icon != null) ...[
                              Icon(
                                status.icon,
                                size: 16,
                                color: status.labelColor,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                status.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: status.labelColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayTinyChip extends StatelessWidget {
  const _TodayTinyChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TodayReminderStatus {
  const _TodayReminderStatus({
    required this.label,
    required this.timeColor,
    required this.dotColor,
    required this.cardColor,
    required this.borderColor,
    required this.labelColor,
    required this.labelBackground,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color timeColor;
  final Color dotColor;
  final Color cardColor;
  final Color borderColor;
  final Color labelColor;
  final Color labelBackground;
  final IconData? icon;
  final bool filled;

  factory _TodayReminderStatus.fromReminder(
    ReminderItem reminder,
    AppThemePalette palette,
  ) {
    final green = palette.success;
    final orange = palette.warning;
    final red = palette.error;
    final gray = palette.textMuted;
    final border = palette.outline;
    final muted = palette.textMuted;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(
      reminder.dueAt.year,
      reminder.dueAt.month,
      reminder.dueAt.day,
    );
    final diffDays = dueDay.difference(today).inDays;

    if (reminder.isCompleted) {
      return _TodayReminderStatus(
        label: '已完成',
        timeColor: gray,
        dotColor: gray,
        cardColor: palette.surfaceContainerLow,
        borderColor: palette.outline,
        labelColor: gray,
        labelBackground: palette.surfaceContainerLow,
        icon: Icons.check_circle_outline_rounded,
      );
    }

    if (diffDays < 0) {
      final days = diffDays.abs();
      return _TodayReminderStatus(
        label: '逾期 $days 天',
        timeColor: red,
        dotColor: red,
        cardColor: palette.errorContainer.withValues(alpha: 0.3),
        borderColor: palette.errorContainer,
        labelColor: red,
        labelBackground: palette.errorContainer,
      );
    }

    if (diffDays == 0 &&
        reminder.hasSpecificTime &&
        reminder.dueAt.isBefore(now)) {
      return _TodayReminderStatus(
        label: '进行中',
        timeColor: green,
        dotColor: green,
        cardColor: palette.surface,
        borderColor: border,
        labelColor: palette.success,
        labelBackground: palette.successContainer,
        filled: true,
      );
    }

    if (diffDays == 0) {
      return _TodayReminderStatus(
        label: '今天',
        timeColor: green,
        dotColor: green,
        cardColor: palette.surface,
        borderColor: border,
        labelColor: muted,
        labelBackground: palette.surfaceContainerLow,
        icon: Icons.calendar_today_rounded,
      );
    }

    return _TodayReminderStatus(
      label: '剩余 $diffDays 天',
      timeColor: orange,
      dotColor: orange,
      cardColor: palette.warningContainer.withValues(alpha: 0.28),
      borderColor: palette.warningContainer,
      labelColor: orange,
      labelBackground: palette.warningContainer,
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.count,
    required this.isSelected,
    required this.isToday,
  });

  final DateTime day;
  final int count;
  final bool isSelected;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final intensity = switch (count) {
      0 => 0.0,
      1 => 0.18,
      2 => 0.28,
      3 => 0.4,
      _ => 0.55,
    };
    final fillColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : palette.primary.withValues(alpha: intensity);
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isToday
        ? palette.primary.withValues(alpha: 0.55)
        : Colors.transparent;
    final textColor = isSelected
        ? palette.onPrimary
        : count > 0
        ? palette.onSurface
        : palette.textMuted;

    return Center(
      child: SizedBox(
        width: 42,
        height: 42,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isToday ? 1.2 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: count > 0 || isSelected
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppStateEmptyCard(
      icon: Icons.notifications_none_rounded,
      title: title,
      subtitle: subtitle,
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return AppStateErrorCard(
      title: title,
      message: message,
      actionLabel: actionLabel,
      onPressed: onPressed,
    );
  }
}

class _InboxQueryEmptyState extends StatelessWidget {
  const _InboxQueryEmptyState({
    required this.summaryLabels,
    required this.onAdjustQuery,
    required this.onClearQuery,
  });

  final List<String> summaryLabels;
  final Future<void> Function() onAdjustQuery;
  final Future<void> Function() onClearQuery;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 640),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.outline),
          boxShadow: const [
            BoxShadow(
              color: _kCardShadowColor,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.outlineSoft, palette.outline],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.search_off_rounded,
                    size: 26,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '没有符合条件的提醒',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '换一个查询条件，或者清空后查看全部提醒。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (summaryLabels.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                '当前条件',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: summaryLabels
                    .map(
                      (label) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: palette.background,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: palette.outline),
                        ),
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: onAdjustQuery,
                  child: const Text('调整查询'),
                ),
                TextButton(onPressed: onClearQuery, child: const Text('清空查询')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewHeroCard extends StatelessWidget {
  const _OverviewHeroCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surface, palette.background],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.outline),
        boxShadow: const [
          BoxShadow(
            color: _kCardShadowColor,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.secondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _DataOverviewPage extends StatelessWidget {
  const _DataOverviewPage({required this.controller});

  final ReminderController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final reminders = controller.reminders;
        final completed = reminders.where((item) => item.isCompleted).length;
        final pending = reminders.length - completed;
        final overdue = reminders.where((item) => item.isOverdue).length;
        final today = reminders.where((item) => item.isDueToday).length;
        final repeatCount = reminders
            .where((item) => item.repeatRule != ReminderRepeatRule.none)
            .length;
        final notifications = reminders
            .where((item) => item.notificationEnabled)
            .length;

        return Scaffold(
          appBar: AppBar(title: const Text('数据概览')),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppThemeScope.of(context).palette.chipBackground,
                  AppThemeScope.of(context).palette.background,
                ],
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _OverviewHeroCard(
                    eyebrow: 'OVERVIEW',
                    title: '${reminders.length} 条提醒在系统中',
                    subtitle: '快速查看待办、逾期、今日和通知配置的整体分布。',
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.28,
                    children: [
                      _MetricMini(label: '全部提醒', value: '${reminders.length}'),
                      _MetricMini(label: '待办', value: '$pending'),
                      _MetricMini(label: '今日', value: '$today'),
                      _MetricMini(label: '逾期', value: '$overdue'),
                      _MetricMini(label: '已完成', value: '$completed'),
                      _MetricMini(label: '开启通知', value: '$notifications'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '数据详情',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 14),
                          _InfoRow(
                            label: '任务清单',
                            value: '${controller.lists.length}',
                          ),
                          _InfoRow(
                            label: '分组',
                            value: '${controller.groups.length}',
                          ),
                          _InfoRow(
                            label: '标签',
                            value: '${controller.tags.length}',
                          ),
                          _InfoRow(label: '循环提醒', value: '$repeatCount'),
                          _InfoRow(label: '开启通知', value: '$notifications'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceManagerPage extends StatefulWidget {
  const _WorkspaceManagerPage({required this.controller});

  final ReminderController controller;

  @override
  State<_WorkspaceManagerPage> createState() => _WorkspaceManagerPageState();
}

class _WorkspaceManagerPageState extends State<_WorkspaceManagerPage> {
  bool _listsOrdering = false;
  bool _groupsOrdering = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务清单与设置')),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppThemeScope.of(context).palette.chipBackground,
              AppThemeScope.of(context).palette.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final lists = _sortedLists();
                final groups = _sortedGroups();
                return ListView(
                  children: [
                    const _OverviewHeroCard(
                      eyebrow: 'WORKSPACE',
                      title: '统一管理清单、分组和标签',
                      subtitle: '这里的调整会直接影响提醒的归类、查询和展示方式。',
                    ),
                    const SizedBox(height: 16),
                    _ManagerSection(
                      title: '任务清单',
                      subtitle: '决定提醒属于哪个主要工作域。',
                      items: lists
                          .map(
                            (item) => _ManagerItem(
                              id: item.id,
                              label: item.name,
                              onEdit: () => _promptNameDialog(
                                context: context,
                                title: '重命名任务清单',
                                initialValue: item.name,
                                onSubmit: (name) =>
                                    widget.controller.renameList(item, name),
                              ),
                              onDelete: () => _confirmDelete(
                                context: context,
                                message:
                                    '删除清单后归属其中的提醒将暂时移至“全部提醒”视图并等待下一次同步处理，你确定要继续吗？',
                                onConfirm: () =>
                                    widget.controller.deleteList(item.id),
                              ),
                            ),
                          )
                          .toList(),
                      emptyHint: '还没有清单，点击右上角加号新建。',
                      reorderable: true,
                      isProcessing: _listsOrdering,
                      onReorder: _onListReorder,
                      onAdd: () => _promptNameDialog(
                        context: context,
                        title: '新建任务清单',
                        onSubmit: (name) => widget.controller.createList(
                          name,
                          AppThemeScope.of(
                            context,
                          ).palette.textMuted.toARGB32(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ManagerSection(
                      title: '分组',
                      subtitle: '帮助你进一步组织同类提醒。',
                      items: groups
                          .map(
                            (item) => _ManagerItem(
                              id: item.id,
                              label: item.name,
                              onEdit: () => _promptNameDialog(
                                context: context,
                                title: '重命名分组',
                                initialValue: item.name,
                                onSubmit: (name) =>
                                    widget.controller.renameGroup(item, name),
                              ),
                              onDelete: () => _confirmDelete(
                                context: context,
                                message: '删除分组仅影响展示，不会移除提醒。',
                                onConfirm: () =>
                                    widget.controller.deleteGroup(item.id),
                              ),
                            ),
                          )
                          .toList(),
                      emptyHint: '可以把“高优先级”“例行事项”拆成不同分组。',
                      reorderable: true,
                      isProcessing: _groupsOrdering,
                      onReorder: _onGroupReorder,
                      onAdd: () => _promptNameDialog(
                        context: context,
                        title: '新建分组',
                        onSubmit: (name) => widget.controller.createGroup(
                          name,
                          Icons.folder.codePoint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ManagerSection(
                      title: '标签',
                      subtitle: '用于交叉标记和快速筛选。',
                      items: widget.controller.tags
                          .map(
                            (item) => _ManagerItem(
                              id: item.id,
                              label: '#${item.name}',
                              onEdit: () => _promptNameDialog(
                                context: context,
                                title: '重命名标签',
                                initialValue: item.name,
                                onSubmit: (name) =>
                                    widget.controller.renameTag(item, name),
                              ),
                              onDelete: () => _confirmDelete(
                                context: context,
                                message: '确认删除标签 ${item.name} 吗？',
                                onConfirm: () =>
                                    widget.controller.deleteTag(item.id),
                              ),
                            ),
                          )
                          .toList(),
                      emptyHint: '给提醒加上 #深度工作、#家庭 等标签以便筛选。',
                      onAdd: () => _promptNameDialog(
                        context: context,
                        title: '新建标签',
                        onSubmit: (name) => widget.controller.createTag(
                          name,
                          AppThemeScope.of(context).palette.primary.toARGB32(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<ReminderList> _sortedLists() {
    final lists = [...widget.controller.lists];
    lists.sort((a, b) {
      final compare = a.sortOrder.compareTo(b.sortOrder);
      if (compare != 0) {
        return compare;
      }
      return a.name.compareTo(b.name);
    });
    return lists;
  }

  List<ReminderGroup> _sortedGroups() {
    final groups = [...widget.controller.groups];
    groups.sort((a, b) {
      final compare = a.sortOrder.compareTo(b.sortOrder);
      if (compare != 0) {
        return compare;
      }
      return a.name.compareTo(b.name);
    });
    return groups;
  }

  Future<void> _onListReorder(int oldIndex, int newIndex) async {
    if (_listsOrdering) {
      return;
    }
    final lists = _sortedLists();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = lists.removeAt(oldIndex);
    lists.insert(newIndex, item);
    setState(() {
      _listsOrdering = true;
    });
    await widget.controller.applyListOrder(lists);
    if (!mounted) {
      return;
    }
    setState(() {
      _listsOrdering = false;
    });
  }

  Future<void> _onGroupReorder(int oldIndex, int newIndex) async {
    if (_groupsOrdering) {
      return;
    }
    final groups = _sortedGroups();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = groups.removeAt(oldIndex);
    groups.insert(newIndex, item);
    setState(() {
      _groupsOrdering = true;
    });
    await widget.controller.applyGroupOrder(groups);
    if (!mounted) {
      return;
    }
    setState(() {
      _groupsOrdering = false;
    });
  }

  Future<void> _promptNameDialog({
    required BuildContext context,
    required String title,
    String? initialValue,
    required Future<void> Function(String name) onSubmit,
  }) async {
    final controller = TextEditingController(text: initialValue ?? '');
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '名称会立即同步到当前工作区。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppThemeScope.of(context).palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '请输入名称',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = '名称不能为空';
                      });
                      return;
                    }
                    await onSubmit(name);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _confirmDelete({
    required BuildContext context,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppThemeScope.of(context).palette.error,
                foregroundColor: AppThemeScope.of(
                  context,
                ).palette.onErrorContainer,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await onConfirm();
    }
  }
}

class _CalendarPage extends StatefulWidget {
  const _CalendarPage({
    required this.controller,
    required this.initialSelectedDate,
    required this.initialFocusedDate,
    required this.onOpenReminder,
    required this.onDeleteReminder,
    required this.onToggleCompletion,
  });

  final ReminderController controller;
  final DateTime initialSelectedDate;
  final DateTime initialFocusedDate;
  final void Function(ReminderItem reminder) onOpenReminder;
  final Future<void> Function(ReminderItem reminder) onDeleteReminder;
  final Future<void> Function(ReminderItem reminder, bool isCompleted)
  onToggleCompletion;

  @override
  State<_CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<_CalendarPage> {
  late DateTime _selectedDate;
  late DateTime _focusedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialSelectedDate.year,
      widget.initialSelectedDate.month,
      widget.initialSelectedDate.day,
    );
    _focusedDate = widget.initialFocusedDate;
  }

  @override
  Widget build(BuildContext context) {
    final reminderCounts = _buildReminderCountMap(widget.controller.reminders);
    final selectedItems = widget.controller.remindersForDate(_selectedDate);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_selectedDate);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('日历'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(_selectedDate),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TableCalendar<int>(
                    locale: 'zh_CN',
                    firstDay: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDay: DateTime.now().add(const Duration(days: 3650)),
                    focusedDay: _focusedDate,
                    selectedDayPredicate: (day) =>
                        isSameDay(day, _selectedDate),
                    eventLoader: (day) {
                      final count = reminderCounts[_dateKey(day)] ?? 0;
                      if (count == 0) {
                        return const [];
                      }
                      return List<int>.filled(count, 1);
                    },
                    calendarFormat: CalendarFormat.month,
                    availableCalendarFormats: const {CalendarFormat.month: '月'},
                    headerStyle: HeaderStyle(
                      titleCentered: true,
                      formatButtonVisible: false,
                      titleTextFormatter: (date, locale) =>
                          DateFormat('yyyy年M月', locale).format(date),
                      titleTextStyle: Theme.of(context).textTheme.titleMedium!
                          .copyWith(fontWeight: FontWeight.w800),
                      leftChevronIcon: const Icon(Icons.chevron_left_rounded),
                      rightChevronIcon: const Icon(Icons.chevron_right_rounded),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekendStyle: Theme.of(context).textTheme.bodySmall!
                          .copyWith(
                            color: AppThemeScope.of(context).palette.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                      weekdayStyle: Theme.of(context).textTheme.bodySmall!
                          .copyWith(
                            color: AppThemeScope.of(context).palette.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    calendarStyle: const CalendarStyle(
                      outsideDaysVisible: false,
                      defaultDecoration: BoxDecoration(),
                      weekendDecoration: BoxDecoration(),
                      todayDecoration: BoxDecoration(),
                      selectedDecoration: BoxDecoration(),
                      cellMargin: EdgeInsets.all(6),
                    ),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDate = selectedDay;
                        _focusedDate = focusedDay;
                      });
                    },
                    onPageChanged: (focusedDay) {
                      setState(() {
                        _focusedDate = focusedDay;
                      });
                    },
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) {
                        return _CalendarDayCell(
                          day: day,
                          count: reminderCounts[_dateKey(day)] ?? 0,
                          isSelected: false,
                          isToday: isSameDay(day, DateTime.now()),
                        );
                      },
                      todayBuilder: (context, day, focusedDay) {
                        return _CalendarDayCell(
                          day: day,
                          count: reminderCounts[_dateKey(day)] ?? 0,
                          isSelected: false,
                          isToday: true,
                        );
                      },
                      selectedBuilder: (context, day, focusedDay) {
                        return _CalendarDayCell(
                          day: day,
                          count: reminderCounts[_dateKey(day)] ?? 0,
                          isSelected: true,
                          isToday: isSameDay(day, DateTime.now()),
                        );
                      },
                      outsideBuilder: (context, day, focusedDay) =>
                          const SizedBox.shrink(),
                      markerBuilder: (context, day, events) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle(
                title: DateFormat('M月d日 EEEE', 'zh_CN').format(_selectedDate),
                subtitle: '按时间查看这一天的提醒安排',
              ),
              const SizedBox(height: 12),
              if (selectedItems.isEmpty)
                const _EmptyPanel(
                  title: '这一天没有提醒',
                  subtitle: '你可以从这里提前规划节奏，时间线会自动联动。',
                )
              else
                ...selectedItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ReminderSwipeAction(
                      reminderId: item.id,
                      onDelete: () => widget.onDeleteReminder(item),
                      child: _TimelineTile(
                        reminder: item,
                        controller: widget.controller,
                        onOpenReminder: () => widget.onOpenReminder(item),
                        onToggleCompletion: (value) =>
                            widget.onToggleCompletion(item, value),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, int> _buildReminderCountMap(List<ReminderItem> reminders) {
  final counts = <String, int>{};
  for (final item in reminders) {
    final key = _dateKey(item.dueAt);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month}-${date.day}';
}

class _ManagerSection extends StatelessWidget {
  const _ManagerSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.emptyHint,
    required this.onAdd,
    this.reorderable = false,
    this.onReorder,
    this.isProcessing = false,
  });

  final String title;
  final String subtitle;
  final List<_ManagerItem> items;
  final String emptyHint;
  final VoidCallback onAdd;
  final bool reorderable;
  final Future<void> Function(int oldIndex, int newIndex)? onReorder;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.outline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: palette.outline,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.inventory_2_rounded,
                        size: 18,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        emptyHint,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (reorderable && onReorder != null)
              _ReorderableList(
                items: items,
                onReorder: onReorder!,
                isProcessing: isProcessing,
              )
            else
              ...items.map(
                (item) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.outline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: '编辑',
                        onPressed: item.onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: '删除',
                        onPressed: item.onDelete,
                        color: AppThemeScope.of(context).palette.error,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ManagerItem {
  const _ManagerItem({
    required this.id,
    required this.label,
    required this.onEdit,
    required this.onDelete,
  });

  final String id;
  final String label;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
}

class _ReorderableList extends StatelessWidget {
  const _ReorderableList({
    required this.items,
    required this.onReorder,
    required this.isProcessing,
  });

  final List<_ManagerItem> items;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final listView = ReorderableListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) async {
        if (isProcessing) {
          return;
        }
        await onReorder(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          key: ValueKey(item.id),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '编辑',
                onPressed: item.onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: item.onDelete,
                color: palette.error,
                icon: const Icon(Icons.delete_outline),
              ),
              const SizedBox(width: 4),
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle_rounded),
              ),
            ],
          ),
        );
      },
    );

    if (!isProcessing) {
      return listView;
    }

    return Stack(
      children: [
        Opacity(opacity: 0.5, child: listView),
        const Positioned.fill(
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ],
    );
  }
}
