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

  void _handleSensorData(Map<String, double> sensorMap) {
    // ✅ merge ค่าใหม่เข้า _latestValues (ใน memory ทันที)
    if (sensorMap['temperature'] != null) _latestValues['temperature'] = sensorMap['temperature']!;
    if (sensorMap['phValue']     != null) _latestValues['phValue']     = sensorMap['phValue']!;
    if (sensorMap['oxygenLevel'] != null) _latestValues['oxygenLevel'] = sensorMap['oxygenLevel']!;
    if (sensorMap['turbidity']   != null) _latestValues['turbidity']   = sensorMap['turbidity']!;

    // ✅ ยิงไป UI ทันที
    _sensorStreamController.add(Map.from(_latestValues));

    // ✅ บันทึก DB แบบ fire-and-forget ไม่บล็อก
    _databaseService.saveSensorData(
      temperature:  _latestValues['temperature']!,
      phValue:      _latestValues['phValue']!,
      oxygenLevel:  _latestValues['oxygenLevel']!,
      turbidity:    _latestValues['turbidity']!,
    );
  }

  // ที่เหลือเหมือนเดิมทุกอย่าง
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