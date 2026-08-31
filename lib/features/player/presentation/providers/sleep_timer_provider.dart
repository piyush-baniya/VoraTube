import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import 'player_providers.dart' show playerProvider;

/// Lifecycle of VoraTube's single sleep timer.
enum SleepTimerPhase { inactive, active, finished }

/// Immutable snapshot of the sleep timer.
///
/// The timer is modeled around an absolute *end timestamp* ([endTimeMs], epoch
/// milliseconds) so the remaining time is always derived from the clock, never
/// from a widget's tick count. This keeps the countdown accurate across
/// rebuilds, navigation, backgrounding, screen lock and lifecycle changes.
@immutable
class SleepTimerState {
  const SleepTimerState._({
    required this.phase,
    this.endTimeMs,
    this.totalDuration,
    this.remaining = Duration.zero,
  });

  const SleepTimerState.inactive() : this._(phase: SleepTimerPhase.inactive);

  const SleepTimerState.active({
    required int endTimeMs,
    required Duration duration,
  }) : this._(
         phase: SleepTimerPhase.active,
         endTimeMs: endTimeMs,
         totalDuration: duration,
         remaining: duration,
       );

  const SleepTimerState.finished() : this._(phase: SleepTimerPhase.finished);

  final SleepTimerPhase phase;

  /// Absolute expiration time in epoch milliseconds, when [phase] is active.
  final int? endTimeMs;

  /// The originally requested duration (or, after a restore, the remaining
  /// duration). Cosmetic — the UI shows [remaining].
  final Duration? totalDuration;

  /// Remaining time as of the last tick. Zero when not active.
  final Duration remaining;

  bool get isActive => phase == SleepTimerPhase.active;
  bool get isFinished => phase == SleepTimerPhase.finished;
  bool get isInactive => phase == SleepTimerPhase.inactive;

  /// Remaining time computed from [now], independent of tick cadence. Falls
  /// back to [remaining] when there is no end timestamp.
  Duration remainingAt(DateTime now) {
    final end = endTimeMs;
    if (end == null) return remaining;
    final ms = end - now.millisecondsSinceEpoch;
    return ms <= 0 ? Duration.zero : Duration(milliseconds: ms);
  }

  SleepTimerState _withRemaining(Duration value) => SleepTimerState._(
    phase: phase,
    endTimeMs: endTimeMs,
    totalDuration: totalDuration,
    remaining: value,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepTimerState &&
          other.phase == phase &&
          other.endTimeMs == endTimeMs &&
          other.totalDuration == totalDuration &&
          other.remaining == remaining;

  @override
  int get hashCode => Object.hash(phase, endTimeMs, totalDuration, remaining);
}

/// Abstraction over where the timer's end timestamp lives, so the controller
/// can be unit tested with an in-memory fake instead of the platform KV store.
abstract interface class SleepTimerPersistence {
  Future<int?> readEndTimeMs();
  Future<void> writeEndTimeMs(int endMs);
  Future<void> clearEndTimeMs();
}

/// KV-backed [SleepTimerPersistence] reusing the app's existing key–value
/// repository (the same store the settings and player snapshot use).
class KvSleepTimerPersistence implements SleepTimerPersistence {
  KvSleepTimerPersistence(this._repository);

  final LibraryRepository _repository;

  static const String key = 'sleepTimer.endTimeMs.v1';

