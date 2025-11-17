import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../../../core/storage/local_profile_store.dart';
import '../data/player_repository.dart';

class GameExitController {
  GameExitController(
    this._playerRepository,
    this._auth,
    this._profileStoreFuture,
  );

  final PlayerRepository _playerRepository;
  final FirebaseAuth _auth;
  final Future<LocalProfileStore> _profileStoreFuture;

  Future<void> leaveGame({required String gameId}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _playerRepository.deletePlayer(gameId: gameId, uid: user.uid);
    } catch (_) {
      // ignore deletion errors, player may not exist
    }

    final store = await _profileStoreFuture;
    await store.clearProfile();

    await _auth.signOut();
  }
}

final gameExitControllerProvider = Provider<GameExitController>((ref) {
  final repo = ref.watch(playerRepositoryProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final profileStoreFuture = ref.watch(localProfileStoreProvider.future);
  return GameExitController(repo, auth, profileStoreFuture);
});
