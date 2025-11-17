import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pin_repository.dart';
import '../domain/pin_point.dart';

final pinsStreamProvider =
    StreamProvider.family<List<PinPoint>, String>((ref, gameId) {
  final repo = ref.watch(pinRepositoryProvider);
  return repo.watchPins(gameId);
});
