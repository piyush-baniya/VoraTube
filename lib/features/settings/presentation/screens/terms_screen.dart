import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// In-app Terms of Use for VoraTube.
///
/// A clean, readable, document-style screen that matches the rest of the app's
/// theme. The wording is deliberately appropriate for a personal, local
/// music-player application and makes no claims the app does not support. There
/// is no company, business entity or registered address — VoraTube is a local
/// music player.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Use')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: const [
          _TermsSection(
            title: 'Acceptance of Terms',
            body:
                'By downloading, installing, or using the VoraTube application '
                '("the App"), you agree to these Terms of Use. If you do not '
                'agree with any part of these terms, please do not use the App.',
          ),
          _TermsSection(
            title: 'Use of VoraTube',
            body:
                'VoraTube is a local-first music player designed to help you '
                'browse, organize, and play music that already exists on your '
                'device. You agree to use the App for lawful, personal, '
                'non-commercial purposes and in a manner that respects the '
                'rights of others. You may not misuse, reverse engineer, or '
                'attempt to disrupt the App.',
          ),
          _TermsSection(
            title: 'Local Music & Device Content',
            body:
                'The App reads audio files already present on your device '
                'through your device\u2019s library, or files you explicitly '
                'choose to import yourself. Your music files and your library '
                'data remain on your device. VoraTube does not upload your '
                'audio files to any server. You are responsible for ensuring '
                'you have the right to use and play the music on your device '
                'in accordance with applicable law.',
          ),
          _TermsSection(
            title: 'Third-Party Services',
            body:
                'To provide certain features, the App may send small, '
                'non-identifying details about a song (such as its title and '
                'artist) to third-party services for lyrics and genre lookup. '
                'The App may also open external websites you explicitly choose '
                'to visit, such as YouTube or a donation page. Those services '
                'are governed by their own terms and privacy policies, and '
                'VoraTube is not responsible for them.',
          ),
          _TermsSection(
            title: 'Advertising',
            body:
                'VoraTube is a fully released app and displays live, production '
                'advertisements served through the Google Mobile Ads SDK '
                '(Google AdMob), unless you activate Premium. Ads are provided '
                'by third parties under their own policies. Activating Premium '
                'is a local entitlement within the App and disables ad '
                'placements.',
          ),
          _TermsSection(
            title: 'Intellectual Property',
            body:
                'Unless stated otherwise, the VoraTube name, logo, and the '
                'interface of the App are the property of the developer. The '
                'music and artwork in your library remain the property of '
                'their respective owners.',
          ),
          _TermsSection(
            title: 'User Responsibility',
            body:
                'You are responsible for how you use the App and for the music '
                'you play through it. Please respect copyright and the rights '
                'of artists and rights holders. VoraTube is provided for use '
                'with media you are lawfully allowed to play.',
          ),
          _TermsSection(
            title: 'Availability',
            body:
                'VoraTube is a fully released app, publicly available on Google '
                'Play. It is provided "as is" and may be updated, changed, or '
                'discontinued at any time. The developer makes no guarantee '
                'that the App will always be available, free of errors, or '
                'compatible with every device.',
          ),
          _TermsSection(
            title: 'Limitation of Liability',
            body:
                'To the maximum extent permitted by law, the developer is not '
                'liable for any indirect, incidental, special, or '
                'consequential damages arising from your use of, or inability '
                'to use, the App. VoraTube does not claim that all music '
                'playback or features will be flawless on every device.',
          ),
          _TermsSection(
            title: 'Changes to These Terms',
            body:
                'These Terms of Use may be updated from time to time as the '
                'App evolves. The current version will always be available '
                'within the App. Continued use of the App after any change '
                'means you accept the updated terms.',
          ),
          _TermsSection(
            title: 'Contact',
            body:
                'If you have questions about these Terms of Use or about '
                'VoraTube, you can contact the developer, Piyush Das, at '
                'baniyapiyushwork@gmail.com.',
          ),
          SizedBox(height: AppTokens.s6),
        ],
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  const _TermsSection({required this.title, required this.body});

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
