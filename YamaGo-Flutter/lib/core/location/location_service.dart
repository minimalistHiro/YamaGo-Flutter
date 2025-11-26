import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// High-level representation of geolocation permission / service state.
enum LocationPermissionStatus {
  granted,
  limited,
  denied,
  deniedForever,
  serviceDisabled,
}

bool _hasForegroundPermission(LocationPermissionStatus status) {
  return status == LocationPermissionStatus.granted ||
      status == LocationPermissionStatus.limited;
}

class LocationPermissionException implements Exception {
  LocationPermissionException(this.status);
  final LocationPermissionStatus status;

  @override
  String toString() => 'LocationPermissionException($status)';
}

final locationPermissionStatusProvider =
    FutureProvider<LocationPermissionStatus>((ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return LocationPermissionStatus.serviceDisabled;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    return LocationPermissionStatus.deniedForever;
  }
  if (permission == LocationPermission.denied) {
    return LocationPermissionStatus.denied;
  }
  if (permission == LocationPermission.whileInUse) {
    return LocationPermissionStatus.limited;
  }

  return LocationPermissionStatus.granted;
});

final locationStreamProvider = StreamProvider<Position>((ref) async* {
  final status = await ref.watch(locationPermissionStatusProvider.future);
  if (!_hasForegroundPermission(status)) {
    throw LocationPermissionException(status);
  }

  yield* Geolocator.getPositionStream(
    locationSettings: _buildLocationSettings(),
  ).handleError((error, stackTrace) {
    debugPrint('location stream error: $error');
  });
});

final lastKnownPositionProvider = FutureProvider<Position?>((ref) async {
  final status = await ref.watch(locationPermissionStatusProvider.future);
  if (!_hasForegroundPermission(status)) {
    return null;
  }
  return Geolocator.getLastKnownPosition();
});

LocationSettings _buildLocationSettings() {
  if (kIsWeb) {
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'YamaGo が現在地を送信中',
          notificationText: 'ゲーム進行のためバックグラウンドで位置情報を共有しています。',
          notificationChannelName: '位置情報のバックグラウンド更新',
          setOngoing: true,
        ),
      );
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        activityType: ActivityType.fitness,
      );
    default:
      return const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );
  }
}
