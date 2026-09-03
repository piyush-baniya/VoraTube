import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// In-app Privacy Policy for VoraTube.
///
/// A clean, readable document-style screen matching the rest of the app's
/// theme. Content reflects the published policy (kept in sync with
/// PRIVACY_POLICY.md and the website) and is framed appropriately for a
/// personal, local music-player application.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: const [
          _PolicyIntro(),
          _PolicySection(
            title: 'Information VoraTube accesses',
            body:
                'VoraTube accesses only what it needs to work as a local music '
                'player: your audio files that already exist on the device, '
                'their metadata (title, artist, album, duration, genre, embedded '
                'artwork), your playback state (song, queue, position, '
                'playlists, favorites, history), and settings you choose in the '
                'App. It does not access your contacts, location, camera, '
                'microphone, or messages.',
          ),
          _PolicySection(
            title: 'Information stored locally on your device',
            body:
                'VoraTube keeps a local database and cache on your device for '
                'your library, playlists, favorites, playback history and '
                'statistics, queue state and playback position, settings, and '
                'cached artwork and lyrics. All of this stays on your device. '
                'VoraTube does not operate a server or cloud storage, and does '
                'not upload your audio files anywhere.',
          ),
          _PolicySection(
            title: 'Music and media permissions',
            body:
                'On Android, VoraTube requests the "Music and audio" permission '
                '(READ_MEDIA_AUDIO) so it can find and play the music on your '
                'device. On older versions it may request storage access for the '
                'same purpose. Your music files are not uploaded. If you use the '
                'ringtone cutter, the "Modify system settings" permission is '
                'used only when you ask to set a cut audio as your ringtone.',
          ),
          _PolicySection(
            title: 'Network communications',
            body:
                'VoraTube needs an internet connection for a small number of '
                'features and never transmits your audio files. For lyrics it '
                'may send a song\u2019s title, artist, and album to the public '
                'LRCLIB service. For genre enrichment it may send a song\u2019s '
                'title and artist to Apple\u2019s iTunes Search API. These '
                'lookups are automatic and best-effort, and results are cached '
                'locally. User-initiated actions include "Find on YouTube" and '
                'opening a donation page, which are only triggered when you tap '
                'them.',
          ),
          _PolicySection(
            title: 'Advertising',
            body:
                'The App integrates the Google Mobile Ads SDK to show banner '
                'and interstitial advertisements. When ads are shown, Google and '
                'its partners may process information under Google\u2019s own '
                'privacy policy. Activating Premium disables all ad placements '
                'and no ad requests are made.',
          ),
          _PolicySection(
            title: 'Accounts and analytics',
            body:
                'VoraTube has no user accounts, no login system, and no cloud '
                'account. It does not include its own analytics or crash-'
                'reporting service and does not build user profiles or track '
                'you across apps or websites.',
          ),
          _PolicySection(
            title: 'Data sharing and security',
            body:
                'VoraTube does not sell, rent, or share your personal data, '
                'because it does not collect personal data on any server. '
                'Information leaves your device only in the limited ways '
                'described above (song metadata to lyrics/genre lookups, '
                'user-initiated pages, and the advertising SDK). Your VoraTube '
                'data is stored locally under Android\u2019s standard app '
                'sandboxing, and communications with lookup services use HTTPS.',
          ),
          _PolicySection(
            title: 'Data retention and deletion',
            body:
                'Your local VoraTube data remains on your device until you '
                'delete it through the App, clear the App\u2019s data in your '
                'device settings, or uninstall the App. VoraTube cannot delete '
                'data retained by third parties such as LRCLIB, Apple, YouTube, '
                'Buy Me a Momo, or Google\u2019s advertising infrastructure.',
          ),
          _PolicySection(
            title: 'Children\u2019s privacy',
            body:
                'VoraTube is a general-audience local music player. It does not '
                'operate accounts or servers and does not knowingly collect '
                'personal information from anyone, including children under 13.',
          ),
          _PolicySection(
            title: 'Changes to this privacy policy',
            body:
                'This privacy policy may be updated as VoraTube evolves (for '
                'example when production advertising is introduced). The current '
                'version is always available within the App and at the policy '
                'URL linked from the App.',
          ),
          _PolicySection(
            title: 'Contact',
            body:
                'If you have questions about this privacy policy or about '
                'VoraTube\u2019s data practices, contact the developer, Piyush '
                'Das, at baniyapiyushwork@gmail.com.',
          ),
          SizedBox(height: AppTokens.s6),
        ],
      ),
    );
  }
}

class _PolicyIntro extends StatelessWidget {
  const _PolicyIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      padding: const EdgeInsets.all(AppTokens.s4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.2),
          width: AppTokens.borderHairline,
        ),
      ),
      child: Text(
        'The short version: your music files and your listening data stay on '
        'your device. VoraTube has no user accounts, no cloud music storage, '
        'and no server-side user profiles. It does send small, non-identifying '
        'song details to third-party lookup services so it can show lyrics and '
        'genres, and it displays ads unless you activate Premium.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          height: 1.5,
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
