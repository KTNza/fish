import 'package:flutter/material.dart';
import 'dashbord.dart';
import 'splash_screen.dart';
import 'Notification.dart';
import 'notification_service.dart';
import 'sensor_data_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // แจ้งเตือนมักจะเป็นแค่การตั้งค่า Local โหลดเร็ว สามารถ await ได้
  await NotificationService().init();

  // 🟢 แก้ตรงนี้! เอาคำว่า await ออก
  // สั่งเชื่อมต่อ MQTT ไปเลย แต่ไม่ต้องหยุดรอ ปล่อยให้มันทำงานเบื้องหลังไป
  final sensorManager = SensorDataManager();
  sensorManager.initializeMqtt(); // <--- ลบ await ทิ้งครับ!

  // ระบบจะมารันคำสั่งนี้ทันที ทำให้แอปเปิดเข้าหน้า Splash Screen ได้ไวปรู๊ด!
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(), // <-- หน้าแรกคือ Splash Screen
        '/dashboard': (context) => const DashboardPage(), // หน้าแดชบอร์ด
        '/notification': (context) => const NotificationPage(), // หน้าแจ้งเตือนนะจ้ะพี่น้อง
      },
    );
  }
}