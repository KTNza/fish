import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashbord.dart';
import 'Connect.dart';
import 'Notification.dart';
import 'notification_service.dart';
import 'mqtt_service.dart';

// ==========================================
// Design tokens
// ==========================================
class _C {
  static const navy      = Color(0xFF1A2340);
  static const teal      = Color(0xFF4DB6AC);
  static const tealLight = Color(0xFF80CBC4);
  static const bg        = Color(0xFFF0F4F8);
  static const white     = Colors.white;
  static const danger    = Color(0xFFE57373);
  static const warn      = Color(0xFFFFB74D);
  static const green     = Color(0xFF4DB6AC);
}

// ==========================================
// ตัวแปรเช็คการเปิดแอปครั้งแรก (Cold Start)
// ==========================================
bool _isAppJustStarted = true; // ✅ เอาคำว่า static ออกแล้ว

// ==========================================
// SetTimePage
// ==========================================
class SetTimePage extends StatefulWidget {
  const SetTimePage({super.key});

  @override
  State<SetTimePage> createState() => _SetTimePageState();
}

class _SetTimePageState extends State<SetTimePage> {
  int _selectedIndex = 1;

  int _feedingIntervalHours   = 4;
  int _feedingIntervalMinutes = 0;
  int _remainingSeconds       = 0;
  Timer? _countdownTimer;
  bool _isFeeding       = false;
  bool _isTimerRunning  = false;
  int? _countdownEndTimeMillis;

  static const int _feedNotificationId     = 1001;
  static const int _lightOnNotificationId  = 1002;
  static const int _lightOffNotificationId = 1003;

  int get _feedingIntervalSeconds =>
      _feedingIntervalHours * 3600 + _feedingIntervalMinutes * 60;

  void _normalizeInterval() {
    if (_feedingIntervalHours >= 24) {
      _feedingIntervalHours   = 24;
      _feedingIntervalMinutes = 0;
    }
    if (_feedingIntervalMinutes >= 60) _feedingIntervalMinutes = 59;
    if (_feedingIntervalMinutes < 0)   _feedingIntervalMinutes = 0;
    if (_feedingIntervalHours < 0)     _feedingIntervalHours   = 0;
    if (_feedingIntervalHours == 24 && _feedingIntervalMinutes > 0)
      _feedingIntervalMinutes = 0;
  }

  TimeOfDay _lightTime    = const TimeOfDay(hour: 6,  minute: 0);
  TimeOfDay _lightOffTime = const TimeOfDay(hour: 18, minute: 0);
  Timer? _lightTimer;
  bool _isLightOn = false;

  // ✅ ตัวแปรควบคุมการเปิด/ปิดระบบตั้งเวลาไฟอัตโนมัติ
  bool _isAutoLightEnabled = true;

  final List<Map<String, String>> _notifications = [];

