import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../domain/pin_point.dart';

class PinRepository {
  PinRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _pinCollection(String gameId) {
    return _firestore.collection('games').doc(gameId).collection('pins');
  }

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
}

final pinRepositoryProvider = Provider<PinRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return PinRepository(firestore);
});
