import 'package:google_maps_flutter/google_maps_flutter.dart';

const LatLng yamanoteCenter = LatLng(35.69, 139.73);

final LatLngBounds yamanoteBounds = LatLngBounds(
  southwest: LatLng(35.639, 139.707),
  northeast: LatLng(35.73, 139.77),
);

const double yamanoteMinZoom = 14.5;
const double yamanoteMaxZoom = 19.0;
