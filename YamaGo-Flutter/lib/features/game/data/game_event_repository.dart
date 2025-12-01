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

  Future<bool> recordTimedEventTrigger({
    required String gameId,
    required int quarterIndex,
    required int requiredRunners,
    required int eventDurationSeconds,
    required int percentProgress,
    required String eventTimeLabel,
    required int totalRunnerCount,
    String? targetPinId,
  }) {
    final gameRef = _firestore.collection('games').doc(gameId);
    return _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(gameRef);
      if (!snapshot.exists) {
        return false;
      }
      final data = snapshot.data();
      final triggered = <int>{
        for (final value in (data?['timedEventQuarters'] as List<dynamic>? ??
            const <dynamic>[]))
          if (value is num) value.toInt(),
      };
      if (triggered.contains(quarterIndex)) {
        return false;
      }
      transaction.update(gameRef, {
        'timedEventQuarters': FieldValue.arrayUnion([quarterIndex]),
        'timedEventActive': true,
        'timedEventActiveStartedAt': FieldValue.serverTimestamp(),
        'timedEventActiveDurationSec': eventDurationSeconds,
        'timedEventActiveQuarter': quarterIndex,
        'timedEventTargetPinId': targetPinId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final eventRef = gameRef.collection('events').doc();
      transaction.set(eventRef, {
        'type': 'timed_event',
        'quarter': quarterIndex,
        'requiredRunners': requiredRunners,
        'eventDurationSeconds': eventDurationSeconds,
        'percentProgress': percentProgress,
        'eventTimeLabel': eventTimeLabel,
        'totalRunnerCount': totalRunnerCount,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }
}

final gameEventRepositoryProvider = Provider<GameEventRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return GameEventRepository(firestore);
});
