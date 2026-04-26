import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _isInitialized = false;

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
    _isInitialized = true;
  }

  Future<void> scheduleRecurringRuleReminder({
    required int notificationId,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      notificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'recurring_reminders',
          'Recurring Reminders',
          channelDescription: 'Reminders for recurring payments',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> cancel(int notificationId) => _plugin.cancel(notificationId);

  Future<void> showRecurringDigest({
    required int autoCreatedCount,
    required int suggestedCount,
  }) async {
    if (autoCreatedCount <= 0 && suggestedCount <= 0) {
      return;
    }

    final List<String> parts = <String>[
      if (autoCreatedCount > 0)
        '$autoCreatedCount auto-created',
      if (suggestedCount > 0)
        '$suggestedCount ready to review',
    ];

    await _plugin.show(
      2001,
      'Recurring payments updated',
      parts.join(' • '),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'recurring_reminders',
          'Recurring Reminders',
          channelDescription: 'Reminders for recurring payments',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
