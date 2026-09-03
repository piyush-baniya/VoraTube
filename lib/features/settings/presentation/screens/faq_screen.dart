import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// In-app FAQ for VoraTube.
///
/// Uses expandable/collapsible question cards that never overflow. Every answer
/// reflects functionality that actually exists in the repository.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const List<({String question, String answer})> entries = [
    (
      question: 'How do I add music to VoraTube?',
      answer:
          'VoraTube reads music that already exists on your device. On '
          'Android, your music library is scanned from the device when the app '
          'starts, and you can scan again anytime from Settings > Library > '
          '"Rescan Library". On iOS, you add music by importing files you '
          'choose yourself.\n\nNo music is ever uploaded — everything stays on '
          'your device.',
    ),
    (
      question: 'Why isn\u2019t a song appearing?',
      answer:
          'A song may be missing because:\n\u2022 The library scan hasn\u2019t '
          'picked it up yet — try Settings > Library > "Rescan Library".\n'
          '\u2022 The file was hidden using the song\u2019s "Hide song" option. '
          'You can restore it from Settings > Library > "Show Hidden Songs".\n'
          '\u2022 The file is not tagged as audio or is not supported by your '
          'device.\n\nIf you recently moved files to your device, a rescan '
          'usually makes them appear.',
    ),
    (
      question: 'How do I refresh my music library?',
      answer:
          'Open Settings > Library and tap "Rescan Library". This checks for '
          'newly added or changed music files and adds them without removing '
          'your playlists, favorites, history, or other data.',
    ),
    (
      question: 'How do I create a playlist?',
      answer:
          'Go to the Playlists tab and create a new playlist. You can add any '
          'song to a playlist from its "More options" (three-dot) menu, and '
          'reorder songs inside a playlist by dragging them.',
    ),
    (
      question: 'How do I play music in the background?',
      answer:
          'Just leave the app open or switch to another app — playback '
          'continues in the background with controls available from the '
          'notification and the lock screen.',
    ),
    (
      question: 'How do I set a song as a ringtone?',
      answer:
          'Open a song\u2019s "More options" (three-dot) menu and choose the '
          'ringtone option. You can cut a portion of the song and save it as '
          'your ringtone. Setting a ringtone is optional and only happens when '
          'you choose to do so.',
    ),
    (
      question: 'Where are downloaded/local songs stored?',
      answer:
          'VoraTube plays music that is already on your device \u2014 VoraTube '
          'does not download or store your music files in the cloud. Songs '
          'stay wherever they are on your device, and any ringtones you create '
          'are saved in app storage and your device\u2019s media library.',
    ),
    (
      question: 'How does the lyrics feature work?',
      answer:
          'Lyrics are shown for a song when they are already embedded in the '
          'file or cached on your device. If lyrics are not available locally, '
          'VoraTube may look them up by sending the song\u2019s title and '
          'artist to a lyrics provider. Playback works fine even when a lyrics '
          'lookup is unavailable.',
    ),
    (
      question: 'Does VoraTube upload my music?',
      answer:
          'No. VoraTube is a local music player and does not upload your music '
          'files, playlists, or listening history anywhere. There are no '
          'VoraTube servers holding your music.',
    ),
    (
      question: 'Does VoraTube require an account?',
      answer:
          'No. VoraTube has no user accounts and no login system. You can use '
          'all of its features without signing up for anything.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppTokens.s4),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppTokens.s2),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _FaqCard(question: entry.question, answer: entry.answer);
        },
      ),
    );
  }
}

class _FaqCard extends StatefulWidget {
  const _FaqCard({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AnimatedSize(
      duration: AppTokens.medium,
      curve: AppTokens.easeOut,
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s4,
              vertical: AppTokens.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.s2),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: AppTokens.fast,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: AppTokens.s3),
                  Text(
                    widget.answer,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
