import 'dart:async';

import 'package:flutter/material.dart';
import 'settime.dart';
import 'Connect.dart';
import 'Notification.dart';
import 'notification_service.dart';
import 'sensor_data_manager.dart';

// หน้าจอหลักของ Dashboard
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isFeeding = false;
  int _selectedIndex = 0;
  bool _hasNotification = false;
  bool _hasBoardSensorData = false;
  bool _isMqttConnected = false;

  StreamSubscription<Map<String, double>>? _sensorSubscription;
  StreamSubscription<bool>? _mqttConnectionSubscription;
  Timer? _connectionCheckTimer;
  
  final SensorDataManager _sensorManager = SensorDataManager();
  final List<Map<String, String>> _notifications = [];

  // ค่าจากเซนเซอร์
  double _temperature = 0.0;
  double _phValue = 0.0;
  double _oxygenLevel = 0.0;
  double _turbidity = 0.0;

  static const double _turbidityAlertThreshold = 5.0;

  bool _tempLowAlerted = false;
  bool _tempHighAlerted = false;
  bool _phLowAlerted = false;
  bool _phHighAlerted = false;
  bool _oxygenLowAlerted = false;
  bool _oxygenHighAlerted = false;
  bool _turbidityHighAlerted = false;

  @override
  void initState() {
    super.initState();
    _startSensorListener();
    _monitorMqttConnection();
  }

  void _startSensorListener() {
    // ฟังข้อมูลเซนเซอร์จาก stream
    _sensorSubscription = _boardSensorStream.listen((sensorValues) {
      updateSensorData(
        temperature: sensorValues['temperature'],
        phValue: sensorValues['phValue'],
        oxygenLevel: sensorValues['oxygenLevel'],
        turbidity: sensorValues['turbidity'],
      );
    });
  }

  void _monitorMqttConnection() {
    // ตรวจสอบสถานะ MQTT ทุกวินาที
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _isMqttConnected = _sensorManager.isMqttConnected();
        });
      }
    });
  }

  Stream<Map<String, double>> get _boardSensorStream {
    // ดึงข้อมูลเซนเซอร์ล่าสุดจากฐานข้อมูล (ที่ได้จาก MQTT)
    return Stream.periodic(const Duration(milliseconds: 500), (_) async {
      final data = await _sensorManager.getLatestSensorData();
      if (data != null) {
        return <String, double>{
          'temperature': (data['temperature'] as num?)?.toDouble() ?? 0.0,
          'phValue': (data['ph_value'] as num?)?.toDouble() ?? 0.0,
          'oxygenLevel': (data['oxygen_level'] as num?)?.toDouble() ?? 0.0,
          'turbidity': (data['turbidity'] as num?)?.toDouble() ?? 0.0,
        };
      }
      return <String, double>{};
    }).asyncExpand<Map<String, double>>((future) async* {
      yield await future;
    }).where((data) => data.isNotEmpty);
  }

  // ฟังก์ชันอัปเดตค่าจากบอร์ด
  void updateSensorData({
    double? temperature,
    double? phValue,
    double? oxygenLevel,
    double? turbidity,
  }) {
    setState(() {
      if (temperature != null) {
        _temperature = temperature;
      }
      if (phValue != null) {
        _phValue = phValue;
      }
      if (oxygenLevel != null) {
        _oxygenLevel = oxygenLevel;
      }
      if (turbidity != null) {
        _turbidity = turbidity;
      }
      _hasBoardSensorData = true;
    });

    // บันทึกลงฐานข้อมูล
    if (temperature != null && phValue != null && oxygenLevel != null && turbidity != null) {
      _sensorManager.saveSensorData(
        temperature: temperature,
        phValue: phValue,
        oxygenLevel: oxygenLevel,
        turbidity: turbidity,
      );
    }

    _checkSensorAlerts();
  }

  void _checkSensorAlerts() {
    if (!_hasBoardSensorData) {
      return;
    }

    if (_temperature < 25.0) {
      if (!_tempLowAlerted) {
        _tempLowAlerted = true;
        _tempHighAlerted = false;
        _addSensorAlert(
          'Low Temperature Alert',
          'Temperature is below 25°C. Current temperature ${_temperature.toStringAsFixed(1)}°C. Increase water temperature slowly.',
        );
      }
    } else if (_temperature > 32.0) {
      if (!_tempHighAlerted) {
        _tempHighAlerted = true;
        _tempLowAlerted = false;
        _addSensorAlert(
          'High Temperature Alert',
          'Temperature is above 32°C. Current temperature ${_temperature.toStringAsFixed(1)}°C. Cool water to reduce stress.',
        );
      }
    } else {
      _tempLowAlerted = false;
      _tempHighAlerted = false;
    }

    if (_phValue < 6.0) {
      if (!_phLowAlerted) {
        _phLowAlerted = true;
        _phHighAlerted = false;
        _addSensorAlert(
          'Low pH Alert',
          'pH is below 6.0. Current pH ${_phValue.toStringAsFixed(1)}. Please adjust to a more neutral level.',
        );
      }
    } else if (_phValue > 8.5) {
      if (!_phHighAlerted) {
        _phHighAlerted = true;
        _phLowAlerted = false;
        _addSensorAlert(
          'High pH Alert',
          'pH is above 8.5. Current pH ${_phValue.toStringAsFixed(1)}. Lower pH to avoid toxic ammonia.',
        );
      }
    } else {
      _phLowAlerted = false;
      _phHighAlerted = false;
    }

    if (_oxygenLevel < 5.0) {
      if (!_oxygenLowAlerted) {
        _oxygenLowAlerted = true;
        _oxygenHighAlerted = false;
        _addSensorAlert(
          'Low Oxygen Alert',
          'Dissolved oxygen dropped below 5.0 mg/L. Current level ${_oxygenLevel.toStringAsFixed(1)} mg/L. Increase aeration immediately.',
        );
      }
    } else if (_oxygenLevel > 10.0) {
      if (!_oxygenHighAlerted) {
        _oxygenHighAlerted = true;
        _oxygenLowAlerted = false;
        _addSensorAlert(
          'High Oxygen Alert',
          'Dissolved oxygen is above 10.0 mg/L. Current level ${_oxygenLevel.toStringAsFixed(1)} mg/L. Check for supersaturation or sensor error.',
        );
      }
    } else {
      _oxygenLowAlerted = false;
      _oxygenHighAlerted = false;
    }

    if (_turbidity > _turbidityAlertThreshold) {
      if (!_turbidityHighAlerted) {
        _turbidityHighAlerted = true;
        _addSensorAlert(
          'High Turbidity Alert',
          'Turbidity is above ${_turbidityAlertThreshold.toStringAsFixed(1)} NTU. Current turbidity ${_turbidity.toStringAsFixed(1)} NTU. Please clean the water or check the filter.',
        );
      }
    } else {
      _turbidityHighAlerted = false;
    }
  }

  void _addSensorAlert(String title, String message) {
    final now = TimeOfDay.now();
    final timeString =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _hasNotification = true;
      _notifications.insert(0, {
        'title': title,
        'message': message,
        'time': timeString,
      });
    });

    // บันทึกลงฐานข้อมูล
    final alertType = title.toLowerCase().split(' ').first;
    _sensorManager.saveAlert(
      title: title,
      message: message,
      type: alertType,
    );

    NotificationService().addHistory(
      title: title,
      body: message,
      time: timeString,
    );

    NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: message,
    );
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _mqttConnectionSubscription?.cancel();
    _connectionCheckTimer?.cancel();
    _sensorManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200], // พื้นหลังสีเทาอ่อน
      appBar: AppBar(
        automaticallyImplyLeading: false, // เอาปุ่ม back ออก
        backgroundColor: Colors.grey[200],
        elevation: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isMqttConnected ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isMqttConnected ? 'Connected' : 'Disconnected',
                style: TextStyle(
                  fontSize: 12,
                  color: _isMqttConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
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
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
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
        padding:
            const EdgeInsets.fromLTRB(20, 10, 20, 20), // เพิ่มระยะห่างด้านบน
        child: Column(
          children: [
            // แถวที่ 1: Temperature & pH
            Row(
              children: [
                Expanded(
                  child: InfoCard(
                    value: '${_temperature.toStringAsFixed(1)}°C',
                    label: 'Temperature',
                    icon: Icons.water_drop,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InfoCard(
                    value: _phValue.toStringAsFixed(1),
                    label: 'pH value in water',
                    icon: Icons.water_drop,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25), // เพิ่มระยะห่าง
            // แถวที่ 2: Feed & Oxygen
            Row(
              children: [
                Expanded(
                  child: FeedCard(
                    isFeeding: _isFeeding,
                    onChanged: (value) {
                      setState(() {
                        _isFeeding = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InfoCard(
                    value: '${_oxygenLevel.toStringAsFixed(1)} Mg/L',
                    label: 'Dissolved Oxygen',
                    icon: Icons.water_drop,
                  ),
                ),
              ],
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
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SetTimePage()),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      height: 160,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 28),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontFamily: 'serif',
              fontWeight: FontWeight.w100,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 30,
            height: 0.8,
            color: Colors.white24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// การ์ดสำหรับให้อาหาร
class FeedCard extends StatelessWidget {
  final bool isFeeding;
  final ValueChanged<bool> onChanged;

  const FeedCard({
    super.key,
    required this.isFeeding,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      height: 160,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.eco, color: Colors.white, size: 28),
          const SizedBox(height: 6),
          const Text(
            'Feed the fish',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: isFeeding,
              onChanged: onChanged,
              activeThumbColor: const Color.fromARGB(248, 3, 107, 3),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.black.withOpacity(0.3),
              trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }
}
