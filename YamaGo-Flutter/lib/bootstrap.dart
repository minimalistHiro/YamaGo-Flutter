import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'core/notifications/push_notification_service.dart';

/// Wraps the top-level initialization so we can centralize error reporting.
Future<void> bootstrap(FutureOr<void> Function() runAppCallback) async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );
    FlutterError.onError = FlutterError.presentError;

    await runAppCallback();
  }, (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
  });
}
