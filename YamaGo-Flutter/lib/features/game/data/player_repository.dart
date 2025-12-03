import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../domain/player.dart';

class PlayerRepository {
  PlayerRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _playersCollection(String gameId) {
    return _firestore.collection('games').doc(gameId).collection('players');
  }

  Stream<List<Player>> watchPlayers(String gameId) {
    return _playersCollection(gameId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => Player.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<Player?> watchPlayer(String gameId, String uid) {
    return _playersCollection(gameId).doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Player.fromFirestore(doc.id, doc.data()!);
    });
  }

  Future<void> updatePlayerPosition({
    required String gameId,
    required String uid,
    required double lat,
    required double lng,
  }) {
    return _playersCollection(gameId).doc(uid).set(
      {
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deletePlayer({
    required String gameId,
    required String uid,
  }) {
    return _playersCollection(gameId).doc(uid).delete();
  }

  Future<void> incrementGeneratorClear({
    required String gameId,
    required String uid,
  }) {
    return _playersCollection(gameId).doc(uid).update({
      'stats.generatorsCleared': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Player?> fetchPlayer({
    required String gameId,
    required String uid,
  }) async {
    final doc = await _playersCollection(gameId).doc(uid).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return Player.fromFirestore(doc.id, doc.data()!);
  }

  Future<void> updatePlayerRole({
    required String gameId,
    required String uid,
    required PlayerRole role,
  }) {
    return _playersCollection(gameId).doc(uid).update({
      'role': role == PlayerRole.oni ? 'oni' : 'runner',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setPlayerActive({
    required String gameId,
    required String uid,
    required bool isActive,
  }) {
    return _playersCollection(gameId).doc(uid).update({
      'active': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePlayerProfile({
    required String gameId,
    required String uid,
    required String nickname,
    String? avatarUrl,
  }) {
    final data = <String, dynamic>{
      'nickname': nickname,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (avatarUrl != null) {
      data['avatarUrl'] = avatarUrl;
    }
    return _playersCollection(gameId).doc(uid).update(data);
  }

  Future<void> addPlayerFcmToken({
    required String gameId,
    required String uid,
    required String token,
  }) {
    return _playersCollection(gameId).doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return PlayerRepository(firestore);
});
