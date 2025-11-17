import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_repository.dart';
import '../data/player_repository.dart';
import '../domain/game.dart';
import '../domain/player.dart';

final playersStreamProvider =
    StreamProvider.family<List<Player>, String>((ref, gameId) {
  final repo = ref.watch(playerRepositoryProvider);
  return repo.watchPlayers(gameId);
});

final playerStreamProvider =
    StreamProvider.family<Player?, ({String gameId, String uid})>(
  (ref, args) {
    final repo = ref.watch(playerRepositoryProvider);
    return repo.watchPlayer(args.gameId, args.uid);
  },
);

final gameStreamProvider = StreamProvider.family<Game?, String>((ref, gameId) {
  final repo = ref.watch(gameRepositoryProvider);
  return repo.watchGame(gameId);
});
