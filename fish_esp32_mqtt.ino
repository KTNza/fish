/*
  ESP32 MQTT Sensor Data Publisher
  ส่งข้อมูลเซนเซอร์ไปยัง HiveMQ MQTT Broker (ฟรี)
  
  Libraries ที่ต้องติดตั้ง:
  - PubSubClient (ค้นหาใน Arduino IDE: Sketch > Include Library > Manage Libraries)
  - WiFi (built-in)
  
  ขั้นตอนติดตั้ง:
  1. เปิด Arduino IDE
  2. ไปที่ Sketch > Include Library > Manage Libraries
  3. ค้นหา "PubSubClient" โดย Nick O'Leary
  4. คลิก Install
*/

#include <WiFi.h>
#include <PubSubClient.h>

// ====== ตั้งค่า WiFi ======
const char* SSID = "YOUR_SSID";              // ชื่อ WiFi ของคุณ
const char* PASSWORD = "YOUR_PASSWORD";      // รหัสผ่าน WiFi

// ====== ตั้งค่า MQTT ======
const char* MQTT_SERVER = "broker.hivemq.com";  // HiveMQ Public Broker (ฟรี)
const int MQTT_PORT = 1883;

// ====== ตั้งค่าเซนเซอร์ ======
// เปลี่ยนหมายเลข pin ตามที่ต่อเซนเซอร์จริง
const int TEMP_SENSOR_PIN = 34;      // ADC pin สำหรับเซนเซอร์อุณหภูมิ
const int PH_SENSOR_PIN = 35;        // ADC pin สำหรับเซนเซอร์ pH
const int OXYGEN_SENSOR_PIN = 32;    // ADC pin สำหรับเซนเซอร์ออกซิเจน
const int TURBIDITY_SENSOR_PIN = 33; // ADC pin สำหรับเซนเซอร์ความขุ่น

// ====== MQTT Topics ======
const char* TOPIC_TEMPERATURE = "fish/sensors/temperature";
const char* TOPIC_PH = "fish/sensors/ph";
const char* TOPIC_OXYGEN = "fish/sensors/oxygen";
const char* TOPIC_TURBIDITY = "fish/sensors/turbidity";
const char* TOPIC_STATUS = "fish/status";

WiFiClient espClient;
PubSubClient client(espClient);

// ตัวแปร
unsigned long lastSensorRead = 0;
const unsigned long SENSOR_INTERVAL = 5000; // อ่านเซนเซอร์ทุก 5 วินาที

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\nStarting Fish Monitor ESP32...");
  
  // เชื่อมต่อ WiFi
  setupWiFi();
  
  // ตั้งค่า MQTT
  client.setServer(MQTT_SERVER, MQTT_PORT);
  client.setCallback(onMessageReceived);
  
  // เชื่อมต่อ MQTT
  reconnectMQTT();
}

void loop() {
  // ตรวจสอบการเชื่อมต่อ MQTT
  if (!client.connected()) {
    reconnectMQTT();
  }
  client.loop();
  
  // อ่านเซนเซอร์ทุก 5 วินาที
  if (millis() - lastSensorRead >= SENSOR_INTERVAL) {
    lastSensorRead = millis();
    readAndPublishSensors();
  }
}

// ====== WiFi Setup ======
void setupWiFi() {
  Serial.print("Connecting to WiFi: ");
  Serial.println(SSID);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(SSID, PASSWORD);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected!");
    Serial.print("IP Address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nFailed to connect to WiFi");
  }
}

// ====== MQTT Reconnect ======
void reconnectMQTT() {
  while (!client.connected()) {
    Serial.print("Attempting MQTT connection...");
    
    // เชื่อมต่อโดยไม่ต้อง username/password (HiveMQ ฟรี)
    if (client.connect("ESP32_FishMonitor")) {
      Serial.println("connected!");
      
      // ประกาศสถานะ
      client.publish(TOPIC_STATUS, "Fish Monitor ESP32 Connected");
      
      // Subscribe (ถ้าต้องการรับคำสั่งจาก Flutter)
      // client.subscribe("fish/commands");
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      Serial.println(" try again in 5 seconds");
      delay(5000);
    }
  }
}

