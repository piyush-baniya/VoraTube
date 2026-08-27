import 'package:flutter/material.dart';

import '../../../../../app/theme/app_tokens.dart';

/// A single settings tile with title, subtitle, leading/trailing widgets.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.subtitleStyle,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? subtitleStyle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInteractive = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s4,
            vertical: AppTokens.s2,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppTokens.s3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style:
                            subtitleStyle ??
                            theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
