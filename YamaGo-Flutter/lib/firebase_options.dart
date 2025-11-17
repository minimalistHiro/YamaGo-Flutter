import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Loads Firebase credentials from `--dart-define` values so real keys never
/// have to be committed. Provide platform-specific values when running:
///
/// ```bash
/// flutter run \
///   --dart-define=FIREBASE_PROJECT_ID=your_project \
///   --dart-define=FIREBASE_ANDROID_API_KEY=xxx \
///   --dart-define=FIREBASE_ANDROID_APP_ID=xxx
/// ```
///
/// Fallback dummy values keep the app compiling when the secrets are absent.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return _web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _android;
      case TargetPlatform.iOS:
        return _ios;
      case TargetPlatform.macOS:
        return _macOS;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return _android;
    }
  }

  static FirebaseOptions get _web => FirebaseOptions(
        apiKey: _resolveValue(
          debugName: 'FIREBASE_WEB_API_KEY',
          platformOverride: _webApiKey,
          fallback: 'YOUR_WEB_API_KEY',
        ),
        appId: _resolveValue(
          debugName: 'FIREBASE_WEB_APP_ID',
          platformOverride: _webAppId,
          fallback: 'YOUR_WEB_APP_ID',
        ),
        messagingSenderId: _resolveValue(
          debugName: 'FIREBASE_WEB_MESSAGING_SENDER_ID',
          platformOverride: _webMessagingSenderId,
          sharedValue: _messagingSenderId,
          fallback: 'YOUR_WEB_SENDER_ID',
        ),
        projectId: _resolveValue(
          debugName: 'FIREBASE_WEB_PROJECT_ID',
          platformOverride: _webProjectId,
          sharedValue: _projectId,
          fallback: 'YOUR_PROJECT_ID',
        ),
        storageBucket: _resolveValue(
          debugName: 'FIREBASE_WEB_STORAGE_BUCKET',
          platformOverride: _webStorageBucket,
          sharedValue: _storageBucket,
          fallback: 'YOUR_STORAGE_BUCKET',
        ),
        authDomain: _resolveValue(
          debugName: 'FIREBASE_WEB_AUTH_DOMAIN',
          platformOverride: _webAuthDomain,
          fallback: 'YOUR_WEB_AUTH_DOMAIN',
        ),
        measurementId: () {
          final value = _resolveValue(
            debugName: 'FIREBASE_WEB_MEASUREMENT_ID',
            platformOverride: _webMeasurementId,
            allowEmpty: true,
          );
          return value.isEmpty ? null : value;
        }(),
      );

  static FirebaseOptions get _android => FirebaseOptions(
        apiKey: _resolveValue(
          debugName: 'FIREBASE_ANDROID_API_KEY',
          platformOverride: _androidApiKey,
          fallback: 'YOUR_ANDROID_API_KEY',
        ),
        appId: _resolveValue(
          debugName: 'FIREBASE_ANDROID_APP_ID',
          platformOverride: _androidAppId,
          fallback: 'YOUR_ANDROID_APP_ID',
        ),
        messagingSenderId: _resolveValue(
          debugName: 'FIREBASE_ANDROID_MESSAGING_SENDER_ID',
          platformOverride: _androidMessagingSenderId,
          sharedValue: _messagingSenderId,
          fallback: 'YOUR_ANDROID_SENDER_ID',
        ),
        projectId: _resolveValue(
          debugName: 'FIREBASE_PROJECT_ID',
          sharedValue: _projectId,
          fallback: 'YOUR_PROJECT_ID',
        ),
        storageBucket: _resolveValue(
          debugName: 'FIREBASE_STORAGE_BUCKET',
          sharedValue: _storageBucket,
          fallback: 'YOUR_STORAGE_BUCKET',
        ),
      );

  static FirebaseOptions get _ios => FirebaseOptions(
        apiKey: _resolveValue(
          debugName: 'FIREBASE_IOS_API_KEY',
          platformOverride: _iosApiKey,
          fallback: 'YOUR_IOS_API_KEY',
        ),
        appId: _resolveValue(
          debugName: 'FIREBASE_IOS_APP_ID',
          platformOverride: _iosAppId,
          fallback: 'YOUR_IOS_APP_ID',
        ),
        messagingSenderId: _resolveValue(
          debugName: 'FIREBASE_IOS_MESSAGING_SENDER_ID',
          platformOverride: _iosMessagingSenderId,
          sharedValue: _messagingSenderId,
          fallback: 'YOUR_IOS_SENDER_ID',
        ),
        projectId: _resolveValue(
          debugName: 'FIREBASE_PROJECT_ID',
          sharedValue: _projectId,
          fallback: 'YOUR_PROJECT_ID',
        ),
        storageBucket: _resolveValue(
          debugName: 'FIREBASE_STORAGE_BUCKET',
          sharedValue: _storageBucket,
          fallback: 'YOUR_STORAGE_BUCKET',
        ),
        iosClientId: () {
          final value = _resolveValue(
            debugName: 'FIREBASE_IOS_CLIENT_ID',
            platformOverride: _iosClientId,
            allowEmpty: true,
          );
          return value.isEmpty ? null : value;
        }(),
        iosBundleId: _resolveValue(
          debugName: 'FIREBASE_IOS_BUNDLE_ID',
          platformOverride: _iosBundleId,
          fallback: 'com.example.yamago',
        ),
      );

  static FirebaseOptions get _macOS => FirebaseOptions(
        apiKey: _resolveValue(
          debugName: 'FIREBASE_MACOS_API_KEY',
          platformOverride: _macosApiKey,
          fallback: 'YOUR_MAC_API_KEY',
        ),
        appId: _resolveValue(
          debugName: 'FIREBASE_MACOS_APP_ID',
          platformOverride: _macosAppId,
          fallback: 'YOUR_MAC_APP_ID',
        ),
        messagingSenderId: _resolveValue(
          debugName: 'FIREBASE_MACOS_MESSAGING_SENDER_ID',
          platformOverride: _macosMessagingSenderId,
          sharedValue: _messagingSenderId,
          fallback: 'YOUR_MAC_SENDER_ID',
        ),
        projectId: _resolveValue(
          debugName: 'FIREBASE_PROJECT_ID',
          sharedValue: _projectId,
          fallback: 'YOUR_PROJECT_ID',
        ),
        storageBucket: _resolveValue(
          debugName: 'FIREBASE_STORAGE_BUCKET',
          sharedValue: _storageBucket,
          fallback: 'YOUR_STORAGE_BUCKET',
        ),
        iosBundleId: _resolveValue(
          debugName: 'FIREBASE_MACOS_BUNDLE_ID',
          platformOverride: _macosBundleId,
          sharedValue: _iosBundleId,
          fallback: 'com.example.yamago',
        ),
      );
}

