import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../application/reminder_notification_service.dart';
import 'reminder_controller.dart';

class ReminderNotificationSettingsPage extends StatefulWidget {
  const ReminderNotificationSettingsPage({
    super.key,
    required this.controller,
    required this.notificationService,
  });

  final ReminderController controller;
  final ReminderNotificationService notificationService;

  @override
  State<ReminderNotificationSettingsPage> createState() =>
      _ReminderNotificationSettingsPageState();
}

class _ReminderNotificationSettingsPageState
    extends State<ReminderNotificationSettingsPage> {
  ReminderNotificationPermissionState? _permissionState;
  int? _pendingCount;
  bool _loading = true;
  bool _requestingPermission = false;
  bool _syncingNotifications = false;
  bool _clearingNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
    });
    try {
      final permissionState = await widget.notificationService
          .getPermissionState();
      final pendingCount = await widget.notificationService
          .pendingRequestCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionState = permissionState;
        _pendingCount = pendingCount;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      _showMessage('读取通知状态失败，请稍后重试。');
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _requestingPermission = true;
    });
    try {
      await widget.notificationService.requestPermissions();
      await _loadStatus();
      _showMessage(
        (_permissionState?.enabled ?? false)
            ? '通知权限状态已更新。'
            : '当前仍未开启通知，请到系统设置中允许 Nexdo 发送通知。',
      );
    } catch (_) {
      _showMessage('请求通知权限失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _requestingPermission = false;
        });
      }
    }
  }

  Future<void> _resyncLocalNotifications() async {
    setState(() {
      _syncingNotifications = true;
    });
    try {
      await widget.notificationService.syncAll(widget.controller.reminders);
      await _loadStatus();
      _showMessage('本地提醒已重新生成。');
    } catch (_) {
      _showMessage('重新生成本地提醒失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _syncingNotifications = false;
        });
      }
    }
  }

  Future<void> _clearPendingNotifications() async {
    setState(() {
      _clearingNotifications = true;
    });
    try {
      await widget.notificationService.clearPendingNotifications();
      await _loadStatus();
      _showMessage('待发送的本地提醒已清空。');
    } catch (_) {
      _showMessage('清空本地提醒失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _clearingNotifications = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final permissionState = _permissionState;
    final notificationEnabledCount = widget.controller.reminders
        .where((item) => item.notificationEnabled)
        .length;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('通知与提醒设置'),
        backgroundColor: palette.background,
        foregroundColor: palette.onSurface,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStatus,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _SettingsSectionCard(
                title: '通知权限',
                child: _loading
                    ? const _SettingsLoadingBlock()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PermissionBanner(
                            enabled: permissionState?.enabled ?? false,
                            provisional:
                                permissionState?.provisionalEnabled ?? false,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _StatusChip(
                                label: '提醒弹窗',
                                enabled: permissionState?.alertEnabled ?? false,
                              ),
                              _StatusChip(
                                label: '声音',
                                enabled: permissionState?.soundEnabled ?? false,
                              ),
                              _StatusChip(
                                label: '角标',
                                enabled: permissionState?.badgeEnabled ?? false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '如果此前拒绝过权限，请到系统设置中为 Nexdo 打开通知权限。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: palette.textMuted,
                                  height: 1.5,
                                ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _requestingPermission
                                  ? null
                                  : _requestPermissions,
                              style: FilledButton.styleFrom(
                                backgroundColor: palette.primary,
                                foregroundColor: palette.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                _requestingPermission ? '请求中...' : '重新请求权限',
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _SettingsSectionCard(
                title: '本地提醒状态',
                child: _loading
                    ? const _SettingsLoadingBlock()
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _MetricTile(
                                  label: '已开启通知的提醒',
                                  value: '$notificationEnabledCount',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricTile(
                                  label: '待发送本地提醒',
                                  value: '${_pendingCount ?? 0}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const _InfoRow(
                            title: '提醒生成规则',
                            value: '仅为开启通知且带具体时间的提醒生成本地通知',
                          ),
                          const SizedBox(height: 10),
                          const _InfoRow(
                            title: '提前提醒时间',
                            value: '在新建或编辑提醒页面单独设置',
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _syncingNotifications
                                      ? null
                                      : _resyncLocalNotifications,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: palette.onSurface,
                                    side: BorderSide(color: palette.outline),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    _syncingNotifications
                                        ? '同步中...'
                                        : '重新生成本地提醒',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _clearingNotifications
                                      ? null
                                      : _clearPendingNotifications,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: palette.onSurface,
                                    side: BorderSide(color: palette.outline),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    _clearingNotifications
                                        ? '清空中...'
                                        : '清空待发送提醒',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              const _SettingsSectionCard(
                title: '使用说明',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(title: '提醒开关', value: '每条提醒是否通知，在新建/编辑提醒页面单独控制'),
                    SizedBox(height: 10),
                    _InfoRow(
                      title: '系统限制',
                      value: '关闭系统通知、静音模式或专注模式，都可能影响提醒送达',
                    ),
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

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A111827),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: palette.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.enabled, required this.provisional});

  final bool enabled;
  final bool provisional;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final backgroundColor = enabled
        ? palette.primaryContainer
        : palette.surfaceContainerLow;
    final foregroundColor = enabled ? palette.secondary : palette.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            enabled
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            color: foregroundColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              enabled ? (provisional ? '通知权限已开启（临时授权）' : '通知权限已开启') : '通知权限未开启',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: enabled ? palette.primaryContainer : palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label · ${enabled ? '已开' : '未开'}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: enabled ? palette.secondary : palette.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.textMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _SettingsLoadingBlock extends StatelessWidget {
  const _SettingsLoadingBlock();

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          width: double.infinity,
          height: 18,
          margin: EdgeInsets.only(bottom: index == 2 ? 0 : 10),
          decoration: BoxDecoration(
            color: palette.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
