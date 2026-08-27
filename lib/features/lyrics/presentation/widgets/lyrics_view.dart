import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/lyrics.dart';
import '../providers/lyrics_providers.dart';

/// Displays lyrics for the currently playing song.
///
/// Shows synced lyrics with current-line highlighting and auto-scrolling,
/// or plain lyrics as a static list, or an appropriate empty state.
///
/// The lyrics view manages its own scroll behavior:
/// - Auto-follows the current line during playback
/// - Pauses auto-follow when the user manually scrolls
/// - Resumes auto-follow after the user stops scrolling
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key, this.height});

  final double? height;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();

  /// Whether the user is currently manually scrolling.
  /// Auto-scroll is paused while this is true.
  bool _isUserScrolling = false;

  /// Timer to resume auto-scroll after user stops scrolling.
  Timer? _userScrollTimer;

  /// Tracks the last highlighted line to avoid duplicate scroll requests.
  int _lastHighlightedIndex = -1;

  @override
  void dispose() {
    _userScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (_isAutoScrolling) return;

    // Detect user-initiated scroll start (drag gestures)
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _isUserScrolling = true;
      _userScrollTimer?.cancel();
    }

    // On scroll end, start a timer to resume auto-scroll
    if (notification is ScrollEndNotification && notification.depth == 0) {
      _userScrollTimer?.cancel();
      _userScrollTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
          });
        }
      });
    }
  }

  bool get _isAutoScrolling => _isUserScrolling == false;

  void _scrollToLine(int index) {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;
    if (_isUserScrolling) return;
    if (index == _lastHighlightedIndex) return;
    _lastHighlightedIndex = index;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;

      // Estimate offset based on approximate item height
      final estimatedItemHeight = 44.0;
      final targetOffset = (index * estimatedItemHeight) - 100.0;
      final clampedOffset = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      try {
        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } catch (_) {}
    });
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
    // Use ValueListenableBuilder for efficient real-time line index updates.
    // This rebuilds ONLY the lyrics list, not the entire LyricsView widget.
    return ValueListenableBuilder<int>(
      valueListenable: notifier.currentLineIndexNotifier,
      builder: (context, currentLineIndex, _) {
        // Scroll to the current line when it changes (and user isn't scrolling)
        if (currentLineIndex >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToLine(currentLineIndex);
          });
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _onScrollNotification(notification);
            return false;
          },
          child: ListView.builder(
            key: ValueKey<int>(currentLineIndex),
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
