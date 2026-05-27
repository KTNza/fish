/*
  ESP32 MQTT Sensor Data Publisher
  ส่งข้อมูลเซนเซอร์ไปยัง HiveMQ MQTT Broker (ฟรี)
  
  📚 Libraries ที่ต้องติดตั้ง:
  1. PubSubClient by Nick O'Leary
  2. WiFi (built-in)
  
  🔧 ขั้นตอนติดตั้ง:
  1. เปิด Arduino IDE
  2. ไปที่ Sketch > Include Library > Manage Libraries
  3. ค้นหา "PubSubClient" > Install
  4. ปลั๊ก ESP32 เข้า USB
  
  ✅ การตั้งค่า:
  - แก้ไข SSID และ PASSWORD ให้ตรงกับ WiFi ของคุณ
  - ตั้งค่า Pin ตามการต่อจริง
  - Upload ลง ESP32
  - ดู Serial Monitor (115200 baud) เพื่อตรวจสอบ
*/

#include <WiFi.h>
#include <PubSubClient.h>
#include <ESP32Servo.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// ====== ⚙️ ตั้งค่า WiFi ======
const char* SSID = "Mingkwan_3BB_2.4GHz";              // 🔧 แก้เป็นชื่อ WiFi ของคุณ
const char* PASSWORD = "0856240292ming";      // 🔧 แก้เป็นรหัสผ่าน WiFi

// ====== 🌐 ตั้งค่า MQTT Broker ======
const char* MQTT_SERVER = "broker.hivemq.com";  // HiveMQ (ฟรี, ไม่ต้องสมัคร)
const int MQTT_PORT = 1883;                     // พอร์ต MQTT มาตรฐาน
const char* MQTT_CLIENT_ID = "ESP32_FishMonitor";  // ชื่อเครื่อง

// ====== 📍 ตั้งค่า Pin สำหรับเซนเซอร์ ======
// 🔧 เปลี่ยนหมายเลข pin ตามการต่อเซนเซอร์จริงของคุณ
// Sensor pin mapping (ตามการต่อของคุณ)
const int DS18B20_PIN = 4;           // DS18B20 (OneWire) -- ต่อขา D4 (ต้องมี 4.7k pull-up ระหว่าง VCC และ DATA)
const int WS2812_PIN = 5;            // WS2812B LED strip (ข้อมูล) - ต่อ D5 (ยังไม่ได้ควบคุมในสเก็ตช์นี้)
const int FEEDER_SERVO_PIN = 13;     // Servo สำหรับให้อาหาร - ต่อ D13
const int IR_PIN = 25;               // IR sensor (เช็คอาหาร) - ต่อ D25
const int TURBIDITY_SENSOR_PIN = 34; // Turbidity - ต่อ A34 (ADC)
const int PH_SENSOR_PIN = 35;        // pH sensor - ต่อ A35 (ADC)
// Oxygen sensor removed: use estimated value from temperature and pH

// ====== 📡 MQTT Topics ======
// (ต้องตรงกับ Flutter App)
const char* TOPIC_TEMPERATURE = "fish/sensors/temperature";
const char* TOPIC_PH = "fish/sensors/ph";
const char* TOPIC_OXYGEN = "fish/sensors/oxygen";
const char* TOPIC_TURBIDITY = "fish/sensors/turbidity";
const char* TOPIC_FOOD = "fish/sensors/food";
const char* TOPIC_STATUS = "fish/status";
const char* TOPIC_CONTROL_FEED = "fish/control/feed";
const char* TOPIC_CONTROL_LIGHT = "fish/control/light";
const char* TOPIC_CONTROL_SETTINGS = "fish/control/settings";

const int FAN_PIN = 18;           // Relay/drive for fan (IN1 ของโมดูลรีเลย์ ต่อเข้าขา 18)
const int FEEDER_OPEN_ANGLE = 110;
const int FEEDER_CLOSED_ANGLE = 10;
const float FAN_TEMP_ON_THRESHOLD = 29.0;  // อุณหภูมิที่พัดลมเปิด
const float FAN_TEMP_OFF_THRESHOLD = 26.0; // อุณหภูมิที่พัดลมปิด

// OneWire / DS18B20 objects
OneWire oneWire(DS18B20_PIN);
DallasTemperature ds18b20(&oneWire);

Servo feederServo;
bool isFanOn = false;
bool foodDetectedGlobal = false;

WiFiClient espClient;
PubSubClient client(espClient);

// ⏱️ ตัวแปรสำหรับ Timing
unsigned long lastSensorRead = 0;
const unsigned long SENSOR_INTERVAL = 5000;  // อ่านเซนเซอร์ทุก 5 วินาที
unsigned long lastReconnectAttempt = 0;
const unsigned long RECONNECT_INTERVAL = 10000; // พยายาม reconnect ทุก 10 วินาที

