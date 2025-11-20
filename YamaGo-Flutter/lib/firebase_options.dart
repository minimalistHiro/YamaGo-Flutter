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
          fallback: _defaultApiKey,
        ),
        appId: _resolveValue(
          debugName: 'FIREBASE_WEB_APP_ID',
          platformOverride: _webAppId,
          fallback: _defaultWebAppId,
        ),
        messagingSenderId: _resolveValue(
          debugName: 'FIREBASE_WEB_MESSAGING_SENDER_ID',
          platformOverride: _webMessagingSenderId,
          sharedValue: _messagingSenderId,
          fallback: _defaultMessagingSenderId,
        ),
        projectId: _resolveValue(
          debugName: 'FIREBASE_WEB_PROJECT_ID',
          platformOverride: _webProjectId,
          sharedValue: _projectId,
          fallback: _defaultProjectId,
        ),
        storageBucket: _resolveValue(
          debugName: 'FIREBASE_WEB_STORAGE_BUCKET',
          platformOverride: _webStorageBucket,
          sharedValue: _storageBucket,
          fallback: _defaultStorageBucket,
        ),
        authDomain: _resolveValue(
          debugName: 'FIREBASE_WEB_AUTH_DOMAIN',
          platformOverride: _webAuthDomain,
          fallback: _defaultAuthDomain,
        ),
        measurementId: () {
          final value = _resolveValue(
            debugName: 'FIREBASE_WEB_MEASUREMENT_ID',
            platformOverride: _webMeasurementId,
            fallback: _defaultMeasurementId,
            allowEmpty: true,
          );
          return value.isEmpty ? null : value;
        }(),
      );

  static FirebaseOptions get _android => FirebaseOptions(
        apiKey: _resolveValue(
          debugName: 'FIREBASE_ANDROID_API_KEY',
          platformOverride: _androidApiKey,
          fallback: _defaultAndroidApiKey,
        ),
        appId: _resolveValue(
          debugName: 'FIREBASE_ANDROID_APP_ID',
          platformOverride: _androidAppId,
          fallback: _defaultAndroidAppId,
        ),
        messagingSenderId: _resolveValue(
          debugName: 'FIREBASE_ANDROID_MESSAGING_SENDER_ID',
          platformOverride: _androidMessagingSenderId,
          sharedValue: _messagingSenderId,
          fallback: _defaultMessagingSenderId,
        ),
        projectId: _resolveValue(
          debugName: 'FIREBASE_PROJECT_ID',
          sharedValue: _projectId,
          fallback: _defaultProjectId,
        ),
        storageBucket: _resolveValue(
          debugName: 'FIREBASE_STORAGE_BUCKET',
          sharedValue: _storageBucket,
          fallback: _defaultStorageBucket,
        ),
      );

  static FirebaseOptions get _ios => FirebaseOptions(
        apiKey: _resolveValue(
          debugName: 'FIREBASE_IOS_API_KEY',
          platformOverride: _iosApiKey,
          fallback: _defaultIosApiKey,
        ),
        appId: _resolveValue(
          debugName: 'FIREBASE_IOS_APP_ID',
          platformOverride: _iosAppId,
          fallback: _defaultIosAppId,
        ),
        messagingSenderId: _resolveValue(
          debugName: 'FIREBASE_IOS_MESSAGING_SENDER_ID',
          platformOverride: _iosMessagingSenderId,
          sharedValue: _messagingSenderId,
          fallback: _defaultMessagingSenderId,
        ),
        projectId: _resolveValue(
          debugName: 'FIREBASE_PROJECT_ID',
          sharedValue: _projectId,
          fallback: _defaultProjectId,
        ),
        storageBucket: _resolveValue(
          debugName: 'FIREBASE_STORAGE_BUCKET',
          sharedValue: _storageBucket,
          fallback: _defaultStorageBucket,
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
          fallback: _defaultIosBundleId,
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
          fallback: _defaultIosBundleId,
        ),
      );
}

const _defaultApiKey = 'AIzaSyCO0i-DxjmLQz82xiubMkpfotc-k6MBuEI';
const _defaultAndroidApiKey = 'AIzaSyCnw9MQkotXZGEQb6x6SUVslysnnL1VKPc';
const _defaultIosApiKey = 'AIzaSyBKqCw_MutiFesHreiTbAkzslft_rOfKpw';
const _defaultWebAppId = '1:598692971255:web:9f5977110f979b13e609f2';
const _defaultAndroidAppId = '1:598692971255:android:bd9f925a7c7707b0e609f2';
const _defaultIosAppId = '1:598692971255:ios:0af7be44589fc219e609f2';
const _defaultProjectId = 'yamago-2ae8d';
const _defaultStorageBucket = 'yamago-2ae8d.firebasestorage.app';
const _defaultMessagingSenderId = '598692971255';
const _defaultMeasurementId = 'G-NL6CP18NNK';
const _defaultAuthDomain = 'yamago-2ae8d.firebaseapp.com';
const _defaultIosBundleId = 'io.groumap.yamago';

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
