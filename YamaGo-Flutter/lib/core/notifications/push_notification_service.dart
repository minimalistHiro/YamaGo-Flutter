import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';
import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // no-op: Firebase may already be initialized.
  }
}

class PushNotificationService {
  PushNotificationService(
    this._messaging,
    this._localNotificationService,
  );

  final FirebaseMessaging _messaging;
  final LocalNotificationService _localNotificationService;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _localNotificationService.initialize();
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _initialized = true;
  }

  Future<String?> getToken() async {
    await initialize();
    try {
      return await _messaging.getToken();
    } catch (error) {
      debugPrint('Failed to fetch FCM token: $error');
      return null;
    }
  }

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'YamaGo チャット';
    final body = notification?.body ?? message.data['body'];
    if (body == null) return;
    final messageId =
        message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    unawaited(
      _localNotificationService.showChatMessageNotification(
        messageId: messageId,
        title: title,
        body: body,
      ),
    );
  }
}

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  final messaging = FirebaseMessaging.instance;
  final localService = ref.watch(localNotificationServiceProvider);
  return PushNotificationService(messaging, localService);
});
