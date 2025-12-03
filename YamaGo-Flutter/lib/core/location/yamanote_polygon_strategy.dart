import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'yamanote_constants.dart';

/// Checks whether the given coordinate is inside the Yamanote station polygon.
bool isPointInsideYamanotePolygon(double lat, double lng) {
  return isPointInsidePolygon(
    lat: lat,
    lng: lng,
    polygon: yamanoteStationPolygon,
  );
}

/// Generic point-in-polygon helper using the even-odd rule.
bool isPointInsidePolygon({
  required double lat,
  required double lng,
  required List<LatLng> polygon,
}) {
  var inside = false;
  if (polygon.isEmpty) {
    return inside;
  }

  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i, i++) {
    final xi = polygon[i].longitude;
    final yi = polygon[i].latitude;
    final xj = polygon[j].longitude;
    final yj = polygon[j].latitude;
    final denominator = yj - yi;

    if (((yi > lat) != (yj > lat)) && denominator.abs() > 1e-12) {
      final intersectionX = (xj - xi) * (lat - yi) / denominator + xi;
      if (lng < intersectionX) {
        inside = !inside;
      }
    }
  }

  return inside;
}

/// Generates a random point inside the polygon that defines the Yamanote loop.
({double lat, double lng})? randomPointInYamanotePolygon({
  math.Random? random,
  int maxAttempts = 200,
}) {
  final generator = random ?? math.Random();
  final sw = yamanoteBounds.southwest;
  final ne = yamanoteBounds.northeast;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final lat = sw.latitude + generator.nextDouble() * (ne.latitude - sw.latitude);
    final lng = sw.longitude + generator.nextDouble() * (ne.longitude - sw.longitude);

    if (isPointInsideYamanotePolygon(lat, lng)) {
      return (lat: lat, lng: lng);
    }
  }

  return null;
}
