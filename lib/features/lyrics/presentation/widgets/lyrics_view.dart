import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/lyrics.dart';
import '../providers/lyrics_providers.dart';

/// Displays lyrics for the currently playing song.
///
/// Shows synced lyrics with current-line highlighting and auto-scrolling,
/// or plain lyrics as a static list, or an appropriate empty state.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key, this.height});

  final double? height;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastHighlightedIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLine(int index) {
    if (!_scrollController.hasClients) return;
    if (index == _lastHighlightedIndex) return;
    _lastHighlightedIndex = index;

    final targetOffset = (index * 52.0) - 100.0;
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyricsAsync = ref.watch(currentLyricsProvider);
    final notifier = ref.read(currentLyricsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: widget.height ?? 280,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rLg),
        ),
      ),
      child: lyricsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => _buildEmpty(
          context,
          icon: Icons.error_outline_rounded,
          message: 'Lyrics unavailable',
        ),
        data: (result) {
          switch (result.status) {
            case LyricsStatus.loading:
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            case LyricsStatus.notFound:
              return _buildEmpty(
                context,
                icon: Icons.lyrics_outlined,
                message: 'No lyrics available',
              );
            case LyricsStatus.error:
              return _buildEmpty(
                context,
                icon: Icons.cloud_off_rounded,
                message: 'Lyrics unavailable',
              );
            case LyricsStatus.offline:
              return _buildEmpty(
                context,
                icon: Icons.cloud_off_rounded,
                message: 'Offline — lyrics unavailable',
              );
            case LyricsStatus.loaded:
              final data = result.data!;
              if (data.isInstrumental) {
                return _buildEmpty(
                  context,
                  icon: Icons.piano_rounded,
                  message: 'Instrumental',
                );
              }
              if (data.isEmpty) {
                return _buildEmpty(
                  context,
                  icon: Icons.lyrics_outlined,
                  message: 'No lyrics available',
                );
              }
              if (data.hasSyncedLines) {
                return _buildSyncedLyrics(
                  context,
                  data,
                  notifier,
                  colorScheme,
                  textTheme,
                );
              }
              return _buildPlainLyrics(context, data, colorScheme, textTheme);
          }
        },
      ),
    );
  }

  Widget _buildSyncedLyrics(
    BuildContext context,
    LyricsData data,
    CurrentLyricsNotifier notifier,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final currentLineIndex = notifier.currentLineIndex;

    if (currentLineIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLine(currentLineIndex);
      });
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s6,
        vertical: AppTokens.s4,
      ),
      itemCount: data.lines.length,
      itemBuilder: (context, index) {
        final line = data.lines[index];
        final isCurrent = index == currentLineIndex;
        final isPast = currentLineIndex >= 0 && index < currentLineIndex;

        return GestureDetector(
          onTap: () => notifier.seekToLine(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s2,
              vertical: AppTokens.s1,
            ),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                fontSize: isCurrent ? 18 : 15,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                color: isCurrent
                    ? colorScheme.onSurface
                    : isPast
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlainLyrics(
    BuildContext context,
    LyricsData data,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s6,
        vertical: AppTokens.s4,
      ),
      itemCount: data.lines.length,
      itemBuilder: (context, index) {
        final line = data.lines[index];
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s2,
            vertical: AppTokens.s1,
          ),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 40,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            message,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
