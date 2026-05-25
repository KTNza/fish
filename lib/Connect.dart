import 'package:flutter/material.dart';
import 'dashbord.dart';
import 'settime.dart';

// หน้าจอเชื่อมต่อ
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  int _selectedIndex = 2; // เลือก ปุ่มขวาสุด
  bool _isConnected = false;
  bool _isSearching = false;
  String? _connectedDevice;
  
  // อุปกรณ์ที่พบหลังจากสแกน (จะเติมจาก Bluetooth scan จริง)
  final List<Map<String, String>> _availableDevices = [];

  // ฟังก์ชันค้นหาอุปกรณ์
  void _scanDevices() {
    if (_isSearching) return;
    
    setState(() {
      _isSearching = true;
    });
    
    // TODO: เชื่อมต่อกับ platform-specific code เพื่อสแกนอุปกรณ์ Bluetooth
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isSearching = false;
          // _availableDevices = resultFromBluetoothScan;
        });
      }
    });
  }

  // ฟังก์ชันเชื่อมต่ออุปกรณ์
  void _connectToDevice(String deviceName, String deviceAddress) {
    setState(() {
      _connectedDevice = deviceName;
      _isConnected = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connected to $deviceName'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ฟังก์ชันตัดการเชื่อมต่อ
  void _disconnect() {
    setState(() {
      _connectedDevice = null;
      _isConnected = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200], // พื้นหลังสีเทาอ่อน
        automaticallyImplyLeading: false, // เอาปุ่ม back ออก
        backgroundColor: Colors.grey[200],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black54),
            onPressed: () {
              Navigator.pushNamed(context, '/notification');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        // ขยับทุกอย่างลงมาโดยเพิ่ม padding ด้านบน
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20), // เพิ่มระยะห่างด้านบน
        child: Column(
          children: [
            // ปุ่มค้นหาอุปกรณ์
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSearching ? null : _scanDevices,
                icon: _isSearching 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.search),
                label: Text(_isSearching ? 'Searching...' : 'Search Devices'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003C7E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // ส่วนแสดงสถานะการเชื่อมต่อ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.router,
                    size: 56,
                    color: Color(0xFF003C7E),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isConnected ? 'Connected' : 'Not Connected',
                    style: TextStyle(
                      color: _isConnected ? Colors.green : Colors.red,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_connectedDevice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'เชื่อมต่อแล้ว 1 ตู้',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_connectedDevice',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (_isConnected)
                    Column(
                      children: [
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _disconnect,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Disconnect'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // รายการอุปกรณ์ที่พบ
            Text(
              'Available Devices',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: Text(
                _availableDevices.isEmpty
                  ? 'ยังไม่มีอุปกรณ์ตัวอย่าง แสดงผลเฉพาะเมื่อสแกนและเชื่อมต่อกับเต้าใช้งานจริง'
                  : 'พบอุปกรณ์ ${_availableDevices.length} ชิ้น',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
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
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SetTimePage()),
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
