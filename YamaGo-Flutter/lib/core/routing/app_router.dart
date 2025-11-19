import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yamago_flutter/features/game_shell/presentation/game_shell_page.dart';
import 'package:yamago_flutter/features/onboarding/presentation/onboarding_pages.dart';
import 'package:yamago_flutter/features/pins/presentation/pin_editor_page.dart';

final appRouterProvider = Provider<GoRouter>(
  (ref) {
    return GoRouter(
      debugLogDiagnostics: true,
      initialLocation: WelcomePage.routePath,
      routes: [
        GoRoute(
          path: WelcomePage.routePath,
          name: WelcomePage.routeName,
          builder: (context, state) => const WelcomePage(),
        ),
        GoRoute(
          path: JoinPage.routePath,
          name: JoinPage.routeName,
          builder: (context, state) => const JoinPage(),
        ),
        GoRoute(
          path: CreateGamePage.routePath,
          name: CreateGamePage.routeName,
          builder: (context, state) => const CreateGamePage(),
        ),
        GoRoute(
          path: PinEditorPage.routePath,
          name: PinEditorPage.routeName,
          builder: (context, state) {
            final gameId = state.pathParameters['gameId'];
            if (gameId == null || gameId.isEmpty) {
              return const WelcomePage();
            }
            return PinEditorPage(gameId: gameId);
          },
        ),
        GoRoute(
          path: GameShellPage.routePath,
          name: GameShellPage.routeName,
          builder: (context, state) {
            final gameId = state.pathParameters['gameId'];
            if (gameId == null || gameId.isEmpty) {
              return const WelcomePage();
            }
            return GameShellPage(gameId: gameId);
          },
        ),
      ],
      errorBuilder: (context, state) {
        return Scaffold(
          body: Center(
            child: Text(
              'Route not found: ${state.uri.toString()}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  },
);
