import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_profile_store.dart';
import '../../game/data/game_repository.dart';

typedef OnboardingState = AsyncValue<void>;

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(
    this._gameRepository,
    this._profileStoreFuture,
  ) : super(const AsyncData(null));

  final GameRepository _gameRepository;
  final Future<LocalProfileStore> _profileStoreFuture;

  Future<String> createGame({
    required String nickname,
    required String ownerUid,
  }) async {
    state = const AsyncLoading();
    try {
      final gameId = await _gameRepository.createGame(ownerUid: ownerUid);
      await _gameRepository.addPlayer(
        gameId: gameId,
        uid: ownerUid,
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
    required String uid,
  }) async {
    state = const AsyncLoading();
    try {
      final exists = await _gameRepository.gameExists(gameId);
      if (!exists) {
        throw StateError('ゲームIDが見つかりません: $gameId');
      }
      await _gameRepository.addPlayer(
        gameId: gameId,
        uid: uid,
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
  final profileStoreFuture = ref.watch(localProfileStoreProvider.future);
  return OnboardingController(repo, profileStoreFuture);
});
