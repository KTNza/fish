import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._privateConstructor();
  static final NotificationService _instance =
      NotificationService._privateConstructor();
  factory NotificationService() => _instance;

  static const String _historyPreferencesKey = 'notificationHistory';
  static const String _readCountPreferencesKey = 'notificationReadCount';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final List<Map<String, String>> _notificationHistory = [];
  int _readNotificationCount = 0;
  final ValueNotifier<bool> hasUnreadNotifications = ValueNotifier(false);

  List<Map<String, String>> get notificationHistory =>
      List.unmodifiable(_notificationHistory);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadHistory(prefs);

    // ⏰ เพิ่ม timezone init
    try {
      tzdata.initializeTimeZones();
      print('✅ Timezone initialized');
    } catch (e) {
      print('⚠️ Timezone init error: $e');
    }

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
      await androidImplementation?.requestNotificationsPermission();
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

    _readNotificationCount = prefs.getInt(_readCountPreferencesKey) ?? 0;
    if (_readNotificationCount > _notificationHistory.length) {
      _readNotificationCount = _notificationHistory.length;
    }
    hasUnreadNotifications.value =
        _notificationHistory.length > _readNotificationCount;
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        _notificationHistory.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList(_historyPreferencesKey, stored);
  }

  Future<void> _saveReadCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readCountPreferencesKey, _readNotificationCount);
  }

  void markNotificationsRead() {
    _readNotificationCount = _notificationHistory.length;
    hasUnreadNotifications.value = false;
    _saveReadCount();
  }

  bool _isDuplicateHistoryEntry(String title, String body, String time) {
    if (_notificationHistory.isEmpty) {
      return false;
    }
    final latest = _notificationHistory.first;
    return latest['title'] == title &&
        latest['message'] == body &&
        latest['time'] == time;
  }

  Future<void> addHistory({
    required String title,
    required String body,
    required String time,
  }) async {
    if (_isDuplicateHistoryEntry(title, body, time)) {
      return;
    }

    _notificationHistory.insert(0, {
      'title': title,
      'message': body,
      'time': time,
    });
    await _saveHistory();
    hasUnreadNotifications.value = true;
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

    final scheduledDateUTC = tz.TZDateTime.from(scheduledDate, tz.UTC);

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDateUTC,
      platformDetails,
      androidAllowWhileIdle: true,
      matchDateTimeComponents: matchDateTimeComponents,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
