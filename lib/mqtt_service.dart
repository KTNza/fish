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

  // 📡 Topics (ต้องตรงกับ Arduino code)
  static const String topicTemperature = 'fish/sensors/temperature';
  static const String topicPh = 'fish/sensors/ph';
  static const String topicOxygen = 'fish/sensors/oxygen';
  static const String topicTurbidity = 'fish/sensors/turbidity';
  static const String topicStatus = 'fish/status';
  static const String topicControlFeed = 'fish/control/feed';
  static const String topicControlLight = 'fish/control/light';
  static const String topicControlSettings = 'fish/control/settings';

  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  final _connectionStateController = StreamController<bool>.broadcast();
  final _sensorDataController =
      StreamController<Map<String, double>>.broadcast();

  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<Map<String, double>> get sensorData => _sensorDataController.stream;

  bool get isConnected => _isConnected;

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
      client.logging(on: true);  // 🔍 เปิด logging สำหรับ debugging

      // ⚙️ ตั้งค่า connection
      client.keepAlivePeriod = 30;
      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;

      // 📍 ตั้งค่า callbacks
      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;
      client.onSubscribed = _onSubscribed;
      client.onSubscribeFail = _onSubscribeFail;

      // 📡 เชื่อมต่อ
      await client.connect();

      // ✅ ตรวจสอบสถานะ
      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _isConnecting = false;
        _connectionStateController.add(true);
        print('✅ MQTT: Connected successfully!');

        // 📥 Subscribe กับ topics
        _subscribeToTopics();

        // 🔄 ยกเลิก reconnect timer
        _reconnectTimer?.cancel();
      } else {
        throw Exception(
            '❌ Connection failed: ${client.connectionStatus?.state}');
      }
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _connectionStateController.add(false);
      print('❌ MQTT Connection Error: $e');

      // 🔄 พยายาม reconnect
      _scheduleReconnect();
    }
  }

  // 📥 Subscribe กับ topics
  void _subscribeToTopics() {
    try {
      client.subscribe(topicTemperature, MqttQos.atMostOnce);
      client.subscribe(topicPh, MqttQos.atMostOnce);
      client.subscribe(topicOxygen, MqttQos.atMostOnce);
      client.subscribe(topicTurbidity, MqttQos.atMostOnce);
      client.subscribe(topicStatus, MqttQos.atMostOnce);

      print('✅ MQTT: Subscribed to all topics');

      // 📨 รับข้อมูล
      client.updates!.listen(
        (List<MqttReceivedMessage<MqttMessage>> messages) {
          for (var message in messages) {
            final topic = message.topic;
            final payload = message.payload as MqttPublishMessage;
            final payloadBytes = payload.payload.message;
            final payloadStr = String.fromCharCodes(payloadBytes);

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

  // 🧮 ประมวลผลข้อมูลจากเซนเซอร์
  void _processSensorMessage(String topic, String payload) {
    try {
      final value = double.tryParse(payload) ?? 0.0;
      final sensorMap = <String, double>{};

      if (topic == topicTemperature) {
        sensorMap['temperature'] = value;
        print('📊 Temperature: $value°C');
      } else if (topic == topicPh) {
        sensorMap['phValue'] = value;
        print('📊 pH: $value');
      } else if (topic == topicOxygen) {
        sensorMap['oxygenLevel'] = value;
        print('📊 Oxygen: $value mg/L');
      } else if (topic == topicTurbidity) {
        sensorMap['turbidity'] = value;
        print('📊 Turbidity: $value NTU');
      } else if (topic == topicStatus) {
        print('📊 Status: $payload');
      }

      if (sensorMap.isNotEmpty) {
        _sensorDataController.add(sensorMap);
      }
    } catch (e) {
      print('❌ Error processing sensor message: $e');
    }
  }

  // 🔄 Callbacks
  void _onConnected() {
    print('✅ MQTT: onConnected callback');
    _isConnected = true;
    _connectionStateController.add(true);
  }

  void _onDisconnected() {
    print('⚠️ MQTT: onDisconnected callback');
    _isConnected = false;
    _connectionStateController.add(false);
    _scheduleReconnect();
  }

  void _onSubscribed(String topic) {
    print('✅ MQTT: Subscribed to $topic');
  }

  void _onSubscribeFail(String topic) {
    print('❌ MQTT: Failed to subscribe to $topic');
  }

  // ⏱️ ตั้งเวลา reconnect
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    print('⏳ MQTT: Scheduling reconnect in ${_reconnectDelay.inSeconds}s...');
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isConnected && !_isConnecting) {
        connect();
      }
    });
  }

  // � Publish a plain-text message
  bool publish(String topic, String payload,
      {MqttQos qos = MqttQos.atMostOnce}) {
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

  bool publishJson(String topic, Map<String, dynamic> data,
      {MqttQos qos = MqttQos.atMostOnce}) {
    return publish(topic, jsonEncode(data), qos: qos);
  }

  // �🔌 Disconnect
  void disconnect() {
    try {
      _reconnectTimer?.cancel();
      client.disconnect();
      _isConnected = false;
      _isConnecting = false;
      _connectionStateController.add(false);
      print('✅ MQTT: Disconnected');
    } catch (e) {
      print('❌ Error disconnecting: $e');
    }
  }

  // 🧹 Cleanup
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _sensorDataController.close();
  }
}
