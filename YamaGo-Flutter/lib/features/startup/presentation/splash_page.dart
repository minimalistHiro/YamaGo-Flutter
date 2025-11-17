import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yamago_flutter/core/services/firebase_providers.dart';
import 'package:yamago_flutter/features/auth/application/auth_providers.dart';
import 'package:yamago_flutter/features/onboarding/presentation/onboarding_pages.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  static const routeName = 'splash';
  static const routePath = '/splash';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    ref.listen(ensureAnonymousSignInProvider, (previous, next) {
      if (!next.hasValue || !context.mounted) return;
      context.go(WelcomePage.routePath);
    });

    final initState = ref.watch(firebaseAppProvider);
    final authState = ref.watch(ensureAnonymousSignInProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF010A0E),
              Color(0xFF052A2F),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'YamaGo',
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 16),
              switch ((initState, authState)) {
                (AsyncData(), AsyncData()) =>
                  const Icon(Icons.check_circle, size: 48),
                (_, AsyncError(:final error)) ||
                (AsyncError(:final error), _) =>
                  Column(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.redAccent),
                      const SizedBox(height: 8),
                      Text(
                        '初期化に失敗しました\n${error.toString()}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: () {
                              ref.invalidate(firebaseAppProvider);
                              ref.invalidate(ensureAnonymousSignInProvider);
                            },
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    ],
                  ),
                _ => const CircularProgressIndicator.adaptive(),
              },
              const SizedBox(height: 24),
              Text(
                authState.isLoading
                    ? 'Firebase で匿名サインイン中...'
                    : 'Firebase を初期化しています...',
                style: textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
