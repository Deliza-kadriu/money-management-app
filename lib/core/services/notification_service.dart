import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _isInitialized = false;
  bool _isTimezoneInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(initializationSettings);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _initializeTimezone();
    _isInitialized = true;
  }

  Future<void> scheduleRecurringRuleReminder({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledFor,
  }) async {
    if (!_isInitialized) {
      return;
    }

    if (!scheduledFor.isAfter(DateTime.now())) {
      await _plugin.show(notificationId, title, body, _notificationDetails);
      return;
    }

    await _plugin.zonedSchedule(
      notificationId,
      title,
      body,
      tz.TZDateTime.from(scheduledFor, tz.local),
      _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancel(int notificationId) => _plugin.cancel(notificationId);

  Future<void> showRecurringDigest({
    required int autoCreatedCount,
    required int suggestedCount,
  }) async {
    if (!_isInitialized) {
      return;
    }

    if (autoCreatedCount <= 0 && suggestedCount <= 0) {
      return;
    }

    final List<String> parts = <String>[
      if (autoCreatedCount > 0) '$autoCreatedCount auto-created',
      if (suggestedCount > 0) '$suggestedCount ready to review',
    ];

    await _plugin.show(
      2001,
      'Recurring payments updated',
      parts.join(' • '),
      _notificationDetails,
    );
  }

  NotificationDetails get _notificationDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      'recurring_reminders',
      'Recurring Reminders',
      channelDescription: 'Reminders for recurring payments',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _initializeTimezone() async {
    if (_isTimezoneInitialized) {
      return;
    }

    tz_data.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    _isTimezoneInitialized = true;
  }
}
