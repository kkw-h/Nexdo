import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../domain/entities/reminder_models.dart';

class ReminderNotificationPermissionState {
  const ReminderNotificationPermissionState({
    required this.enabled,
    this.alertEnabled,
    this.badgeEnabled,
    this.soundEnabled,
    this.provisionalEnabled = false,
  });

  final bool enabled;
  final bool? alertEnabled;
  final bool? badgeEnabled;
  final bool? soundEnabled;
  final bool provisionalEnabled;
}

class ReminderNotificationService {
  ReminderNotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const macos = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: android,
      iOS: ios,
      macOS: macos,
    );

    await _plugin.initialize(settings);
    await requestPermissions();
  }

  Future<void> requestPermissions() async {
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<ReminderNotificationPermissionState> getPermissionState() async {
    if (Platform.isIOS) {
      final permissions = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return ReminderNotificationPermissionState(
        enabled: permissions?.isEnabled ?? false,
        alertEnabled: permissions?.isAlertEnabled,
        badgeEnabled: permissions?.isBadgeEnabled,
        soundEnabled: permissions?.isSoundEnabled,
        provisionalEnabled: permissions?.isProvisionalEnabled ?? false,
      );
    }

    if (Platform.isMacOS) {
      final permissions = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return ReminderNotificationPermissionState(
        enabled: permissions?.isEnabled ?? false,
        alertEnabled: permissions?.isAlertEnabled,
        badgeEnabled: permissions?.isBadgeEnabled,
        soundEnabled: permissions?.isSoundEnabled,
        provisionalEnabled: permissions?.isProvisionalEnabled ?? false,
      );
    }

    if (Platform.isAndroid) {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      return ReminderNotificationPermissionState(enabled: enabled ?? false);
    }

    return const ReminderNotificationPermissionState(enabled: false);
  }

  Future<int> pendingRequestCount() async {
    final requests = await _plugin.pendingNotificationRequests();
    return requests.length;
  }

  Future<void> clearPendingNotifications() async {
    await _plugin.cancelAllPendingNotifications();
  }

  Future<void> syncAll(Iterable<ReminderItem> reminders) async {
    await _plugin.cancelAll();
    for (final reminder in reminders) {
      await scheduleForReminder(reminder);
    }
  }

  Future<void> scheduleForReminder(ReminderItem reminder) async {
    final notificationId = _notificationId(reminder.id);
    await _plugin.cancel(notificationId);

    final remindBeforeMinutes = reminder.remindBeforeMinutes ?? 0;
    final scheduledAt = reminder.dueAt.subtract(
      Duration(minutes: remindBeforeMinutes),
    );

    if (!reminder.notificationEnabled ||
        reminder.isCompleted ||
        !reminder.hasSpecificTime ||
        scheduledAt.isBefore(DateTime.now()) ||
        (reminder.repeatEndAt != null &&
            reminder.dueAt.isAfter(reminder.repeatEndAt!))) {
      return;
    }

    await _plugin.zonedSchedule(
      notificationId,
      reminder.title,
      reminder.note?.isNotEmpty == true ? reminder.note : '提醒时间到了',
      tz.TZDateTime.from(scheduledAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          '提醒事项',
          channelDescription: '提醒事项本地通知',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: _matchDateTimeComponents(reminder),
    );
  }

  Future<void> cancelReminder(String reminderId) async {
    await _plugin.cancel(_notificationId(reminderId));
  }

  int _notificationId(String id) {
    return id.hashCode & 0x7fffffff;
  }

  DateTimeComponents? _matchDateTimeComponents(ReminderItem reminder) {
    if (reminder.repeatEndAt != null) {
      return null;
    }
    switch (reminder.repeatRule) {
      case ReminderRepeatRule.none:
        return null;
      case ReminderRepeatRule.daily:
        return DateTimeComponents.time;
      case ReminderRepeatRule.weekly:
        return DateTimeComponents.dayOfWeekAndTime;
      case ReminderRepeatRule.monthly:
        return DateTimeComponents.dayOfMonthAndTime;
      case ReminderRepeatRule.yearly:
        return DateTimeComponents.dateAndTime;
      case ReminderRepeatRule.workday:
      case ReminderRepeatRule.restday:
        return null;
    }
  }
}
