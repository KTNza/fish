import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._privateConstructor();
  static final NotificationService _instance =
      NotificationService._privateConstructor();
  factory NotificationService() => _instance;

  static const String _historyPreferencesKey = 'notificationHistory';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final List<Map<String, String>> _notificationHistory = [];

  List<Map<String, String>> get notificationHistory =>
      List.unmodifiable(_notificationHistory);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadHistory(prefs);

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
    );

    if (Platform.isAndroid) {
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestPermission();
    }
  }

  Future<void> _loadHistory(SharedPreferences prefs) async {
    final stored = prefs.getStringList(_historyPreferencesKey) ?? [];
    _notificationHistory.clear();
    for (final item in stored) {
      try {
        final data = jsonDecode(item) as Map<String, dynamic>;
        _notificationHistory
            .add(data.map((key, value) => MapEntry(key, value.toString())));
      } catch (_) {
        // Ignore malformed entries.
      }
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        _notificationHistory.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList(_historyPreferencesKey, stored);
  }

  Future<void> addHistory({
    required String title,
    required String body,
    required String time,
  }) async {
    _notificationHistory.insert(0, {
      'title': title,
      'message': body,
      'time': time,
    });
    await _saveHistory();
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'fish_scheduled_alerts_channel',
      'Fish Scheduled Alerts',
      channelDescription: 'Scheduled notifications for feeding and lights',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      ticker: 'Fish Scheduled Alert',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notificationsPlugin.schedule(
      id,
      title,
      body,
      scheduledDate,
      platformDetails,
      androidAllowWhileIdle: true,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'fish_alerts_channel',
      'Fish Alerts',
      channelDescription: 'แจ้งเตือนการให้อาหารและการควบคุมไฟ',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      ticker: 'Fish Alert',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notificationsPlugin.show(id, title, body, platformDetails);
  }
}
