import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'bootstrap.dart';

Future<void> main() async {
  await bootstrap(() async {
    runApp(
      const ProviderScope(
        child: YamaGoApp(),
      ),
    );
  });
}
