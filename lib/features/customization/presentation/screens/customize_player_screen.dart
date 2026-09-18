import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import 'screen_layout_editor_screen.dart';

/// The Customize Player editor: delegates to the shared
/// [ScreenLayoutEditorScreen] with a full-player preview.
class CustomizePlayerScreen extends StatelessWidget {
  const CustomizePlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenLayoutEditorScreen(
      screenId: kPlayerScreenId,
      title: 'Customize Player',
      savedMessage: 'Player layout saved.',
      previewBuilder: (context, layout) => _PlayerLayoutPreview(layout: layout),
    );
  }
}

/// A stylized, always-updating representation of the configured full player:
/// artwork on the left, the transport stack on the right.
class _PlayerLayoutPreview extends StatelessWidget {
  const _PlayerLayoutPreview({required this.layout});

  final ScreenLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    final soft = colorScheme.onSurfaceVariant.withValues(alpha: 0.18);

    final ordered = groupPlayerZones(layout.components);
    final artwork = ordered.firstWhere(
      (c) => c.id == 'player.artwork',
      orElse: () => layout.components.first,
    );
    final artSize = switch (artwork.size) {
      ComponentSize.small => 72.0,
      ComponentSize.medium => 92.0,
      ComponentSize.large => 116.0,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s1),
          child: Text(
            'PREVIEW',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          height: 168,
          padding: const EdgeInsets.all(AppTokens.s3),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTokens.rXl),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: AppTokens.borderHairline,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: artSize,
                child: Center(
                  child: Container(
                    width: artSize,
                    height: artSize,
                    decoration: BoxDecoration(
                      color: artwork.styleId == 'immersive'
                          ? accent.withValues(alpha: 0.42)
                          : accent.withValues(alpha: 0.24),
                      borderRadius: artwork.styleId == 'immersive'
                          ? BorderRadius.circular(AppTokens.rSm)
                          : BorderRadius.circular(AppTokens.rLg),
                      boxShadow: artwork.styleId == 'immersive'
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final component in ordered)
                      if (component.visible && component.id != 'player.artwork')
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.s1,
                          ),
                          child: _previewBlock(
                            component: component,
                            accent: accent,
                            soft: soft,
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewBlock({
    required ComponentLayout component,
    required Color accent,
    required Color soft,
  }) {
    switch (component.id) {
      case 'player.trackInfo':
        final titleHeight = switch (component.size) {
          ComponentSize.small => 9.0,
          ComponentSize.medium => 11.0,
          ComponentSize.large => 14.0,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pill(titleHeight, 0.55, soft),
            const SizedBox(height: 4),
            _pill(titleHeight - 3, 0.35, soft),
          ],
        );
      case 'player.progress':
        final barHeight = switch (component.size) {
          ComponentSize.small => 4.0,
          ComponentSize.medium => 6.0,
          ComponentSize.large => 9.0,
        };
        return _track(barHeight, accent, soft);
      case 'player.secondaryControls':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: AppTokens.s2),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: i == 0 ? 0.9 : 0.35),
                ),
              ),
            ],
          ],
        );
      case 'player.primaryControls':
        final playSize = switch (component.size) {
          ComponentSize.small => 20.0,
          ComponentSize.medium => 26.0,
          ComponentSize.large => 32.0,
        };
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _circle(9, soft, stroke: true),
            const SizedBox(width: AppTokens.s2),
            _circle(playSize, accent),
            const SizedBox(width: AppTokens.s2),
            _circle(9, soft, stroke: true),
          ],
        );
      case 'player.quickActions':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _circle(8, accent.withValues(alpha: 0.5)),
            const SizedBox(width: AppTokens.s2),
            _circle(8, soft, stroke: true),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _pill(double height, double widthFactor, Color color) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppTokens.rFull),
        ),
      ),
    );
  }

  Widget _track(double height, Color accent, Color soft) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(AppTokens.rFull),
          ),
        ),
        FractionallySizedBox(
          widthFactor: 0.45,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AppTokens.rFull),
            ),
          ),
        ),
        Container(
          width: height + 5,
          height: height + 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
        ),
      ],
    );
  }

  Widget _circle(double size, Color color, {bool stroke = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: stroke ? Colors.transparent : color,
        border: stroke ? Border.all(color: color, width: 1.5) : null,
      ),
    );
  }
}
