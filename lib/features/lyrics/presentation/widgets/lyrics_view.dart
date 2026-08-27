import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
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

class _LyricsViewState extends ConsumerState<LyricsView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  /// Whether the user is currently manually scrolling.
  /// Auto-scroll is paused while this is true.
  bool _isUserScrolling = false;

  /// Timer to resume auto-scroll after user stops scrolling.
  Timer? _userScrollTimer;

  /// Tracks the last highlighted line to avoid duplicate scroll requests.
  int _lastHighlightedIndex = -1;

  /// Animation controller for line highlight transitions.
  late final AnimationController _highlightController;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      duration: AppTokens.fast,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _userScrollTimer?.cancel();
    _scrollController.dispose();
    _highlightController.dispose();
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
      final estimatedItemHeight = 48.0;
      final targetOffset = (index * estimatedItemHeight) - 120.0;
      final clampedOffset = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      try {
        _scrollController.animateTo(
          clampedOffset,
          duration: AppTokens.medium,
          curve: AppTokens.easeOut,
        );
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyricsAsync = ref.watch(currentLyricsProvider);
    final notifier = ref.read(currentLyricsProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: widget.height ?? 320,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.9)
            : AppColors.surfaceLight.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXl),
        ),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: AppTokens.borderHairline,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 24,
            offset: const Offset(0, -8),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXl),
        ),
        child: lyricsAsync.when(
          loading: () => _buildLoadingState(),
          error: (_, __) => _buildEmptyState(
            icon: Icons.error_outline_rounded,
            message: 'Lyrics unavailable',
            subtitle: 'Unable to load lyrics at this time',
          ),
          data: (result) {
            switch (result.status) {
              case LyricsStatus.loading:
                return _buildLoadingState();
              case LyricsStatus.notFound:
                return _buildEmptyState(
                  icon: Icons.lyrics_outlined,
                  message: 'No lyrics available',
                  subtitle: 'This song doesn\'t have lyrics yet',
                );
              case LyricsStatus.error:
                return _buildEmptyState(
                  icon: Icons.cloud_off_rounded,
                  message: 'Lyrics unavailable',
                  subtitle: 'Failed to fetch lyrics',
                );
              case LyricsStatus.offline:
                return _buildEmptyState(
                  icon: Icons.cloud_off_rounded,
                  message: 'Offline — lyrics unavailable',
                  subtitle: 'Connect to the internet to fetch lyrics',
                );
              case LyricsStatus.loaded:
                final data = result.data!;
                if (data.isInstrumental) {
                  return _buildEmptyState(
                    icon: Icons.piano_rounded,
                    message: 'Instrumental',
                    subtitle: 'This track has no vocals',
                  );
                }
                if (data.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.lyrics_outlined,
                    message: 'No lyrics available',
                    subtitle: 'This song doesn\'t have lyrics yet',
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
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppTokens.s4),
          Text(
            'Fetching lyrics...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.15),
                    Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.03),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppTokens.s5),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s6,
              vertical: AppTokens.s5,
            ),
            itemCount: data.lines.length,
            itemBuilder: (context, index) {
              final line = data.lines[index];
              final isCurrent = index == currentLineIndex;
              final isPast = currentLineIndex >= 0 && index < currentLineIndex;
              final isUpcoming =
                  currentLineIndex >= 0 && index > currentLineIndex + 1;

              return _SyncedLyricLine(
                key: ValueKey(index),
                line: line,
                isCurrent: isCurrent,
                isPast: isPast,
                isUpcoming: isUpcoming,
                onTap: () => notifier.seekToLine(index),
                colorScheme: colorScheme,
                textTheme: textTheme,
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
        vertical: AppTokens.s5,
      ),
      itemCount: data.lines.length,
      itemBuilder: (context, index) {
        final line = data.lines[index];
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3,
            vertical: AppTokens.s2,
          ),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.7,
            ),
          ),
        );
      },
    );
  }
}

class _SyncedLyricLine extends StatefulWidget {
  const _SyncedLyricLine({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.isPast,
    required this.isUpcoming,
    required this.onTap,
    required this.colorScheme,
    required this.textTheme,
  });

  final LyricsLine line;
  final bool isCurrent;
  final bool isPast;
  final bool isUpcoming;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  State<_SyncedLyricLine> createState() => _SyncedLyricLineState();
}

class _SyncedLyricLineState extends State<_SyncedLyricLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: AppTokens.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController, curve: AppTokens.press),
    );

    if (widget.isCurrent) {
      _scaleController.forward();
    }
  }

  @override
  void didUpdateWidget(_SyncedLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent != oldWidget.isCurrent) {
      if (widget.isCurrent) {
        _scaleController.forward();
      } else {
        _scaleController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = widget.isCurrent;
    final isPast = widget.isPast;
    final isUpcoming = widget.isUpcoming;

    Color textColor;
    double fontSize;
    FontWeight fontWeight;
    double opacity;

    if (isCurrent) {
      textColor = widget.colorScheme.onSurface;
      fontSize = 20;
      fontWeight = FontWeight.w700;
      opacity = 1.0;
    } else if (isPast) {
      textColor = widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
      fontSize = 15;
      fontWeight = FontWeight.w400;
      opacity = 0.7;
    } else if (isUpcoming) {
      textColor = widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
      fontSize = 15;
      fontWeight = FontWeight.w400;
      opacity = 0.5;
    } else {
      textColor = widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
      fontSize = 15;
      fontWeight = FontWeight.w400;
      opacity = 1.0;
    }

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: opacity,
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: AppTokens.fast,
                curve: AppTokens.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s3,
                  vertical: AppTokens.s2,
                ),
                child: Text(
                  widget.line.text,
                  textAlign: TextAlign.center,
                  style: widget.textTheme.bodyLarge?.copyWith(
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    color: textColor,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