// ✅ Setup ครั้งแรกเมื่อเปิดบอร์ด
void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n╔════════════════════════════════════════╗");
  Serial.println("║   🐟 Fish Monitor ESP32 Starting... 🐟  ║");
  Serial.println("╚════════════════════════════════════════╝");
  
  // 🌐 เชื่อมต่อ WiFi
  setupWiFi();

  // 🔌 ตั้งค่า actuator, sensor และ I/O
  ds18b20.begin(); // เริ่มใช้งาน DS18B20

  feederServo.attach(FEEDER_SERVO_PIN);
  feederServo.write(FEEDER_CLOSED_ANGLE);

  pinMode(FAN_PIN, OUTPUT);
  digitalWrite(FAN_PIN, LOW);

  pinMode(IR_PIN, INPUT); // IR sensor as digital input
  
  // 📡 ตั้งค่า MQTT
  client.setServer(MQTT_SERVER, MQTT_PORT);
  client.setCallback(onMessageReceived);
  
  delay(500);
  
  // เชื่อมต่อ MQTT ครั้งแรก
  reconnectMQTT();
}

// 🔄 Loop หลัก - ทำงานซ้ำไป ๆ
void loop() {
  // ✅ ตรวจสอบการเชื่อมต่อ MQTT
  if (!client.connected()) {
    // ♻️ พยายาม reconnect ทุก 10 วินาที
    if (millis() - lastReconnectAttempt >= RECONNECT_INTERVAL) {
      lastReconnectAttempt = millis();
      reconnectMQTT();
    }
  } else {
    // 🔄 ให้ MQTT client ทำงานต่อไป
    client.loop();
    
    // 📊 อ่านและส่งข้อมูลเซนเซอร์ทุก 5 วินาที
    if (millis() - lastSensorRead >= SENSOR_INTERVAL) {
      lastSensorRead = millis();
      readAndPublishSensors();
    }
  }
}

// ====== 🌐 ฟังก์ชัน WiFi Setup ======
void setupWiFi() {
  Serial.println("\n🔌 Connecting to WiFi...");
  Serial.print("📡 SSID: ");
  Serial.println(SSID);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(SSID, PASSWORD);
  
  int attempts = 0;
  int maxAttempts = 30;  // ลองเชื่อมต่อสูงสุด 30 ครั้ง (15 วินาที)
  
  while (WiFi.status() != WL_CONNECTED && attempts < maxAttempts) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  Serial.println();
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("✅ WiFi connected!");
    Serial.print("   IP Address: ");
    Serial.println(WiFi.localIP());
    Serial.print("   Signal Strength: ");
    Serial.print(WiFi.RSSI());
    Serial.println(" dBm");
  } else {
    Serial.println("❌ Failed to connect to WiFi");
    Serial.println("   ⚠️  Check SSID and PASSWORD settings!");
  }
}

// ====== 📡 ฟังก์ชัน MQTT Reconnect ======
void reconnectMQTT() {
  // 🔄 พยายามเชื่อมต่อซ้ำ ๆ จนกว่าจะสำเร็จ
  if (!client.connected()) {
    Serial.print("🔄 Attempting MQTT connection to ");
    Serial.print(MQTT_SERVER);
    Serial.print(":");
    Serial.print(MQTT_PORT);
    Serial.print("... ");
    
    // เชื่อมต่อ MQTT (HiveMQ ไม่ต้องใช้ username/password)
    if (client.connect(MQTT_CLIENT_ID)) {
      Serial.println("✅ Connected!");
      
      // 📢 ประกาศสถานะ
      client.publish(TOPIC_STATUS, "✅ Fish Monitor ESP32 Online");
      Serial.println("   📤 Status published to MQTT");
      
      // 📥 Subscribe เพื่อรับคำสั่งจากแอป
      client.subscribe(TOPIC_CONTROL_FEED);
      client.subscribe(TOPIC_CONTROL_LIGHT);
      client.subscribe(TOPIC_CONTROL_SETTINGS);
      Serial.println("   📥 Subscribed to control topics");
      
    } else {
      Serial.print("❌ Failed. Error code: ");
      Serial.println(client.state());
      Serial.println("   ⏳ Retrying in 10 seconds...");
    }
  }
}

