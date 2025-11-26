import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_profile_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../game/application/game_exit_controller.dart';

/// Cleans up leftover local/remote player data when the app boots.
final startupCleanupProvider = FutureProvider<void>((ref) async {
  final profileStore = await ref.watch(localProfileStoreProvider.future);
  final lastGameId = profileStore.lastGameId;
  if (lastGameId == null || lastGameId.isEmpty) {
    return;
  }

  // Ensure we have a Firebase user so GameExitController can perform cleanup.
  await ref.read(ensureAnonymousSignInProvider.future);

  final exitController = ref.read(gameExitControllerProvider);
  try {
    await exitController.leaveGame(gameId: lastGameId);
  } catch (error, stackTrace) {
    debugPrint('Startup cleanup failed: $error');
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
  }
});
