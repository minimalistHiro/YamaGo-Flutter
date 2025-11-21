import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../../../core/storage/local_profile_store.dart';
import '../../../core/storage/player_avatar_storage.dart';
import '../../auth/application/auth_providers.dart';
import '../data/player_repository.dart';
import '../domain/player.dart';

class GameExitController {
  GameExitController(
    this._playerRepository,
    this._auth,
    this._profileStoreFuture,
    this._avatarStorageFuture,
    this._ref,
  );

  final PlayerRepository _playerRepository;
  final FirebaseAuth _auth;
  final Future<LocalProfileStore> _profileStoreFuture;
  final Future<PlayerAvatarStorage> _avatarStorageFuture;
  final Ref _ref;

  Future<void> leaveGame({required String gameId}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    Player? player;
    try {
      player = await _playerRepository.fetchPlayer(
        gameId: gameId,
        uid: user.uid,
      );
    } catch (_) {
      player = null;
    }

    try {
      await _playerRepository.deletePlayer(gameId: gameId, uid: user.uid);
    } catch (_) {
      // ignore deletion errors, player may not exist
    }

    final avatarUrl = player?.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      try {
        final avatarStorage = await _avatarStorageFuture;
        await avatarStorage.deleteAvatarByUrl(avatarUrl);
      } catch (_) {
        // ignore failures while cleaning up avatar
      }
    }

    final store = await _profileStoreFuture;
    await store.clearProfile();

    await _auth.signOut();
    _ref.invalidate(ensureAnonymousSignInProvider);
  }
}

final gameExitControllerProvider = Provider<GameExitController>((ref) {
  final repo = ref.watch(playerRepositoryProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final profileStoreFuture = ref.watch(localProfileStoreProvider.future);
  final avatarStorageFuture = ref.watch(playerAvatarStorageProvider.future);
  return GameExitController(
    repo,
    auth,
    profileStoreFuture,
    avatarStorageFuture,
    ref,
  );
});
