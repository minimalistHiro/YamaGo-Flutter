import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';

class CaptureRepository {
  CaptureRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> captureRunner({
    required String gameId,
    required String attackerUid,
    required String victimUid,
  }) async {
    final gameRef = _firestore.collection('games').doc(gameId);
    final attackerRef = gameRef.collection('players').doc(attackerUid);
    final victimRef = gameRef.collection('players').doc(victimUid);
    final captureLogRef = gameRef.collection('captures').doc();
    final eventRef = gameRef.collection('events').doc();

    await _firestore.runTransaction((transaction) async {
      final attackerSnap = await transaction.get(attackerRef);
      final victimSnap = await transaction.get(victimRef);
      if (!attackerSnap.exists || !victimSnap.exists) {
        throw StateError('プレイヤー情報が見つかりませんでした。');
      }
      final attacker = attackerSnap.data()!;
      final victim = victimSnap.data()!;
      final attackerRole = attacker['role'] as String? ?? 'runner';
      final victimRole = victim['role'] as String? ?? 'runner';
      if (attackerRole != 'oni') {
        throw StateError('鬼のみ捕獲できます。');
      }
      if (victimRole != 'runner') {
        throw StateError('逃走者のみ捕獲対象です。');
      }
      final victimStatus = victim['status'] as String? ?? 'active';
      if (victimStatus == 'downed' || victimStatus == 'eliminated') {
        throw StateError('対象はすでに捕獲済みです。');
      }

      final now = FieldValue.serverTimestamp();
      final attackerName = attacker['nickname'] as String? ?? 'No name';
      final victimName = victim['nickname'] as String? ?? 'No name';
      transaction.update(victimRef, {
        'status': 'downed',
        'capturedAt': now,
        'stats.capturedTimes': FieldValue.increment(1),
      });
      transaction.update(attackerRef, {
        'stats.captures': FieldValue.increment(1),
      });
      transaction.set(captureLogRef, {
        'attackerUid': attackerUid,
        'victimUid': victimUid,
        'createdAt': now,
      });
      transaction.set(eventRef, {
        'type': 'capture',
        'actorUid': attackerUid,
        'actorName': attackerName,
        'attackerUid': attackerUid,
        'attackerName': attackerName,
        'targetUid': victimUid,
        'targetName': victimName,
        'victimUid': victimUid,
        'victimName': victimName,
        'createdAt': now,
      });
    });
  }
}

final captureRepositoryProvider = Provider<CaptureRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return CaptureRepository(firestore);
});
