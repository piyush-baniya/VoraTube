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

  /// Whether the user chose to enter a custom wall-clock time (hour + minute +
  /// AM/PM) rather than a preset on-the-hour chip.
  bool _isCustomTime = false;

  /// Custom wall-clock time being composed (24-hour hour + minute).
  int _customHour24 = 21;
  int _customMinute = 0;

  /// Whether the selected wall-clock time repeats every day.
  bool _repeatDaily = false;

  final TextEditingController _customMinutes = TextEditingController();
  final TextEditingController _customSeconds = TextEditingController();

  /// The parsed custom duration, or null when the input is invalid/empty.
  Duration? get _customDuration {
    final minutes = int.tryParse(_customMinutes.text.trim()) ?? 0;
    final seconds = int.tryParse(_customSeconds.text.trim()) ?? 0;
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
    _customMinutes.dispose();
    _customSeconds.dispose();
    super.dispose();
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
        OutlinedButton.icon(
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
          OutlinedButton.icon(
            onPressed: _ignoreToday,
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Ignore for today'),
          ),
          const SizedBox(height: AppTokens.s2),
        ],
        OutlinedButton.icon(
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
          'out — your spot is kept.',
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
            ChoiceChip(
              avatar: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Custom time'),
              onSelected: (_) => setState(() {
                _isCustomTime = true;
                _selectedHour = null;
                _isCustom = false;
              }),
              selected: _isCustomTime,
            ),
          ],
        ),
        if (_isCustomTime) ...[
          const SizedBox(height: AppTokens.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _TimeStepper(
                  label: 'Hour',
                  value: _customHour24 % 12 == 0 ? 12 : _customHour24 % 12,
                  onChanged: (v) => setState(() {
                    final h12 = v == 0 ? 12 : v;
                    final isPm = _customHour24 >= 12;
                    _customHour24 = (isPm ? h12 % 12 + 12 : h12 % 12);
                  }),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: _TimeStepper(
                  label: 'Minute',
                  value: _customMinute,
                  max: 59,
                  onChanged: (v) => setState(() {
                    _customMinute = v.clamp(0, 59);
                  }),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              _AmPmToggle(
                value: _customHour24 >= 12,
                onChanged: (_) => setState(() {
                  final h12 = _customHour24 % 12 == 0 ? 12 : _customHour24 % 12;
                  _customHour24 = _customHour24 >= 12
                      ? (h12 % 12)
                      : (h12 % 12) + 12;
                }),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s1),
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
              child: TextField(
                controller: _customMinutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: TextField(
                controller: _customSeconds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seconds',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.s2),
        Text(
          custom == null
              ? 'Enter a duration greater than zero.'
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

/// A compact − / value / + stepper used to compose a custom wall-clock time.
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
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

/// AM / PM segmented toggle for the custom wall-clock time.
class _AmPmToggle extends StatelessWidget {
  const _AmPmToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AM/PM',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.s1),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('AM'),
              icon: Icon(Icons.wb_sunny_outlined, size: 16),
            ),
            ButtonSegment(
              value: true,
              label: Text('PM'),
              icon: Icon(Icons.nights_stay_outlined, size: 16),
            ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
          ),
        ),
      ],
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
