import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/application/auth_providers.dart';
import '../../../core/location/location_service.dart';
import '../data/player_repository.dart';

/// Listens to the device location stream and writes updates directly to
/// the player's Firestore document for the specified game.
final playerLocationUpdaterProvider =
    Provider.autoDispose.family<void, String>((ref, gameId) {
  final authState = ref.watch(authStateStreamProvider);
  final user = authState.value;
  if (user == null) {
    return;
  }

  final repo = ref.watch(playerRepositoryProvider);

  ref.listen(locationStreamProvider, (previous, next) {
    next.whenData((position) {
      repo.updatePlayerPosition(
        gameId: gameId,
        uid: user.uid,
        lat: position.latitude,
        lng: position.longitude,
      );
    });
  });
});
