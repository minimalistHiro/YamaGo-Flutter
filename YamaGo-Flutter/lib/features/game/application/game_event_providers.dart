import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_event_repository.dart';
import '../domain/game_event.dart';

final gameEventsStreamProvider =
    StreamProvider.family<List<GameEvent>, String>((ref, gameId) {
  final repo = ref.watch(gameEventRepositoryProvider);
  return repo.watchRecentEvents(gameId);
});
