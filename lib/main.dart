import 'package:flutter/material.dart';
import 'dashbord.dart';
import 'splash_screen.dart';
import 'Notification.dart';
import 'notification_service.dart';
import 'sensor_data_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  
  // เชื่อมต่อ MQTT
  final sensorManager = SensorDataManager();
  await sensorManager.initializeMqtt();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // 2. แก้ไข routes ให้เริ่มต้นที่ SplashScreen
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(), // <-- หน้าแรกคือ Splash Screen
        '/dashboard': (context) => const DashboardPage(), // หน้าแดชบอร์ด
        '/notification': (context) => const NotificationPage(), // หน้าแจ้งเตือน
        // หากมีหน้าอื่นๆ ก็ใส่เพิ่มตรงนี้
      },
    );
  }
}
