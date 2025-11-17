import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// High-level representation of geolocation permission / service state.
enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
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

  return LocationPermissionStatus.granted;
});

final locationStreamProvider = StreamProvider<Position>((ref) async* {
  final status = await ref.watch(locationPermissionStatusProvider.future);
  if (status != LocationPermissionStatus.granted) {
    throw LocationPermissionException(status);
  }

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    ),
  ).handleError((error, stackTrace) {
    debugPrint('location stream error: $error');
  });
});

final lastKnownPositionProvider = FutureProvider<Position?>((ref) async {
  final status = await ref.watch(locationPermissionStatusProvider.future);
  if (status != LocationPermissionStatus.granted) {
    return null;
  }
  return Geolocator.getLastKnownPosition();
});
