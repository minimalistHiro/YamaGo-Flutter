import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../domain/game.dart';

class GameRepository {
  GameRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _gameCollection =>
      _firestore.collection('games');

  Future<bool> gameExists(String gameId) async {
    final doc = await _gameCollection.doc(gameId).get();
    return doc.exists;
  }

  Future<String> createGame({required String ownerUid}) async {
    final docRef = _gameCollection.doc();
    await docRef.set({
      'status': 'pending',
      'ownerUid': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Stream<Game?> watchGame(String gameId) {
    return _gameCollection.doc(gameId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Game.fromFirestore(doc);
    });
  }

  Future<void> addPlayer({
    required String gameId,
    required String uid,
    required String nickname,
    required String role,
  }) async {
    final playerRef =
        _gameCollection.doc(gameId).collection('players').doc(uid);
    await playerRef.set({
      'nickname': nickname,
      'role': role,
      'active': true,
      'status': 'active',
      'lat': null,
      'lng': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'stats': {
        'captures': 0,
        'capturedTimes': 0,
      },
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> startCountdown({
    required String gameId,
    required int durationSeconds,
  }) {
    return _gameCollection.doc(gameId).update({
      'status': 'countdown',
      'countdownStartAt': FieldValue.serverTimestamp(),
      'countdownDurationSec': durationSeconds,
    });
  }

  Future<void> startGame({required String gameId}) {
    return _gameCollection.doc(gameId).update({
      'status': 'running',
      'startAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> endGame({required String gameId}) {
    return _gameCollection.doc(gameId).update({
      'status': 'ended',
    });
  }

  Future<void> updateOwner({
    required String gameId,
    required String newOwnerUid,
  }) {
    return _gameCollection.doc(gameId).update({
      'ownerUid': newOwnerUid,
    });
  }
}

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return GameRepository(firestore);
});