  // ──────────────────────────────────────
  // Persistence / scheduling
  // ──────────────────────────────────────
  Future<void> _saveTimerState(int endTimeMillis) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feedingTimerRunning', true);
    await prefs.setInt('feedingEndTimeMillis', endTimeMillis);
    await prefs.setInt('feedingIntervalHours', _feedingIntervalHours);
    await prefs.setInt('feedingIntervalMinutes', _feedingIntervalMinutes);
  }

  Future<void> _saveIntervalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('feedingIntervalHours', _feedingIntervalHours);
    await prefs.setInt('feedingIntervalMinutes', _feedingIntervalMinutes);
  }

  Future<void> _scheduleFeedingNotification() async {
    await NotificationService().cancelNotification(_feedNotificationId);
    if (_isTimerRunning && _countdownEndTimeMillis != null) {
      final scheduledDate =
      DateTime.fromMillisecondsSinceEpoch(_countdownEndTimeMillis!);
      if (scheduledDate.isAfter(DateTime.now())) {
        await NotificationService().scheduleNotification(
          id: _feedNotificationId,
          title: 'ถึงเวลาให้อาหารปลาแล้ว',
          body:
          'ได้เวลาให้อาหารปลาเวลา ${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')} น.',
          scheduledDate: scheduledDate,
        );
      }
    }
  }

  Future<void> _scheduleLightNotifications() async {
    await NotificationService().cancelNotification(_lightOnNotificationId);
    await NotificationService().cancelNotification(_lightOffNotificationId);

    // ถ้าระบบไฟอัตโนมัติถูกปิดอยู่ ไม่ต้องตั้งแจ้งเตือน
    if (!_isAutoLightEnabled) return;

    final now = DateTime.now();
    DateTime nextOn = DateTime(now.year, now.month, now.day,
        _lightTime.hour, _lightTime.minute);
    if (!nextOn.isAfter(now)) nextOn = nextOn.add(const Duration(days: 1));

    DateTime nextOff = DateTime(now.year, now.month, now.day,
        _lightOffTime.hour, _lightOffTime.minute);
    if (!nextOff.isAfter(now)) nextOff = nextOff.add(const Duration(days: 1));

    await NotificationService().scheduleNotification(
      id: _lightOnNotificationId,
      title: 'เปิดไฟอัตโนมัติ',
      body:
      'ไฟตู้ปลาจะเปิดเวลา ${_lightTime.hour.toString().padLeft(2, '0')}:${_lightTime.minute.toString().padLeft(2, '0')} น.',
      scheduledDate: nextOn,
    );
    await NotificationService().scheduleNotification(
      id: _lightOffNotificationId,
      title: 'ปิดไฟอัตโนมัติ',
      body:
      'ไฟตู้ปลาจะปิดเวลา ${_lightOffTime.hour.toString().padLeft(2, '0')}:${_lightOffTime.minute.toString().padLeft(2, '0')} น.',
      scheduledDate: nextOff,
    );
  }

  Future<void> _clearTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feedingTimerRunning', false);
    await prefs.remove('feedingEndTimeMillis');
  }

  Future<void> _saveLightSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lightOnHour',    _lightTime.hour);
    await prefs.setInt('lightOnMinute',  _lightTime.minute);
    await prefs.setInt('lightOffHour',   _lightOffTime.hour);
    await prefs.setInt('lightOffMinute', _lightOffTime.minute);
    await prefs.setBool('lightIsOn', _isLightOn);
    await prefs.setBool('isAutoLightEnabled', _isAutoLightEnabled);
  }

  bool _computeLightOn(TimeOfDay now, TimeOfDay onTime, TimeOfDay offTime) {
    final nowM = now.hour * 60 + now.minute;
    final onM  = onTime.hour * 60 + onTime.minute;
    final offM = offTime.hour * 60 + offTime.minute;
    if (onM <= offM) return nowM >= onM && nowM < offM;
    return nowM >= onM || nowM < offM;
  }

  // ──────────────────────────────────────
  // Timer logic
  // ──────────────────────────────────────
  void _startCountdown({int? startSeconds}) {
    final intervalSeconds = startSeconds ??
        (_feedingIntervalSeconds <= 0 ? 60 : _feedingIntervalSeconds);
    final endTimeMillis = DateTime.now()
        .add(Duration(seconds: intervalSeconds))
        .millisecondsSinceEpoch;
    _countdownTimer?.cancel();
    setState(() {
      _remainingSeconds       = intervalSeconds;
      _isFeeding              = false;
      _isTimerRunning         = true;
      _countdownEndTimeMillis = endTimeMillis;
    });
    _saveTimerState(endTimeMillis);
    _saveIntervalSettings();
    _scheduleFeedingNotification();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _countdownTimer?.cancel();
        _triggerFeeding();
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _remainingSeconds =
      _feedingIntervalSeconds <= 0 ? 60 : _feedingIntervalSeconds;
      _isFeeding              = false;
      _isTimerRunning         = false;
      _countdownEndTimeMillis = null;
    });
    _clearTimerState();
    NotificationService().cancelNotification(_feedNotificationId);
  }

  void _triggerFeeding({bool restartCountdown = true}) {
    final now        = TimeOfDay.now();
    final timeString =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _isFeeding = true;
      _notifications.insert(0, {
        'title':   'ถึงเวลาให้อาหาร',
        'message': 'ระบบกำลังให้อาหารปลาอัตโนมัติ ($timeString)',
        'time':    timeString,
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('🐟 กำลังให้อาหารปลา...'),
      backgroundColor: _C.navy,
      duration: Duration(seconds: 2),
    ));

    NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'ได้เวลาให้อาหารปลา',
      body: 'ระบบได้ทำการให้อาหารปลาเรียบร้อยแล้ว ($timeString)',
    );
    NotificationService().addHistory(
      title: 'ได้เวลาให้อาหารปลา',
      body: 'ระบบได้ทำการให้อาหารปลาเรียบร้อยแล้ว ($timeString)',
      time: timeString,
    );
    _publishControlCommand(MqttService.topicControlFeed, 'feed');

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _isFeeding = false);
      if (restartCountdown && _isTimerRunning) _startCountdown();
    });
  }

  String _formatTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')} ชม. ${m.toString().padLeft(2, '0')} นาที ${s.toString().padLeft(2, '0')} วิ.';
  }

  void _sendTimeSettingsToDevice() {
    final settings = {
      'feedingIntervalHours':   _feedingIntervalHours,
      'feedingIntervalMinutes': _feedingIntervalMinutes,
      'lightOnTime':
      '${_lightTime.hour.toString().padLeft(2, '0')}:${_lightTime.minute.toString().padLeft(2, '0')}',
      'lightOffTime':
      '${_lightOffTime.hour.toString().padLeft(2, '0')}:${_lightOffTime.minute.toString().padLeft(2, '0')}',
      'isAutoLightEnabled': _isAutoLightEnabled,
    };
    MqttService().publishJson(MqttService.topicControlSettings, settings);
  }

  void _publishControlCommand(String topic, String payload) {
    MqttService().publish(topic, payload);
  }

  void _startLightTimer() {
    _lightTimer?.cancel();
    _lightTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      // ✅ ถ้าระบบไฟอัตโนมัติถูกปิดอยู่ ให้ข้ามการทำงานไปเลย
      if (!_isAutoLightEnabled) return;

      final now        = TimeOfDay.now();
      final onM        = _lightTime.hour * 60 + _lightTime.minute;
      final offM       = _lightOffTime.hour * 60 + _lightOffTime.minute;
      final nowM       = now.hour * 60 + now.minute;
      final timeString =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      if (nowM == onM && !_isLightOn) {
        setState(() {
          _isLightOn = true;
          _notifications.insert(0, {
            'title':   'ไฟเปิดอัตโนมัติ',
            'message': 'ระบบเปิดไฟเวลา $timeString น.',
            'time':    timeString,
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('💡 ระบบเปิดไฟตามเวลาที่ตั้งไว้'),
          backgroundColor: _C.navy,
          duration: Duration(seconds: 2),
        ));
        NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'ไฟเปิดอัตโนมัติ',
          body: 'ระบบเปิดไฟเวลา $timeString น.',
        );
        NotificationService()
            .addHistory(title: 'ไฟเปิดอัตโนมัติ', body: 'ระบบเปิดไฟเวลา $timeString น.', time: timeString);
        _publishControlCommand(MqttService.topicControlLight, 'light_on');
      }

      if (nowM == offM && _isLightOn) {
        setState(() {
          _isLightOn = false;
          _notifications.insert(0, {
            'title':   'ไฟปิดอัตโนมัติ',
            'message': 'ระบบปิดไฟเวลา $timeString น.',
            'time':    timeString,
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('💡 ระบบปิดไฟตามเวลาที่ตั้งไว้'),
          backgroundColor: _C.navy,
          duration: Duration(seconds: 2),
        ));
        NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'ไฟปิดอัตโนมัติ',
          body: 'ระบบปิดไฟเวลา $timeString น.',
        );
        NotificationService()
            .addHistory(title: 'ไฟปิดอัตโนมัติ', body: 'ระบบปิดไฟเวลา $timeString น.', time: timeString);
        _publishControlCommand(MqttService.topicControlLight, 'light_off');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSavedState();
      _sendTimeSettingsToDevice();
      _startLightTimer();
      _scheduleLightNotifications();
    });
  }

  Future<void> _loadSavedState() async {
    final prefs           = await SharedPreferences.getInstance();
    final savedHours      = prefs.getInt('feedingIntervalHours');
    final savedMinutes    = prefs.getInt('feedingIntervalMinutes');
    final running         = prefs.getBool('feedingTimerRunning') ?? false;
    final savedEndMillis  = prefs.getInt('feedingEndTimeMillis');
    final savedOnHour     = prefs.getInt('lightOnHour');
    final savedOnMinute   = prefs.getInt('lightOnMinute');
    final savedOffHour    = prefs.getInt('lightOffHour');
    final savedOffMinute  = prefs.getInt('lightOffMinute');
    final savedAutoLight  = prefs.getBool('isAutoLightEnabled') ?? true;

    // โหลดสถานะไฟเดิมที่เคยเซฟไว้
    bool savedLightIsOn = prefs.getBool('lightIsOn') ?? false;

    setState(() {
      if (savedHours   != null) _feedingIntervalHours   = savedHours;
      if (savedMinutes != null) _feedingIntervalMinutes = savedMinutes;
      if (savedOnHour  != null && savedOnMinute  != null)
        _lightTime    = TimeOfDay(hour: savedOnHour,  minute: savedOnMinute);
      if (savedOffHour != null && savedOffMinute != null)
        _lightOffTime = TimeOfDay(hour: savedOffHour, minute: savedOffMinute);

      _isAutoLightEnabled = savedAutoLight;
      _isTimerRunning         = running;
      _countdownEndTimeMillis = savedEndMillis;
      _notifications
        ..clear()
        ..addAll(NotificationService().notificationHistory);
    });

    // ✅ ถ้าเปิดแอปครั้งแรก ให้บังคับปิดไฟ (Cold Start)
    if (_isAppJustStarted) {
      setState(() {
        _isLightOn = false;
        _isAppJustStarted = false; // ปิดสถานะเปิดแอปครั้งแรก
      });
      _saveLightSettings(); // บันทึกทับค่าเก่า
    } else {
      // ✅ ถ้าสลับหน้าไปมา ให้ดึงค่าที่แอปจำไว้ล่าสุด
      setState(() {
        _isLightOn = savedLightIsOn;
      });
    }

    _publishControlCommand(
        MqttService.topicControlLight, _isLightOn ? 'light_on' : 'light_off');

    if (_isTimerRunning && _countdownEndTimeMillis != null) {
      final endTime    = DateTime.fromMillisecondsSinceEpoch(_countdownEndTimeMillis!);
      final secondsLeft = endTime.difference(DateTime.now()).inSeconds;
      if (secondsLeft > 0) {
        _startCountdown(startSeconds: secondsLeft);
      } else {
        _triggerFeeding();
      }
    } else {
      setState(() {
        _remainingSeconds =
        _feedingIntervalSeconds <= 0 ? 60 : _feedingIntervalSeconds;
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _lightTimer?.cancel();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      ).then((_) {
        if (mounted) setState(() => _selectedIndex = 1);
      });
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ConnectPage()),
      ).then((_) {
        if (mounted) setState(() => _selectedIndex = 1);
      });
    }
  }

  // ──────────────────────────────────────
  // Bottom sheet pickers
  // ──────────────────────────────────────
  void _showTimePicker(BuildContext context, TimeOfDay initialTime,
      Function(TimeOfDay) onTimeSelected) {
    int selectedHour   = initialTime.hour;
    int selectedMinute = initialTime.minute;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: 450,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: _C.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('เลือกเวลา',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: _C.navy)),
            const SizedBox(height: 20),
            _WheelRow(
              leftCount: 24,
              rightCount: 60,
              leftInitial: initialTime.hour,
              rightInitial: initialTime.minute,
              leftLabel: 'ชั่วโมง',
              rightLabel: 'นาที',
              onLeftChanged:  (i) => setModal(() => selectedHour   = i),
              onRightChanged: (i) => setModal(() => selectedMinute = i),
            ),
            const SizedBox(height: 24),
            _ConfirmButton(onPressed: () {
              onTimeSelected(TimeOfDay(hour: selectedHour, minute: selectedMinute));
              Navigator.pop(ctx);
            }),
          ]),
        ),
      ),
    );
  }

  void _showIntervalPicker(BuildContext context, int initialHours,
      int initialMinutes, Function(int, int) onIntervalSelected) {
    int selectedHour   = initialHours;
    int selectedMinute = initialMinutes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: 450,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: _C.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('ตั้งรอบการให้อาหาร',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: _C.navy)),
            const SizedBox(height: 20),
            _WheelRow(
              leftCount: 25,
              rightCount: 60,
              leftInitial: initialHours,
              rightInitial: initialMinutes,
              leftLabel: 'ชั่วโมง',
              rightLabel: 'นาที',
              onLeftChanged:  (i) => setModal(() => selectedHour   = i),
              onRightChanged: (i) => setModal(() => selectedMinute = i),
            ),
            const SizedBox(height: 24),
            _ConfirmButton(onPressed: () {
              onIntervalSelected(selectedHour, selectedMinute);
              Navigator.pop(ctx);
            }),
          ]),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _C.bg,
        body: SafeArea(
          child: Column(children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(children: [
                  _buildCountdownCard(),
                  const SizedBox(height: 16),

                  // ✅ เพิ่มสวิตช์ควบคุมระบบไฟอัตโนมัติ
                  _buildAutoLightToggleCard(),
                  const SizedBox(height: 16),

                  // ซ่อนช่องตั้งเวลาถ้าผู้ใช้ปิดระบบอัตโนมัติ
                  if (_isAutoLightEnabled) ...[
                    _buildLightCard(
                      title: 'เวลาเปิดไฟ (อัตโนมัติ)',
                      time: _lightTime,
                      icon: Icons.wb_sunny_rounded,
                      accentColor: const Color(0xFFFFB74D),
                      onEdit: () => _showTimePicker(context, _lightTime, (t) {
                        setState(() {
                          _lightTime = t;
                        });
                        _sendTimeSettingsToDevice();
                        _saveLightSettings();
                        _scheduleLightNotifications();
                        _startLightTimer();
                      }),
                    ),
                    const SizedBox(height: 16),
                    _buildLightCard(
                      title: 'เวลาปิดไฟ (อัตโนมัติ)',
                      time: _lightOffTime,
                      icon: Icons.nights_stay_rounded,
                      accentColor: const Color(0xFF9575CD),
                      onEdit: () => _showTimePicker(context, _lightOffTime, (t) {
                        setState(() {
                          _lightOffTime = t;
                        });
                        _sendTimeSettingsToDevice();
                        _saveLightSettings();
                        _scheduleLightNotifications();
                        _startLightTimer();
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _buildManualLightCard(),
                ]),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 4),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ตารางเวลา', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800,
            color: _C.navy, letterSpacing: -0.5,
          )),
          const Text('ตั้งเวลาให้อาหารและควบคุมแสงสว่าง', style: TextStyle(
            fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w500,
          )),
        ]),
        const Spacer(),
        ValueListenableBuilder<bool>(
          valueListenable: NotificationService().hasUnreadNotifications,
          builder: (context, hasUnread, _) => GestureDetector(
            onTap: () {
              NotificationService().markNotificationsRead();
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => NotificationPage(notifications: _notifications),
              ));
            },
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _C.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 10, offset: const Offset(0, 4),
                )],
              ),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.notifications_none_rounded,
                    color: _C.navy, size: 22),
                if (hasUnread)
                  Positioned(
                    right: 9, top: 9,
                    child: Container(width: 7, height: 7,
                        decoration: const BoxDecoration(
                            color: Color(0xFFFF5252), shape: BoxShape.circle)),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _buildCountdownCard() {
    final accent = _C.teal;
    return _StyledCard(
      accentColor: accent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // title row
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.restaurant_rounded,
                  color: _C.teal, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('ตั้งเวลาให้อาหาร', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: _C.navy,
            )),
          ]),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isTimerRunning
                  ? _C.teal.withOpacity(0.12)
                  : Colors.black.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isTimerRunning ? 'กำลังทำงาน' : 'หยุดทำงาน',
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: _isTimerRunning ? const Color(0xFF2E7D72) : Colors.black38,
              ),
            ),
          ),
        ]),

        const SizedBox(height: 16),

        // countdown display
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: _isFeeding ? const Color(0xFF4DB6AC) : _C.navy,
          ),
          child: _isFeeding
              ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle_outline_rounded,
                color: Colors.white, size: 36),
            SizedBox(height: 8),
            Text('🐟 กำลังให้อาหาร...', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white,
                    fontSize: 20, fontWeight: FontWeight.w700)),
          ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('ให้อาหารครั้งต่อไปในอีก',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),

            // ✅ นำ FittedBox มาครอบทับตัวหนังสือไว้ ป้องกันตกบรรทัด
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatTime(_remainingSeconds > 0
                    ? _remainingSeconds
                    : (_feedingIntervalSeconds <= 0 ? 60 : _feedingIntervalSeconds)),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              // ✅ ใช้ตัวย่อ ชม.
              'รอบปกติ: ทุกๆ $_feedingIntervalHours ชม. $_feedingIntervalMinutes นาที',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ]),
        ),

        const SizedBox(height: 16),

        _buildIntervalRow(),

        const SizedBox(height: 16),

        // control buttons
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ActionButton(
            label: 'เริ่ม', icon: Icons.play_arrow_rounded,
            color: const Color(0xFF4DB6AC),
            onTap: _startCountdown,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'หยุด', icon: Icons.stop_rounded,
            color: _C.danger,
            onTap: _stopCountdown,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'ให้อาหารทันที', icon: Icons.restaurant_rounded,
            color: _C.navy,
            onTap: () => _triggerFeeding(restartCountdown: false),
          ),
        ]),
      ]),
    );
  }

  Widget _buildIntervalRow() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ตั้งรอบการให้อาหาร',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: Colors.black.withOpacity(0.5))),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _IntervalStepper(
          label: 'ชม.',
          value: _feedingIntervalHours,
          onDecrement: () {
            if (_feedingIntervalHours > 0) {
              setState(() { _feedingIntervalHours--; _normalizeInterval(); });
              _stopCountdown(); _saveIntervalSettings(); _sendTimeSettingsToDevice();
            }
          },
          onIncrement: () {
            if (_feedingIntervalHours < 24) {
              setState(() { _feedingIntervalHours++; _normalizeInterval(); });
              _stopCountdown(); _saveIntervalSettings(); _sendTimeSettingsToDevice();
            }
          },
          onTap: () => _showIntervalPicker(
            context, _feedingIntervalHours, _feedingIntervalMinutes,
                (h, m) {
              setState(() {
                _feedingIntervalHours   = h;
                _feedingIntervalMinutes = m;
                _normalizeInterval();
                if (_feedingIntervalSeconds <= 0) _feedingIntervalMinutes = 1;
              });
              _stopCountdown(); _saveIntervalSettings(); _sendTimeSettingsToDevice();
            },
          ),
        ),
        const SizedBox(width: 16),
        _IntervalStepper(
          label: 'นาที',
          value: _feedingIntervalMinutes,
          onDecrement: () {
            if (_feedingIntervalMinutes > 0) {
              setState(() {
                _feedingIntervalMinutes--;
                if (_feedingIntervalSeconds <= 0) _feedingIntervalMinutes = 1;
              });
              _stopCountdown(); _saveIntervalSettings(); _sendTimeSettingsToDevice();
            }
          },
          onIncrement: () {
            if (_feedingIntervalMinutes < 59 && _feedingIntervalHours < 24) {
              setState(() { _feedingIntervalMinutes++; _normalizeInterval(); });
              _stopCountdown(); _saveIntervalSettings(); _sendTimeSettingsToDevice();
            }
          },
          onTap: () => _showIntervalPicker(
            context, _feedingIntervalHours, _feedingIntervalMinutes,
                (h, m) {
              setState(() {
                _feedingIntervalHours   = h;
                _feedingIntervalMinutes = m;
                _normalizeInterval();
                if (_feedingIntervalSeconds <= 0) _feedingIntervalMinutes = 1;
              });
              _stopCountdown(); _saveIntervalSettings(); _sendTimeSettingsToDevice();
            },
          ),
        ),
      ]),
    ]);
  }

  // ✅ การ์ดสำหรับเปิด-ปิดระบบตั้งเวลาอัตโนมัติ
  Widget _buildAutoLightToggleCard() {
    final accent = _isAutoLightEnabled ? _C.teal : Colors.black26;
    return _StyledCard(
      accentColor: accent,
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.access_time_rounded,
            color: accent, size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ตั้งเวลาไฟอัตโนมัติ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: _C.navy)),
            Text(_isAutoLightEnabled ? 'เปิดใช้งานอยู่' : 'ปิดใช้งาน',
                style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6))),
          ]),
        ),
        Switch(
          value: _isAutoLightEnabled,
          onChanged: (value) {
            setState(() => _isAutoLightEnabled = value);
            _saveLightSettings();
            _scheduleLightNotifications();
            if (value) {
              _startLightTimer();
            } else {
              _lightTimer?.cancel();
            }
          },
          activeColor: _C.teal,
          activeTrackColor: _C.teal.withOpacity(0.3),
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Colors.grey.withOpacity(0.3),
        ),
      ]),
    );
  }

  Widget _buildLightCard({
    required String title,
    required TimeOfDay time,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onEdit,
  }) {
    return _StyledCard(
      accentColor: accentColor,
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accentColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.45))),
            const SizedBox(height: 2),
            Text(time.format(context),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w300,
                    color: _C.navy, letterSpacing: -0.5)),
          ]),
        ),
        GestureDetector(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('แก้ไข',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: accentColor)),
          ),
        ),
      ]),
    );
  }

  Widget _buildManualLightCard() {
    final accent = _isLightOn ? const Color(0xFFFFB74D) : Colors.black26;
    return _StyledCard(
      accentColor: _isLightOn ? const Color(0xFFFFB74D) : const Color(0xFF90A4AE),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _isLightOn ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
            color: accent, size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('เปิด-ปิดไฟด้วยตัวเอง',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: _C.navy)),
            Text(_isLightOn ? 'ไฟกำลังเปิดอยู่' : 'ไฟกำลังปิดอยู่',
                style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6))),
            const SizedBox(height: 2),
            Text(
                _isAutoLightEnabled
                    ? 'ระบบอัตโนมัติจะยังทำงานต่อตามเวลาที่ตั้งไว้'
                    : 'ควบคุมแบบแมนนวล 100%',
                style: TextStyle(fontSize: 9, color: Colors.black.withOpacity(0.4))),
          ]),
        ),
        Switch(
          value: _isLightOn,
          onChanged: (value) {
            setState(() => _isLightOn = value);
            _saveLightSettings();
            _publishControlCommand(MqttService.topicControlLight,
                value ? 'light_on' : 'light_off');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(value ? '💡 เปิดไฟด้วยตัวเองแล้ว' : '💡 ปิดไฟด้วยตัวเองแล้ว'),
              backgroundColor: _C.navy,
              duration: const Duration(seconds: 1),
            ));
          },
          activeColor: const Color(0xFFFFB74D),
          activeTrackColor: const Color(0xFFFFB74D).withOpacity(0.3),
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Colors.grey.withOpacity(0.3),
        ),
      ]),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: _C.navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_rounded,     label: 'หน้าหลัก', selected: _selectedIndex == 0, onTap: () => _onNavTap(0)),
              _NavItem(icon: Icons.timer_rounded,    label: 'ตั้งเวลา',  selected: _selectedIndex == 1, onTap: () => _onNavTap(1)),
              _NavItem(icon: Icons.wifi_rounded,     label: 'ระบบ Wi-Fi',selected: _selectedIndex == 2, onTap: () => _onNavTap(2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// Shared sub-widgets
// ==========================================

class _StyledCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  const _StyledCard({required this.child, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: accentColor.withOpacity(0.22), width: 1.5),
      ),
      child: child,
    );
  }
}