// ====== 📊 ฟังก์ชันอ่านและส่งข้อมูลเซนเซอร์ ======
void readAndPublishSensors() {
  Serial.println("\n📊 Reading sensors...");
  
  // 🔍 อ่านค่าเซนเซอร์
  // DS18B20 (OneWire)
  ds18b20.requestTemperatures();
  float temperature = ds18b20.getTempCByIndex(0);
  if (temperature == DEVICE_DISCONNECTED_C) {
    Serial.println("   ❌ DS18B20 not found or disconnected");
    temperature = 0.0;
  }

  // อ่านค่าอนาล็อกจากเซนเซอร์อื่น ๆ
  int rawPh = analogRead(PH_SENSOR_PIN);
  int rawTurbidity = analogRead(TURBIDITY_SENSOR_PIN);

  // แปลงค่า ADC เป็นค่าจริง (ปรับสูตรตามเซนเซอร์จริงของคุณ)
  float ph = (rawPh / 4095.0) * 14.0;              // pH 0-14
  // Estimate dissolved oxygen (mg/L) from temperature and pH
  float oxygen = estimateDissolvedOxygen(temperature, ph);
  float turbidity = (rawTurbidity / 4095.0) * 10.0; // turbidity 0-10 NTU

  // อ่านสถานะ IR (เช็คอาหาร) - ปรับ logic ตามโมดูลของคุณ
  int irRaw = digitalRead(IR_PIN);
  bool foodDetected = (irRaw == LOW); // หากเซนเซอร์ให้ LOW เมื่อมีวัตถุบนทางออก
  foodDetectedGlobal = foodDetected;

  updateFanByTemperature(temperature);

  // 📤 ส่งข้อมูลไปยัง MQTT
  publishSensorValue(TOPIC_TEMPERATURE, temperature, "🌡️ Temperature");
  publishSensorValue(TOPIC_PH, ph, "📊 pH");
  publishSensorValue(TOPIC_OXYGEN, oxygen, "💨 Oxygen");
  publishSensorValue(TOPIC_TURBIDITY, turbidity, "🌫️ Turbidity");
  // รายงานสถานะการมีอาหาร (IR)
  if (client.publish(TOPIC_FOOD, foodDetected ? "1" : "0")) {
    Serial.print("   ✅ Food sensor: ");
    Serial.println(foodDetected ? "DETECTED" : "CLEAR");
  }
  
  Serial.println("✅ All sensors published to MQTT");
}

// ====== 📤 ฟังก์ชันหนุนส่งค่าตัวเดียว ======
void publishSensorValue(const char* topic, float value, const char* name) {
  char payload[20];
  dtostrf(value, 8, 2, payload);  // แปลง float เป็น string
  
  if (client.publish(topic, payload)) {
    Serial.print("   ✅ ");
    Serial.print(name);
    Serial.print(": ");
    Serial.print(payload);
    Serial.println(" [Published OK]");
  } else {
    Serial.print("   ❌ ");
    Serial.print(name);
    Serial.println(" [Publish Failed]");
  }
}

void updateFanByTemperature(float temperature) {
  if (temperature >= FAN_TEMP_ON_THRESHOLD && !isFanOn) {
    setFanState(true);
    client.publish(TOPIC_STATUS, "✅ Fan ON - High water temperature");
  } else if (temperature <= FAN_TEMP_OFF_THRESHOLD && isFanOn) {
    setFanState(false);
    client.publish(TOPIC_STATUS, "✅ Fan OFF - Temperature normal");
  }
}

// ====== 📨 ฟังก์ชันรับข้อมูลจาก MQTT (สำหรับ 2-way communication) ======
void activateFeeder() {
  // ถ้า IR ตรวจพบอาหารค้างอยู่ ให้ข้ามการให้อาหารเพื่อหลีกเลี่ยงการอุดตัน
  if (foodDetectedGlobal) {
    Serial.println("   ⚠️ Feed skipped: food detected by IR sensor");
    client.publish(TOPIC_STATUS, "⚠️ Feed skipped - food detected");
    return;
  }

  Serial.println("   🔧 Activating feeder...");
  feederServo.write(FEEDER_OPEN_ANGLE);
  delay(1200);
  feederServo.write(FEEDER_CLOSED_ANGLE);
  delay(500);
  Serial.println("   ✅ Feeder cycle complete");
}

void setFanState(bool on) {
  Serial.print("   🔧 Setting fan: ");
  Serial.println(on ? "ON" : "OFF");
  digitalWrite(FAN_PIN, on ? HIGH : LOW);
  isFanOn = on;
}

