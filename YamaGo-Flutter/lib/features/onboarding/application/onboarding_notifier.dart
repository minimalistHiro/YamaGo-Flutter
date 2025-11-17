import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../../../core/storage/local_profile_store.dart';
import '../../game/data/game_repository.dart';

typedef OnboardingState = AsyncValue<void>;

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(
    this._gameRepository,
    this._auth,
    this._profileStoreFuture,
  ) : super(const AsyncData(null));

  final GameRepository _gameRepository;
  final FirebaseAuth _auth;
  final Future<LocalProfileStore> _profileStoreFuture;

  Future<String> createGame({required String nickname}) async {
    state = const AsyncLoading();
    try {
      final user = await _currentUser();
      final gameId = await _gameRepository.createGame(ownerUid: user.uid);
      await _gameRepository.addPlayer(
        gameId: gameId,
        uid: user.uid,
        nickname: nickname,
        role: 'oni',
      );
      await _persistProfile(nickname: nickname, lastGameId: gameId);
      state = const AsyncData(null);
      return gameId;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> joinGame({
    required String gameId,
    required String nickname,
  }) async {
    state = const AsyncLoading();
    try {
      final user = await _currentUser();
      final exists = await _gameRepository.gameExists(gameId);
      if (!exists) {
        throw StateError('ゲームIDが見つかりません: $gameId');
      }
      await _gameRepository.addPlayer(
        gameId: gameId,
        uid: user.uid,
        nickname: nickname,
        role: 'runner',
      );
      await _persistProfile(nickname: nickname, lastGameId: gameId);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<User> _currentUser() async {
    final existing = _auth.currentUser;
    if (existing != null) {
      return existing;
    }
    final credential = await _auth.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError('Anonymous sign-in failed');
    }
    return user;
  }

  Future<void> _persistProfile({
    required String nickname,
    required String lastGameId,
  }) async {
    final store = await _profileStoreFuture;
    await store.saveNickname(nickname);
    await store.saveLastGameId(lastGameId);
  }
}

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
  final repo = ref.watch(gameRepositoryProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final profileStoreFuture = ref.watch(localProfileStoreProvider.future);
  return OnboardingController(repo, auth, profileStoreFuture);
});
