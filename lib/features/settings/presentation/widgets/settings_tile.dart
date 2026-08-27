import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../../../shared/widgets/pressable_scale.dart';

/// A premium settings tile with title, subtitle, leading/trailing widgets.
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
    this.showDivider = true,
    this.contentPadding,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? subtitleStyle;
  final VoidCallback? onLongPress;
  final bool showDivider;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isInteractive = onTap != null;

    return Column(
      children: [
        PressableScale(
          onTap: onTap,
          onLongPress: onLongPress,
          scale: 0.99,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding:
                    contentPadding ??
                    const EdgeInsets.symmetric(
                      horizontal: AppTokens.s5,
                      vertical: AppTokens.s3,
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
                              color: colorScheme.onSurface,
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
                                    height: 1.4,
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
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s5 + 48 + AppTokens.s3,
              0,
              AppTokens.s5,
              0,
            ),
            child: Divider(
              height: AppTokens.borderHairline,
              thickness: AppTokens.borderHairline,
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              indent: 0,
              endIndent: 0,
            ),
          ),
      ],
    );
  }
}

/// A settings tile with a switch toggle.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SettingsTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: colorScheme.primary,
        activeTrackColor: colorScheme.primary.withValues(alpha: 0.32),
        inactiveThumbColor: isDark
            ? AppColors.textTertiaryDark
            : AppColors.textTertiaryLight,
        inactiveTrackColor: isDark
            ? AppColors.surfaceHighDark
            : AppColors.surfaceHighLight,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onTap: onTap ?? () => onChanged(!value),
    );
  }
}

/// A settings tile with a slider.
class SettingsSliderTile extends StatelessWidget {
  const SettingsSliderTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.divisions,
    this.label,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int divisions;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SettingsTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s5,
        vertical: AppTokens.s4,
      ),
      trailing: SizedBox(
        width: 120,
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          label: label,
          activeColor: colorScheme.primary,
          inactiveColor: colorScheme.surfaceContainerHighest,
          thumbColor: colorScheme.primary,
          overlayColor: WidgetStateProperty.all(
            colorScheme.primary.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}

/// A settings tile with a popup menu for selection.
class SettingsSelectTile<T> extends StatelessWidget {
  const SettingsSelectTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
    required this.items,
    this.itemBuilder,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final T value;
  final ValueChanged<T> onChanged;
  final List<T> items;
  final Widget Function(BuildContext, T)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SettingsTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: PopupMenuButton<T>(
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (context) => items.map((item) {
          return PopupMenuItem<T>(
            value: item,
            child: itemBuilder?.call(context, item) ?? Text(item.toString()),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
          child: Text(
            value.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings tile with a button action.
class SettingsActionTile extends StatelessWidget {
  const SettingsActionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.buttonText,
    required this.onPressed,
    this.buttonStyle = FilledButton.styleFrom,
    this.isDestructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final String buttonText;
  final VoidCallback onPressed;
  final ButtonStyle Function() buttonStyle;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SettingsTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: FilledButton.tonal(
        onPressed: onPressed,
        style: buttonStyle().copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (isDestructive) {
              return colorScheme.error;
            }
            return colorScheme.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (isDestructive) {
              return colorScheme.onError;
            }
            return colorScheme.onSurface;
          }),
        ),
        child: Text(buttonText),
      ),
    );
  }
}
