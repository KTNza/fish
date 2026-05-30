import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashbord.dart';
import 'Notification.dart';
import 'notification_service.dart';
import 'settime.dart';
import 'mqtt_service.dart';
import 'sensor_data_manager.dart';

// ==========================================
// Design tokens — ตรงกับ Dashboard / SetTimePage
// ==========================================
class _C {
  static const navy      = Color(0xFF1A2340);
  static const teal      = Color(0xFF4DB6AC);
  static const bg        = Color(0xFFF0F4F8);
  static const white     = Colors.white;
  static const danger    = Color(0xFFE57373);
  static const warn      = Color(0xFFFFB74D);
  static const success   = Color(0xFF4DB6AC);
}

// ==========================================
// ConnectPage
// ==========================================
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 2;

  bool _isConnecting = false;
  bool _isConnected  = false;
  Timer? _statusCheckTimer;

  // ── ของเดิมที่หายไป ──
  final SensorDataManager _sensorManager = SensorDataManager();
  final List<Map<String, String>> _notifications = [];

  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // โหลด notification history
    _notifications
      ..clear()
      ..addAll(NotificationService().notificationHistory);

    // เริ่ม sensor listener (สำคัญ — ให้ MQTT ทำงานต่อเนื่อง)
    _sensorManager.initializeMqtt();

    _checkConnectionStatus();

    if (!MqttService().isConnected && !_isConnecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconnect());
    }

    _statusCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkConnectionStatus();
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _pulseController.dispose();
    // ไม่ dispose _sensorManager เพราะเป็น singleton ที่ใช้ร่วมกับหน้าอื่น
    super.dispose();
  }

  void _checkConnectionStatus() {
    final online = MqttService().isDeviceOnline;
    if (mounted && _isConnected != online) {
      setState(() => _isConnected = online);
    }
  }

  Future<void> _reconnect() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);

    try {
      await MqttService().connect();
    } catch (e) {
      debugPrint('Connection failed: $e');
    }

    await Future.delayed(const Duration(seconds: 2));
    _checkConnectionStatus();

    if (mounted) {
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _isConnected ? '✅ พบสัญญาณจากตู้ปลา!' : '❌ ไม่พบสัญญาณตู้ปลา',
        ),
        backgroundColor: _isConnected ? _C.teal : _C.danger,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // [FIX] Navigator เหมือน Dashboard
  void _onNavTap(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      ).then((_) { if (mounted) setState(() => _selectedIndex = 2); });
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetTimePage()),
      ).then((_) { if (mounted) setState(() => _selectedIndex = 2); });
    }
  }

  // ──────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // สีและข้อความตามสถานะ
    final Color accentColor = _isConnecting
        ? _C.warn
        : _isConnected
        ? _C.teal
        : _C.danger;

    final IconData statusIcon = _isConnecting
        ? Icons.wifi_find_rounded
        : _isConnected
        ? Icons.wifi_rounded
        : Icons.wifi_off_rounded;

    final String statusTitle = _isConnecting
        ? 'กำลังค้นหาตู้ปลา...'
        : _isConnected
        ? 'เชื่อมต่อสำเร็จ'
        : 'ขาดการเชื่อมต่อ';

    final String statusSub = _isConnected
        ? 'รับ-ส่งข้อมูล Real-time\nผ่าน HiveMQ Broker'
        : 'ไม่พบสัญญาณจากบอร์ด ESP32\nโปรดตรวจสอบการเสียบปลั๊กที่ตู้ปลา';

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
                  // ── Status card ──
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: _C.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(
                          color: accentColor.withOpacity(0.25), width: 1.5),
                    ),
                    child: Column(children: [
                      // animated pulse icon
                      ScaleTransition(
                        scale: _isConnecting ? _pulseAnimation
                            : const AlwaysStoppedAnimation(1.0),
                        child: Container(
                          width: 96, height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor.withOpacity(0.10),
                          ),
                          child: Icon(statusIcon,
                              size: 48, color: accentColor),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // status label pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: accentColor),
                          ),
                          const SizedBox(width: 6),
                          Text(statusTitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              )),
                        ]),
                      ),

                      const SizedBox(height: 12),

                      Text(statusSub,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black.withOpacity(0.4),
                            height: 1.6,
                          )),

                      const SizedBox(height: 28),

                      // reconnect button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isConnecting ? null : _reconnect,
                          icon: _isConnecting
                              ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                              strokeWidth: 2,
                            ),
                          )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            _isConnecting ? 'กำลังเชื่อมต่อ...' : 'Reconnect System',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.navy,
                            foregroundColor: _C.white,
                            disabledBackgroundColor:
                            _C.navy.withOpacity(0.4),
                            disabledForegroundColor: _C.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // ── Info tiles ──
                  _buildInfoTile(
                    icon: Icons.router_rounded,
                    label: 'Broker',
                    value: 'HiveMQ Public',
                    accentColor: _C.teal,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoTile(
                    icon: Icons.developer_board_rounded,
                    label: 'Device',
                    value: 'ESP32 Smart Betta',
                    accentColor: const Color(0xFF64B5F6),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoTile(
                    icon: Icons.sync_rounded,
                    label: 'Protocol',
                    value: 'MQTT v3.1.1',
                    accentColor: const Color(0xFFCE93D8),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  // ──────────────────────────────────────
  // Header — เหมือน Dashboard
  // ──────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 4),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Connection', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800,
            color: _C.navy, letterSpacing: -0.5,
          )),
          Text('สถานะการเชื่อมต่อระบบ', style: TextStyle(
            fontSize: 12, color: Colors.black38,
            fontWeight: FontWeight.w500,
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
                    child: Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                          color: Color(0xFFFF5252),
                          shape: BoxShape.circle),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  // ──────────────────────────────────────
  // Info tile
  // ──────────────────────────────────────
  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.20), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accentColor, size: 18),
        ),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Colors.black.withOpacity(0.4),
                fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _C.navy)),
      ]),
    );
  }

  // ──────────────────────────────────────
  // Bottom nav — เหมือน Dashboard
  // ──────────────────────────────────────
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
              _NavItem(icon: Icons.history_rounded,  label: 'ประวัติ',  selected: _selectedIndex == 1, onTap: () => _onNavTap(1)),
              _NavItem(icon: Icons.settings_rounded, label: 'ตั้งค่า',  selected: _selectedIndex == 2, onTap: () => _onNavTap(2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────
// _NavItem (shared style)
// ──────────────────────────────────────
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
          color: selected
              ? Colors.white.withOpacity(0.12)
              : Colors.transparent,
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