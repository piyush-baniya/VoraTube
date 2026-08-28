import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/lyrics.dart';
import '../../../lyrics/presentation/providers/lyrics_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';

/// Compact lyrics panel that sits at the bottom of the full player.
///
/// Shows synced lyrics with current-line highlighting and auto-scroll,
/// or plain lyrics as a static list, or an appropriate empty state.
///
/// Height is constrained to 180-260 dp with a dark glass surface.
class CompactLyricsPanel extends ConsumerStatefulWidget {
  const CompactLyricsPanel({super.key, this.height = 220});

  final double height;

  @override
  ConsumerState<CompactLyricsPanel> createState() => _CompactLyricsPanelState();
}

class _CompactLyricsPanelState extends ConsumerState<CompactLyricsPanel>
    with SingleTickerProviderStateMixin {
  /// How long to wait after the user stops dragging before auto-follow
  /// takes over the scroll position again.
  static const Duration _autoFollowResumeDelay = Duration(seconds: 4);

  // Typography. Constant across every line so measured geometry stays valid.
  static const double _fontSize = 17;
  static const double _textHeight = 1.5;
  static const FontWeight _lineWeight = FontWeight.w600;
  static const double _linePadV = 8;
  static const double _linePadH = AppTokens.s3;
  static const double _minLineExtent = 38;
  static const double _activeScale = 1.05;

  /// Height of the collapsed "current line" preview.
  static const double _previewHeight = 76;

  final ScrollController _scrollController = ScrollController();

  /// Set in [dispose] before the controller is released. Every deferred
  /// callback checks this first.
  bool _disposed = false;

  /// Whether the panel shows the full lyrics list. When false, only a compact
  /// preview of the current line is shown; tapping expands it.
  bool _expanded = true;

  bool _isUserScrolling = false;
  Timer? _userScrollTimer;

  /// Last index auto-follow asked the list to centre on.
  int _lastRequestedIndex = -1;

  /// Latest index reported by the provider, used to re-arm auto-follow after
  /// the user stops scrolling without waiting for the next line change.
  int _lastKnownIndex = -1;

  /// At most one frame callback is ever outstanding.
  bool _scrollScheduled = false;
  int? _pendingIndex;

  // Cached line geometry.
  _LyricsMetrics? _metrics;
  List<LyricsLine>? _metricsSource;
  double _metricsWidth = 0;
  double _metricsScaleKey = 0;
  double _listTopPadding = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    // Order matters: mark disposed before releasing anything, so a frame
    // callback that fires between these lines cannot observe a live flag.
    _disposed = true;
    _userScrollTimer?.cancel();
    _userScrollTimer = null;
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollNotification(ScrollNotification notification) {
    // Only user drags may pause auto-follow. Programmatic `animateTo` scrolls
    // report a null `dragDetails`, so they can never disable following.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrollTimer?.cancel();
      _userScrollTimer = null;
      if (!_isUserScrolling) {
        setState(() => _isUserScrolling = true);
      }
      return;
    }

    if (notification is ScrollEndNotification && notification.depth == 0) {
      if (!_isUserScrolling) return;
      _userScrollTimer?.cancel();
      _userScrollTimer = Timer(_autoFollowResumeDelay, _resumeAutoFollow);
    }
  }

  void _toggleExpanded() {
    if (_disposed || !mounted) return;
    setState(() => _expanded = !_expanded);
  }

  void _resumeAutoFollow() {
    if (_disposed || !mounted) return;
    _userScrollTimer?.cancel();
    _userScrollTimer = null;
    if (_isUserScrolling) {
      setState(() => _isUserScrolling = false);
    }
    // Re-arm so the current line is recentred even if it has not advanced
    // while the user was reading.
    _lastRequestedIndex = -1;
    _requestScrollTo(_lastKnownIndex);
  }

  /// Queues a scroll to [index], collapsing repeated requests into a single
  /// post-frame callback.
  void _requestScrollTo(int index) {
    if (_disposed || index < 0) return;
    if (_isUserScrolling) return;

    _lastRequestedIndex = index;
    _pendingIndex = index;
    if (_scrollScheduled) return;
    _scrollScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _scrollScheduled = false;
      final target = _pendingIndex;
      _pendingIndex = null;
      if (target != null) _scrollToLine(target);
    });
  }

  void _scrollToLine(int index) {
    if (_disposed || !mounted) return;
    if (_isUserScrolling) return;
    if (!_scrollController.hasClients) return;

    final metrics = _metrics;
    if (metrics == null || index < 0 || index >= metrics.extents.length) return;

    final position = _scrollController.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return;
    }

    final centre =
        _listTopPadding + metrics.offsets[index] + (metrics.extents[index] / 2);
    final target = centre - (position.viewportDimension / 2);
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((clamped - position.pixels).abs() < 1.5) return;

    if (MediaQuery.disableAnimationsOf(context)) {
      _scrollController.jumpTo(clamped);
      return;
    }
    _scrollController.animateTo(
      clamped,
      duration: AppTokens.medium,
      curve: AppTokens.easeOut,
    );
  }

  // ── Line measurement ───────────────────────────────────────────────────

  _LyricsMetrics _metricsFor({
    required List<LyricsLine> lines,
    required TextStyle style,
    required double maxWidth,
    required TextScaler scaler,
  }) {
    final scaleKey = scaler.scale(_fontSize);
    final cached = _metrics;
    if (cached != null &&
        identical(_metricsSource, lines) &&
        (_metricsWidth - maxWidth).abs() < 0.5 &&
        (_metricsScaleKey - scaleKey).abs() < 0.01) {
      return cached;
    }

    final offsets = List<double>.filled(lines.length, 0);
    final extents = List<double>.filled(lines.length, 0);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: scaler,
    );

    var cursor = 0.0;
    for (var i = 0; i < lines.length; i++) {
      painter.text = TextSpan(text: lines[i].text, style: style);
      painter.layout(maxWidth: maxWidth);
      final extent = math.max(_minLineExtent, painter.height + _linePadV * 2);
      offsets[i] = cursor;
      extents[i] = extent;
      cursor += extent;
    }
    painter.dispose();

    final metrics = _LyricsMetrics(offsets: offsets, extents: extents);
    _metrics = metrics;
    _metricsSource = lines;
    _metricsWidth = maxWidth;
    _metricsScaleKey = scaleKey;
    // Geometry changed, so any queued centring request is stale.
    _lastRequestedIndex = -1;
    return metrics;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lyricsAsync = ref.watch(currentLyricsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.accent;

    final container = AnimatedSize(
      duration: AppTokens.medium,
      curve: AppTokens.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        height: _expanded ? widget.height : _previewHeight,
        margin: const EdgeInsets.fromLTRB(
          AppTokens.s4,
          0,
          AppTokens.s4,
          AppTokens.s4,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDark.withValues(alpha: 0.85)
              : AppColors.surfaceLight.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXl),
          ),
          border: Border(
            top: BorderSide(
              color: accent.withValues(alpha: 0.2),
              width: AppTokens.borderHairline,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
              spreadRadius: -2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXl),
          ),
          child: _expanded
              ? _buildExpanded(lyricsAsync)
              : _buildCollapsedPreview(lyricsAsync),
        ),
      ),
    );
    return container;
  }

  Widget _buildExpanded(AsyncValue<LyricsResult> lyricsAsync) {
    return Column(
      children: [
        _LyricsPanelHeader(expanded: true, onToggle: _toggleExpanded),
        Expanded(
          child: lyricsAsync.when(
            loading: () => _buildLoadingState(),
            error: (_, _) => _buildMessageState(
              icon: Icons.error_outline_rounded,
              message: 'Lyrics unavailable',
              subtitle: 'Unable to load lyrics at this time',
              onRetry: _retry,
            ),
            data: _buildResult,
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedPreview(AsyncValue<LyricsResult> lyricsAsync) {
    return _LyricsPanelHeader(
      expanded: false,
      onToggle: _toggleExpanded,
      previewText: _previewText(lyricsAsync),
    );
  }

  /// Best single line to preview when the panel is collapsed, or null when
  /// there is nothing useful to preview yet.
  String? _previewText(AsyncValue<LyricsResult> lyricsAsync) {
    final result = lyricsAsync.valueOrNull;
    if (result == null ||
        result.status != LyricsStatus.loaded ||
        result.data == null) {
      return null;
    }
    final data = result.data!;
    if (data.isInstrumental) return 'Instrumental';
    final lines = _linesOf(data);
    if (lines.isEmpty) return null;
    if (data.hasSyncedLines) {
      final idx = ref.watch(currentLyricLineIndexProvider).valueOrNull ?? -1;
      if (idx >= 0 && idx < lines.length) return lines[idx].text;
    }
    return lines.first.text;
  }

  List<LyricsLine> _linesOf(LyricsData data) {
    if (data.lines.isNotEmpty) return data.lines;
    final text = data.plainText.trim();
    if (text.isEmpty) return const [];
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => LyricsLine(text: line))
        .toList(growable: false);
  }

  Widget _buildResult(LyricsResult result) {
    switch (result.status) {
      case LyricsStatus.loading:
        return _buildLoadingState();
      case LyricsStatus.notFound:
        return _buildMessageState(
          icon: Icons.lyrics_outlined,
          message: 'No lyrics found',
          subtitle: 'We couldn\'t find lyrics for this track yet.',
          onRetry: _retry,
        );
      case LyricsStatus.error:
        return _buildMessageState(
          icon: Icons.cloud_off_rounded,
          message: 'Lyrics unavailable',
          subtitle: 'Fetching lyrics failed. Check your connection.',
          onRetry: _retry,
        );
      case LyricsStatus.offline:
        return _buildMessageState(
          icon: Icons.wifi_off_rounded,
          message: 'No internet connection available.',
          subtitle: 'You\'re offline. Connect to the internet to fetch lyrics.',
          onRetry: _retry,
        );
      case LyricsStatus.loaded:
        final data = result.data;
        if (data == null) {
          return _buildMessageState(
            icon: Icons.lyrics_outlined,
            message: 'No lyrics found',
            subtitle: 'We couldn\'t find lyrics for this track yet.',
            onRetry: _retry,
          );
        }
        if (data.isInstrumental) {
          return _buildMessageState(
            icon: Icons.piano_rounded,
            message: 'Instrumental',
            subtitle: 'This track has no vocals.',
          );
        }
        final lines = _linesOf(data);
        if (lines.isEmpty) {
          return _buildMessageState(
            icon: Icons.lyrics_outlined,
            message: 'No lyrics found',
            subtitle: 'We couldn\'t find lyrics for this track yet.',
            onRetry: _retry,
          );
        }
        if (data.hasSyncedLines) {
          return _buildSyncedLyrics(lines);
        }
        return _buildPlainLyrics(lines);
    }
  }

  Widget _buildSyncedLyrics(List<LyricsLine> lines) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentIndex =
        ref.watch(currentLyricLineIndexProvider).valueOrNull ?? -1;
    _lastKnownIndex = currentIndex;

    final baseStyle = TextStyle(
      fontSize: _fontSize,
      height: _textHeight,
      fontWeight: _lineWeight,
      color: colorScheme.onSurface,
    );

    final activeColor = colorScheme.onSurface;
    final pastColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    final futureColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.62);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : widget.height;
        final textWidth = math.max(
          48.0,
          constraints.maxWidth - (AppTokens.s6 * 2) - (_linePadH * 2),
        );

        final metrics = _metricsFor(
          lines: lines,
          style: baseStyle,
          maxWidth: textWidth,
          scaler: MediaQuery.textScalerOf(context),
        );

        // Generous padding lets the first and last lines reach the centre.
        final topPadding = viewportHeight * 0.25;
        final bottomPadding = viewportHeight * 0.35;
        _listTopPadding = topPadding;

        if (currentIndex >= 0 && currentIndex != _lastRequestedIndex) {
          _requestScrollTo(currentIndex);
        }

        final list = NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _onScrollNotification(notification);
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: topPadding,
              bottom: bottomPadding,
              left: AppTokens.s6,
              right: AppTokens.s6,
            ),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isCurrent = index == currentIndex;
              final isPast = currentIndex >= 0 && index < currentIndex;
              final timestamp = line.startTimeMs;

              return _SyncedLyricLine(
                text: line.text,
                extent: metrics.extents[index],
                style: baseStyle,
                isCurrent: isCurrent,
                idleColor: isPast ? pastColor : futureColor,
                activeColor: activeColor,
                glowColor: AppColors.accent,
                animate: !MediaQuery.disableAnimationsOf(context),
                activeScale: _activeScale,
                horizontalPadding: _linePadH,
                onTap: timestamp == null ? null : () => _seekTo(timestamp),
              );
            },
          ),
        );

        return Stack(
          children: [
            Positioned.fill(child: _EdgeFade(child: list)),
            if (_isUserScrolling && currentIndex >= 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: AppTokens.s4,
                child: Center(
                  child: _ResumeFollowChip(onTap: _resumeAutoFollow),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPlainLyrics(List<LyricsLine> lines) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _EdgeFade(
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s6,
          vertical: AppTokens.s4,
        ),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _linePadH,
              vertical: 6,
            ),
            child: Text(
              lines[index].text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.82),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            'Finding lyrics…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String message,
    required String subtitle,
    VoidCallback? onRetry,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.16),
                    Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.03),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: Icon(
                icon,
                size: 30,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppTokens.s4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTokens.s4),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try again'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s4,
                    vertical: AppTokens.s2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _retry() => ref.invalidate(currentLyricsProvider);

  void _seekTo(int milliseconds) =>
      ref.read(playerProvider).seek(Duration(milliseconds: milliseconds));
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.11, 0.86, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

class _SyncedLyricLine extends StatelessWidget {
  const _SyncedLyricLine({
    required this.text,
    required this.extent,
    required this.style,
    required this.isCurrent,
    required this.idleColor,
    required this.activeColor,
    required this.glowColor,
    required this.animate,
    required this.activeScale,
    required this.horizontalPadding,
    required this.onTap,
  });

  final String text;
  final double extent;
  final TextStyle style;
  final bool isCurrent;
  final Color idleColor;
  final Color activeColor;
  final Color glowColor;
  final bool animate;
  final double activeScale;
  final double horizontalPadding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: extent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: isCurrent ? 1.0 : 0.0),
          duration: animate ? AppTokens.normal : Duration.zero,
          curve: AppTokens.easeOut,
          builder: (context, t, _) {
            final color = Color.lerp(idleColor, activeColor, t)!;
            final scale = 1.0 + ((activeScale - 1.0) * t);
            return Transform.scale(
              scale: scale,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Center(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: style.copyWith(
                      color: color,
                      shadows: t < 0.02
                          ? null
                          : [
                              Shadow(
                                color: AppColors.accent.withValues(
                                  alpha: 0.3 * t,
                                ),
                                blurRadius: 14 * t,
                              ),
                            ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ResumeFollowChip extends StatelessWidget {
  const _ResumeFollowChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Resume following lyrics',
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTokens.rFull),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.rFull),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s3,
              vertical: AppTokens.s2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location_rounded,
                  size: 14,
                  color: AppColors.accent,
                ),
                const SizedBox(width: AppTokens.s1),
                Text(
                  'Follow',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header for the collapsible lyrics panel.
///
/// When [expanded] it is a slim drag-to-collapse bar above the lyrics list.
/// When collapsed it is a tap target previewing the current lyric line, which
/// expands the panel back to the full list.
class _LyricsPanelHeader extends StatelessWidget {
  const _LyricsPanelHeader({
    required this.expanded,
    required this.onToggle,
    this.previewText,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final String? previewText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = AppColors.accent;

    if (expanded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: SizedBox(
          height: 44,
          width: double.infinity,
          child: Row(
            children: [
              const SizedBox(width: AppTokens.s4),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppTokens.rFull),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTokens.s4),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        child: Row(
          children: [
            Icon(Icons.lyrics_rounded, size: 20, color: accent),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lyrics',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText ?? 'Tap to view lyrics',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.s2),
            Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 22,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Immutable per-line layout geometry for the synced lyrics list.
@immutable
class _LyricsMetrics {
  const _LyricsMetrics({required this.offsets, required this.extents});

  /// Distance from the first line's top edge to each line's top edge.
  final List<double> offsets;

  /// Laid-out height of each line, including its vertical padding.
  final List<double> extents;
}
