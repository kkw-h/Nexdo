import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../auth/data/auth_repository.dart'
    show AuthRepository, AuthException;
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/change_password_page.dart';
import '../../auth/presentation/device_management_page.dart';
import 'package:nexdo/src/core/network/api_client.dart';
import '../application/reminder_notification_service.dart';
import '../data/datasources/reminder_local_data_source.dart';
import '../data/repositories/remote_reminder_workspace_repository.dart';
import '../domain/entities/reminder_models.dart';
import 'reminder_controller.dart';
import 'reminder_form_page.dart';

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

class _ReminderAppShellState extends State<ReminderAppShell> {
  static const _permissionPromptKey = 'permission_prompt.shown';
  ReminderController? _controller;
  ReminderFilter _selectedFilter = ReminderFilter.all;
  ReminderSortMode _sortMode = ReminderSortMode.dueDate;
  int _selectedNavIndex = 0;
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  String? _error;
  bool _refreshing = false;
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
      });
      _startCountdownTicker();
      await _maybeShowPermissionPrompt(preferences);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
      await widget.onLogout();
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
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _initialize, child: const Text('重试加载')),
              ],
            ),
          ),
        ),
      );
    }
    if (controller == null || controller.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final todayItems = controller.remindersForDate(DateTime.now());
        final pages = [
          _buildTodayView(controller, todayItems),
          _buildInboxView(controller),
          _buildQuickNotesView(),
          _buildProfileView(controller),
        ];
        final titles = ['今日', '清单', '闪念', '我的'];
        final fabLabel = _selectedNavIndex == 2 ? '新建闪念' : '新建提醒';
        final fabIcon = _selectedNavIndex == 2
            ? Icons.bolt_rounded
            : Icons.add_alert_rounded;

        return Scaffold(
          floatingActionButton: _selectedNavIndex == 3
              ? null
              : FloatingActionButton.extended(
                  onPressed: () {
                    if (_selectedNavIndex == 2) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('闪念创建功能下一步补上')),
                      );
                      return;
                    }
                    _openForm(controller);
                  },
                  icon: Icon(fabIcon),
                  label: Text(fabLabel),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedNavIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedNavIndex = index;
              });
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
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '我的',
              ),
            ],
          ),
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFDCEEE6), Color(0xFFF5F7F2)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopBar(
                      title: titles[_selectedNavIndex],
                      onOpenCalendar: () => _openCalendarPage(controller),
                      showCalendarButton:
                          _selectedNavIndex == 0 || _selectedNavIndex == 1,
                      onRefresh:
                          (_selectedNavIndex == 2 || _selectedNavIndex == 3)
                          ? null
                          : (_refreshing
                                ? null
                                : () => _refreshData(controller)),
                      isRefreshing:
                          (_selectedNavIndex == 2 || _selectedNavIndex == 3)
                          ? false
                          : _refreshing,
                      refreshCountdownLabel:
                          (_selectedNavIndex == 2 || _selectedNavIndex == 3)
                          ? null
                          : _countdownLabel(),
                    ),
                    const SizedBox(height: 16),
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
        );
      },
    );
  }

  Future<void> _refreshData(ReminderController controller) async {
    setState(() {
      _refreshing = true;
    });
    try {
      await controller.refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已刷新最新数据')));
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      await widget.onLogout();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('刷新失败，请稍后再试')));
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Widget _buildInboxView(ReminderController controller) {
    final reminders = _sortReminders(controller.remindersFor(_selectedFilter));

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _FilterBar(
                selectedFilter: _selectedFilter,
                onChanged: (filter) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                controller: controller,
              ),
            ),
            _SortButton(
              mode: _sortMode,
              onChanged: (mode) {
                setState(() {
                  _sortMode = mode;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: reminders.isEmpty
              ? const _EmptyPanel(
                  title: '当前没有提醒',
                  subtitle: '先创建提醒，列表会按时间自动排列。',
                )
              : ListView.separated(
                  itemCount: reminders.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final reminder = reminders[index];
                    return _ReminderCard(
                      reminder: reminder,
                      controller: controller,
                      onTap: () => _openForm(controller, reminder: reminder),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTodayView(
    ReminderController controller,
    List<ReminderItem> todayItems,
  ) {
    final orderedItems = _sortReminders(todayItems);

    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '今日任务',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            _SortButton(
              mode: _sortMode,
              onChanged: (mode) {
                setState(() {
                  _sortMode = mode;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (orderedItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '${orderedItems.where((item) => !item.isCompleted).length} 条待处理',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
            ),
          ),
        const SizedBox(height: 2),
        if (orderedItems.isEmpty)
          const _EmptyPanel(title: '今天还没有排程', subtitle: '加一条提醒，时间线就会按顺序展示出来。')
        else
          ...orderedItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TodayReminderRow(
                reminder: item,
                controller: controller,
                onOpenReminder: () => _openForm(controller, reminder: item),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickNotesView() {
    return ListView(
      children: const [
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('先快速记下灵感、待办和临时提醒，后续再整理进清单。'),
        ),
        _EmptyPanel(title: '闪念功能准备中', subtitle: '下一步可以补成本地快速记录、转任务和批量整理。'),
      ],
    );
  }

  Widget _buildProfileView(ReminderController controller) {
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFDCEEE6),
                  child: Text(
                    widget.currentUser.name.trim().isEmpty
                        ? 'N'
                        : widget.currentUser.name.trim()[0].toUpperCase(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF126A5A),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.currentUser.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.currentUser.email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF60716B),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await widget.onLogout();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('退出'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '查看当前提醒数据和使用情况。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
          ),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
            leading: const Icon(Icons.bar_chart_rounded),
            title: const Text('查看数据概览'),
            subtitle: const Text('总提醒、待办、逾期等详细统计'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openDataOverview(controller),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
            leading: const Icon(Icons.lock_reset_rounded),
            title: const Text('修改密码'),
            subtitle: const Text('更新当前账号登录密码'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ChangePasswordPage(repository: widget.authRepository),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
            leading: const Icon(Icons.tune_rounded),
            title: const Text('任务清单与设置'),
            subtitle: const Text('管理清单、分组、标签等配置'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openWorkspaceManager(controller),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: const Icon(Icons.devices_rounded),
            title: const Text('设备管理'),
            subtitle: const Text('查看当前账号的在线设备'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      DeviceManagementPage(repository: widget.authRepository),
                ),
              );
            },
          ),
        ),
      ],
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
        ),
      ),
    );

    if (result == null) {
      return;
    }

    await controller.saveReminder(result.reminder);
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
    return '${seconds}s';
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onOpenCalendar,
    required this.showCalendarButton,
    required this.onRefresh,
    required this.isRefreshing,
    required this.refreshCountdownLabel,
  });

  final String title;
  final VoidCallback onOpenCalendar;
  final bool showCalendarButton;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final String? refreshCountdownLabel;

  @override
  Widget build(BuildContext context) {
    final countdownText = refreshCountdownLabel == null
        ? '刷新'
        : '刷新 · $refreshCountdownLabel';
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (onRefresh != null)
          TextButton.icon(
            onPressed: onRefresh,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              foregroundColor: const Color(0xFF126A5A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: const BorderSide(color: Color(0xFFDCE6E1)),
              ),
            ),
            icon: isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              countdownText,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        if (showCalendarButton)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton.filledTonal(
              onPressed: onOpenCalendar,
              icon: const Icon(Icons.calendar_month_rounded),
            ),
          ),
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.mode, required this.onChanged});

  final ReminderSortMode mode;
  final ValueChanged<ReminderSortMode> onChanged;

  static const _labels = {
    ReminderSortMode.dueDate: '到期时间',
    ReminderSortMode.createdAt: '创建时间',
    ReminderSortMode.title: '标题',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReminderSortMode>(
      tooltip: '排序方式',
      onSelected: onChanged,
      itemBuilder: (context) {
        return ReminderSortMode.values
            .map(
              (item) => CheckedPopupMenuItem<ReminderSortMode>(
                value: item,
                checked: item == mode,
                child: Text(_labels[item]!),
              ),
            )
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E6E3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 16, color: Color(0xFF126A5A)),
            const SizedBox(width: 6),
            Text(
              _labels[mode]!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF126A5A)),
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
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF60716B)),
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
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selectedFilter,
    required this.onChanged,
    required this.controller,
  });

  final ReminderFilter selectedFilter;
  final ValueChanged<ReminderFilter> onChanged;
  final ReminderController controller;

  @override
  Widget build(BuildContext context) {
    final labels = {
      ReminderFilter.all: '全部',
      ReminderFilter.pending: '未完成',
      ReminderFilter.completed: '已完成',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ReminderFilter.values.map((filter) {
          final isSelected = filter == selectedFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              label: Text(
                '${labels[filter]} ${controller.remindersFor(filter).length}',
              ),
              selected: isSelected,
              onSelected: (_) => onChanged(filter),
              side: BorderSide.none,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.controller,
    required this.onTap,
  });

  final ReminderItem reminder;
  final ReminderController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final list = controller.findList(reminder.listId);
    final group = controller.findGroup(reminder.groupId);
    final dateFormatter = DateFormat('M月d日', 'zh_CN');
    final dateLabel = reminder.isDueToday
        ? '今天'
        : dateFormatter.format(reminder.dueAt);
    final timeLabel = reminder.hasSpecificTime
        ? DateFormat('HH:mm', 'zh_CN').format(reminder.dueAt)
        : '全天';
    final statusLabel = reminder.isCompleted
        ? '已完成'
        : reminder.isOverdue
        ? '已逾期'
        : '进行中';
    final statusColor = reminder.isCompleted
        ? const Color(0xFF4B6F5F)
        : reminder.isOverdue
        ? const Color(0xFFB85C38)
        : const Color(0xFF126A5A);

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dueDate = DateTime(
      reminder.dueAt.year,
      reminder.dueAt.month,
      reminder.dueAt.day,
    );
    final dayDiff = dueDate.difference(todayDate).inDays;
    String distanceLabel;
    if (reminder.isCompleted) {
      distanceLabel = '已完成';
    } else if (dayDiff > 0) {
      distanceLabel = '剩余$dayDiff天';
    } else if (dayDiff == 0) {
      distanceLabel = '剩余0天';
    } else {
      distanceLabel = '超期${dayDiff.abs()}天';
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DueTimeBadge(
                dateLabel: dateLabel,
                timeLabel: timeLabel,
                highlightColor: statusColor,
                isCompleted: reminder.isCompleted,
                isOverdue: reminder.isOverdue,
                distanceLabel: distanceLabel,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            reminder.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  decoration: reminder.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: reminder.isCompleted
                                      ? const Color(0xFF7E8A85)
                                      : null,
                                ),
                          ),
                        ),
                        Checkbox(
                          value: reminder.isCompleted,
                          onChanged: (value) => controller.toggleCompletion(
                            reminder,
                            value ?? false,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.list_alt_rounded,
                          label: list?.name ?? '未分配',
                        ),
                        if (group != null)
                          _InfoChip(
                            icon: Icons.folder_open_rounded,
                            label: group.name,
                          ),
                        _InfoChip(
                          icon: Icons.flag_rounded,
                          label: statusLabel,
                          foreground: statusColor,
                          background: statusColor.withValues(alpha: 0.12),
                        ),
                        if (reminder.repeatRule != ReminderRepeatRule.none)
                          _InfoChip(
                            icon: Icons.repeat_rounded,
                            label: reminder.repeatRule.label,
                          ),
                      ],
                    ),
                    if (reminder.note != null && reminder.note!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        reminder.note!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6A7A74),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DueTimeBadge extends StatelessWidget {
  const _DueTimeBadge({
    required this.dateLabel,
    required this.timeLabel,
    required this.highlightColor,
    required this.isCompleted,
    required this.isOverdue,
    required this.distanceLabel,
  });

  final String dateLabel;
  final String timeLabel;
  final Color highlightColor;
  final bool isCompleted;
  final bool isOverdue;
  final String distanceLabel;

  @override
  Widget build(BuildContext context) {
    final baseColor = isOverdue
        ? const Color(0xFFFFE8E0)
        : isCompleted
        ? const Color(0xFFEEF4F0)
        : highlightColor.withValues(alpha: 0.15);
    final borderColor = isOverdue
        ? const Color(0xFFF0B7A3)
        : highlightColor.withValues(alpha: 0.35);

    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            dateLabel,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5F6F68)),
          ),
          const SizedBox(height: 4),
          Text(
            timeLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: isOverdue
                  ? const Color(0xFFB85C38)
                  : (isCompleted
                        ? const Color(0xFF7E8A85)
                        : const Color(0xFF163E36)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            distanceLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF5F6F68),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? const Color(0xFFF2F5F4);
    final fg = foreground ?? const Color(0xFF4B5C57);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.reminder,
    required this.controller,
    required this.onOpenReminder,
  });

  final ReminderItem reminder;
  final ReminderController controller;
  final VoidCallback onOpenReminder;

  @override
  Widget build(BuildContext context) {
    final list = controller.findList(reminder.listId);
    final isOverdue = reminder.isOverdue;
    final isCompleted = reminder.isCompleted;
    final baseTextColor = isCompleted ? const Color(0xFF9AA6A1) : null;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      decoration: isCompleted
          ? TextDecoration.lineThrough
          : TextDecoration.none,
      color: baseTextColor,
    );

    return Card(
      color: isOverdue
          ? const Color(0xFFFFF4EF)
          : (isCompleted ? const Color(0xFFF4F6F4) : null),
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
                              ? const Color(0xFFB85C38)
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
                  color: isOverdue
                      ? const Color(0xFFF0C8B9)
                      : const Color(0xFFD9E4DE),
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
                                      ? const Color(0xFF9AA6A1)
                                      : const Color(0xFF60716B),
                                ),
                          ),
                          if (isOverdue)
                            const _Pill(
                              label: '超时未完成',
                              color: Color(0xFFFBE0D6),
                              foreground: Color(0xFFB85C38),
                            ),
                          if (isCompleted)
                            const _Pill(
                              label: '已完成',
                              color: Color(0xFFE5EFE7),
                              foreground: Color(0xFF3E6A4D),
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
                  onChanged: (value) =>
                      controller.toggleCompletion(reminder, value ?? false),
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
  });

  final ReminderItem reminder;
  final ReminderController controller;
  final VoidCallback onOpenReminder;

  @override
  Widget build(BuildContext context) {
    final list = controller.findList(reminder.listId);
    final isOverdue = reminder.isOverdue;
    final isCompleted = reminder.isCompleted;
    final backgroundColor = isOverdue
        ? const Color(0xFFFFF4EF)
        : (isCompleted ? const Color(0xFFF4F6F4) : const Color(0xFFF8FBF9));
    final borderColor = isOverdue
        ? const Color(0xFFF0C8B9)
        : const Color(0xFFE0E6E3);
    final titleColor = isCompleted
        ? const Color(0xFF9AA6A1)
        : const Color(0xFF163E36);
    final subtitleColor = isCompleted
        ? const Color(0xFF9AA6A1)
        : const Color(0xFF60716B);
    final statusLabel = isCompleted
        ? '已完成'
        : isOverdue
        ? '超时未完成'
        : (list?.name ?? '未分类清单');

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpenReminder,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 68),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? const Color(0xFFFBE0D6)
                      : const Color(0xFFEAF2EE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  reminder.hasSpecificTime
                      ? DateFormat('HH:mm').format(reminder.dueAt)
                      : '全天',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isOverdue
                        ? const Color(0xFFB85C38)
                        : const Color(0xFF126A5A),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: subtitleColor),
                    ),
                    if (reminder.note?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        reminder.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: subtitleColor),
                      ),
                    ],
                  ],
                ),
              ),
              Checkbox(
                value: reminder.isCompleted,
                onChanged: (value) =>
                    controller.toggleCompletion(reminder, value ?? false),
              ),
            ],
          ),
        ),
      ),
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
    final intensity = switch (count) {
      0 => 0.0,
      1 => 0.18,
      2 => 0.28,
      3 => 0.4,
      _ => 0.55,
    };
    final fillColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF126A5A).withValues(alpha: intensity);
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isToday
        ? const Color(0xFF126A5A).withValues(alpha: 0.55)
        : Colors.transparent;
    final textColor = isSelected
        ? Colors.white
        : count > 0
        ? const Color(0xFF163E36)
        : const Color(0xFF5F6F68);

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.notifications_none_rounded, size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF60716B)),
            ),
          ],
        ),
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
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _MetricMini(
                                label: '全部提醒',
                                value: '${reminders.length}',
                              ),
                            ),
                            Expanded(
                              child: _MetricMini(
                                label: '待办',
                                value: '$pending',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _MetricMini(label: '今日', value: '$today'),
                            ),
                            Expanded(
                              child: _MetricMini(
                                label: '逾期',
                                value: '$overdue',
                              ),
                            ),
                            Expanded(
                              child: _MetricMini(
                                label: '已完成',
                                value: '$completed',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final lists = _sortedLists();
              final groups = _sortedGroups();
              return ListView(
                children: [
                  Text(
                    '任务清单 / 分组 / 标签',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '先用本地数据维护组织结构，后续接 API 时可以整体复用。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  _ManagerSection(
                    title: '任务清单',
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
                      onSubmit: (name) =>
                          widget.controller.createList(name, 0xFF126A5A),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ManagerSection(
                    title: '分组',
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
                      onSubmit: (name) =>
                          widget.controller.createTag(name, 0xFF6B5FB3),
                    ),
                  ),
                ],
              );
            },
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
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '请输入名称',
                  errorText: errorText,
                ),
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
                backgroundColor: const Color(0xFFB85C38),
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
  });

  final ReminderController controller;
  final DateTime initialSelectedDate;
  final DateTime initialFocusedDate;
  final void Function(ReminderItem reminder) onOpenReminder;

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
                            color: const Color(0xFF7A8A84),
                            fontWeight: FontWeight.w700,
                          ),
                      weekdayStyle: Theme.of(context).textTheme.bodySmall!
                          .copyWith(
                            color: const Color(0xFF7A8A84),
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
                    child: _TimelineTile(
                      reminder: item,
                      controller: widget.controller,
                      onOpenReminder: () => widget.onOpenReminder(item),
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
    required this.items,
    required this.emptyHint,
    required this.onAdd,
    this.reorderable = false,
    this.onReorder,
    this.isProcessing = false,
  });

  final String title;
  final List<_ManagerItem> items;
  final String emptyHint;
  final VoidCallback onAdd;
  final bool reorderable;
  final Future<void> Function(int oldIndex, int newIndex)? onReorder;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text(
                emptyHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF60716B),
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
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '编辑',
                        onPressed: item.onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: '删除',
                        onPressed: item.onDelete,
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
        return ListTile(
          key: ValueKey(item.id),
          contentPadding: EdgeInsets.zero,
          title: Text(item.label),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '编辑',
                onPressed: item.onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: item.onDelete,
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
