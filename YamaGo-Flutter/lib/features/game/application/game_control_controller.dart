import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_repository.dart';

class GameControlController {
  GameControlController(this._repository);

  final GameRepository _repository;

  Future<void> startCountdown({
    required String gameId,
    required int durationSeconds,
  }) {
    return _repository.startCountdown(
      gameId: gameId,
      durationSeconds: durationSeconds,
    );
  }

  Future<void> startGame({required String gameId}) {
    return _repository.startGame(gameId: gameId);
  }

  Future<void> endGame({required String gameId}) {
    return _repository.endGame(gameId: gameId);
  }
}

final gameControlControllerProvider = Provider<GameControlController>((ref) {
  final repo = ref.watch(gameRepositoryProvider);
  return GameControlController(repo);
});
