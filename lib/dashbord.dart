import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'settime.dart';
import 'Connect.dart';
import 'Notification.dart';
import 'notification_service.dart';
import 'sensor_data_manager.dart';
import 'mqtt_service.dart';

// ==========================================
// ค่ามาตรฐานสำหรับ "ลูกปลากัด" โดยเฉพาะ
// แก้ตรงนี้จุดเดียวถ้าอยากปรับ threshold
// ==========================================
class BettaFryParams {
  // อุณหภูมิ (°C) — ลูกปลากัดชอบอุ่นกว่าปลาโต
  static const double tempDanger  = 22.0;
  static const double tempLow     = 24.0;
  static const double tempIdealLo = 26.0;
  static const double tempIdealHi = 29.0;
  static const double tempHigh    = 31.0;
  static const double tempDangerH = 33.0;

  // pH — ลูกปลากัดชอบกรดอ่อน
  static const double phDangerLo  = 6.0;
  static const double phLow       = 6.5;
  static const double phIdealLo   = 6.8;
  static const double phIdealHi   = 7.5;
  static const double phHigh      = 8.0;
  static const double phDangerHi  = 8.5;

  // DO (mg/L)
  static const double doLow       = 3.0;
  static const double doIdealLo   = 5.0;
  static const double doIdealHi   = 8.0;
  static const double doHigh      = 10.0;

  // ความขุ่น (NTU)
  static const double turbClear   = 1.0;
  static const double turbMild    = 5.0;

  // Alert thresholds
  static const double alertTempLo  = tempLow;
  static const double alertTempHi  = tempHigh;
  static const double alertPhLo    = phLow;
  static const double alertPhHi    = phHigh;
  static const double alertDoLo    = doLow;
  static const double alertDoHi    = doHigh;
}

// ==========================================
// [FIX 2] Type-safe meta classes แทน Map<String, dynamic>
// ==========================================
class SensorMeta {
  final Color color;
  final String label;
  final IconData icon;
  const SensorMeta({required this.color, required this.label, required this.icon});
}

class SimpleMeta {
  final Color color;
  final String label;
  const SimpleMeta({required this.color, required this.label});
}

SensorMeta _tempMeta(double t) {
  if (t < BettaFryParams.tempDanger)
    return const SensorMeta(color: Color(0xFF90CAF9), label: 'อันตราย! เย็นมาก',      icon: Icons.ac_unit);
  if (t < BettaFryParams.tempLow)
    return const SensorMeta(color: Color(0xFF4FC3F7), label: 'เย็นเกินไป',             icon: Icons.ac_unit);
  if (t < BettaFryParams.tempIdealLo)
    return const SensorMeta(color: Color(0xFF80CBC4), label: 'เย็นนิดหน่อย',           icon: Icons.thermostat);
  if (t <= BettaFryParams.tempIdealHi)
    return const SensorMeta(color: Color(0xFF4DB6AC), label: 'อุณหภูมิเหมาะสม',        icon: Icons.check_circle_outline);
  if (t <= BettaFryParams.tempHigh)
    return const SensorMeta(color: Color(0xFFFFB74D), label: 'อุ่นเกินไปนิดหน่อย',    icon: Icons.thermostat);
  if (t <= BettaFryParams.tempDangerH)
    return const SensorMeta(color: Color(0xFFFF8A65), label: 'ร้อนเกินไป',             icon: Icons.warning_amber_rounded);
  return   const SensorMeta(color: Color(0xFFE57373), label: 'อันตราย! ร้อนมาก',      icon: Icons.dangerous_outlined);
}

SimpleMeta _phMeta(double ph) {
  if (ph < BettaFryParams.phDangerLo)  return const SimpleMeta(color: Color(0xFFE57373), label: 'กรดอันตราย');
  if (ph < BettaFryParams.phLow)       return const SimpleMeta(color: Color(0xFFFF8A65), label: 'กรดเกินไป');
  if (ph < BettaFryParams.phIdealLo)   return const SimpleMeta(color: Color(0xFFFFCC80), label: 'กรดอ่อน');
  if (ph <= BettaFryParams.phIdealHi)  return const SimpleMeta(color: Color(0xFF4DB6AC), label: 'pH เหมาะสม');
  if (ph <= BettaFryParams.phHigh)     return const SimpleMeta(color: Color(0xFF64B5F6), label: 'ด่างอ่อน');
  if (ph <= BettaFryParams.phDangerHi) return const SimpleMeta(color: Color(0xFF9575CD), label: 'ด่างเกินไป');
  return                                      const SimpleMeta(color: Color(0xFFE57373), label: 'ด่างอันตราย');
}