  @override
  Future<int?> readEndTimeMs() async {
    try {
      final raw = await _repository.kvGet(key);
      return raw == null ? null : int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeEndTimeMs(int endMs) async {
    try {
      await _repository.kvSet(key, '$endMs');
    } catch (_) {}
  }

  @override
  Future<void> clearEndTimeMs() async {
    try {
      await _repository.kvSet(key, '');
    } catch (_) {}
  }
}

/// Centralized sleep timer state.
///
/// One instance exists for the whole app (via [sleepTimerProvider]); screens
/// (Full Player, song menu, Settings) all observe this same timer. The
/// countdown runs on an internal [Timer.periodic] owned by the controller — it
/// does **not** depend on any visible widget staying mounted — and each tick
/// recomputes the remaining time from the absolute end timestamp, so it stays
/// correct even when the isolate is throttled in the background.
class SleepTimerController extends StateNotifier<SleepTimerState> {
  SleepTimerController({
    required PlayerController player,
    required SleepTimerPersistence persistence,
    DateTime Function()? now,
    Duration tickInterval = const Duration(seconds: 1),
  }) : _player = player,
       _persistence = persistence,
       _now = now ?? DateTime.now,
       _tickInterval = tickInterval,
       super(const SleepTimerState.inactive());

  /// Maximum allowed duration for a custom timer.
  static const Duration maxDuration = Duration(hours: 6);

  final PlayerController _player;
  final SleepTimerPersistence _persistence;
  final DateTime Function() _now;
  final Duration _tickInterval;

  Timer? _timer;

  /// Restores a persisted timer (e.g. after app/process restart).
  ///
  /// If the stored end timestamp is still in the future the timer resumes;
  /// if it has already expired the timer is marked [SleepTimerPhase.finished]
  /// so the one-shot "Sleep Timer Finished" popup shows on the next launch.
  /// No playback operation is performed here — a fresh launch has nothing
  /// playing that this timer should pause.
  Future<void> restore() async {
    final endMs = await _persistence.readEndTimeMs();
    if (endMs == null || state.isActive || state.isFinished) return;
    final remaining = endMs - _now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      await _persistence.clearEndTimeMs();
      state = const SleepTimerState.finished();
    } else {
      state = SleepTimerState.active(
        endTimeMs: endMs,
        duration: Duration(milliseconds: remaining),
      );
      _startTicking();
    }
  }

  /// Starts (or replaces) the timer with [duration]. Invalid durations are
  /// ignored. Only one timer may exist at a time — starting replaces any active
  /// timer rather than creating a second one.
  Future<void> start(Duration duration) async {
    if (duration <= Duration.zero) return;
    final capped = duration > maxDuration ? maxDuration : duration;
    _timer?.cancel();
    final endMs = _now().add(capped).millisecondsSinceEpoch;
    state = SleepTimerState.active(endTimeMs: endMs, duration: capped);
    _startTicking();
    await _persistence.writeEndTimeMs(endMs);
  }

  /// Cancels the timer. Never pauses playback, changes the song, position or
  /// queue — music, if playing, keeps playing.
  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState.inactive();
    await _persistence.clearEndTimeMs();
  }

  /// Clears the [SleepTimerPhase.finished] marker once the popup has been
  /// shown and dismissed, so the popup never reappears by itself.
  void dismissFinished() {
    if (!state.isFinished) return;
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState.inactive();
  }

  void _startTicking() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    final end = state.endTimeMs;
    if (end == null) return;
    final remaining = end - _now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      unawaited(_expire());
      return;
    }
    state = state._withRemaining(Duration(milliseconds: remaining));
  }

  Future<void> _expire() async {
    _timer?.cancel();
    _timer = null;
    // Re-verify the timer is still active right before pausing, so a cancel or
    // a replace racing with the final tick never pauses unexpectedly.
    if (!state.isActive) return;
    try {
      if (_player.current.isPlaying) {
        await _player.pause();
      }
    } catch (_) {
      // Pausing is best-effort; an engine hiccup must not crash the timer.
    }
    await _persistence.clearEndTimeMs();
    // Preserve the current song and position: pause() already does; we never
    // call next(), seek() or clear the queue here.
    state = const SleepTimerState.finished();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// The app's single sleep timer. Created with the existing [playerProvider] so
/// expiration pauses playback through the established player controller — never
/// through a second audio engine.
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, SleepTimerState>((ref) {
      final player = ref.watch(playerProvider);
      final repo = ref.watch(libraryRepositoryProvider);
      final controller = SleepTimerController(
        player: player,
        persistence: KvSleepTimerPersistence(repo),
      );
      unawaited(controller.restore());
      return controller;
    });

/// Narrow boolean: is a timer currently counting down?
final sleepTimerIsActiveProvider = Provider<bool>(
  (ref) => ref.watch(sleepTimerProvider.select((s) => s.isActive)),
);

/// The remaining duration shown to the user (zero when inactive).
final sleepTimerRemainingProvider = Provider<Duration>(
  (ref) => ref.watch(sleepTimerProvider.select((s) => s.remaining)),
);

/// Formats a remaining duration as `mm:ss` (or `h:mm:ss` beyond an hour), the
/// compact form used on the Full Player and Settings.
String formatSleepTimer(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '${d.inMinutes.toString().padLeft(2, '0')}:$s';
}
