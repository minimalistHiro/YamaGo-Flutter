import 'package:google_maps_flutter/google_maps_flutter.dart';

const LatLng yamanoteCenter = LatLng(35.735, 139.725);

final LatLngBounds yamanoteBounds = LatLngBounds(
  southwest: LatLng(35.60, 139.63),
  northeast: LatLng(35.88, 139.82),
);

const double yamanoteMinZoom = 13.0;
const double yamanoteMaxZoom = 19.0;
