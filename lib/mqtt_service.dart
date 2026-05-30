import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  late MqttServerClient client;

  // MQTT Broker ฟรี (HiveMQ)
  static const String brokerUrl = 'broker.hivemq.com';
  static const int brokerPort = 1883;
  static final String clientId = 'fish_monitor_app_${DateTime.now().millisecondsSinceEpoch}';

  // 📡 Topics
  static const String topicTemperature     = 'kritanai/fish/sensors/temperature';
  static const String topicPh              = 'kritanai/fish/sensors/ph';
  static const String topicOxygen          = 'kritanai/fish/sensors/oxygen';
  static const String topicTurbidity       = 'kritanai/fish/sensors/turbidity';
  static const String topicStatus          = 'kritanai/fish/status';
  static const String topicControlFeed     = 'kritanai/fish/control/feed';
  static const String topicControlLight    = 'kritanai/fish/control/light';
  static const String topicControlSettings = 'kritanai/fish/control/settings';

  bool _isConnected = false; // สถานะแอป <-> เซิร์ฟเวอร์
  bool _isConnecting = false;

  // 💓 ระบบจับชีพจรตู้ปลา (Heartbeat)
  bool _isDeviceOnline = false; // สถานะตู้ปลา <-> เซิร์ฟเวอร์
  DateTime _lastMessageTime = DateTime.now();
  Timer? _heartbeatTimer;

  Timer? _reconnectTimer;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  final _connectionStateController = StreamController<bool>.broadcast();
  final _deviceStateController = StreamController<bool>.broadcast(); // แจ้งเตือนเมื่อตู้ปลาดับ
  final _sensorDataController = StreamController<Map<String, double>>.broadcast();

  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<bool> get deviceState => _deviceStateController.stream;
  Stream<Map<String, double>> get sensorData => _sensorDataController.stream;

  // อ่านค่าสถานะว่าระบบเชื่อมต่อสมบูรณ์หรือไม่ (ต้องต่อเซิร์ฟเวอร์ติด + ตู้ปลาส่งข้อมูลมา)
  bool get isConnected => _isConnected;
  bool get isDeviceOnline => _isConnected && _isDeviceOnline;

  factory MqttService() {
    return _instance;
  }

  MqttService._internal();

  // 🔌 เชื่อมต่อ MQTT
  Future<void> connect() async {
    if (_isConnecting || _isConnected) {
      print('⚠️ MQTT: Already connecting or connected');
      return;
    }

    _isConnecting = true;

    try {
      print('🔌 MQTT: Connecting to $brokerUrl:$brokerPort...');

      client = MqttServerClient(brokerUrl, clientId);
      client.port = brokerPort;
      client.logging(on: false);  // ปิด log จะได้ไม่รกจอเกินไป

      client.keepAlivePeriod = 30;
      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;

      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;
      client.onSubscribed = _onSubscribed;
      client.onSubscribeFail = _onSubscribeFail;

      await client.connect();

      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _isConnecting = false;
        _connectionStateController.add(true);
        print('✅ MQTT: Connected to Server successfully!');

        _subscribeToTopics();
        _reconnectTimer?.cancel();

        // 💓 เริ่มจับเวลาชีพจรตู้ปลา (เช็กทุก 3 วินาที)
        _startHeartbeatMonitor();

      } else {
        throw Exception('❌ Connection failed: ${client.connectionStatus?.state}');
      }
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _isDeviceOnline = false;
      _connectionStateController.add(false);
      print('❌ MQTT Connection Error: $e');
      _scheduleReconnect();
    }
  }

  // 💓 ฟังก์ชันเฝ้าระวังชีพจรตู้ปลา
  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _lastMessageTime = DateTime.now(); // รีเซ็ตเวลาเริ่มต้น

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isConnected) return;

      // ตู้ปลาส่งข้อมูลทุกๆ 5 วินาที ถ้าหายไปเกิน 15 วินาทีแปลว่าเน็ตหลุด/ถอดปลั๊ก
      final secondsSinceLastMessage = DateTime.now().difference(_lastMessageTime).inSeconds;

      if (secondsSinceLastMessage > 15) {
        if (_isDeviceOnline) {
          print('⚠️ ตู้ปลาขาดการติดต่อ (ออฟไลน์)!');
          _isDeviceOnline = false;
          _deviceStateController.add(false);
        }
      }
    });
  }

  void _subscribeToTopics() {
    try {
      client.subscribe(topicTemperature, MqttQos.atMostOnce);
      client.subscribe(topicPh, MqttQos.atMostOnce);
      client.subscribe(topicOxygen, MqttQos.atMostOnce);
      client.subscribe(topicTurbidity, MqttQos.atMostOnce);
      client.subscribe(topicStatus, MqttQos.atMostOnce);

      print('✅ MQTT: Subscribed to all topics');

      client.updates!.listen(
            (List<MqttReceivedMessage<MqttMessage>> messages) {
          for (var message in messages) {
            final topic = message.topic;
            final payload = message.payload as MqttPublishMessage;
            final payloadBytes = payload.payload.message;
            final payloadStr = String.fromCharCodes(payloadBytes);

            // 💓 ทุกครั้งที่ได้รับข้อความ แปลว่าตู้ปลายังมีชีวิตอยู่! อัปเดตเวลาล่าสุดทันที
            _lastMessageTime = DateTime.now();
            if (!_isDeviceOnline) {
              _isDeviceOnline = true;
              _deviceStateController.add(true);
              print('🎉 ตู้ปลากลับมาออนไลน์แล้ว!');
            }

            _processSensorMessage(topic, payloadStr);
          }
        },
        onError: (error) {
          print('❌ MQTT: Error listening to messages: $error');
          _scheduleReconnect();
        },
        onDone: () {
          print('⚠️ MQTT: Message stream closed');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      print('❌ MQTT: Error subscribing to topics: $e');
      _scheduleReconnect();
    }
  }

  void _processSensorMessage(String topic, String payload) {
    try {
      final value = double.tryParse(payload) ?? 0.0;
      final sensorMap = <String, double>{};

      if (topic == topicTemperature) {
        sensorMap['temperature'] = value;
      } else if (topic == topicPh) {
        sensorMap['phValue'] = value;
      } else if (topic == topicOxygen) {
        sensorMap['oxygenLevel'] = value;
      } else if (topic == topicTurbidity) {
        sensorMap['turbidity'] = value;
      }

      if (sensorMap.isNotEmpty) {
        _sensorDataController.add(sensorMap);
      }
    } catch (e) {
      print('❌ Error processing sensor message: $e');
    }
  }

  void _onConnected() {
    print('✅ MQTT: onConnected callback');
    _isConnected = true;
    _connectionStateController.add(true);
  }

  void _onDisconnected() {
    print('⚠️ MQTT: onDisconnected callback');
    _isConnected = false;
    _isDeviceOnline = false;
    _heartbeatTimer?.cancel();
    _connectionStateController.add(false);
    _deviceStateController.add(false);
    _scheduleReconnect();
  }

  void _onSubscribed(String topic) {}

  void _onSubscribeFail(String topic) {}

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isConnected && !_isConnecting) {
        connect();
      }
    });
  }

  bool publish(String topic, String payload, {MqttQos qos = MqttQos.atMostOnce}) {
    if (!_isConnected || client.connectionStatus?.state != MqttConnectionState.connected) {
      print('⚠️ MQTT publish failed: not connected');
      return false;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    client.publishMessage(topic, qos, builder.payload!);
    print('📤 MQTT: Published to $topic -> $payload');
    return true;
  }

  bool publishJson(String topic, Map<String, dynamic> data, {MqttQos qos = MqttQos.atMostOnce}) {
    return publish(topic, jsonEncode(data), qos: qos);
  }

  void disconnect() {
    try {
      _reconnectTimer?.cancel();
      _heartbeatTimer?.cancel();
      client.disconnect();
      _isConnected = false;
      _isConnecting = false;
      _isDeviceOnline = false;
      _connectionStateController.add(false);
      print('✅ MQTT: Disconnected');
    } catch (e) {
      print('❌ Error disconnecting: $e');
    }
  }

  void dispose() {
    disconnect();
    // ❌ คอมเมนต์ปิดไว้ ห้ามทำลายท่อ Stream เพื่อป้องกัน Error: Bad state ตอนสลับหน้าจอ
    // _connectionStateController.close();
    // _deviceStateController.close();
    // _sensorDataController.close();
  }
}