import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';

const _inactivePlayerGracePeriod = Duration(minutes: 5);

class RescueRepository {
  RescueRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _playersCollection(String gameId) {
    return _firestore.collection('games').doc(gameId).collection('players');
  }

  Future<void> rescueRunner({
    required String gameId,
    required String rescuerUid,
    required String victimUid,
  }) async {
    if (rescuerUid == victimUid) {
      throw StateError('自分自身を救出することはできません。');
    }
    final gameRef = _firestore.collection('games').doc(gameId);
    final rescuerRef = _playersCollection(gameId).doc(rescuerUid);
    final victimRef = _playersCollection(gameId).doc(victimUid);
    final eventRef = gameRef.collection('events').doc();

    await _firestore.runTransaction((transaction) async {
      final rescuerSnap = await transaction.get(rescuerRef);
      final victimSnap = await transaction.get(victimRef);
      if (!rescuerSnap.exists || !victimSnap.exists) {
        throw StateError('プレイヤー情報が見つかりませんでした。');
      }
      final rescuerData = rescuerSnap.data()!;
      final victimData = victimSnap.data()!;
      final rescuerRole = rescuerData['role'] as String? ?? 'runner';
      final victimRole = victimData['role'] as String? ?? 'runner';
      if (rescuerRole != 'runner') {
        throw StateError('救出できるのは逃走者のみです。');
      }
      if (victimRole != 'runner') {
        throw StateError('逃走者のみが救出対象です。');
      }
      final rescuerStatus = rescuerData['status'] as String? ?? 'active';
      if (rescuerStatus != 'active') {
        throw StateError('救出できる状態ではありません。');
      }
      if (!_isPlayerWithinGrace(rescuerData)) {
        throw StateError('救出できる状態ではありません。');
      }
      final victimStatus = victimData['status'] as String? ?? 'active';
      if (victimStatus != 'downed') {
        throw StateError('対象は救出が不要です。');
      }
      if (!_isPlayerWithinGrace(victimData)) {
        throw StateError('対象はすでにゲームから離脱しています。');
      }
      final now = FieldValue.serverTimestamp();
      transaction.update(victimRef, {
        'status': 'active',
        'rescuedAt': now,
        'lastRescuedBy': rescuerUid,
        'stats.rescuedTimes': FieldValue.increment(1),
        'updatedAt': now,
      });
      transaction.update(rescuerRef, {
        'stats.rescues': FieldValue.increment(1),
        'updatedAt': now,
      });
      transaction.set(eventRef, {
        'type': 'rescue',
        'actorUid': rescuerUid,
        'actorName': rescuerData['nickname'] as String? ?? 'No name',
        'rescuerUid': rescuerUid,
        'rescuerName': rescuerData['nickname'] as String? ?? 'No name',
        'targetUid': victimUid,
        'targetName': victimData['nickname'] as String? ?? 'No name',
        'victimUid': victimUid,
        'victimName': victimData['nickname'] as String? ?? 'No name',
        'createdAt': now,
      });
    });
  }

  bool _isPlayerWithinGrace(Map<String, dynamic> playerData) {
    final isActive = playerData['active'] as bool? ?? true;
    if (isActive) {
      return true;
    }
    final updatedAt = playerData['updatedAt'];
    if (updatedAt is Timestamp) {
      final now = DateTime.now();
      final updatedAtDate = updatedAt.toDate();
      final age = now.difference(updatedAtDate);
      if (age.isNegative) {
        return true;
      }
      return age <= _inactivePlayerGracePeriod;
    }
    return false;
  }
}

final rescueRepositoryProvider = Provider<RescueRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return RescueRepository(firestore);
});
