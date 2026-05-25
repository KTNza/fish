# Fish Monitor - MQTT + SQLite Setup Guide

## 📱 Flutter App Setup

### 1. เพิ่ม Dependencies
ขั้นตอนการเพิ่ม dependencies ได้ทำแล้ว:
- `sqflite` - ฐานข้อมูล SQLite
- `mqtt_client` - เชื่อมต่อ MQTT
- `path` - จัดการเส้นทาง

### 2. ไฟล์ที่สร้างใหม่
```
lib/
  ├── database_service.dart        # บริการฐานข้อมูล SQLite
  ├── mqtt_service.dart            # บริการเชื่อมต่อ MQTT
  ├── sensor_data_manager.dart     # จัดการข้อมูลเซนเซอร์
  └── dashbord.dart               # อัปเดตแล้ว
```

### 3. คุณสมบัติ
✅ เชื่อมต่อ MQTT (HiveMQ ฟรี)
✅ เก็บข้อมูลเซนเซอร์ใน SQLite
✅ เก็บประวัติการแจ้งเตือน
✅ ซิงค์แบบเรียลไทม์
✅ ทำงานแม้ปิดแอป (ข้อมูลไม่หาย)

---

## 🔌 ESP32 Setup

### 1. ติดตั้ง Arduino IDE
1. ดาวน์โหลด [Arduino IDE](https://www.arduino.cc/en/software)
2. ติดตั้ง ESP32 boards:
   - File → Preferences
   - ค้นหา "Additional Board Manager URLs"
   - เพิ่ม: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - OK
   - Tools → Board → Boards Manager
   - ค้นหา "ESP32" → Install

### 2. ติดตั้ง Libraries
1. Sketch → Include Library → Manage Libraries
2. ค้นหาและติดตั้ง:
   - **PubSubClient** (โดย Nick O'Leary)

### 3. อัพโหลดโค้ด
1. เปิด `fish_esp32_mqtt.ino`
2. แก้ไข:
   ```cpp
   const char* SSID = "YOUR_SSID";        // ชื่อ WiFi
   const char* PASSWORD = "YOUR_PASSWORD"; // รหัส WiFi
   ```
3. เลือกบอร์ด:
   - Tools → Board → ESP32 → ESP32 Dev Module
4. เลือก COM Port: Tools → Port → COM3 (หรือตามเครื่องของคุณ)
5. Upload (Ctrl+U หรือ Sketch → Upload)

### 4. ตรวจสอบการทำงาน
1. Tools → Serial Monitor
2. ควรเห็น:
   ```
   WiFi connected!
   IP Address: 192.168.X.X
   Attempting MQTT connection...
   connected!
   Published Temperature: 28.50
   ```

---

## 🌐 MQTT Broker (HiveMQ) - ฟรี 100%

### Broker Settings
- **URL**: `broker.hivemq.com`
- **Port**: `1883`
- **Protocol**: MQTT v3.1.1
- **Authentication**: ไม่ต้อง (Public)

### Topics ที่ใช้
```
fish/sensors/temperature  → อุณหภูมิ
fish/sensors/ph           → pH
fish/sensors/oxygen       → ออกซิเจน
fish/sensors/turbidity    → ความขุ่น
fish/status               → สถานะระบบ
```

### Monitor MQTT Messages (Optional)
ใช้เว็บไซต์ HiveMQ:
1. ไป https://www.hivemq.com/mqtt-websocket-client/
2. Connect กับ `broker.hivemq.com` : `8001`
3. Subscribe ที่ `fish/#`
4. เห็นข้อมูลเซนเซอร์แบบ real-time

---

## 📊 SQLite Database Schema

### ตาราง `sensor_data`
| Column | Type | ข้อมูล |
|--------|------|--------|
| id | INTEGER | Primary Key |
| temperature | REAL | อุณหภูมิ (°C) |
| ph_value | REAL | pH (0-14) |
| oxygen_level | REAL | ออกซิเจน (mg/L) |
| turbidity | REAL | ความขุ่น (NTU) |
| timestamp | INTEGER | เวลาบันทึก |

### ตาราง `alerts`
| Column | Type | ข้อมูล |
|--------|------|--------|
| id | INTEGER | Primary Key |
| title | TEXT | ชื่อการแจ้งเตือน |
| message | TEXT | ข้อความ |
| type | TEXT | ประเภท (temp, ph, oxygen, turbidity) |
| timestamp | INTEGER | เวลาแจ้ง |
| synced | BOOLEAN | ส่งไป cloud แล้วหรือยัง |

---

## 🔧 Troubleshooting

### 1. ESP32 ไม่เชื่อมต่อ WiFi
```cpp
// ตรวจสอบ SSID และ PASSWORD
const char* SSID = "ตรวจสอบอีกครั้ง";
const char* PASSWORD = "ตรวจสอบอีกครั้ง";
```

### 2. MQTT ไม่เชื่อมต่อ
- ตรวจสอบ WiFi เชื่อมต่ออยู่หรือไม่
- ตรวจสอบ Firewall ไม่บล็อก port 1883
- ลองใช้บอร์ก MQTT อื่น เช่น mosquitto

### 3. Flutter ไม่รับข้อมูล
- ตรวจสอบ MQTT broker มีข้อมูลส่งหรือไม่ (ใช้ HiveMQ Websocket Client)
- ตรวจสอบ Topics ตรงกันหรือไม่
- ตรวจสอบ WiFi ของ Device กับ PC เป็นเครือข่ายเดียวกันหรือไม่

### 4. Database ไม่บันทึก
- ตรวจสอบ App มี Permission เขียน file หรือไม่
- ลบแล้วลงใหม่

---

## 📝 ฟังก์ชันหลัก

### SensorDataManager
```dart
// เริ่มต้น
final manager = SensorDataManager();
await manager.initializeMqtt();

// บันทึกข้อมูลเซนเซอร์
await manager.saveSensorData(
  temperature: 28.5,
  phValue: 7.2,
  oxygenLevel: 8.5,
  turbidity: 2.3,
);

// ดึงข้อมูลล่าสุด
final data = await manager.getLatestSensorData();

// บันทึกการแจ้งเตือน
await manager.saveAlert(
  title: 'High Temperature',
  message: 'Temperature above 32°C',
  type: 'temp',
);

// ตรวจสอบ MQTT
bool connected = manager.isMqttConnected();
Stream<bool> status = manager.getMqttConnectionStatus();
```

---

## ⚙️ หมายเหตุสำคัญ

1. **เซนเซอร์**: ต้องแปลงค่า ADC (0-4095) เป็นหน่วยจริง
   - ตรวจสอบ datasheet ของเซนเซอร์
   - ใช้ calibration ที่ถูกต้อง

2. **MQTT Topics**: ต้องตรงกันระหว่าง ESP32 และ Flutter

3. **Frequency**: ปัจจุบัน: 5 วินาที (สามารถปรับได้)

4. **Battery**: MQTT ประหยัดพลังงาน ต่าง Bluetooth

---

## 🎉 สำเร็จ!

ระบบของคุณพร้อมแล้ว:
- ✅ ESP32 อ่านเซนเซอร์
- ✅ ส่งข้อมูล MQTT
- ✅ Flutter รับข้อมูล
- ✅ บันทึกลง SQLite
- ✅ ซิงค์ real-time

ทดลองใช้งานได้เลย! 🚀
