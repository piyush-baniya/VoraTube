import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import 'screen_layout_editor_screen.dart';

/// The Customize Mini Player editor: delegates to the shared
/// [ScreenLayoutEditorScreen] with a mini-bar preview.
class CustomizeMiniPlayerScreen extends StatelessWidget {
  const CustomizeMiniPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenLayoutEditorScreen(
      screenId: kMiniScreenId,
      title: 'Customize Mini Player',
      savedMessage: 'Mini player layout saved.',
      previewBuilder: (context, layout) => _MiniLayoutPreview(layout: layout),
    );
  }
}

/// A stylized, always-updating representation of the configured mini bar.
class _MiniLayoutPreview extends StatelessWidget {
  const _MiniLayoutPreview({required this.layout});

  final ScreenLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    final soft = colorScheme.onSurfaceVariant.withValues(alpha: 0.18);

    final artwork = layout.component('mini.artwork');
    final trackInfo = layout.component('mini.trackInfo');
    final progress = layout.component('mini.progress');
    final secondary = layout.component('mini.secondaryControls');
    final artSize = switch (artwork?.size ?? ComponentSize.medium) {
      ComponentSize.small => 36.0,
      ComponentSize.medium => 44.0,
      ComponentSize.large => 52.0,
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
          height: artSize + 20,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
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
              Container(
                width: artSize,
                height: artSize,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(AppTokens.rMd),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (trackInfo?.visible ?? true) ...[
                      _pill(
                        trackInfo!.size == ComponentSize.small ? 8 : 10,
                        0.55,
                        soft,
                      ),
                      if (trackInfo.size != ComponentSize.small) ...[
                        const SizedBox(height: 4),
                        _pill(7, 0.35, soft),
                      ],
                      const SizedBox(height: 6),
                    ],
                    if (progress?.visible ?? true)
                      _pill(
                        progress!.styleId == 'bold' ? 4 : 2.5,
                        1.0,
                        accent.withValues(alpha: 0.65),
                      ),
                  ],
                ),
              ),
              if (secondary?.visible ?? true)
                Padding(
                  padding: const EdgeInsets.only(right: AppTokens.s2),
                  child: _circle(7, accent.withValues(alpha: 0.8)),
                ),
              _circle(13, soft, stroke: true),
              const SizedBox(width: AppTokens.s2),
              _circle(18, accent),
              const SizedBox(width: AppTokens.s2),
              _circle(13, soft, stroke: true),
            ],
          ),
        ),
      ],
    );
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
