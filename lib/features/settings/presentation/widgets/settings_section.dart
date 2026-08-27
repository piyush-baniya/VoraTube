import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// A settings section with a title and children.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s4,
            0,
            AppTokens.s4,
            AppTokens.s2,
          ),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rMd),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
