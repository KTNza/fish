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
  // รายการแจ้งเตือน (ตัวอย่าง)
  late List<Map<String, String>> _notifications;

  @override
  void initState() {
    super.initState();
    // Use notifications passed from the previous screen if available,
    // otherwise load shared history from NotificationService.
    if (widget.notifications != null && widget.notifications!.isNotEmpty) {
      _notifications = List.from(widget.notifications!);
    } else {
      _notifications = NotificationService().notificationHistory;
    }

    if (widget.title != null && widget.message != null) {
      final now = TimeOfDay.now();
      final timeString =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} น.';
      _notifications.insert(0, {
        'title': widget.title!,
        'message': widget.message!,
        'time': timeString,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 15),
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
                                notification['title']!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Text(
                              notification['time']!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          notification['message']!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
