import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashbord.dart';
import 'Connect.dart';
import 'Notification.dart';
import 'notification_service.dart';

// หน้าจอตั้งเวลา
class SetTimePage extends StatefulWidget {
  const SetTimePage({super.key});

  @override
  State<SetTimePage> createState() => _SetTimePageState();
}

class _SetTimePageState extends State<SetTimePage> {
  int _selectedIndex = 1; // เลือก ปุ่มกลาง

  int _feedingIntervalHours = 4;
  int _feedingIntervalMinutes = 0;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  bool _isFeeding = false;
  bool _isTimerRunning = false;
  int? _countdownEndTimeMillis;

  static const int _feedNotificationId = 1001;
  static const int _lightOnNotificationId = 1002;
  static const int _lightOffNotificationId = 1003;

  int get _feedingIntervalSeconds =>
      _feedingIntervalHours * 3600 + _feedingIntervalMinutes * 60;

  void _normalizeInterval() {
    if (_feedingIntervalHours >= 24) {
      _feedingIntervalHours = 24;
      _feedingIntervalMinutes = 0;
    }
    if (_feedingIntervalMinutes >= 60) {
      _feedingIntervalMinutes = 59;
    }
    if (_feedingIntervalMinutes < 0) {
      _feedingIntervalMinutes = 0;
    }
    if (_feedingIntervalHours < 0) {
      _feedingIntervalHours = 0;
    }
    if (_feedingIntervalHours == 24 && _feedingIntervalMinutes > 0) {
      _feedingIntervalMinutes = 0;
    }
  }

  // เวลาไฟ
  TimeOfDay _lightTime = const TimeOfDay(hour: 06, minute: 00);
  TimeOfDay _lightOffTime = const TimeOfDay(hour: 18, minute: 00);
  Timer? _lightTimer;
  bool _isLightOn = false;

  // สถานะแจ้งเตือน
  bool _hasNotification = false;

  // รายการแจ้งเตือน
  final List<Map<String, String>> _notifications = [];

