import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // ตั้งเวลา 3 วินาที แล้วค่อยเปลี่ยนไปหน้า dashboard
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacementNamed(context, '/dashboard');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0052CC), // สีน้ำเงิน
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- ส่วนของรูปภาพที่มีกรอบ ---
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle, // ทำให้กรอบเป็นวงกลม
                border: Border.all(
                  color: Colors.grey.shade300, // สีของเส้นขอบ
                  width: 4, // ความหนาของเส้นขอบ
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.cover,
                  width: 162,
                  height: 162,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.image_not_supported,
                      color: Colors.grey,
                      size: 80,
                    );
                  },
                ),
              ),
            ),
            // ------------------------------------
            const SizedBox(height: 24),
            // --- ส่วนที่แก้ไขเพื่อเพิ่มเส้นขอบ (Stroke) ให้ตัวหนังสือ ---
            Stack(
              children: <Widget>[
                // ตัวหนังสือชั้นล่าง (เส้นขอบ)
                Text(
                  'SMART BETTA FISH\nBREEDING TANK',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900, // ทำให้เส้นขอบหนา
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 2.5 // ความหนาของเส้นขอบ
                      ..color = Colors.black.withOpacity(0.6), // สีของเส้นขอบ
                  ),
                ),
                // ตัวหนังสือชั้นบน (สีปกติ)
                const Text(
                  'SMART BETTA FISH\nBREEDING TANK',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900, // ทำให้ตัวหนังสือหนา
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            // ----------------------------------------------------
          ],
        ),
      ),
    );
  }
}

