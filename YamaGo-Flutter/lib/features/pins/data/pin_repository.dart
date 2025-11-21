import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../../../core/location/yamanote_constants.dart';
import '../domain/pin_point.dart';

class PinRepository {
  PinRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _pinCollection(String gameId) {
    return _firestore.collection('games').doc(gameId).collection('pins');
  }

  static const int _pinDuplicatePrecision = 6;

  Stream<List<PinPoint>> watchPins(String gameId) {
    return _pinCollection(gameId).snapshots().map(
          (snapshot) =>
              snapshot.docs.map(PinPoint.fromFirestore).toList(growable: false),
        );
  }

  Future<void> updatePinPosition({
    required String gameId,
    required String pinId,
    required double lat,
    required double lng,
  }) {
    return _pinCollection(gameId).doc(pinId).update({
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePinStatus({
    required String gameId,
    required String pinId,
    required PinStatus status,
  }) {
    return _pinCollection(gameId).doc(pinId).update({
      'status': switch (status) {
        PinStatus.pending => 'pending',
        PinStatus.clearing => 'clearing',
        PinStatus.cleared => 'cleared',
      },
      'cleared': status == PinStatus.cleared,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reseedPinsWithRandomLocations({
    required String gameId,
    required int targetCount,
  }) async {
    final sanitizedCount = targetCount.clamp(0, 20);
    final pinsRef = _pinCollection(gameId);
    final snapshot = await pinsRef.get();
    final batch = _firestore.batch();
    var hasChanges = false;

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
      hasChanges = true;
    }

    if (sanitizedCount <= 0) {
      if (hasChanges) {
        await batch.commit();
      }
      return;
    }

    final locations = _generatePinLocations(sanitizedCount);
    for (final location in locations) {
      final docRef = pinsRef.doc();
      batch.set(docRef, {
        'lat': location.lat,
        'lng': location.lng,
        'type': 'yellow',
        'status': 'pending',
        'cleared': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      hasChanges = true;
    }

    if (hasChanges) {
      await batch.commit();
    }
  }

  List<({double lat, double lng})> _generatePinLocations(int count) {
    final random = math.Random();
    final sw = yamanoteBounds.southwest;
    final ne = yamanoteBounds.northeast;
    final locations = <({double lat, double lng})>[];
    final usedKeys = <String>{};
    final maxAttempts = math.max(count * 200, 200);
    var attempts = 0;

    while (locations.length < count && attempts < maxAttempts) {
      final lat = sw.latitude + random.nextDouble() * (ne.latitude - sw.latitude);
      final lng = sw.longitude + random.nextDouble() * (ne.longitude - sw.longitude);
      final key = _formatLocationKey(lat, lng);
      if (usedKeys.add(key)) {
        locations.add((lat: lat, lng: lng));
      } else {
        attempts += 1;
      }
    }

    var fallbackOffset = 0;
    while (locations.length < count && fallbackOffset < count * 2) {
      final lat = yamanoteCenter.latitude;
      final lng = yamanoteCenter.longitude + fallbackOffset * 0.0001;
      fallbackOffset += 1;
      final key = _formatLocationKey(lat, lng);
      if (usedKeys.add(key)) {
        locations.add((lat: lat, lng: lng));
      }
    }

    return locations;
  }

  String _formatLocationKey(double lat, double lng) {
    return '${lat.toStringAsFixed(_pinDuplicatePrecision)}:${lng.toStringAsFixed(_pinDuplicatePrecision)}';
  }
}

final pinRepositoryProvider = Provider<PinRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return PinRepository(firestore);
});
