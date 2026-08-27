import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_shell.dart';
import 'theme/app_theme.dart';
import '../features/settings/presentation/providers/settings_providers.dart';

class VoraTubeApp extends ConsumerWidget {
  const VoraTubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'VoraTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}
