import 'package:flutter/material.dart';
import 'notification_service.dart';

// หน้าจอแจ้งเตือน
class NotificationPage extends StatefulWidget {
  final String? title;
  final String? message;
  final List<Map<String, String>>? notifications;

  const NotificationPage(
      {super.key, this.title, this.message, this.notifications});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  // รายการแจ้งเตือน
  late List<Map<String, String>> _notifications;

  @override
  void initState() {
    super.initState();
    // โหลดข้อมูลจากหน้าก่อนหน้า หรือดึงจาก NotificationService
    if (widget.notifications != null && widget.notifications!.isNotEmpty) {
      _notifications = List.from(widget.notifications!);
    } else {
      _notifications = NotificationService().notificationHistory;
    }

    // หากมีการส่งแจ้งเตือนใหม่เข้ามาตรงๆ
    if (widget.title != null && widget.message != null) {
      final now = DateTime.now();
      final timeString =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} น.';

      // สร้าง format วันที่ เช่น 03/06/2569
      final dateString =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year + 543}';

      _notifications.insert(0, {
        'title': widget.title!,
        'message': widget.message!,
        'time': timeString,
        'date': dateString, // เพิ่มคีย์วันที่เข้าไปด้วย
      });
    }
  }

  // ฟังก์ชันสำหรับจัดกลุ่มแจ้งเตือนตามวันที่
  Map<String, List<Map<String, String>>> _groupNotificationsByDate() {
    Map<String, List<Map<String, String>>> grouped = {};

    for (var notification in _notifications) {
      // ดึงคีย์ 'date' ออกมา ถ้าไม่มี (สำหรับข้อมูลเก่า) ให้ถือว่าเป็น "วันนี้"
      String date = notification['date'] ?? 'วันนี้';

      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(notification);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    // ดึงข้อมูลที่จัดกลุ่มแล้วมาใช้งาน
    final groupedNotifications = _groupNotificationsByDate();
    final sortedDates = groupedNotifications.keys.toList();

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.grey[200],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'แจ้งเตือน',
          style: TextStyle(color: Colors.black54),
        ),
        centerTitle: true,
      ),
      body: _notifications.isEmpty
          ? const Center(
        child: Text(
          'ไม่มีแจ้งเตือน',
          style: TextStyle(fontSize: 18, color: Colors.black54),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final dateKey = sortedDates[index];
          final dayNotifications = groupedNotifications[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==========================================
              // ส่วนหัวแสดงวันที่ (Date Header)
              // ==========================================
              Padding(
                padding: EdgeInsets.only(
                    left: 4,
                    bottom: 12,
                    top: index == 0 ? 0 : 20 // เว้นระยะห่างด้านบนถ้าไม่ใช่วันแรก
                ),
                child: Text(
                  dateKey,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),

              // ==========================================
              // ส่วนแสดงการ์ดแจ้งเตือนในวันนั้นๆ
              // ==========================================
              ...dayNotifications.map((notification) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning,
                              color: Colors.red,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                notification['title'] ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Text(
                              notification['time'] ?? '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          notification['message'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}