String _resolveValue({
  required String debugName,
  String platformOverride = '',
  String sharedValue = '',
  String fallback = '',
  bool allowEmpty = false,
}) {
  final value = platformOverride.isNotEmpty
      ? platformOverride
      : (sharedValue.isNotEmpty ? sharedValue : fallback);

  if (value.isNotEmpty) {
    if (value == fallback && fallback.startsWith('YOUR_') && kDebugMode) {
      debugPrint(
        'Firebase option $debugName is still using the placeholder "$fallback". '
        'Provide a real value with --dart-define=$debugName=YOUR_VALUE.',
      );
    }
    return value;
  }

  if (allowEmpty) {
    return '';
  }

  throw StateError(
    'Missing Firebase configuration for $debugName. '
    'Pass it via --dart-define=$debugName=YOUR_VALUE.',
  );
}

const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
const _messagingSenderId =
    String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');

const _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _androidMessagingSenderId =
    String.fromEnvironment('FIREBASE_ANDROID_MESSAGING_SENDER_ID');

const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
const _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
const _iosMessagingSenderId =
    String.fromEnvironment('FIREBASE_IOS_MESSAGING_SENDER_ID');

const _macosApiKey = String.fromEnvironment('FIREBASE_MACOS_API_KEY');
const _macosAppId = String.fromEnvironment('FIREBASE_MACOS_APP_ID');
const _macosMessagingSenderId =
    String.fromEnvironment('FIREBASE_MACOS_MESSAGING_SENDER_ID');
const _macosBundleId = String.fromEnvironment('FIREBASE_MACOS_BUNDLE_ID');

const _webApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
const _webMessagingSenderId =
    String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID');
const _webProjectId = String.fromEnvironment('FIREBASE_WEB_PROJECT_ID');
const _webStorageBucket =
    String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET');
const _webAuthDomain = String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN');
const _webMeasurementId =
    String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID');
