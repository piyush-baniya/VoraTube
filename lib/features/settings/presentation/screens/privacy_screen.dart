import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// Plain-language explanation of VoraTube's implemented data behaviour.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: const [
          _PrivacySection(
            icon: Icons.phone_android_rounded,
            title: 'Your library stays on your device',
            body: 'VoraTube reads music you already own. Song metadata, favorites, playlists, play history, queue state, and settings are stored locally on this device.',
          ),
          _PrivacySection(
            icon: Icons.image_outlined,
            title: 'Artwork and cache',
            body: 'Artwork thumbnails and cached lyrics are kept in the app’s local storage to make browsing and playback faster.',
          ),
          _PrivacySection(
            icon: Icons.lyrics_outlined,
            title: 'Lyrics',
            body: 'When lyrics are not already embedded or cached, VoraTube can send song and artist metadata to its lyrics provider to look them up. Playback does not depend on that request.',
          ),
          _PrivacySection(
            icon: Icons.open_in_new_rounded,
            title: 'External pages',
            body: 'Find on YouTube opens an external search, and Support the Developer opens the Buy Me a Momo page. Those services handle their own data under their policies.',
          ),
          _PrivacySection(
            icon: Icons.insights_outlined,
            title: 'No built-in analytics',
            body: 'This app has no analytics or account system in its code. It does not upload your music library, listening history, or playlists.',
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      padding: const EdgeInsets.all(AppTokens.s4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppTokens.s1),
                Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