// ====== อ่านและส่งข้อมูลเซนเซอร์ ======
void readAndPublishSensors() {
  // อ่านค่า ADC (0-4095)
  int rawTemp = analogRead(TEMP_SENSOR_PIN);
  int rawPh = analogRead(PH_SENSOR_PIN);
  int rawOxygen = analogRead(OXYGEN_SENSOR_PIN);
  int rawTurbidity = analogRead(TURBIDITY_SENSOR_PIN);
  
  // แปลงค่าเป็นหน่วยที่ใช้จริง
  // ⚠️ ต้องแก้ไขสูตรตามเซนเซอร์จริงของคุณ
  
  // อุณหภูมิ (0-50°C)
  float temperature = (rawTemp / 4095.0) * 50.0;
  
  // pH (0-14)
  float ph = (rawPh / 4095.0) * 14.0;
  
  // ออกซิเจน (0-20 mg/L)
  float oxygen = (rawOxygen / 4095.0) * 20.0;
  
  // ความขุ่น (0-10 NTU)
  float turbidity = (rawTurbidity / 4095.0) * 10.0;
  
  // ส่งข้อมูล MQTT (ส่งเป็น string)
  char payload[10];
  
  // ส่งอุณหภูมิ
  dtostrf(temperature, 5, 2, payload);
  client.publish(TOPIC_TEMPERATURE, payload);
  Serial.print("Published Temperature: ");
  Serial.println(payload);
  
  // ส่ง pH
  dtostrf(ph, 5, 2, payload);
  client.publish(TOPIC_PH, payload);
  Serial.print("Published pH: ");
  Serial.println(payload);
  
  // ส่งออกซิเจน
  dtostrf(oxygen, 5, 2, payload);
  client.publish(TOPIC_OXYGEN, payload);
  Serial.print("Published Oxygen: ");
  Serial.println(payload);
  
  // ส่งความขุ่น
  dtostrf(turbidity, 5, 2, payload);
  client.publish(TOPIC_TURBIDITY, payload);
  Serial.print("Published Turbidity: ");
  Serial.println(payload);
  
  // ส่งคำสั่งตรวจสอบสถานะ
  client.publish(TOPIC_STATUS, "Reading sensors...");
}

// ====== รับข้อมูลจาก MQTT (ถ้ามี) ======
void onMessageReceived(char* topic, byte* payload, unsigned int length) {
  Serial.print("Message received on topic: ");
  Serial.println(topic);
  Serial.print("Payload: ");
  for (unsigned int i = 0; i < length; i++) {
    Serial.print((char)payload[i]);
  }
  Serial.println();
}

/*
  ====== ข้อมูลสำคัญ ======
  
  1. ค่า Raw ADC (0-4095) ต้องแปลงเป็นค่าจริง
     - อุณหภูมิ: ทำให้สามารถเปลี่ยนแปลง 0-50°C
     - pH: 0-14
     - ออกซิเจน: 0-20 mg/L
     - ความขุ่น: 0-10 NTU
  
  2. หากใช้ Analog Sensors ต่อ ADC แบบตรงๆ
     ต้องแปลงตามคุณสมบัติของเซนเซอร์จริง
     
  3. หากใช้ Digital Sensors (I2C, SPI)
     ต้องเปลี่ยนโค้ดการอ่านข้อมูล
  
  4. เมื่อต่อเสร็จแล้ว:
     - เปลี่ยน SSID และ PASSWORD
     - อัพโหลดโค้ดลงบอร์ด ESP32
     - เปิด Serial Monitor เพื่อดูข้อมูล
     - ตรวจสอบว่ามีการส่งข้อมูล MQTT ได้
*/
