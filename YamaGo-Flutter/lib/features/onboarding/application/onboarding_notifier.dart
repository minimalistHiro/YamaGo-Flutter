import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_profile_store.dart';
import '../../../core/storage/player_avatar_storage.dart';
import '../../game/data/game_repository.dart';

typedef OnboardingState = AsyncValue<void>;

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(
    this._gameRepository,
    this._profileStoreFuture,
    this._avatarStorageFuture,
  ) : super(const AsyncData(null));

  final GameRepository _gameRepository;
  final Future<LocalProfileStore> _profileStoreFuture;
  final Future<PlayerAvatarStorage> _avatarStorageFuture;

  Future<String> createGame({
    required String nickname,
    required String ownerUid,
    Uint8List? avatarBytes,
  }) async {
    state = const AsyncLoading();
    try {
      final gameId = await _gameRepository.createGame(ownerUid: ownerUid);
      String? avatarUrl;
      if (avatarBytes != null && avatarBytes.isNotEmpty) {
        final avatarStorage = await _avatarStorageFuture;
        avatarUrl = await avatarStorage.uploadAvatar(
          uid: ownerUid,
          bytes: avatarBytes,
        );
      }
      await _gameRepository.addPlayer(
        gameId: gameId,
        uid: ownerUid,
        nickname: nickname,
        role: 'oni',
        avatarUrl: avatarUrl,
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
    Uint8List? avatarBytes,
  }) async {
    state = const AsyncLoading();
    try {
      final exists = await _gameRepository.gameExists(gameId);
      if (!exists) {
        throw StateError('ゲームIDが見つかりません: $gameId');
      }
      String? avatarUrl;
      if (avatarBytes != null && avatarBytes.isNotEmpty) {
        final avatarStorage = await _avatarStorageFuture;
        avatarUrl = await avatarStorage.uploadAvatar(
          uid: uid,
          bytes: avatarBytes,
        );
      }
      final existingRole = await _gameRepository.fetchPlayerRole(
        gameId: gameId,
        uid: uid,
      );
      final resolvedRole = existingRole ?? await _determineNextRole(gameId);
      await _gameRepository.addPlayer(
        gameId: gameId,
        uid: uid,
        nickname: nickname,
        role: resolvedRole,
        avatarUrl: avatarUrl,
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

  Future<String> _determineNextRole(String gameId) async {
    final playerCount = await _gameRepository.countPlayers(gameId: gameId);
    return playerCount.isEven ? 'oni' : 'runner';
  }
}

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
  final repo = ref.watch(gameRepositoryProvider);
  final profileStoreFuture = ref.watch(localProfileStoreProvider.future);
  final avatarStorageFuture = ref.watch(playerAvatarStorageProvider.future);
  return OnboardingController(
    repo,
    profileStoreFuture,
    avatarStorageFuture,
  );
});
