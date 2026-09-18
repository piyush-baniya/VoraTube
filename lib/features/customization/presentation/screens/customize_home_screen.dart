import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import 'screen_layout_editor_screen.dart';

/// The Customize Home editor: delegates to the shared [ScreenLayoutEditorScreen]
/// with a Home-specific preview.
class CustomizeHomeScreen extends StatelessWidget {
  const CustomizeHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenLayoutEditorScreen(
      screenId: kHomeScreenId,
      title: 'Customize Home',
      savedMessage: 'Home layout saved.',
      previewBuilder: (context, layout) => _HomeLayoutPreview(layout: layout),
    );
  }
}

/// A stylized, always-updating representation of the configured Home.
class _HomeLayoutPreview extends StatelessWidget {
  const _HomeLayoutPreview({required this.layout});

  final ScreenLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
          height: 216,
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
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final component in layout.components)
                  if (component.visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.s2),
                      child: _PreviewBlock(component: component),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One section's stylized preview block. Dimensions track the component's
/// size preset and shape tracks its style, so the preview reflects edits.
class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({required this.component});

  final ComponentLayout component;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final soft = colorScheme.onSurfaceVariant.withValues(alpha: 0.18);

    switch (component.id) {
      case 'home.continueListening':
        final height = switch (component.size) {
          ComponentSize.small => 44.0,
          ComponentSize.medium => 62.0,
          ComponentSize.large => 82.0,
        };
        return _block(
          height: height,
          color: accent.withValues(alpha: 0.16),
          child: Row(
            children: [
              _square(height - 16, accent.withValues(alpha: 0.35)),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(0.5, soft),
                    if (component.styleId != 'compact') ...[
                      const SizedBox(height: 6),
                      _bar(0.3, soft),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      case 'home.listeningInsights':
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _block(
                    height: component.size == ComponentSize.small ? 26 : 32,
                    color: accent.withValues(alpha: 0.12),
                    child: _bar(0.5, soft),
                  ),
                ),
                const SizedBox(width: AppTokens.s2),
                Expanded(
                  child: _block(
                    height: component.size == ComponentSize.small ? 26 : 32,
                    color: accent.withValues(alpha: 0.12),
                    child: _bar(0.5, soft),
                  ),
                ),
              ],
            ),
            if (component.styleId != 'chips' &&
                component.size != ComponentSize.small) ...[
              const SizedBox(height: AppTokens.s2),
              _block(
                height: 40,
                color: accent.withValues(alpha: 0.18),
                child: _bar(0.6, soft),
              ),
            ],
          ],
        );
      case 'home.playlists':
        if (component.styleId == 'grid') {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                ],
              ),
              const SizedBox(height: AppTokens.s2),
              Row(
                children: [
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: AppTokens.s2),
              SizedBox(
                width: 54,
                child: _squareBlock(accent.withValues(alpha: 0.14)),
              ),
            ],
          ],
        );
      case 'home.allSongs':
        final rows = switch (component.size) {
          ComponentSize.small => 2,
          ComponentSize.medium => 3,
          ComponentSize.large => 4,
        };
        return Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: AppTokens.s2),
              Row(
                children: [
                  _square(22, accent.withValues(alpha: 0.14)),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(child: _bar(0.7, soft)),
                ],
              ),
            ],
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _block({
    required double height,
    required Color color,
    required Widget child,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: child,
    );
  }

  Widget _squareBlock(Color color) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
    );
  }

  Widget _square(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
    );
  }

  Widget _bar(double widthFactor, Color color) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppTokens.rFull),
        ),
      ),
    );
  }
}
