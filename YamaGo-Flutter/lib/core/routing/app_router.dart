import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yamago_flutter/features/game_shell/presentation/game_shell_page.dart';
import 'package:yamago_flutter/features/onboarding/presentation/onboarding_pages.dart';
import 'package:yamago_flutter/features/pins/presentation/pin_editor_page.dart';
import 'package:yamago_flutter/features/startup/presentation/splash_page.dart';

final appRouterProvider = Provider<GoRouter>(
  (ref) {
    return GoRouter(
      debugLogDiagnostics: true,
      initialLocation: SplashPage.routePath,
      routes: [
        GoRoute(
          path: SplashPage.routePath,
          name: SplashPage.routeName,
          builder: (context, state) => const SplashPage(),
        ),
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
          path: '/game/:gameId',
          redirect: (context, state) {
            final gameId = state.pathParameters['gameId'];
            if (gameId == null || gameId.isEmpty) {
              return WelcomePage.routePath;
            }
            return '/game/$gameId/map';
          },
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
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            final gameId = state.pathParameters['gameId'] ?? 'unknown';
            return GameShellPage(
              gameId: gameId,
              navigationShell: navigationShell,
            );
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: GameMapSection.routePath,
                  name: GameMapSection.routeName,
                  pageBuilder: (context, state) {
                    final gameId = state.pathParameters['gameId'] ?? 'unknown';
                    return NoTransitionPage(
                      child: GameMapSection(gameId: gameId),
                    );
                  },
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: GameChatSection.routePath,
                  name: GameChatSection.routeName,
                  pageBuilder: (context, state) {
                    final gameId = state.pathParameters['gameId'] ?? 'unknown';
                    return NoTransitionPage(
                      child: GameChatSection(gameId: gameId),
                    );
                  },
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: GameSettingsSection.routePath,
                  name: GameSettingsSection.routeName,
                  pageBuilder: (context, state) {
                    final gameId = state.pathParameters['gameId'] ?? 'unknown';
                    return NoTransitionPage(
                      child: GameSettingsSection(gameId: gameId),
                    );
                  },
                ),
              ],
            ),
          ],
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
