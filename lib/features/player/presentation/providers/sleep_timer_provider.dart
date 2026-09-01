import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import 'player_providers.dart' show playerProvider;

/// Lifecycle of VoraTube's single sleep timer.
enum SleepTimerPhase { inactive, active, finished }

/// What the sleep timer is counting toward.
///
/// [countdown] is the classic minutes/seconds timer. [timeOfDay] fires at a
/// wall-clock hour and can repeat daily.
enum SleepTimerMode { countdown, timeOfDay }

/// The user's configured sleep-timer schedule, independent of the live
/// countdown, so a recurring wall-clock timer can be re-armed later (even after
/// an app restart).
@immutable
class SleepTimerSchedule {
  const SleepTimerSchedule({
    required this.mode,
    this.hour,
    this.minute = 0,
    this.recurring = false,
    this.ignoreForDate,
  });

  factory SleepTimerSchedule.fromJson(Map<String, dynamic> json) {
    return SleepTimerSchedule(
      mode: json['mode'] == 'timeOfDay'
          ? SleepTimerMode.timeOfDay
          : SleepTimerMode.countdown,
      hour: json['hour'] as int?,
      minute: json['minute'] as int? ?? 0,
      recurring: json['recurring'] as bool? ?? false,
      ignoreForDate: json['ignoreForDate'] as String?,
    );
  }

  final SleepTimerMode mode;

  /// The wall-clock hour (0–23) this timer should fire at, when
  /// [mode] is [SleepTimerMode.timeOfDay].
  final int? hour;

  /// The wall-clock minute (0–59) this timer should fire at, when
  /// [mode] is [SleepTimerMode.timeOfDay]. Older persisted schedules written
  /// before minute support default to 0 (on the hour).
  final int minute;

  /// Whether a [SleepTimerMode.timeOfDay] timer repeats every day.
  final bool recurring;

  /// A `yyyy-MM-dd` date on which a recurring timer should *not* fire, for
  /// the "ignore for today" action. Only ever equals "today" while in effect.
  final String? ignoreForDate;

  Map<String, dynamic> toJson() => {
    'mode': mode == SleepTimerMode.timeOfDay ? 'timeOfDay' : 'countdown',
    if (hour != null) 'hour': hour,
    if (minute != 0) 'minute': minute,
    if (recurring) 'recurring': true,
    if (ignoreForDate != null) 'ignoreForDate': ignoreForDate,
  };

  String encode() => jsonEncode(toJson());

  static SleepTimerSchedule? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return SleepTimerSchedule.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepTimerSchedule &&
          other.mode == mode &&
          other.hour == hour &&
          other.minute == minute &&
          other.recurring == recurring &&
          other.ignoreForDate == ignoreForDate;

  @override
  int get hashCode => Object.hash(mode, hour, minute, recurring, ignoreForDate);
}

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
    this.mode = SleepTimerMode.countdown,
    this.hour,
    this.minute = 0,
    this.recurring = false,
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

  /// An active timer aimed at a wall-clock [hour]:[minute] (`hour` 0–23).
  const SleepTimerState.activeTimeOfDay({
    required int endTimeMs,
    required int hour,
    int minute = 0,
    required bool recurring,
  }) : this._(
         phase: SleepTimerPhase.active,
         endTimeMs: endTimeMs,
         mode: SleepTimerMode.timeOfDay,
         hour: hour,
         minute: minute,
         recurring: recurring,
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

  /// Which mode this timer runs in.
  final SleepTimerMode mode;

  /// The wall-clock hour this timer targets, when [mode] is timeOfDay.
  final int? hour;

  /// The wall-clock minute this timer targets, when [mode] is timeOfDay.
  final int minute;

  /// Whether a timeOfDay timer repeats every day.
  final bool recurring;

  bool get isActive => phase == SleepTimerPhase.active;
  bool get isFinished => phase == SleepTimerPhase.finished;
  bool get isInactive => phase == SleepTimerPhase.inactive;
  bool get isTimeOfDay => mode == SleepTimerMode.timeOfDay;

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
    mode: mode,
    hour: hour,
    minute: minute,
    recurring: recurring,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepTimerState &&
          other.phase == phase &&
          other.endTimeMs == endTimeMs &&
          other.totalDuration == totalDuration &&
          other.remaining == remaining &&
          other.mode == mode &&
          other.hour == hour &&
          other.minute == minute &&
          other.recurring == recurring;

  @override
  int get hashCode => Object.hash(
    phase,
    endTimeMs,
    totalDuration,
    remaining,
    mode,
    hour,
    minute,
    recurring,
  );
}

