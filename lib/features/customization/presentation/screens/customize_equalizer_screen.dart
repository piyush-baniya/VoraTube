import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import 'screen_layout_editor_screen.dart';

/// The Customize Equalizer editor: delegates to the shared
/// [ScreenLayoutEditorScreen] with an equalizer preview.
class CustomizeEqualizerScreen extends StatelessWidget {
  const CustomizeEqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenLayoutEditorScreen(
      screenId: kEqualizerScreenId,
      title: 'Customize Equalizer',
      savedMessage: 'Equalizer layout saved.',
      previewBuilder: (context, layout) =>
          _EqualizerLayoutPreview(layout: layout),
    );
  }
}

/// A stylized representation of the Equalizer screen: the protected graph is
/// always drawn, and every other block follows the configured visibility.
class _EqualizerLayoutPreview extends StatelessWidget {
  const _EqualizerLayoutPreview({required this.layout});

  final ScreenLayout layout;

  bool _visible(String id) => layout.component(id)?.visible ?? true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    final soft = colorScheme.onSurfaceVariant.withValues(alpha: 0.18);

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _pill(10, 42, soft),
                  const Spacer(),
                  _pill(10, 46, accent.withValues(alpha: 0.5)),
                ],
              ),
              if (_visible('equalizer.nowPlaying')) ...[
                const SizedBox(height: AppTokens.s2),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(AppTokens.rSm),
                      ),
                    ),
                    const SizedBox(width: AppTokens.s2),
                    Expanded(child: _pill(9, 0.6, soft)),
                  ],
                ),
              ],
              const SizedBox(height: AppTokens.s2),
              // The curve is protected: always visible in the preview.
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTokens.rMd),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: CustomPaint(painter: _PreviewCurvePainter(accent)),
              ),
              const SizedBox(height: AppTokens.s2),
              if (_visible('equalizer.presets'))
                Wrap(
                  spacing: AppTokens.s1,
                  runSpacing: AppTokens.s1,
                  children: [
                    for (var i = 0; i < 4; i++)
                      Container(
                        width: 30 + i * 6,
                        height: 18,
                        decoration: BoxDecoration(
                          color: i == 0 ? accent.withValues(alpha: 0.6) : soft,
                          borderRadius: BorderRadius.circular(AppTokens.rFull),
                        ),
                      ),
                  ],
                ),
              if (_visible('equalizer.quickControls')) ...[
                const SizedBox(height: AppTokens.s2),
                for (var i = 0; i < 2; i++) ...[
                  _track(5, accent, soft),
                  const SizedBox(height: AppTokens.s1),
                ],
              ],
              if (_visible('equalizer.bandControls')) ...[
                const SizedBox(height: AppTokens.s1),
                for (var i = 0; i < 2; i++) ...[
                  Row(
                    children: [
                      _pill(8, 0.2, soft),
                      const SizedBox(width: AppTokens.s1),
                      Expanded(child: _track(5, accent, soft)),
                    ],
                  ),
                  const SizedBox(height: AppTokens.s1),
                ],
              ],
              if (_visible('equalizer.preamp')) ...[
                const SizedBox(height: AppTokens.s1),
                Row(
                  children: [
                    _pill(8, 0.3, soft),
                    const SizedBox(width: AppTokens.s1),
                    Expanded(child: _track(5, accent, soft)),
                  ],
                ),
              ],
              if (_visible('equalizer.processing')) ...[
                const SizedBox(height: AppTokens.s2),
                for (var i = 0; i < 2; i++) ...[
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: AppTokens.s2),
                      Expanded(child: _pill(8, 0.5, soft)),
                    ],
                  ),
                  const SizedBox(height: AppTokens.s1),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(double height, double width, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.rFull),
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
          widthFactor: 0.4,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(AppTokens.rFull),
            ),
          ),
        ),
        Container(
          width: height + 4,
          height: height + 4,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
        ),
      ],
    );
  }
}

class _PreviewCurvePainter extends CustomPainter {
  const _PreviewCurvePainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final path = Path();
    const samples = [0.45, 0.3, 0.55, 0.7, 0.4, 0.6, 0.35, 0.5, 0.65, 0.45];
    for (var i = 0; i < samples.length; i++) {
      final x = size.width / (samples.length - 1) * i;
      final y = size.height * samples[i];
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PreviewCurvePainter oldDelegate) =>
      oldDelegate.accent != accent;
}
