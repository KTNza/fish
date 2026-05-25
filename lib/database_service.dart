import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'fish_monitor.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // ตารางเก็บข้อมูลเซนเซอร์
    await db.execute(
      '''
      CREATE TABLE sensor_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        temperature REAL,
        ph_value REAL,
        oxygen_level REAL,
        turbidity REAL,
        timestamp INTEGER
      )
      ''',
    );

    // ตารางเก็บประวัติการแจ้งเตือน
    await db.execute(
      '''
      CREATE TABLE alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        message TEXT,
        type TEXT,
        timestamp INTEGER,
        synced BOOLEAN DEFAULT 0
      )
      ''',
    );
  }

  // บันทึกข้อมูลเซนเซอร์
  Future<int> saveSensorData({
    required double temperature,
    required double phValue,
    required double oxygenLevel,
    required double turbidity,
  }) async {
    final db = await database;
    return await db.insert(
      'sensor_data',
      {
        'temperature': temperature,
        'ph_value': phValue,
        'oxygen_level': oxygenLevel,
        'turbidity': turbidity,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  // ดึงข้อมูลเซนเซอร์ล่าสุด
  Future<Map<String, dynamic>?> getLatestSensorData() async {
    final db = await database;
    final result = await db.query(
      'sensor_data',
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    return result.isNotEmpty ? result.first : null;
  }

  // ดึงข้อมูลเซนเซอร์ทั้งหมด (ตั้งแต่เมื่อไหร่)
  Future<List<Map<String, dynamic>>> getAllSensorData() async {
    final db = await database;
    return await db.query(
      'sensor_data',
      orderBy: 'timestamp DESC',
    );
  }

  // ดึงข้อมูลเซนเซอร์ของวันนี้
  Future<List<Map<String, dynamic>>> getTodaySensorData() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final timestamp = startOfDay.millisecondsSinceEpoch;

    return await db.query(
      'sensor_data',
      where: 'timestamp >= ?',
      whereArgs: [timestamp],
      orderBy: 'timestamp DESC',
    );
  }

  // บันทึกการแจ้งเตือน
  Future<int> saveAlert({
    required String title,
    required String message,
    required String type, // 'temp', 'ph', 'oxygen', 'turbidity'
  }) async {
    final db = await database;
    return await db.insert(
      'alerts',
      {
        'title': title,
        'message': message,
        'type': type,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
    );
  }

  // ดึงการแจ้งเตือนทั้งหมด
  Future<List<Map<String, dynamic>>> getAllAlerts() async {
    final db = await database;
    return await db.query(
      'alerts',
      orderBy: 'timestamp DESC',
    );
  }

  // ดึงการแจ้งเตือนที่ยังไม่ซิงค์
  Future<List<Map<String, dynamic>>> getUnsyncedAlerts() async {
    final db = await database;
    return await db.query(
      'alerts',
      where: 'synced = 0',
      orderBy: 'timestamp DESC',
    );
  }

  // ทำเครื่องหมายการแจ้งเตือนว่าซิงค์เรียบร้อย
  Future<int> markAlertSynced(int alertId) async {
    final db = await database;
    return await db.update(
      'alerts',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [alertId],
    );
  }

  // ลบข้อมูลเซนเซอร์เก่า (เก็บแค่ 7 วันล่าสุด)
  Future<int> cleanOldData() async {
    final db = await database;
    final sevenDaysAgo =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;

    return await db.delete(
      'sensor_data',
      where: 'timestamp < ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
