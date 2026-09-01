import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../providers/sleep_timer_provider.dart';

/// The compact presets offered when the timer is not running.
const List<Duration> kSleepTimerPresets = [
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(hours: 1),
];

/// Aloud the sheet to offer wall-clock "end at a time" presets.
const int kUpcomingHourCount = 5;

/// Opens the Sleep Timer bottom sheet.
///
/// The sheet is a pure view over [sleepTimerProvider]. Starting or cancelling
/// a timer routes through the controller, so every entry point (Full Player,
/// song menu, Settings) sees the same canonical timer.
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerStatefulWidget {
  const _SleepTimerSheet();

  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  /// The user's currently selected preset while the timer is inactive.
  Duration _selected = kSleepTimerPresets[1];

  /// Whether the user chose "Custom" (and is entering a manual duration).
  bool _isCustom = false;

  /// The wall-clock hour currently selected in the "end at a time" section, or
  /// null when none is selected.
  int? _selectedHour;

  /// Whether a wall-clock stop time was chosen on the clock picker (as opposed
  /// to an on-the-hour preset chip). Set by [_pickOnClock]; drives the
  /// "Playback stops at ..." preview and the time-based "Set time" button.
  bool _isCustomTime = false;

  /// Custom wall-clock time being composed (24-hour hour + minute).
  int _customHour24 = 21;
  int _customMinute = 0;

  /// Whether the selected wall-clock time repeats every day.
  bool _repeatDaily = false;

  /// Custom duration being composed with the tap steppers (minutes/seconds).
  int _customMinutesValue = 15;
  int _customSecondsValue = 0;

  /// The parsed custom duration, or null when the input is invalid/empty.
  Duration? get _customDuration {
    final minutes = _customMinutesValue;
    final seconds = _customSecondsValue;
    if (minutes < 0 || seconds < 0) return null;
    final total = Duration(minutes: minutes, seconds: seconds);
    if (total <= Duration.zero) return null;
    return total > SleepTimerController.maxDuration
        ? SleepTimerController.maxDuration
        : total;
  }

  /// The duration the Start/Restart button will use.
  Duration get _chosen =>
      _isCustom ? (_customDuration ?? _selected) : _selected;

  @override
  void dispose() {
    super.dispose();
  }

  /// Opens the Material clock dial so the user can pick the stop time on a
  /// real clock face instead of composing it with steppers.
  Future<void> _pickOnClock() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _customHour24 % 24, minute: _customMinute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customHour24 = picked.hour;
      _customMinute = picked.minute;
      _isCustomTime = true;
      _selectedHour = null;
      _isCustom = false;
    });
  }

  Future<void> _start(Duration d) async {
    await ref.read(sleepTimerProvider.notifier).start(d);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _startAtHour(int hour) async {
    final notifier = ref.read(sleepTimerProvider.notifier);
    await notifier.startTimeOfDay(hour, recurring: _repeatDaily);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _startAtTime(int hour, int minute) async {
    final notifier = ref.read(sleepTimerProvider.notifier);
    await notifier.startTimeOfDay(
      hour,
      minute: minute,
      recurring: _repeatDaily,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _ignoreToday() async {
    final notifier = ref.read(sleepTimerProvider.notifier);
    await notifier.ignoreToday();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(sleepTimerProvider);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s6),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.s5),
                Row(
                  children: [
                    Icon(Icons.bedtime_rounded, color: colorScheme.primary),
                    const SizedBox(width: AppTokens.s3),
                    Text(
                      'Sleep Timer',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s4),
                if (state.isActive)
                  _buildActive(theme, colorScheme, state)
                else
                  _buildInactive(theme, colorScheme),
                const SizedBox(height: AppTokens.s4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActive(
    ThemeData theme,
    ColorScheme colorScheme,
    SleepTimerState state,
  ) {
    if (state.isTimeOfDay) {
      return _buildActiveTimeOfDay(theme, colorScheme, state);
    }
    return _buildActiveCountdown(theme, colorScheme, state);
  }

  Widget _buildActiveCountdown(
    ThemeData theme,
    ColorScheme colorScheme,
    SleepTimerState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Playback stops in ${formatSleepTimer(state.remaining)}',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTokens.s2),
        Text(
          'The timer keeps running in the background and when the screen is off.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.s6),
        FilledButton.tonalIcon(
          onPressed: () async {
            await ref.read(sleepTimerProvider.notifier).cancel();
            if (mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.bedtime_off_rounded),
          label: const Text('Turn off timer'),
        ),
      ],
    );
  }

  Widget _buildActiveTimeOfDay(
    ThemeData theme,
    ColorScheme colorScheme,
    SleepTimerState state,
  ) {
    final hour = state.hour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'Playback stops at ${hour == null ? '' : formatTimeOfDay(hour)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppTokens.s2),
        Text(
          state.recurring
              ? 'Repeats every day at the same time. '
                    'In ${formatSleepTimer(state.remaining)}.'
              : 'In ${formatSleepTimer(state.remaining)}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.s6),
        if (state.recurring) ...[
          FilledButton.tonalIcon(
            onPressed: _ignoreToday,
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Ignore for today'),
          ),
          const SizedBox(height: AppTokens.s2),
        ],
        FilledButton.tonalIcon(
          onPressed: () async {
            await ref.read(sleepTimerProvider.notifier).cancel();
            if (mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.bedtime_off_rounded),
          label: const Text('Turn off timer'),
        ),
      ],
    );
  }

  Widget _buildInactive(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stop playback automatically. Playback pauses when the timer runs '
          'out â€” your spot is kept.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.s5),
        Wrap(
          spacing: AppTokens.s2,
          runSpacing: AppTokens.s2,
          children: [
            for (final d in kSleepTimerPresets)
              ChoiceChip(
                label: Text(_presetLabel(d)),
                onSelected: (_) => setState(() {
                  _selected = d;
                  _isCustom = false;
                  _selectedHour = null;
                  _isCustomTime = false;
                }),
                selected: !_isCustom && _selectedHour == null && d == _selected,
              ),
            ChoiceChip(
              avatar: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Custom'),
              onSelected: (_) => setState(() {
                _isCustom = true;
                _selectedHour = null;
                _isCustomTime = false;
              }),
              selected: _isCustom,
            ),
          ],
        ),
        if (_isCustom) ...[
          const SizedBox(height: AppTokens.s5),
          _buildCustomFields(theme, colorScheme),
        ],
        const SizedBox(height: AppTokens.s5),
        FilledButton.icon(
          onPressed: () {
            if (_isCustom && _customDuration == null) return;
            _start(_chosen);
          },
          icon: const Icon(Icons.bedtime_rounded),
          label: const Text('Start timer'),
        ),
        const SizedBox(height: AppTokens.s4),
        Row(
          children: [
            Expanded(child: Divider(color: colorScheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
              child: Text(
                'or end at a time',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Divider(color: colorScheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: AppTokens.s4),
        FilledButton.tonalIcon(
          onPressed: _pickOnClock,
          icon: const Icon(Icons.access_time_rounded),
          label: const Text('Pick a time on the clock'),
        ),
        const SizedBox(height: AppTokens.s4),
        Wrap(
          spacing: AppTokens.s2,
          runSpacing: AppTokens.s2,
          children: [
            for (final h in upcomingHours(
              DateTime.now(),
              count: kUpcomingHourCount,
            ))
              ChoiceChip(
                label: Text(formatTimeOfDay(h)),
                onSelected: (_) => setState(() {
                  _selectedHour = h;
                  _isCustom = false;
                  _isCustomTime = false;
                }),
                selected: _selectedHour == h && !_isCustomTime,
              ),
          ],
        ),
        if (_isCustomTime) ...[
          const SizedBox(height: AppTokens.s4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Playback stops at ${formatTimeOfDay(_customHour24, minute: _customMinute)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppTokens.s3),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeat daily'),
            subtitle: const Text('Only for the time selected above.'),
            value: _repeatDaily,
            onChanged: (v) => setState(() => _repeatDaily = v),
          ),
        ),
        const SizedBox(height: AppTokens.s2),
        FilledButton.tonalIcon(
          onPressed: _selectedHour == null && !_isCustomTime
              ? null
              : _isCustomTime
              ? () => _startAtTime(_customHour24, _customMinute)
              : () => _startAtHour(_selectedHour!),
          icon: const Icon(Icons.schedule_rounded),
          label: const Text('Set time'),
        ),
      ],
    );
  }

  Widget _buildCustomFields(ThemeData theme, ColorScheme colorScheme) {
    final custom = _customDuration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _TimeStepper(
                label: 'Minutes',
                value: _customMinutesValue,
                max: 359,
                onChanged: (v) =>
                    setState(() => _customMinutesValue = v.clamp(0, 359)),
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: _TimeStepper(
                label: 'Seconds',
                value: _customSecondsValue,
                max: 59,
                onChanged: (v) =>
                    setState(() => _customSecondsValue = v.clamp(0, 59)),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.s2),
        Text(
          custom == null
              ? 'Choose a duration greater than zero.'
              : 'Custom: ${formatSleepTimer(custom)}'
                    '${custom >= SleepTimerController.maxDuration ? ' (max 6 h)' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: custom == null
                ? colorScheme.error
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _presetLabel(Duration d) {
    if (d.inHours > 0) return '${d.inHours} h';
    return '${d.inMinutes} min';
  }
}

/// A compact âˆ’ / value / + stepper used to compose a custom wall-clock time.
class _TimeStepper extends StatelessWidget {
  const _TimeStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 23,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.s1),
        Row(
          children: [
            _stepButton(context, Icons.remove_rounded, () {
              onChanged(value == 0 ? max : value - 1);
            }),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
                alignment: Alignment.center,
                child: Text(
                  value.toString(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _stepButton(context, Icons.add_rounded, () {
              onChanged(value == max ? 0 : value + 1);
            }),
          ],
        ),
      ],
    );
  }

  Widget _stepButton(BuildContext context, IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
      ),
    );
  }
}

/// An animated full-screen overlay shown when the sleep timer expires and
/// playback pauses, with an animated sleeping icon.
///
/// Displayed by [HomeShell] only while the app is visible. Dismissing it
/// clears the [SleepTimerPhase.finished] marker so it never reappears by
/// itself; a recurring timer is re-armed for its next daily occurrence.
Future<void> showSleepTimerFinishedDialog(
  BuildContext context, {
  SleepTimerState state = const SleepTimerState.finished(),
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Sleep timer finished',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _SleepTimerFinishedOverlay(state: state),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppTokens.easeOutExpo,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SleepTimerFinishedOverlay extends StatefulWidget {
  const _SleepTimerFinishedOverlay({required this.state});

  final SleepTimerState state;

  @override
  State<_SleepTimerFinishedOverlay> createState() =>
      _SleepTimerFinishedOverlayState();
}

class _SleepTimerFinishedOverlayState extends State<_SleepTimerFinishedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    // A bounded number of drift cycles so the overlay stays lively on device
    // but still settles for tests and avoids endless CPU frames.
    _controller.repeat(reverse: true, count: 6);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final recurring = widget.state.recurring;
    final hour = widget.state.hour;

    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(AppTokens.s6),
          padding: const EdgeInsets.all(AppTokens.s6),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTokens.rXxl),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: _SleepingIcon(
                  animation: _controller,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppTokens.s5),
              Text(
                'Sleep Timer Finished',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTokens.s3),
              Text(
                recurring && hour != null
                    ? 'Playback was stopped. Re-armed for '
                          '${formatTimeOfDay(hour)} tomorrow.'
                    : 'Playback was stopped by your sleep timer. '
                          'Your spot has been kept.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTokens.s6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An animated sleeping-face icon (closed eyes + drifting Z's).
class _SleepingIcon extends StatelessWidget {
  const _SleepingIcon({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final drift = animation.value;
            return Opacity(
              opacity: 0.35 + 0.65 * (1 - drift),
              child: Transform.translate(
                offset: Offset(8 + 8 * drift, -6 - 10 * drift),
                child: Transform.rotate(
                  angle: -0.5 + 0.2 * drift,
                  child: Text(
                    'Z',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final drift = animation.value;
            return Opacity(
              opacity: 0.2 + 0.6 * drift,
              child: Transform.translate(
                offset: Offset(-10 - 10 * drift, -14 + 12 * drift),
                child: Transform.rotate(
                  angle: 0.5 - 0.25 * drift,
                  child: Text(
                    'z',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Icon(Icons.bedtime_rounded, size: 64, color: color),
      ],
    );
  }
}