/// Abstraction over where the timer's end timestamp lives, so the controller
/// can be unit tested with an in-memory fake instead of the platform KV store.
abstract interface class SleepTimerPersistence {
  Future<int?> readEndTimeMs();
  Future<void> writeEndTimeMs(int endMs);
  Future<void> clearEndTimeMs();
}

/// Optional capability to persist the [SleepTimerSchedule] (mode, wall-clock
/// hour, recurring flag, ignore-for-today date).
///
/// Kept as a separate interface so existing [SleepTimerPersistence] fakes in
/// tests (which only cover countdown timers) keep compiling unchanged.
abstract interface class SleepTimerSchedulePersistence {
  Future<SleepTimerSchedule?> readSchedule();
  Future<void> writeSchedule(SleepTimerSchedule schedule);
  Future<void> clearSchedule();
}

/// KV-backed [SleepTimerPersistence] reusing the app's existing key–value
/// repository (the same store the settings and player snapshot use). Also
/// persists the [SleepTimerSchedule] so recurring wall-clock timers survive an
/// app restart.
class KvSleepTimerPersistence
    implements SleepTimerPersistence, SleepTimerSchedulePersistence {
  KvSleepTimerPersistence(this._repository);

  final LibraryRepository _repository;

  static const String key = 'sleepTimer.endTimeMs.v1';
  static const String scheduleKey = 'sleepTimer.schedule.v1';

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

  @override
  Future<SleepTimerSchedule?> readSchedule() async {
    try {
      final raw = await _repository.kvGet(scheduleKey);
      return SleepTimerSchedule.decode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeSchedule(SleepTimerSchedule schedule) async {
    try {
      await _repository.kvSet(scheduleKey, schedule.encode());
    } catch (_) {}
  }

  @override
  Future<void> clearSchedule() async {
    try {
      await _repository.kvSet(scheduleKey, '');
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
  }) : this._(player, persistence, now ?? DateTime.now, tickInterval);

  SleepTimerController._(
    this._player,
    this._persistence,
    DateTime Function() now,
    this._tickInterval,
  ) : _now = now,
      super(const SleepTimerState.inactive());

  /// Maximum allowed duration for a custom countdown timer.
  static const Duration maxDuration = Duration(hours: 6);

  final PlayerController _player;
  final SleepTimerPersistence _persistence;
  final DateTime Function() _now;
  final Duration _tickInterval;

  Timer? _timer;

  /// The currently persisted schedule, kept in memory for the UI. Null means a
  /// plain countdown timer (or no timer at all).
  SleepTimerSchedule? _schedule;

  SleepTimerSchedulePersistence? get _scheduleStore =>
      _persistence is SleepTimerSchedulePersistence
      ? _persistence as SleepTimerSchedulePersistence
      : null;

  /// The active schedule, or null when the timer is a plain countdown.
  SleepTimerSchedule? get schedule => _schedule;

  /// Restores a persisted timer (e.g. after app/process restart).
  ///
  /// A recurring wall-clock timer is always re-armed for its next occurrence.
  /// A one-shot timer resumes if its end timestamp is still in the future, or
  /// is marked [SleepTimerPhase.finished] if it has already expired. No
  /// playback operation is performed here — a fresh launch has nothing playing
  /// that this timer should pause.
  Future<void> restore() async {
    if (state.isActive || state.isFinished) return;
    _schedule = await _scheduleStore?.readSchedule();
    if (_schedule != null && _schedule!.mode == SleepTimerMode.timeOfDay) {
      final hour = _schedule!.hour;
      if (hour == null) {
        await cancel();
        return;
      }
      if (_schedule!.recurring) {
        // A recurring timer always re-arms; it never shows as "finished" on
        // restart even if a previous end timestamp already passed.
        await _armTimeOfDay(
          hour,
          minute: _schedule!.minute,
          recurring: true,
          ignoreForDate: _schedule!.ignoreForDate,
          writeSchedule: true,
        );
        return;
      }
      // One-shot wall-clock: fall through to end-time restore below.
    }
    final endMs = await _persistence.readEndTimeMs();
    if (endMs == null) return;
    final remaining = endMs - _now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      await _persistence.clearEndTimeMs();
      await _scheduleStore?.clearSchedule();
      _schedule = null;
      state = const SleepTimerState.finished();
    } else {
      state = SleepTimerState.active(
        endTimeMs: endMs,
        duration: Duration(milliseconds: remaining),
      );
      _startTicking();
    }
  }

  /// Starts (or replaces) the timer as a plain countdown with [duration].
  /// Invalid durations are ignored. Only one timer may exist at a time —
  /// starting replaces any active timer rather than creating a second one.
  Future<void> start(Duration duration) async {
    if (duration <= Duration.zero) return;
    final capped = duration > maxDuration ? maxDuration : duration;
    _schedule = null;
    await _scheduleStore?.clearSchedule();
    _timer?.cancel();
    final endMs = _now().add(capped).millisecondsSinceEpoch;
    state = SleepTimerState.active(endTimeMs: endMs, duration: capped);
    _startTicking();
    await _persistence.writeEndTimeMs(endMs);
  }

  /// Starts (or replaces) the timer to fire at a wall-clock [hour]:[minute]
  /// (`hour` 0–23, `minute` 0–59).
  ///
  /// When [recurring] is true the timer repeats at the same time every day;
  /// otherwise it fires once. The countdown runs until the next occurrence of
  /// that time.
  Future<void> startTimeOfDay(
    int hour, {
    int minute = 0,
    required bool recurring,
  }) async {
    await _armTimeOfDay(
      hour,
      minute: minute,
      recurring: recurring,
      ignoreForDate: recurring ? _schedule?.ignoreForDate : null,
      writeSchedule: true,
    );
  }

  /// Skips today's occurrence of a recurring timer while keeping it armed for
  /// the same hour tomorrow (and beyond). Does nothing for a one-shot timer.
  Future<void> ignoreToday() async {
    final schedule = _schedule;
    final hour = state.hour ?? schedule?.hour;
    if (schedule == null ||
        !schedule.recurring ||
        hour == null ||
        !state.isActive) {
      return;
    }
    final today = _dateKey(_now());
    final updated = SleepTimerSchedule(
      mode: SleepTimerMode.timeOfDay,
      hour: hour,
      minute: schedule.minute,
      recurring: true,
      ignoreForDate: today,
    );
    _schedule = updated;
    await _scheduleStore?.writeSchedule(updated);
    await _armTimeOfDay(
      hour,
      minute: schedule.minute,
      recurring: true,
      ignoreForDate: today,
      writeSchedule: false,
    );
  }

  Future<void> _armTimeOfDay(
    int hour, {
    int minute = 0,
    required bool recurring,
    String? ignoreForDate,
    bool writeSchedule = true,
  }) async {
    final normalizedHour = hour % 24;
    final normalizedMinute = minute % 60;
    final end = _nextOccurrence(
      _now(),
      normalizedHour,
      normalizedMinute,
      ignoreForDate,
    );
    _timer?.cancel();
    state = SleepTimerState.activeTimeOfDay(
      endTimeMs: end.millisecondsSinceEpoch,
      hour: normalizedHour,
      minute: normalizedMinute,
      recurring: recurring,
    );
    if (writeSchedule) {
      _schedule = SleepTimerSchedule(
        mode: SleepTimerMode.timeOfDay,
        hour: normalizedHour,
        minute: normalizedMinute,
        recurring: recurring,
        ignoreForDate: ignoreForDate,
      );
      await _scheduleStore?.writeSchedule(_schedule!);
    }
    _startTicking();
    await _persistence.writeEndTimeMs(end.millisecondsSinceEpoch);
  }

  /// Cancels the timer. Never pauses playback, changes the song, position or
  /// queue — music, if playing, keeps playing.
  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    _schedule = null;
    state = const SleepTimerState.inactive();
    await _persistence.clearEndTimeMs();
    await _scheduleStore?.clearSchedule();
  }

  /// Clears the [SleepTimerPhase.finished] marker once the popup has been
  /// shown and dismissed. A recurring timer is re-armed for its next daily
  /// occurrence instead of being switched off; a one-shot timer returns to
  /// inactive.
  void dismissFinished() {
    if (!state.isFinished) return;
    _timer?.cancel();
    _timer = null;
    final schedule = _schedule;
    final hour = state.hour ?? schedule?.hour;
    final minute = state.minute != 0 || state.mode == SleepTimerMode.timeOfDay
        ? state.minute
        : schedule?.minute ?? 0;
    if (schedule != null &&
        schedule.mode == SleepTimerMode.timeOfDay &&
        schedule.recurring &&
        hour != null) {
      unawaited(
        _armTimeOfDay(
          hour,
          minute: minute,
          recurring: true,
          ignoreForDate: schedule.ignoreForDate,
        ),
      );
      return;
    }
    state = const SleepTimerState.inactive();
  }

  DateTime _nextOccurrence(
    DateTime now,
    int hour,
    int minute,
    String? ignoreForDate,
  ) {
    final t = DateTime(now.year, now.month, now.day, hour, minute);
    if (!t.isAfter(now)) {
      return DateTime(now.year, now.month, now.day + 1, hour, minute);
    }
    // Still today, but the user asked to ignore today.
    if (ignoreForDate != null && _dateKey(t) == ignoreForDate) {
      return DateTime(now.year, now.month, now.day + 1, hour, minute);
    }
    return t;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
    final wasTimeOfDay = state.isTimeOfDay;
    final recurring = state.recurring;
    final hour = state.hour;
    final minute = state.minute;
    try {
      if (_player.current.isPlaying) {
        await _player.pause();
      }
    } catch (_) {
      // Pausing is best-effort; an engine hiccup must not crash the timer.
    }
    await _persistence.clearEndTimeMs();
    if (wasTimeOfDay && !recurring) {
      // One-shot wall-clock timers are fully spent once they fire.
      await _scheduleStore?.clearSchedule();
      _schedule = null;
    }
    // Preserve the current song and position: pause() already does; we never
    // call next(), seek() or clear the queue here. The finished state carries
    // the mode/recurring/hour so the popup can tailor its copy.
    state = SleepTimerState._(
      phase: SleepTimerPhase.finished,
      endTimeMs: null,
      mode: wasTimeOfDay ? SleepTimerMode.timeOfDay : SleepTimerMode.countdown,
      hour: hour,
      minute: minute,
      recurring: recurring,
    );
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

/// The currently configured schedule (null for a plain countdown timer).
final sleepTimerScheduleProvider = Provider<SleepTimerSchedule?>(
  (ref) => ref.watch(sleepTimerProvider.notifier.select((c) => c.schedule)),
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

/// Formats a wall-clock hour in 12-hour form, e.g. `9:00 PM` or `12:00 AM`.
String formatTimeOfDay(int hour, {int minute = 0}) {
  final h = hour % 24;
  final m = minute.clamp(0, 59);
  final period = h < 12 ? 'AM' : 'PM';
  final displayHour = h % 12 == 0 ? 12 : h % 12;
  final displayMinute = m.toString().padLeft(2, '0');
  return '$displayHour:$displayMinute $period';
}

/// Returns the [count] nearest upcoming whole hours after [now].
List<int> upcomingHours(DateTime now, {int count = 5}) {
  final onTheHour = now.minute == 0 && now.second == 0 && now.millisecond == 0;
  var h = onTheHour ? now.hour : (now.hour + 1) % 24;
  final result = <int>[];
  while (result.length < count) {
    result.add(h);
    h = (h + 1) % 24;
  }
  return result;
}