class _IntervalStepper extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onTap;
  const _IntervalStepper({
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: onDecrement,
          child: const Icon(Icons.remove_rounded, size: 18, color: _C.navy),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 28,
            child: Column(children: [
              Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w700, color: _C.navy)),
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.black38)),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onIncrement,
          child: const Icon(Icons.add_rounded, size: 18, color: _C.navy),
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label, required this.icon,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ConfirmButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: const Text('ยืนยัน',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _WheelRow extends StatelessWidget {
  final int leftCount, rightCount;
  final int leftInitial, rightInitial;
  final String leftLabel, rightLabel;
  final ValueChanged<int> onLeftChanged, onRightChanged;
  const _WheelRow({
    required this.leftCount,  required this.rightCount,
    required this.leftInitial, required this.rightInitial,
    required this.leftLabel,  required this.rightLabel,
    required this.onLeftChanged, required this.onRightChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _wheel(leftCount, leftInitial, leftLabel, onLeftChanged),
      const SizedBox(width: 32),
      _wheel(rightCount, rightInitial, rightLabel, onRightChanged),
    ]);
  }

  Widget _wheel(int count, int initial, String label,
      ValueChanged<int> onChange) {
    return Column(children: [
      Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: _C.navy)),
      const SizedBox(height: 8),
      SizedBox(
        width: 72, height: 150,
        child: ListWheelScrollView.useDelegate(
          itemExtent: 48,
          controller: FixedExtentScrollController(initialItem: initial),
          onSelectedItemChanged: onChange,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count,
            builder: (ctx, i) => Center(
              child: Text(
                i.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 22,
                  color: i == initial ? _C.navy : Colors.black38,
                  fontWeight:
                  i == initial ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
            horizontal: selected ? 16 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Icon(icon,
              color: selected ? Colors.white : Colors.white38, size: 22),
          if (selected) ...[
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(
                color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}