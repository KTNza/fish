import 'dart:async';
import 'database_service.dart';
import 'mqtt_service.dart';

class SensorDataManager {
  static final SensorDataManager _instance = SensorDataManager._internal();
  final _databaseService = DatabaseService();
  final _mqttService = MqttService();

  // ✅ Stream ส่งตรงไป UI ทันที ไม่ผ่าน DB
  final _sensorStreamController = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get sensorStream => _sensorStreamController.stream;

  // ✅ เก็บค่าล่าสุดในหน่วยความจำ ไม่ต้อง query DB
  final Map<String, double> _latestValues = {
    'temperature': 0.0,
    'phValue':     0.0,
    'oxygenLevel': 0.0,
    'turbidity':   0.0,
  };

  // ✅ เพิ่มตัวแปรเก็บเวลาที่บันทึกลง DB ครั้งล่าสุด และตั้งค่าความถี่
  DateTime? _lastDbSaveTime;
  final int _dbSaveIntervalMinutes = 5; // กำหนดให้บันทึกลงฐานข้อมูลทุกๆ 5 นาที

  factory SensorDataManager() => _instance;
  SensorDataManager._internal();

  Future<void> initializeMqtt() async {
    try {
      await _mqttService.connect();
      _mqttService.sensorData.listen(_handleSensorData);
    } catch (e) {
      print('Error initializing MQTT: $e');
    }
  }

  // ✅ เพิ่มฟังก์ชันแปลง Voltage เป็น NTU ก่อนเซฟลง DB (อัปเดตค่า Calibration ล่าสุดจากไฟอะแดปเตอร์)
  double _convertVoltageToNTU(double voltage) {
    double clearVoltage = 3.65; // น้ำใสสุดที่วัดได้
    double muddyVoltage = 0.20; // น้ำขุ่นมิดที่วัดได้

    if (voltage >= clearVoltage) return 0.0;
    if (voltage <= muddyVoltage) return 100.0;

    return ((clearVoltage - voltage) / (clearVoltage - muddyVoltage)) * 100.0;
  }

  void _handleSensorData(Map<String, double> sensorMap) {
    // ✅ merge ค่าใหม่เข้า _latestValues (ใน memory ทันที)
    if (sensorMap['temperature'] != null) _latestValues['temperature'] = sensorMap['temperature']!;
    if (sensorMap['phValue']     != null) _latestValues['phValue']     = sensorMap['phValue']!;
    if (sensorMap['oxygenLevel'] != null) _latestValues['oxygenLevel'] = sensorMap['oxygenLevel']!;
    if (sensorMap['turbidity']   != null) _latestValues['turbidity']   = sensorMap['turbidity']!; // เก็บเป็น Raw Voltage

    // ✅ ยิงไป UI ทันที (UI จะอัปเดตแบบ Real-time ตลอดเวลาที่ MQTT ส่งมา)
    _sensorStreamController.add(Map.from(_latestValues));

    // ✅ เช็คเวลาก่อนเซฟลง DB แบบ fire-and-forget
    final now = DateTime.now();
    bool shouldSaveToDb = _lastDbSaveTime == null ||
        now.difference(_lastDbSaveTime!).inMinutes >= _dbSaveIntervalMinutes;

    if (shouldSaveToDb) {
      // 🚨 แปลงความขุ่นจาก Voltage เป็น NTU ก่อนเซฟลง Database 🚨
      double turbNTU = _convertVoltageToNTU(_latestValues['turbidity']!);

      _databaseService.saveSensorData(
        temperature:  _latestValues['temperature']!,
        phValue:      _latestValues['phValue']!,
        oxygenLevel:  _latestValues['oxygenLevel']!,
        turbidity:    turbNTU, // เซฟเป็น NTU ลงฐานข้อมูล
      ).then((_) {
        // บันทึกเวลาล่าสุดเมื่อทำการเซฟสำเร็จ
        _lastDbSaveTime = now;
        print("💾 [DB] Saved sensor data at $now");
      }).catchError((e) {
        print("❌ [DB] Error saving data: $e");
      });
    }
  }

  // ====================================================
  // ส่วนที่เหลือเหมือนเดิมทุกอย่าง สามารถเรียกใช้งานได้ปกติ
  // ====================================================

  Future<int> saveSensorData({required double temperature, required double phValue, required double oxygenLevel, required double turbidity}) {
    return _databaseService.saveSensorData(temperature: temperature, phValue: phValue, oxygenLevel: oxygenLevel, turbidity: turbidity);
  }

  Future<Map<String, dynamic>?> getLatestSensorData() => _databaseService.getLatestSensorData();

  Future<List<Map<String, dynamic>>> getAllSensorData() => _databaseService.getAllSensorData();

  Future<List<Map<String, dynamic>>> getTodaySensorData() => _databaseService.getTodaySensorData();

  Future<int> saveAlert({required String title, required String message, required String type}) => _databaseService.saveAlert(title: title, message: message, type: type);

  Future<List<Map<String, dynamic>>> getAllAlerts() => _databaseService.getAllAlerts();

  bool isMqttConnected() => _mqttService.isConnected;

  Stream<bool> getMqttConnectionStatus() => _mqttService.connectionState;

  Future<int> cleanOldData() => _databaseService.cleanOldData();

  void dispose() {
    // ❌ คอมเมนต์ปิดไว้ Service พวกนี้เราต้องใช้ตลอดชีพ ห้ามปิดท่อ Stream เด็ดขาด
    // _sensorStreamController.close();
    // _mqttService.dispose();

    // ส่วน DB จะปิดหรือไม่ปิดก็ได้ แต่สำหรับ Singleton แนะนำให้เปิดค้างไว้เลยจะเสถียรกว่าครับ
    // _databaseService.close();
  }
}