SimpleMeta _doMeta(double d) {
  if (d < BettaFryParams.doLow)       return const SimpleMeta(color: Color(0xFFE57373), label: 'ออกซิเจนต่ำมาก');
  if (d < BettaFryParams.doIdealLo)   return const SimpleMeta(color: Color(0xFFFFB74D), label: 'ออกซิเจนต่ำ');
  if (d <= BettaFryParams.doIdealHi)  return const SimpleMeta(color: Color(0xFF4DB6AC), label: 'ออกซิเจนเหมาะสม');
  if (d <= BettaFryParams.doHigh)     return const SimpleMeta(color: Color(0xFF64B5F6), label: 'ออกซิเจนสูง');
  return                                     const SimpleMeta(color: Color(0xFFBA68C8), label: 'สูงผิดปกติ');
}

SimpleMeta _turbMeta(double t) {
  if (t <= BettaFryParams.turbClear) return const SimpleMeta(color: Color(0xFF4DB6AC), label: 'น้ำใส');
  if (t <= BettaFryParams.turbMild)  return const SimpleMeta(color: Color(0xFFFFB74D), label: 'เริ่มขุ่น');
  return                                    const SimpleMeta(color: Color(0xFFE57373), label: 'ขุ่นมาก');
}

// ==========================================
// Dashboard Page
// ==========================================
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _hasBoardSensorData = false;
  bool _isMqttConnected = false;

  // [FIX 1] เก็บเวลา last update เป็น state แทนคำนวณตอน build
  String _lastUpdatedTime = '--:--';

  StreamSubscription<Map<String, double>>? _sensorSubscription;
  Timer? _connectionCheckTimer;

  final SensorDataManager _sensorManager = SensorDataManager();
  final List<Map<String, String>> _notifications = [];

  double _temperature  = 0.0;
  double _phValue      = 0.0;
  double _oxygenLevel  = 0.0;
  double _turbidity    = 0.0;

  // Alert flags
  bool _tempLowAlerted           = false;
  bool _tempHighAlerted          = false;
  bool _phLowAlerted             = false;
  bool _phHighAlerted            = false;
  bool _oxygenLowAlerted         = false;
  bool _oxygenHighAlerted        = false;
  bool _turbidityModerateAlerted = false;
  bool _turbidityHighAlerted     = false;

  late List<AnimationController> _cardControllers;
  late List<Animation<double>> _cardAnimations;

  @override
  void initState() {
    super.initState();

    _cardControllers = List.generate(4, (i) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    ));
    _cardAnimations = _cardControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOutCubic))
        .toList();

    Future.delayed(const Duration(milliseconds: 100), () {
      for (int i = 0; i < 4; i++) {
        Future.delayed(Duration(milliseconds: i * 80), () {
          if (mounted) _cardControllers[i].forward();
        });
      }
    });

    _startSensorListener();
    _monitorMqttConnection();
    _notifications
      ..clear()
      ..addAll(NotificationService().notificationHistory);
  }

  void _startSensorListener() {
    _sensorSubscription = _sensorManager.sensorStream.listen((sensorValues) {
      updateSensorData(
        temperature:  sensorValues['temperature'],
        phValue:      sensorValues['phValue'],
        oxygenLevel:  sensorValues['oxygenLevel'],
        turbidity:    sensorValues['turbidity'],
      );
    });
  }

  void _monitorMqttConnection() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() => _isMqttConnected = MqttService().isDeviceOnline);
      }
    });
  }

  void updateSensorData({
    double? temperature,
    double? phValue,
    double? oxygenLevel,
    double? turbidity,
  }) {
    // [FIX 1] อัปเดตเวลาใน setState เดียวกับข้อมูล — ไม่กระพริบ
    final now = TimeOfDay.now();
    final timeString =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      if (temperature  != null) _temperature  = temperature;
      if (phValue      != null) _phValue      = phValue;
      if (oxygenLevel  != null) _oxygenLevel  = oxygenLevel;
      if (turbidity    != null) _turbidity    = turbidity;
      _hasBoardSensorData = true;
      _lastUpdatedTime = timeString;
    });

    if (temperature != null && phValue != null &&
        oxygenLevel != null && turbidity != null) {
      _sensorManager.saveSensorData(
        temperature:  temperature,
        phValue:      phValue,
        oxygenLevel:  oxygenLevel,
        turbidity:    turbidity,
      );
    }
    _checkSensorAlerts();
  }

  // ==========================================
  // Alert — ใช้ค่ามาตรฐาน BettaFryParams
  // ==========================================
  void _checkSensorAlerts() {
    if (!_hasBoardSensorData) return;

    // อุณหภูมิ
    if (_temperature < BettaFryParams.alertTempLo) {
      if (!_tempLowAlerted) {
        _tempLowAlerted = true; _tempHighAlerted = false;
        _addSensorAlert(
          'อุณหภูมิต่ำเกินไป',
          'อุณหภูมิ ${_temperature.toStringAsFixed(1)}°C ต่ำกว่า ${BettaFryParams.alertTempLo}°C '
              'ลูกปลากัดเสี่ยงป่วย ควรเพิ่มอุณหภูมิน้ำ',
        );
      }
    } else if (_temperature > BettaFryParams.alertTempHi) {
      if (!_tempHighAlerted) {
        _tempHighAlerted = true; _tempLowAlerted = false;
        _addSensorAlert(
          'อุณหภูมิสูงเกินไป',
          'อุณหภูมิ ${_temperature.toStringAsFixed(1)}°C สูงกว่า ${BettaFryParams.alertTempHi}°C '
              'ลูกปลากัดเครียด ควรลดอุณหภูมิน้ำ',
        );
      }
    } else {
      _tempLowAlerted = false;
      _tempHighAlerted = false;
    }

    // pH
    if (_phValue < BettaFryParams.alertPhLo) {
      if (!_phLowAlerted) {
        _phLowAlerted = true; _phHighAlerted = false;
        _addSensorAlert(
          'pH ต่ำเกินไป',
          'pH ${_phValue.toStringAsFixed(1)} ต่ำกว่า ${BettaFryParams.alertPhLo} '
              'น้ำเป็นกรดเกินไปสำหรับลูกปลากัด',
        );
      }
    } else if (_phValue > BettaFryParams.alertPhHi) {
      if (!_phHighAlerted) {
        _phHighAlerted = true; _phLowAlerted = false;
        _addSensorAlert(
          'pH สูงเกินไป',
          'pH ${_phValue.toStringAsFixed(1)} สูงกว่า ${BettaFryParams.alertPhHi} '
              'ควรปรับให้อยู่ในช่วง 6.8–7.5',
        );
      }
    } else {
      _phLowAlerted = false;
      _phHighAlerted = false;
    }

    // DO
    if (_oxygenLevel < BettaFryParams.alertDoLo) {
      if (!_oxygenLowAlerted) {
        _oxygenLowAlerted = true; _oxygenHighAlerted = false;
        _addSensorAlert(
          'ออกซิเจนต่ำมาก',
          'DO ${_oxygenLevel.toStringAsFixed(1)} mg/L ต่ำกว่า ${BettaFryParams.alertDoLo} mg/L '
              'เพิ่มการเติมอากาศทันที (ลูกปลากัดยังหายใจอากาศเองไม่ได้)',
        );
      }
    } else if (_oxygenLevel > BettaFryParams.alertDoHi) {
      if (!_oxygenHighAlerted) {
        _oxygenHighAlerted = true; _oxygenLowAlerted = false;
        _addSensorAlert(
          'ออกซิเจนสูงผิดปกติ',
          'DO ${_oxygenLevel.toStringAsFixed(1)} mg/L สูงกว่า ${BettaFryParams.alertDoHi} mg/L '
              'ตรวจสอบเซนเซอร์หรือระบบเติมอากาศ',
        );
      }
    } else {
      _oxygenLowAlerted = false;
      _oxygenHighAlerted = false;
    }

    // ความขุ่น
    if (_turbidity <= BettaFryParams.turbClear) {
      _turbidityModerateAlerted = false;
      _turbidityHighAlerted = false;
    } else if (_turbidity <= BettaFryParams.turbMild) {
      if (!_turbidityModerateAlerted) {
        _turbidityModerateAlerted = true; _turbidityHighAlerted = false;
        _addSensorAlert('น้ำเริ่มขุ่น',
            '${_turbidity.toStringAsFixed(1)} NTU ควรตรวจสอบระบบกรองน้ำ');
      }
    } else {
      if (!_turbidityHighAlerted) {
        _turbidityHighAlerted = true; _turbidityModerateAlerted = false;
        _addSensorAlert('น้ำขุ่นมาก',
            '${_turbidity.toStringAsFixed(1)} NTU ต้องเปลี่ยนน้ำและทำความสะอาดระบบกรองทันที');
      }
    }
  }

  bool _isDuplicateAlert(String title, String message, String time) {
    if (_notifications.isEmpty) return false;
    final last = _notifications.first;
    return last['title'] == title &&
        last['message'] == message &&
        last['time'] == time;
  }

  void _addSensorAlert(String title, String message) {
    final now = TimeOfDay.now();
    final timeString =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (_isDuplicateAlert(title, message, timeString)) return;

    setState(() {
      _notifications.insert(0, {
        'title': title, 'message': message, 'time': timeString,
      });
    });

    final alertType = title.toLowerCase().split(' ').first;
    _sensorManager.saveAlert(title: title, message: message, type: alertType);
    NotificationService().addHistory(title: title, body: message, time: timeString);
    NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: message,
    );
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _connectionCheckTimer?.cancel();
    for (final c in _cardControllers) c.dispose();
    _sensorManager.dispose();
    super.dispose();
  }

  // ==========================================
  // BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    // [FIX 2] ใช้ type-safe classes แทน Map — เข้าถึงด้วย . แทน []
    final SensorMeta tempMeta = _tempMeta(_temperature);
    final SimpleMeta phMeta   = _phMeta(_phValue);
    final SimpleMeta doMeta   = _doMeta(_oxygenLevel);
    final SimpleMeta turbMeta = _turbMeta(_turbidity);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusRow(),
                      const SizedBox(height: 16),
                      _buildParamGuide(),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                          child: _AnimatedCard(
                            animation: _cardAnimations[0],
                            child: SensorCard(
                              value: '${_temperature.toStringAsFixed(1)}°C',
                              label: 'อุณหภูมิน้ำ',
                              statusLabel: tempMeta.label,
                              accentColor: tempMeta.color,
                              icon: tempMeta.icon,
                              idealRange: '26–29°C',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _AnimatedCard(
                            animation: _cardAnimations[1],
                            child: SensorCard(
                              value: _phValue.toStringAsFixed(1),
                              label: 'ค่า pH',
                              statusLabel: phMeta.label,
                              accentColor: phMeta.color,
                              icon: Icons.science_outlined,
                              idealRange: '6.8–7.5',
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: _AnimatedCard(
                            animation: _cardAnimations[2],
                            child: SensorCard(
                              value: '${_turbidity.toStringAsFixed(1)} NTU',
                              label: 'ความขุ่นของน้ำ',
                              statusLabel: turbMeta.label,
                              accentColor: turbMeta.color,
                              icon: Icons.water_drop_outlined,
                              idealRange: '< 1 NTU',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _AnimatedCard(
                            animation: _cardAnimations[3],
                            child: SensorCard(
                              value: '${_oxygenLevel.toStringAsFixed(1)} mg/L',
                              label: 'ออกซิเจน (ประมาณการ)',
                              statusLabel: doMeta.label,
                              accentColor: doMeta.color,
                              icon: Icons.bubble_chart_outlined,
                              idealRange: '5–8 mg/L',
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      _buildLastUpdated(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildParamGuide() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4DB6AC).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline_rounded,
                size: 14, color: Color(0xFF4DB6AC)),
            const SizedBox(width: 6),
            Text(
              'ค่ามาตรฐานสำหรับลูกปลากัด',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2340).withOpacity(0.7),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _paramRow('อุณหภูมิ', '26–29°C', _temperature,
              BettaFryParams.tempIdealLo, BettaFryParams.tempIdealHi),
          _paramRow('pH', '6.8–7.5', _phValue,
              BettaFryParams.phIdealLo, BettaFryParams.phIdealHi),
          _paramRow('ออกซิเจน', '5–8 mg/L', _oxygenLevel,
              BettaFryParams.doIdealLo, BettaFryParams.doIdealHi),
          _paramRow('ความขุ่น', '< 1 NTU', _turbidity,
              0, BettaFryParams.turbClear),
        ],
      ),
    );
  }

  Widget _paramRow(String name, String ideal, double current,
      double lo, double hi) {
    final inRange = current >= lo && current <= hi;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 72,
          child: Text(name,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ),
        Text(ideal,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: Color(0xFF1A2340))),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: inRange
                ? const Color(0xFF4DB6AC).withOpacity(0.12)
                : const Color(0xFFE57373).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            inRange ? '✓ ปกติ' : '⚠ ผิดปกติ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: inRange
                  ? const Color(0xFF2E7D72)
                  : const Color(0xFFB71C1C),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 4),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Smart Betta', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: Color(0xFF1A2340), letterSpacing: -0.5,
              )),
              Text('ระบบดูแลลูกปลากัด', style: TextStyle(
                fontSize: 12, color: Colors.black38,
                fontWeight: FontWeight.w500,
              )),
            ],
          ),
          const Spacer(),
          ValueListenableBuilder<bool>(
            valueListenable: NotificationService().hasUnreadNotifications,
            builder: (context, hasUnread, _) {
              return GestureDetector(
                onTap: () {
                  NotificationService().markNotificationsRead();
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NotificationPage(notifications: _notifications),
                  ));
                },
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 10, offset: const Offset(0, 4),
                    )],
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    const Icon(Icons.notifications_none_rounded,
                        color: Color(0xFF1A2340), size: 22),
                    if (hasUnread)
                      Positioned(
                        right: 9, top: 9,
                        child: Container(
                          width: 7, height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF5252),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    final isOnline = _isMqttConnected;
    final dotColor  = isOnline ? const Color(0xFF4DB6AC) : const Color(0xFFE57373);
    final bgColor   = dotColor.withOpacity(0.13);
    final textColor = isOnline ? const Color(0xFF2E7D72) : const Color(0xFFB71C1C);
    final label     = isOnline ? 'ตู้ปลา: ออนไลน์' : 'ตู้ปลา: ออฟไลน์';

    return Row(children: [
      GestureDetector(
        onTap: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ConnectPage()),
        ).then((_) { if (mounted) setState(() => _selectedIndex = 0); }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 7, height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 14, color: textColor),
          ]),
        ),
      ),
    ]);
  }

  // [FIX 1] ใช้ _lastUpdatedTime จาก state แทนคำนวณตอน build
  Widget _buildLastUpdated() {
    return Center(
      child: Text(
        'อัปเดตล่าสุด $_lastUpdatedTime น.',
        style: const TextStyle(fontSize: 11, color: Colors.black26),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A2340),
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
              _NavItem(icon: Icons.history_rounded,  label: 'ประวัติ',  selected: _selectedIndex == 1, onTap: () => _onNavTap(1)),
              _NavItem(icon: Icons.settings_rounded, label: 'ตั้งค่า',  selected: _selectedIndex == 2, onTap: () => _onNavTap(2)),
            ],
          ),
        ),
      ),
    );
  }

  // [FIX 3] ใช้ pushReplacement เพื่อป้องกัน push ซ้อน
  // และ reset _selectedIndex กลับ 0 เมื่อกลับมาหน้าหลัก
  void _onNavTap(int index) {
    if (index == _selectedIndex) return; // กันกด tab เดิมซ้ำ

    setState(() => _selectedIndex = index);

    if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetTimePage()),
      ).then((_) {
        // เมื่อกลับมา reset index กลับหน้าหลัก
        if (mounted) setState(() => _selectedIndex = 0);
      });
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ConnectPage()),
      ).then((_) {
        if (mounted) setState(() => _selectedIndex = 0);
      });
    }
  }
}

// ==========================================
// Animated Card Wrapper
// ==========================================
class _AnimatedCard extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _AnimatedCard({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }
}

// ==========================================
// Sensor Card
// ==========================================
class SensorCard extends StatelessWidget {
  final String value;
  final String label;
  final String statusLabel;
  final Color accentColor;
  final IconData icon;
  final String idealRange;

  const SensorCard({
    super.key,
    required this.value,
    required this.label,
    required this.statusLabel,
    required this.accentColor,
    required this.icon,
    required this.idealRange,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      height: 176,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: accentColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: Color(0xFF1A2340),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.black.withOpacity(0.4),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(
              'เหมาะสม: $idealRange',
              style: TextStyle(
                fontSize: 9,
                color: accentColor.withOpacity(0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            height: 3,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Bottom Nav Item
// ==========================================
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Icon(icon,
              color: selected ? Colors.white : Colors.white38,
              size: 22),
          if (selected) ...[
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            )),
          ],
        ]),
      ),
    );
  }
}