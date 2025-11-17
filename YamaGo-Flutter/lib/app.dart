import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';

/// Root widget for the YamaGo mobile application.
class YamaGoApp extends ConsumerWidget {
  const YamaGoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF22B59B),
      brightness: Brightness.dark,
    );

    return MaterialApp.router(
      title: 'YamaGo',
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF010A0E),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
        ),
      ),
    );
  }
}
