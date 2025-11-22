import 'package:google_maps_flutter/google_maps_flutter.dart';

const LatLng yamanoteCenter = LatLng(35.75, 139.725);

final LatLngBounds yamanoteBounds = LatLngBounds(
  southwest: LatLng(35.65, 139.65),
  northeast: LatLng(35.85, 139.8),
);

const double yamanoteMinZoom = 14.0;
const double yamanoteMaxZoom = 19.0;
