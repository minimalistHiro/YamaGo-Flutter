import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_repository.dart';
import '../../pins/data/pin_repository.dart';
import '../domain/game.dart';
import '../../../core/time/server_time_service.dart';

class GameControlController {
  GameControlController(
    this._repository,
    this._pinRepository,
    this._serverTimeService,
  );

  final GameRepository _repository;
  final PinRepository _pinRepository;
  final ServerTimeService _serverTimeService;

  Future<void> startCountdown({
    required String gameId,
    required int durationSeconds,
  }) async {
    DateTime? countdownStartAt;
    DateTime? countdownEndAt;
    try {
      final serverNow = await _serverTimeService.fetchServerTime();
      countdownStartAt = serverNow.add(const Duration(seconds: 1));
      countdownEndAt = countdownStartAt.add(Duration(seconds: durationSeconds));
    } catch (error, stackTrace) {
      debugPrint('Failed to sync server time before countdown: $error');
      debugPrint('$stackTrace');
    }
    await _repository.startCountdown(
      gameId: gameId,
      durationSeconds: durationSeconds,
      countdownStartAt: countdownStartAt,
      countdownEndAt: countdownEndAt,
    );
  }

  Future<void> startGame({
    required String gameId,
  }) async {
    await _repository.startGame(gameId: gameId);
  }

  Future<void> endGame({
    required String gameId,
    int? pinCount,
    required GameEndResult result,
  }) async {
    await _repository.endGame(gameId: gameId, result: result);
    final resolvedPinCount = await _resolvePinCount(gameId, pinCount);
    if (resolvedPinCount != null) {
      await _pinRepository.reseedPinsWithRandomLocations(
        gameId: gameId,
        targetCount: resolvedPinCount,
      );
    }
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
  final serverTimeService = ref.watch(serverTimeServiceProvider);
  return GameControlController(repo, pinRepo, serverTimeService);
});
