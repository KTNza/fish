import 'database_service.dart';
import 'mqtt_service.dart';

class SensorDataManager {
  static final SensorDataManager _instance = SensorDataManager._internal();
  final _databaseService = DatabaseService();
  final _mqttService = MqttService();

  factory SensorDataManager() {
    return _instance;
  }

  SensorDataManager._internal();

  // เชื่อมต่อ MQTT
  Future<void> initializeMqtt() async {
    try {
      await _mqttService.connect();

      // ฟังข้อมูลจาก MQTT แล้วบันทึกลงฐานข้อมูล
      _mqttService.sensorData.listen((sensorMap) {
        _handleSensorData(sensorMap);
      });
    } catch (e) {
      print('Error initializing MQTT: $e');
    }
  }

  // จัดการข้อมูลที่ได้จาก MQTT
  void _handleSensorData(Map<String, double> sensorMap) async {
    // ดึงข้อมูล latest ลงเอก
    final latest = await getLatestSensorData();

    double temperature = latest?['temperature'] ?? 0.0;
    double ph = latest?['ph_value'] ?? 0.0;
    double oxygen = latest?['oxygen_level'] ?? 0.0;
    double turbidity = latest?['turbidity'] ?? 0.0;

    // อัปเดตด้วยค่าใหม่
    temperature = sensorMap['temperature'] ?? temperature;
    ph = sensorMap['phValue'] ?? ph;
    oxygen = sensorMap['oxygenLevel'] ?? oxygen;
    turbidity = sensorMap['turbidity'] ?? turbidity;

    // บันทึกลงฐานข้อมูล
    await _databaseService.saveSensorData(
      temperature: temperature,
      phValue: ph,
      oxygenLevel: oxygen,
      turbidity: turbidity,
    );
  }

  // บันทึกข้อมูลเซนเซอร์
  Future<int> saveSensorData({
    required double temperature,
    required double phValue,
    required double oxygenLevel,
    required double turbidity,
  }) {
    return _databaseService.saveSensorData(
      temperature: temperature,
      phValue: phValue,
      oxygenLevel: oxygenLevel,
      turbidity: turbidity,
    );
  }

  // ดึงข้อมูลเซนเซอร์ล่าสุด
  Future<Map<String, dynamic>?> getLatestSensorData() {
    return _databaseService.getLatestSensorData();
  }

  // ดึงข้อมูลเซนเซอร์ทั้งหมด
  Future<List<Map<String, dynamic>>> getAllSensorData() {
    return _databaseService.getAllSensorData();
  }

  // ดึงข้อมูลเซนเซอร์ของวันนี้
  Future<List<Map<String, dynamic>>> getTodaySensorData() {
    return _databaseService.getTodaySensorData();
  }

  // บันทึกการแจ้งเตือน
  Future<int> saveAlert({
    required String title,
    required String message,
    required String type,
  }) {
    return _databaseService.saveAlert(
      title: title,
      message: message,
      type: type,
    );
  }

  // ดึงการแจ้งเตือนทั้งหมด
  Future<List<Map<String, dynamic>>> getAllAlerts() {
    return _databaseService.getAllAlerts();
  }

  // ตรวจสอบสถานะการเชื่อมต่อ MQTT
  bool isMqttConnected() {
    return _mqttService.isConnected;
  }

  // ดึง stream สถานะการเชื่อมต่อ
  Stream<bool> getMqttConnectionStatus() {
    return _mqttService.connectionState;
  }

  // ลบข้อมูลเก่า
  Future<int> cleanOldData() {
    return _databaseService.cleanOldData();
  }

  // ปิดการเชื่อมต่อ
  void dispose() {
    _mqttService.dispose();
    _databaseService.close();
  }
}
