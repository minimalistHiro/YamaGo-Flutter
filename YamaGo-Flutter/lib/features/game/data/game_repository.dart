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
    const defaultSettings = GameSettingsInput(
      captureRadiusM: 100,
      runnerSeeKillerRadiusM: 500,
      runnerSeeRunnerRadiusM: 1000,
      runnerSeeGeneratorRadiusM: 3000,
      killerDetectRunnerRadiusM: 500,
      killerSeeGeneratorRadiusM: 3000,
      pinCount: 10,
      countdownDurationSec: 900,
      gameDurationSec: 7200,
      generatorClearDurationSec: 180,
    );
    await docRef.set({
      'status': 'pending',
      'ownerUid': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
       'updatedAt': FieldValue.serverTimestamp(),
      ...defaultSettings.toMap(),
    });
    return docRef.id;
  }

  Stream<Game?> watchGame(String gameId) {
    return _gameCollection.doc(gameId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Game.fromFirestore(doc);
    });
  }

  Future<Game?> fetchGame(String gameId) async {
    final doc = await _gameCollection.doc(gameId).get();
    if (!doc.exists) {
      return null;
    }
    return Game.fromFirestore(doc);
  }

  Future<void> addPlayer({
    required String gameId,
    required String uid,
    required String nickname,
    required String role,
    String? avatarUrl,
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
        'rescues': 0,
        'rescuedTimes': 0,
      },
      'joinedAt': FieldValue.serverTimestamp(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    }, SetOptions(merge: true));
  }

  Future<int> countPlayers({required String gameId}) async {
    final playersRef = _gameCollection.doc(gameId).collection('players');
    try {
      final aggregate = await playersRef.count().get();
      return aggregate.count ?? 0;
    } on FirebaseException {
      final snapshot = await playersRef.get();
      return snapshot.size;
    }
  }

  Future<String?> fetchPlayerRole({
    required String gameId,
    required String uid,
  }) async {
    final playerRef =
        _gameCollection.doc(gameId).collection('players').doc(uid);
    final snapshot = await playerRef.get();
    if (!snapshot.exists) return null;
    final data = snapshot.data();
    if (data == null) return null;
    final role = data['role'] as String?;
    if (role == 'oni' || role == 'runner') {
      return role;
    }
    return null;
  }

  Future<void> startCountdown({
    required String gameId,
    required int durationSeconds,
    DateTime? countdownStartAt,
    DateTime? countdownEndAt,
  }) {
    final updates = <String, dynamic>{
      'status': 'countdown',
      'countdownStartAt': countdownStartAt != null
          ? Timestamp.fromDate(countdownStartAt)
          : FieldValue.serverTimestamp(),
      'countdownDurationSec': durationSeconds,
      'timedEventQuarters': <int>[],
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (countdownEndAt != null) {
      updates['countdownEndAt'] = Timestamp.fromDate(countdownEndAt);
    }
    return _gameCollection.doc(gameId).update(updates);
  }

  Future<void> startGame({required String gameId}) {
    return _gameCollection.doc(gameId).update({
      'status': 'running',
      'startAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> endGame({
    required String gameId,
    required GameEndResult result,
  }) async {
    await _gameCollection.doc(gameId).update({
      'status': 'ended',
      'endResult': gameEndResultToRawValue(result),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _reviveDownedRunners(gameId: gameId);
  }

  Future<void> _reviveDownedRunners({required String gameId}) async {
    final playersRef = _gameCollection.doc(gameId).collection('players');
    final snapshot = await playersRef
        .where('role', isEqualTo: 'runner')
        .where('status', isEqualTo: 'downed')
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'status': 'active',
      });
    }
    await batch.commit();
  }

  Future<void> updateOwner({
    required String gameId,
    required String newOwnerUid,
  }) {
    return _gameCollection.doc(gameId).update({
      'ownerUid': newOwnerUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGameSettings({
    required String gameId,
    required GameSettingsInput settings,
  }) {
    return _gameCollection.doc(gameId).update({
      ...settings.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGame({required String gameId}) async {
    final docRef = _gameCollection.doc(gameId);
    final subcollections = [
      'players',
      'pins',
      'captures',
      'alerts',
      'events',
      'messages_oni',
      'messages_runner',
      'locations',
    ];
    for (final collection in subcollections) {
      try {
        await _deleteSubcollection(docRef, collection);
      } catch (error) {
        // Ignore permission errors for subcollections so that at least the parent
        // document can be removed and the caller can continue with cleanup.
        assert(() {
          // Helps during development while keeping release builds quiet.
          // ignore: avoid_print
          print('Failed to delete $collection for game $gameId: $error');
          return true;
        }());
      }
    }
    await docRef.delete();
  }

  Future<void> _deleteSubcollection(
    DocumentReference<Map<String, dynamic>> docRef,
    String collection,
  ) async {
    const batchLimit = 300;
    final colRef = docRef.collection(collection);
    while (true) {
      final snapshot = await colRef.limit(batchLimit).get();
      if (snapshot.docs.isEmpty) {
        break;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return GameRepository(firestore);
});

class GameSettingsInput {
  const GameSettingsInput({
    required this.captureRadiusM,
    required this.runnerSeeKillerRadiusM,
    required this.runnerSeeRunnerRadiusM,
    required this.runnerSeeGeneratorRadiusM,
    required this.killerDetectRunnerRadiusM,
    required this.killerSeeGeneratorRadiusM,
    required this.pinCount,
    required this.countdownDurationSec,
    required this.gameDurationSec,
    required this.generatorClearDurationSec,
  });

  final int captureRadiusM;
  final int runnerSeeKillerRadiusM;
  final int runnerSeeRunnerRadiusM;
  final int runnerSeeGeneratorRadiusM;
  final int killerDetectRunnerRadiusM;
  final int killerSeeGeneratorRadiusM;
  final int pinCount;
  final int countdownDurationSec;
  final int gameDurationSec;
  final int generatorClearDurationSec;

  Map<String, dynamic> toMap() {
    return {
      'captureRadiusM': captureRadiusM,
      'runnerSeeKillerRadiusM': runnerSeeKillerRadiusM,
      'runnerSeeRunnerRadiusM': runnerSeeRunnerRadiusM,
      'runnerSeeGeneratorRadiusM': runnerSeeGeneratorRadiusM,
      'killerDetectRunnerRadiusM': killerDetectRunnerRadiusM,
      'killerSeeGeneratorRadiusM': killerSeeGeneratorRadiusM,
      'pinCount': pinCount,
      'countdownDurationSec': countdownDurationSec,
      'gameDurationSec': gameDurationSec,
      'generatorClearDurationSec': generatorClearDurationSec,
    };
  }
}
