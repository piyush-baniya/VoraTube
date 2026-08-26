import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'theme/app_theme.dart';

class VoraTubeApp extends StatelessWidget {
  const VoraTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoraTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
