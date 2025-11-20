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
    );
    await docRef.set({
      'status': 'pending',
      'ownerUid': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
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

  Future<void> updateGameSettings({
    required String gameId,
    required GameSettingsInput settings,
  }) {
    return _gameCollection.doc(gameId).update(settings.toMap());
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
    };
  }
}
