import 'package:flutter/material.dart';

import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/screen_header.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'Settings'),
          Expanded(
            child: EmptyState(
              icon: Icons.tune_rounded,
              title: 'Nothing to configure yet',
              message:
                  'Playback, appearance and about options will appear here.',
            ),
          ),
        ],
      ),
    );
  }
}