  // ฟังก์ชันเริ่มนับถอยหลัง
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
          title: 'Feed Fish',
          body:
              'Time to feed the fish at ${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}.',
          scheduledDate: scheduledDate,
        );
      }
    }
  }

  Future<void> _scheduleLightNotifications() async {
    await NotificationService().cancelNotification(_lightOnNotificationId);
    await NotificationService().cancelNotification(_lightOffNotificationId);

    final now = DateTime.now();
    DateTime nextOn = DateTime(
      now.year,
      now.month,
      now.day,
      _lightTime.hour,
      _lightTime.minute,
    );
    if (!nextOn.isAfter(now)) {
      nextOn = nextOn.add(const Duration(days: 1));
    }

    DateTime nextOff = DateTime(
      now.year,
      now.month,
      now.day,
      _lightOffTime.hour,
      _lightOffTime.minute,
    );
    if (!nextOff.isAfter(now)) {
      nextOff = nextOff.add(const Duration(days: 1));
    }

    await NotificationService().scheduleNotification(
      id: _lightOnNotificationId,
      title: 'Lights On',
      body:
          'Lights will turn on at ${_lightTime.hour.toString().padLeft(2, '0')}:${_lightTime.minute.toString().padLeft(2, '0')}.',
      scheduledDate: nextOn,
    );

    await NotificationService().scheduleNotification(
      id: _lightOffNotificationId,
      title: 'Lights Off',
      body:
          'Lights will turn off at ${_lightOffTime.hour.toString().padLeft(2, '0')}:${_lightOffTime.minute.toString().padLeft(2, '0')}.',
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
    await prefs.setInt('lightOnHour', _lightTime.hour);
    await prefs.setInt('lightOnMinute', _lightTime.minute);
    await prefs.setInt('lightOffHour', _lightOffTime.hour);
    await prefs.setInt('lightOffMinute', _lightOffTime.minute);
    await prefs.setBool('lightIsOn', _isLightOn);
  }

  bool _computeLightOn(TimeOfDay now, TimeOfDay onTime, TimeOfDay offTime) {
    final nowMinutes = now.hour * 60 + now.minute;
    final onMinutes = onTime.hour * 60 + onTime.minute;
    final offMinutes = offTime.hour * 60 + offTime.minute;

    if (onMinutes <= offMinutes) {
      return nowMinutes >= onMinutes && nowMinutes < offMinutes;
    }
    return nowMinutes >= onMinutes || nowMinutes < offMinutes;
  }

  void _startCountdown({int? startSeconds}) {
    final intervalSeconds = startSeconds ??
        (_feedingIntervalSeconds <= 0 ? 60 : _feedingIntervalSeconds);
    final endTimeMillis = DateTime.now()
        .add(Duration(seconds: intervalSeconds))
        .millisecondsSinceEpoch;
    _countdownTimer?.cancel();
    setState(() {
      _remainingSeconds = intervalSeconds;
      _isFeeding = false;
      _isTimerRunning = true;
      _countdownEndTimeMillis = endTimeMillis;
    });
    _saveTimerState(endTimeMillis);
    _saveIntervalSettings();
    _scheduleFeedingNotification();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
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
      _isFeeding = false;
      _isTimerRunning = false;
      _countdownEndTimeMillis = null;
    });
    _clearTimerState();
    NotificationService().cancelNotification(_feedNotificationId);
  }

  // ฟังก์ชันเมื่อถึงเวลาให้อาหาร
  void _triggerFeeding() {
    final now = TimeOfDay.now();
    final timeString =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _isFeeding = true;
      _hasNotification = true;
      _notifications.insert(0, {
        'title': 'Feed Fish',
        'message': 'Time to feed the fish ($timeString)',
        'time': timeString,
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🐟 Time to feed the fish!'),
        backgroundColor: Color(0xFF003C7E),
        duration: Duration(seconds: 2),
      ),
    );

    NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Time to Feed Fish',
      body: 'Time to feed the fish ($timeString)',
    );
    NotificationService().addHistory(
      title: 'Time to Feed Fish',
      body: 'Time to feed the fish ($timeString)',
      time: timeString,
    );

    // รอ 3 วินาทีแล้วเริ่มนับถอยหลังใหม่
    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        _isFeeding = false;
      });
      _startCountdown();
    });
  }

  // ฟังก์ชันแปลงวินาทีเป็นรูปแบบ HH:MM:SS
  String _formatTime(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ฟังก์ชันส่งเวลาไปยัง Hardware
  void _sendTimeSettingsToDevice() {
    // TODO: เชื่อมต่อกับ Bluetooth/API เพื่อส่งเวลาไปยังอุปกรณ์
    // ตัวอย่างโครงสร้างข้อมูลที่จะส่ง:
    final timeSettings = {
      'feedingIntervalHours': _feedingIntervalHours,
      'feedingIntervalMinutes': _feedingIntervalMinutes,
      'lightOnTime':
          '${_lightTime.hour.toString().padLeft(2, '0')}:${_lightTime.minute.toString().padLeft(2, '0')}',
      'lightOffTime':
          '${_lightOffTime.hour.toString().padLeft(2, '0')}:${_lightOffTime.minute.toString().padLeft(2, '0')}',
    };

    // ส่ง timeSettings ไปยัง hardware ผ่าน Bluetooth/API
    print('Sending time settings: $timeSettings');
  }

  // ฟังก์ชันตรวจสอบเวลาเปิด/ปิดไฟ
  void _startLightTimer() {
    _lightTimer?.cancel();
    _lightTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final now = TimeOfDay.now();
      final lightOnMinutes = _lightTime.hour * 60 + _lightTime.minute;
      final lightOffMinutes = _lightOffTime.hour * 60 + _lightOffTime.minute;
      final nowMinutes = now.hour * 60 + now.minute;
      final timeString =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      if (nowMinutes == lightOnMinutes && !_isLightOn) {
        setState(() {
          _isLightOn = true;
          _hasNotification = true;
          _notifications.insert(0, {
            'title': 'Lights On',
            'message': 'Lights turned on at $timeString',
            'time': timeString,
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💡 Lights turned on'),
            backgroundColor: Color(0xFF003C7E),
            duration: Duration(seconds: 2),
          ),
        );

        NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Lights On',
          body: 'Lights turned on at $timeString',
        );
        NotificationService().addHistory(
          title: 'Lights On',
          body: 'Lights turned on at $timeString',
          time: timeString,
        );
      }

      if (nowMinutes == lightOffMinutes && _isLightOn) {
        setState(() {
          _isLightOn = false;
          _hasNotification = true;
          _notifications.insert(0, {
            'title': 'Lights Off',
            'message': 'Lights turned off at $timeString',
            'time': timeString,
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💡 Lights turned off'),
            backgroundColor: Color(0xFF003C7E),
            duration: Duration(seconds: 2),
          ),
        );

        NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Lights Off',
          body: 'Lights turned off at $timeString',
        );
        NotificationService().addHistory(
          title: 'Lights Off',
          body: 'Lights turned off at $timeString',
          time: timeString,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSavedState();
      _startLightTimer();
      _scheduleLightNotifications();
    });
  }

  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHours = prefs.getInt('feedingIntervalHours');
    final savedMinutes = prefs.getInt('feedingIntervalMinutes');
    final running = prefs.getBool('feedingTimerRunning') ?? false;
    final savedEndMillis = prefs.getInt('feedingEndTimeMillis');
    final savedLightOnHour = prefs.getInt('lightOnHour');
    final savedLightOnMinute = prefs.getInt('lightOnMinute');
    final savedLightOffHour = prefs.getInt('lightOffHour');
    final savedLightOffMinute = prefs.getInt('lightOffMinute');

    setState(() {
      if (savedHours != null) _feedingIntervalHours = savedHours;
      if (savedMinutes != null) _feedingIntervalMinutes = savedMinutes;
      if (savedLightOnHour != null && savedLightOnMinute != null) {
        _lightTime = TimeOfDay(
          hour: savedLightOnHour,
          minute: savedLightOnMinute,
        );
      }
      if (savedLightOffHour != null && savedLightOffMinute != null) {
        _lightOffTime = TimeOfDay(
          hour: savedLightOffHour,
          minute: savedLightOffMinute,
        );
      }
      _isTimerRunning = running;
      _countdownEndTimeMillis = savedEndMillis;
      _notifications
        ..clear()
        ..addAll(NotificationService().notificationHistory);
    });

    final now = TimeOfDay.now();
    setState(() {
      _isLightOn = _computeLightOn(now, _lightTime, _lightOffTime);
    });

    if (_isTimerRunning && _countdownEndTimeMillis != null) {
      final now = DateTime.now();
      final endTime =
          DateTime.fromMillisecondsSinceEpoch(_countdownEndTimeMillis!);
      final secondsLeft = endTime.difference(now).inSeconds;

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

  // ฟังก์ชันแสดงตัวเลือกเวลาแบบเลื่อนและพิมพ์
  void _showTimePicker(BuildContext context, TimeOfDay initialTime,
      Function(TimeOfDay) onTimeSelected) {
    int selectedHour = initialTime.hour;
    int selectedMinute = initialTime.minute;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              height: 450,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Select Time',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  // เลื่อนเวลา
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ชั่วโมง
                      Column(
                        children: [
                          const Text('Hours', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 80,
                            height: 150,
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 50,
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  return Center(
                                    child: Text(
                                      '$index',
                                      style: TextStyle(
                                        fontSize: 24,
                                        color: selectedHour == index
                                            ? const Color(0xFF003C7E)
                                            : Colors.black,
                                        fontWeight: selectedHour == index
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 24,
                              ),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  selectedHour = index;
                                });
                              },
                              controller: FixedExtentScrollController(
                                  initialItem: initialTime.hour),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      // นาที
                      Column(
                        children: [
                          const Text('Minutes', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 80,
                            height: 150,
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 50,
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  return Center(
                                    child: Text(
                                      '$index',
                                      style: TextStyle(
                                        fontSize: 24,
                                        color: selectedMinute == index
                                            ? const Color(0xFF003C7E)
                                            : Colors.black,
                                        fontWeight: selectedMinute == index
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 60,
                              ),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  selectedMinute = index;
                                });
                              },
                              controller: FixedExtentScrollController(
                                  initialItem: initialTime.minute),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      onTimeSelected(TimeOfDay(
                          hour: selectedHour, minute: selectedMinute));
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003C7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child:
                        const Text('Confirm', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showIntervalPicker(BuildContext context, int initialHours,
      int initialMinutes, Function(int, int) onIntervalSelected) {
    int selectedHour = initialHours;
    int selectedMinute = initialMinutes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              height: 450,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Select Interval',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          const Text('Hours', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 80,
                            height: 150,
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 50,
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  return Center(
                                    child: Text(
                                      '$index',
                                      style: TextStyle(
                                        fontSize: 24,
                                        color: selectedHour == index
                                            ? const Color(0xFF003C7E)
                                            : Colors.black,
                                        fontWeight: selectedHour == index
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 25,
                              ),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  selectedHour = index;
                                });
                              },
                              controller: FixedExtentScrollController(
                                  initialItem: selectedHour),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Column(
                        children: [
                          const Text('Minutes', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 80,
                            height: 150,
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 50,
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  return Center(
                                    child: Text(
                                      '$index',
                                      style: TextStyle(
                                        fontSize: 24,
                                        color: selectedMinute == index
                                            ? const Color(0xFF003C7E)
                                            : Colors.black,
                                        fontWeight: selectedMinute == index
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 60,
                              ),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  selectedMinute = index;
                                });
                              },
                              controller: FixedExtentScrollController(
                                  initialItem: selectedMinute),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      onIntervalSelected(selectedHour, selectedMinute);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003C7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child:
                        const Text('Confirm', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // สร้างการ์ดแสดงการนับถอยหลัง
  Widget _buildCountdownCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Feeding',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.restaurant, color: Color(0xFF003C7E), size: 28),
            ],
          ),
          const SizedBox(height: 20),

          // แสดงสถานะการให้อาหาร
          if (_isFeeding)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.green,
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 40),
                  SizedBox(height: 8),
                  Text(
                    '🐟 Feeding...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF003C7E),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Countdown',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(_remainingSeconds > 0
                        ? _remainingSeconds
                        : (_feedingIntervalSeconds <= 0
                            ? 60
                            : _feedingIntervalSeconds)),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontFamily: 'serif',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Feed every $_feedingIntervalHours hr $_feedingIntervalMinutes min',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ตัวเลือกช่วงเวลา
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set Interval',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade400, width: 1),
                    color: Colors.white,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 1,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  iconSize: 18,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 24, height: 24),
                                  padding: EdgeInsets.zero,
                                  splashRadius: 14,
                                  onPressed: () {
                                    if (_feedingIntervalHours > 0) {
                                      setState(() {
                                        _feedingIntervalHours--;
                                        _normalizeInterval();
                                        if (_feedingIntervalSeconds <= 0) {
                                          _feedingIntervalMinutes = 1;
                                        }
                                      });
                                      _stopCountdown();
                                      _saveIntervalSettings();
                                      _sendTimeSettingsToDevice();
                                    }
                                  },
                                ),
                                SizedBox(
                                  width: 28,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      _showIntervalPicker(
                                        context,
                                        _feedingIntervalHours,
                                        _feedingIntervalMinutes,
                                        (hour, minute) {
                                          setState(() {
                                            _feedingIntervalHours = hour;
                                            _feedingIntervalMinutes = minute;
                                            _normalizeInterval();
                                            if (_feedingIntervalSeconds <= 0) {
                                              _feedingIntervalMinutes = 1;
                                            }
                                          });
                                          _stopCountdown();
                                          _saveIntervalSettings();
                                          _sendTimeSettingsToDevice();
                                        },
                                      );
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _feedingIntervalHours.toString(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  iconSize: 18,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 24, height: 24),
                                  padding: EdgeInsets.zero,
                                  splashRadius: 14,
                                  onPressed: () {
                                    if (_feedingIntervalHours < 24) {
                                      setState(() {
                                        _feedingIntervalHours++;
                                        _normalizeInterval();
                                      });
                                      _stopCountdown();
                                      _saveIntervalSettings();
                                      _sendTimeSettingsToDevice();
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text('hr', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        flex: 1,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  iconSize: 16,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 24, height: 24),
                                  padding: EdgeInsets.zero,
                                  splashRadius: 14,
                                  onPressed: () {
                                    if (_feedingIntervalMinutes > 0) {
                                      setState(() {
                                        _feedingIntervalMinutes--;
                                        if (_feedingIntervalSeconds <= 0) {
                                          _feedingIntervalMinutes = 1;
                                        }
                                      });
                                      _stopCountdown();
                                      _saveIntervalSettings();
                                      _sendTimeSettingsToDevice();
                                    }
                                  },
                                ),
                                SizedBox(
                                  width: 28,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      _showIntervalPicker(
                                        context,
                                        _feedingIntervalHours,
                                        _feedingIntervalMinutes,
                                        (hour, minute) {
                                          setState(() {
                                            _feedingIntervalHours = hour;
                                            _feedingIntervalMinutes = minute;
                                            if (_feedingIntervalSeconds <= 0) {
                                              _feedingIntervalMinutes = 1;
                                            }
                                          });
                                          _stopCountdown();
                                          _saveIntervalSettings();
                                          _sendTimeSettingsToDevice();
                                        },
                                      );
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _feedingIntervalMinutes.toString(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  iconSize: 16,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 24, height: 24),
                                  padding: EdgeInsets.zero,
                                  splashRadius: 14,
                                  onPressed: () {
                                    if (_feedingIntervalMinutes < 59 &&
                                        _feedingIntervalHours < 24) {
                                      setState(() {
                                        _feedingIntervalMinutes++;
                                        _normalizeInterval();
                                      });
                                      _stopCountdown();
                                      _saveIntervalSettings();
                                      _sendTimeSettingsToDevice();
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text('min', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ปุ่มควบคุม
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _startCountdown,
                    icon: const Icon(Icons.play_arrow, size: 14),
                    label: const Text('Start', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(72, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _stopCountdown,
                    icon: const Icon(Icons.stop, size: 14),
                    label: const Text('Stop', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(72, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _triggerFeeding,
                    icon: const Icon(Icons.restaurant, size: 14),
                    label: const Text('Feed', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003C7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(84, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200], // พื้นหลังสีเทาอ่อน
      appBar: AppBar(
        automaticallyImplyLeading: false, // เอาปุ่ม back ออก
        backgroundColor: Colors.grey[200],
        elevation: 0,
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_none, color: Colors.black54),
                if (_hasNotification)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              setState(() {
                _hasNotification = false;
              });
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NotificationPage(
                    notifications: _notifications,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        // ขยับทุกอย่างลงมาโดยเพิ่ม padding ด้านบน
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20), // ระยะห่างเท่ากัน
        child: Column(
          children: [
            // ส่วนนับถอยหลังการให้อาหาร
            _buildCountdownCard(),
            const SizedBox(height: 20),
            // ส่วนตั้งเวลาเปิดไฟ
            TimeCard(
              title: 'Light on Time',
              time: _lightTime,
              icon: Icons.lightbulb,
              onPressed: () {
                _showTimePicker(context, _lightTime, (TimeOfDay newTime) {
                  setState(() {
                    _lightTime = newTime;
                    _isLightOn = _computeLightOn(
                        TimeOfDay.now(), _lightTime, _lightOffTime);
                  });
                  _sendTimeSettingsToDevice();
                  _saveLightSettings();
                  _scheduleLightNotifications();
                });
              },
            ),
            const SizedBox(height: 20),
            // ส่วนตั้งเวลาปิดไฟ
            TimeCard(
              title: 'Light Off Time',
              time: _lightOffTime,
              icon: Icons.lightbulb_outline,
              onPressed: () {
                _showTimePicker(context, _lightOffTime, (TimeOfDay newTime) {
                  setState(() {
                    _lightOffTime = newTime;
                    _isLightOn = _computeLightOn(
                        TimeOfDay.now(), _lightTime, _lightOffTime);
                  });
                  _sendTimeSettingsToDevice();
                  _saveLightSettings();
                  _scheduleLightNotifications();
                });
              },
            ),
          ],
        ),
      ),
      // แถบเมนูด้านล่าง
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          if (index == 0) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ConnectPage()),
            );
          }
        },
        backgroundColor: const Color(0xFF003C7E),
        selectedItemColor: Colors.white.withOpacity(0.9),
        unselectedItemColor: Colors.white.withOpacity(0.7),
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// --- Custom Widgets ---

// การ์ดแสดงข้อมูลทั่วไป
class InfoCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const InfoCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      height: 170, // ทำให้การ์ดสูงขึ้น
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF003C7E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(4, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontFamily: 'serif',
                  fontWeight: FontWeight.w100,
                ),
              ),
              Icon(icon, color: Colors.white.withOpacity(0.9), size: 28),
            ],
          ),
          const Divider(color: Colors.white24, thickness: 0.8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// การ์ดสำหรับตั้งเวลา
class TimeCard extends StatelessWidget {
  final String title;
  final TimeOfDay time;
  final IconData icon;
  final VoidCallback onPressed;

  const TimeCard({
    super.key,
    required this.title,
    required this.time,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(icon, color: const Color(0xFF003C7E), size: 24),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF003C7E),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  time.format(context),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF003C7E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.edit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
