import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:async';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  late MqttServerClient client;

  // MQTT Broker ฟรี
  static const String brokerUrl = 'broker.hivemq.com';
  static const int brokerPort = 1883;
  static const String clientId = 'fish_monitor_app';

  // Topics
  static const String topicTemperature = 'fish/sensors/temperature';
  static const String topicPh = 'fish/sensors/ph';
  static const String topicOxygen = 'fish/sensors/oxygen';
  static const String topicTurbidity = 'fish/sensors/turbidity';
  static const String topicStatus = 'fish/status';

  bool _isConnected = false;
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

  Future<void> connect() async {
    try {
      client = MqttServerClient(brokerUrl, clientId);
      client.port = brokerPort;

      // ตั้งค่า connection
      client.keepAlivePeriod = 30;
      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;
      client.onSubscribed = _onSubscribed;

      // เชื่อมต่อ
      await client.connect();

      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _connectionStateController.add(true);

        // Subscribe กับ topics
        _subscribeToTopics();
      } else {
        disconnect();
        throw Exception(
            'Failed to connect: ${client.connectionStatus?.state}');
      }
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      print('MQTT Connection Error: $e');
      rethrow;
    }
  }

  void _subscribeToTopics() {
    client.subscribe(topicTemperature, MqttQos.atMostOnce);
    client.subscribe(topicPh, MqttQos.atMostOnce);
    client.subscribe(topicOxygen, MqttQos.atMostOnce);
    client.subscribe(topicTurbidity, MqttQos.atMostOnce);

    // รับข้อมูล
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (var message in messages) {
        final topic = message.topic;
        final payload = message.payload as MqttPublishMessage;
        final payloadBytes = payload.payload.message;
        final payloadStr = String.fromCharCodes(payloadBytes);

        _processSensorMessage(topic, payloadStr);
      }
    });
  }

  void _processSensorMessage(String topic, String payload) {
    try {
      final value = double.tryParse(payload) ?? 0.0;

      // สร้าง map ของข้อมูลเซนเซอร์
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
      print('Error processing sensor message: $e');
    }
  }

  void _onConnected() {
    print('MQTT Connected');
  }

  void _onDisconnected() {
    _isConnected = false;
    _connectionStateController.add(false);
    print('MQTT Disconnected');
  }

  void _onSubscribed(String topic) {
    print('Subscribed to: $topic');
  }

  void disconnect() {
    client.disconnect();
    _isConnected = false;
    _connectionStateController.add(false);
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _sensorDataController.close();
  }
}
