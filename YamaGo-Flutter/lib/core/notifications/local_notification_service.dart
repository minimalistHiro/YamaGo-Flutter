import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _chatChannelId = 'chat_messages';
const String _chatChannelName = 'チャット通知';
const String _chatChannelDescription = 'チームチャットと総合チャットの新着メッセージを通知します。';
const String _mapEventChannelId = 'map_events';
const String _mapEventChannelName = 'マップイベント';
const String _mapEventChannelDescription = 'マップ上の捕獲や発電所解除、ゲーム終了などを通知します。';

class LocalNotificationService {
  LocalNotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(initializationSettings);
    await _requestPermissions();
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    final androidImplementation = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();

    final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final macImplementation = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> showChatMessageNotification({
    required String messageId,
    required String title,
    required String body,
  }) async {
    await initialize();

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _chatChannelId,
        _chatChannelName,
        channelDescription: _chatChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    );

    final notificationId = messageId.hashCode & 0x7fffffff;
    await _plugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
    );
  }

  Future<void> showMapEventNotification({
    required String notificationId,
    required String title,
    required String body,
  }) async {
    await initialize();

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _mapEventChannelId,
        _mapEventChannelName,
        channelDescription: _mapEventChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    );

    final notificationHash = notificationId.hashCode & 0x7fffffff;
    await _plugin.show(
      notificationHash,
      title,
      body,
      notificationDetails,
    );
  }
}

final localNotificationServiceProvider =
    Provider<LocalNotificationService>((ref) {
  return LocalNotificationService();
});