void onMessageReceived(char* topic, byte* payload, unsigned int length) {
  Serial.print("\n📨 Message received on: ");
  Serial.println(topic);
  String message;
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.print("   Payload: ");
  Serial.println(message);
  
  if (String(topic) == TOPIC_CONTROL_FEED) {
    if (message == "feed") {
      activateFeeder();
      client.publish(TOPIC_STATUS, "✅ Feed command executed");
    }
  } else if (String(topic) == TOPIC_CONTROL_LIGHT) {
    if (message == "light_on") {
      setFanState(true);
      client.publish(TOPIC_STATUS, "✅ Fan turned on");
    } else if (message == "light_off") {
      setFanState(false);
      client.publish(TOPIC_STATUS, "✅ Fan turned off");
    }
  } else if (String(topic) == TOPIC_CONTROL_SETTINGS) {
    Serial.println("   🔧 Received settings update (ignored in this sketch)");
    client.publish(TOPIC_STATUS, "✅ Settings received");
  }
}

// ====== 🔬 ฟังก์ชันประมาณค่า Dissolved Oxygen (DO) ======
// ใช้สูตรประมาณค่าอิ่มตัวของออกซิเจน (mg/L) ตามอุณหภูมิ (empirical polynomial)
// แล้วปรับค่าด้วยผลกระทบจาก pH (ปรับเล็กน้อยเป็น factor)
// สูตรสำหรับ DO_sat เป็นสมการเชิงพหุนามประมาณค่าในช่วง 0-30 °C
float estimateDissolvedOxygen(float tempC, float pH) {
  if (tempC <= -50 || tempC >= 150 || tempC == DEVICE_DISCONNECTED_C) {
    return 0.0;
  }

  // Empirical polynomial for DO saturation (mg/L) vs temperature
  // Valid approx for 0-30°C: DO_sat = 14.652 - 0.41022*T + 0.007991*T^2 - 0.000077774*T^3
  float T = tempC;
  float DO_sat = 14.652 - 0.41022 * T + 0.007991 * T * T - 0.000077774 * T * T * T;
  if (DO_sat < 0) DO_sat = 0.0;

  // Adjust for pH effect (small modifier): assume neutral pH (~7) is baseline.
  // This is a heuristic adjustment: each pH unit away from 7 adjusts DO by ~3%.
  float pH_offset = pH - 7.0;
  float factor = 1.0 - 0.03 * pH_offset; // if pH>7 reduces slightly, if pH<7 increases slightly
  // Clamp factor to reasonable bounds
  if (factor < 0.75) factor = 0.75;
  if (factor > 1.05) factor = 1.05;

  float estimatedDO = DO_sat * factor;
  // Clamp final value
  if (estimatedDO < 0) estimatedDO = 0.0;
  if (estimatedDO > 20.0) estimatedDO = 20.0;
  return estimatedDO;
}

/*
  ════════════════════════════════════════════════════════
  📋 ข้อมูลติดตั้งและแก้ไขปัญหา
  ════════════════════════════════════════════════════════
  
  1️⃣ ก่อนอัพโหลดโค้ด:
     - แก้ SSID และ PASSWORD ให้ตรงกับ WiFi จริง
     - เลือกบอร์ด: ESP32 Dev Module
     - ตั้ง Baud Rate: 115200
  
  2️⃣ หากเซนเซอร์อ่านค่าผิด:
     - ตรวจสอบการต่อ Pin ให้ถูกต้อง
     - ใช้ analogRead(PIN) เพื่อตรวจสอบค่า Raw
     - ปรับสูตรการแปลงค่า (linear conversion)
     - บางเซนเซอร์ต้องใช้ library เฉพาะ (เช่น I2C, DS18B20)
  
  3️⃣ หากไม่เชื่อมต่อ MQTT:
     - ตรวจสอบ WiFi ได้ไหม (ดู Serial Monitor)
     - ตรวจสอบ MQTT_SERVER และ MQTT_PORT
     - ทดลองใช้ MQTT Explorer เพื่อทดสอบ Broker
     - ตรวจสอบ firewall
  
  4️⃣ ข้อมูล Topics (ต้องตรงกับ Flutter App):
     - fish/sensors/temperature  -> ค่าอุณหภูมิ
     - fish/sensors/ph           -> ค่า pH
     - fish/sensors/oxygen       -> ค่าออกซิเจน
     - fish/sensors/turbidity    -> ค่าความขุ่น
     - fish/status               -> สถานะการเชื่อมต่อ
  
  5️⃣ การทดสอบ MQTT:
     - ใช้ MQTT Explorer: http://mqtt-explorer.com/
     - เชื่อมต่อไปที่ broker.hivemq.com:1883
     - Subscribe ไปที่ fish/sensors/# เพื่อดูข้อมูล
  
  6️⃣ หมายเหตุสำคัญ:
     - โค้ดนี้ส่งข้อมูลทุก 5 วินาที
     - หากเซนเซอร์ใช้ I2C ต้องใช้ Wire library
     - สำหรับเซนเซอร์ดิจิตอล (DS18B20) ต้องติดตั้ง library เพิ่มเติม
  
  ════════════════════════════════════════════════════════
*/
