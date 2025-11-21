import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_repository.dart';
import '../../pins/data/pin_repository.dart';

class GameControlController {
  GameControlController(this._repository, this._pinRepository);

  final GameRepository _repository;
  final PinRepository _pinRepository;

  Future<void> startCountdown({
    required String gameId,
    required int durationSeconds,
  }) {
    return _repository.startCountdown(
      gameId: gameId,
      durationSeconds: durationSeconds,
    );
  }

  Future<void> startGame({
    required String gameId,
    int? pinCount,
  }) async {
    final resolvedPinCount = await _resolvePinCount(gameId, pinCount);
    if (resolvedPinCount != null) {
      await _pinRepository.reseedPinsWithRandomLocations(
        gameId: gameId,
        targetCount: resolvedPinCount,
      );
    }
    await _repository.startGame(gameId: gameId);
  }

  Future<void> endGame({required String gameId}) {
    return _repository.endGame(gameId: gameId);
  }

  Future<int?> _resolvePinCount(String gameId, int? providedCount) async {
    if (providedCount != null) {
      return providedCount;
    }
    final game = await _repository.fetchGame(gameId);
    return game?.pinCount;
  }
}

final gameControlControllerProvider = Provider<GameControlController>((ref) {
  final repo = ref.watch(gameRepositoryProvider);
  final pinRepo = ref.watch(pinRepositoryProvider);
  return GameControlController(repo, pinRepo);
});
