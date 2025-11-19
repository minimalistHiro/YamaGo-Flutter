import 'dart:async';

import 'package:flutter/widgets.dart';

/// Wraps the top-level initialization so we can centralize error reporting.
Future<void> bootstrap(FutureOr<void> Function() runAppCallback) async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = FlutterError.presentError;

    await runAppCallback();
  }, (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
  });
}
