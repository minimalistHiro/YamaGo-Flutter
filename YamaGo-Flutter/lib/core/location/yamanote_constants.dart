import 'package:google_maps_flutter/google_maps_flutter.dart';

const LatLng yamanoteCenter = LatLng(35.69, 139.73);

final LatLngBounds yamanoteBounds = LatLngBounds(
  southwest: LatLng(35.617, 139.707),
  northeast: LatLng(35.73, 139.77),
);

/// Ordered polygon made by connecting every Yamanote Line station clockwise.
///
/// These coordinates are intentionally simplified but stay close to the real
/// station locations so that any point that passes the polygon test feels like
/// it is inside the loop.
const List<LatLng> yamanoteStationPolygon = [
  LatLng(35.681236, 139.767125), // Tokyo
  LatLng(35.673146, 139.763912), // Yurakucho
  LatLng(35.66623, 139.758987), // Shimbashi
  LatLng(35.654998, 139.757531), // Hamamatsucho
  LatLng(35.645551, 139.747148), // Tamachi
  LatLng(35.635547, 139.74201), // Takanawa Gateway
  LatLng(35.628479, 139.738758), // Shinagawa
  LatLng(35.6197, 139.728553), // Osaki
  LatLng(35.62565, 139.723539), // Gotanda
  LatLng(35.633998, 139.715828), // Meguro
  LatLng(35.646687, 139.710084), // Ebisu
  LatLng(35.658034, 139.701636), // Shibuya
  LatLng(35.67022, 139.702042), // Harajuku
  LatLng(35.683061, 139.702042), // Yoyogi
  LatLng(35.690921, 139.700258), // Shinjuku
  LatLng(35.701306, 139.700044), // Shin-Okubo
  LatLng(35.712285, 139.703782), // Takadanobaba
  LatLng(35.721994, 139.706181), // Mejiro
  LatLng(35.728926, 139.71038), // Ikebukuro
  LatLng(35.731145, 139.728046), // Otsuka
  LatLng(35.733492, 139.739219), // Sugamo
  LatLng(35.736453, 139.74801), // Komagome
  LatLng(35.738524, 139.760968), // Tabata
  LatLng(35.732231, 139.766942), // Nishi-Nippori
  LatLng(35.727772, 139.770987), // Nippori
  LatLng(35.72128, 139.778576), // Uguisudani
  LatLng(35.713768, 139.777254), // Ueno
  LatLng(35.707118, 139.774219), // Okachimachi
  LatLng(35.698353, 139.773114), // Akihabara
  LatLng(35.69169, 139.770883), // Kanda
  LatLng(35.681236, 139.767125), // Back to Tokyo to close the loop
];

const double yamanoteMinZoom = 13.0;
const double yamanoteMaxZoom = 19.0;
