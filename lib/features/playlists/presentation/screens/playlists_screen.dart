import 'package:flutter/material.dart';

import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/screen_header.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: 'Playlists'),
          Expanded(
            child: EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'No playlists yet',
              message: 'Create your first playlist.',
            ),
          ),
        ],
      ),
    );
  }
}
