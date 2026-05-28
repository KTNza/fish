import 'dart:async';
import 'package:flutter/material.dart';
import 'dashbord.dart';
import 'Notification.dart';
import 'notification_service.dart';
import 'settime.dart';
import 'mqtt_service.dart';

// หน้าจอเชื่อมต่อและตรวจสอบสถานะ
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  int _selectedIndex = 2;

  bool _isConnecting = false;
  bool _isConnected = false;
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkConnectionStatus();

    // 🔥 เพิ่มระบบ Auto-Connect: ถ้าเปิดหน้านี้มาแล้วยังไม่ต่อเน็ต ให้มันพยายามต่อเองเลย!
    if (!MqttService().isConnected && !_isConnecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reconnect();
      });
    }

    // ตั้งเวลาเช็กชีพจรตู้ปลาทุกๆ 2 วินาที แบบ Real-time
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkConnectionStatus();
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  // ลอจิกสำคัญ: เช็กว่า "ตู้ปลา" ออนไลน์จริงๆ หรือไม่
  void _checkConnectionStatus() {
    bool isFishTankOnline = MqttService().isDeviceOnline;

    if (mounted && _isConnected != isFishTankOnline) {
      setState(() {
        _isConnected = isFishTankOnline;
      });
    }
  }

  // ฟังก์ชันปุ่มกด และ Auto-connect
  void _reconnect() async {
    if (_isConnecting) return; // ป้องกันการกดรัวๆ

    setState(() {
      _isConnecting = true;
    });

    try {
      // สั่งให้แอปต่อเซิร์ฟเวอร์ใหม่
      await MqttService().connect();
    } catch (e) {
      print('Connection failed: $e');
    }

    // รอระบบเซ็ตตัว 2 วินาที
    await Future.delayed(const Duration(seconds: 2));
    _checkConnectionStatus();

    if (mounted) {
      setState(() {
        _isConnecting = false;
      });

      if (_isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ พบสัญญาณจากตู้ปลา!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ ไม่พบสัญญาณตู้ปลา (กำลังรอข้อมูล...)'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.grey[200],
        elevation: 0,
        title: const Text(
          'System Status',
          style: TextStyle(
            color: Color(0xFF003C7E),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: NotificationService().hasUnreadNotifications,
            builder: (context, hasUnread, child) {
              return IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_none, color: Colors.black54),
                    if (hasUnread)
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
                  NotificationService().markNotificationsRead();
                  Navigator.pushNamed(context, '/notification');
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _isConnecting
                          ? Colors.orange.withOpacity(0.1)
                          : _isConnected
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isConnecting
                          ? Icons.wifi_find
                          : (_isConnected ? Icons.wifi : Icons.wifi_off),
                      size: 64,
                      color: _isConnecting
                          ? Colors.orange
                          : _isConnected
                              ? Colors.green
                              : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isConnecting
                        ? 'กำลังค้นหาตู้ปลา...'
                        : _isConnected
                            ? 'เชื่อมต่อตู้ปลาสำเร็จ'
                            : 'ขาดการเชื่อมต่อตู้ปลา',
                    style: TextStyle(
                      color: _isConnecting
                          ? Colors.orange
                          : _isConnected
                              ? Colors.green
                              : Colors.red,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConnected
                        ? 'ระบบกำลังรับ-ส่งข้อมูลแบบ Real-time\nผ่าน HiveMQ Broker'
                        : 'ไม่พบสัญญาณจากบอร์ด ESP32\nโปรดตรวจสอบการเสียบปลั๊กไฟที่ตู้ปลา',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting ? null : _reconnect,
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _isConnecting ? 'Connecting...' : 'Reconnect System',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF003C7E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: _isConnecting ? 0 : 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Network Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(Icons.dns, 'Broker', 'broker.hivemq.com'),
                  const Divider(height: 24),
                  _buildDetailRow(Icons.tag, 'Port', '1883'),
                  const Divider(height: 24),
                  _buildDetailRow(
                    Icons.security,
                    'Security',
                    'No SSL (Development)',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );
          } else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SetTimePage()),
            );
          }
        },
        backgroundColor: const Color(0xFF003C7E),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white.withOpacity(0.5),
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

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 24, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
