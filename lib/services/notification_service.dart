import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null, // default icon
      [
        NotificationChannel(
          channelGroupKey: 'omi_channel_group',
          channelKey: 'omi_ai_responses',
          channelName: 'AI Responses',
          channelDescription: 'Notifications for Omi AI responses',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
        )
      ],
      channelGroups: [
        NotificationChannelGroup(
          channelGroupKey: 'omi_channel_group',
          channelGroupName: 'Omi Notifications',
        )
      ],
      debug: false,
    );
    
    // Request permission
    await AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });
  }

  Future<void> showAiResponse(String message) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'omi_ai_responses',
        title: 'Omi',
        body: message,
        notificationLayout: NotificationLayout.BigText,
      ),
    );
  }

  Future<void> showNotification(String title, String body) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'omi_ai_responses',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
      ),
    );
  }
}
