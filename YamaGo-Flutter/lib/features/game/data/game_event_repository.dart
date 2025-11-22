import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../domain/game_event.dart';

class GameEventRepository {
  GameEventRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<GameEvent>> watchRecentEvents(String gameId, {int limit = 25}) {
    final collection = _firestore
        .collection('games')
        .doc(gameId)
        .collection('events')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    return collection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => GameEvent.fromFirestore(doc)).toList();
    });
  }
}

final gameEventRepositoryProvider = Provider<GameEventRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return GameEventRepository(firestore);
});
