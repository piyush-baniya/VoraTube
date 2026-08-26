import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ingest/ingest_service.dart';
import '../../../../shared/widgets/screen_header.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../providers/library_providers.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isAndroid) {
        ref.read(scanControllerProvider.notifier).refreshPermission();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScreenHeader(title: 'Library'),
          Expanded(
            child: Platform.isIOS ? const _ImportBody() : const _ScanBody(),
          ),
        ],
      ),
    );
  }
}

class _ScanBody extends ConsumerWidget {
  const _ScanBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    return switch (state) {
      ScanPermissionNeeded() => _PermissionView(
        permanentlyDenied: state.permanentlyDenied,
      ),
      ScanReady() => const _ReadyView(),
      ScanRunning() => _RunningView(
        phase: state.phase,
        processedCount: state.processedCount,
        addedCount: state.addedCount,
        totalHint: state.totalHint,
      ),
      ScanComplete() => _CompleteView(summary: state.summary),
      ScanFailure() => _FailureView(message: state.message),
    };
  }
}

class _ImportBody extends ConsumerWidget {
  const _ImportBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    return switch (state) {
      ImportReady() => const _ImportReadyView(),
      Importing() => _ImportingView(
        phase: state.phase,
        processedCount: state.processedCount,
        totalCount: state.totalCount,
        importedCount: state.importedCount,
        skippedCount: state.skippedCount,
        failedCount: state.failedCount,
      ),
      ImportComplete() => _ImportCompleteView(summary: state.summary),
      ImportFailure() => _FailureView(message: state.message),
    };
  }
}

class _PermissionView extends ConsumerWidget {
  const _PermissionView({required this.permanentlyDenied});

  final bool permanentlyDenied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_rounded,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
            semanticLabel: 'Your music lives here',
          ),
          const SizedBox(height: 16),
          Text(
            'Allow access to your music',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'VoraTube plays music stored on your device. Nothing is '
            'uploaded and nothing leaves your phone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () =>
                ref.read(scanControllerProvider.notifier).requestPermission(),
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Allow access'),
          ),
          if (permanentlyDenied) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  ref.read(scanControllerProvider.notifier).openSettings(),
              child: const Text('Open settings'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadyView extends ConsumerWidget {
  const _ReadyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () =>
                ref.read(scanControllerProvider.notifier).startScan(),
            icon: const Icon(Icons.radar_rounded),
            label: const Text('Scan Music'),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'VoraTube will look for audio files already on this device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({
    required this.phase,
    required this.processedCount,
    required this.addedCount,
    this.totalHint,
  });

  final ScanPhase phase;
  final int processedCount;
  final int addedCount;
  final int? totalHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phaseLabel = switch (phase) {
      ScanPhase.reading => 'Scanning\u2026',
      ScanPhase.artwork => 'Preparing artwork\u2026',
      ScanPhase.finalizing => 'Finishing up\u2026',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 20),
          Text(
            phaseLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (phase == ScanPhase.reading) ...[
            const SizedBox(height: 6),
            Text(
              '$processedCount songs found',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (totalHint != null) ...[
            const SizedBox(height: 6),
            Text(
              '$addedCount new songs \u00b7 $totalHint album covers to prepare',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompleteView extends ConsumerWidget {
  const _CompleteView({required this.summary});

  final ScanSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.done_all_rounded,
            size: 56,
            color: theme.colorScheme.primary,
            semanticLabel: 'Scan complete',
          ),
          const SizedBox(height: 16),
          Text(
            '${summary.totalSongs} songs found',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan complete \u00b7 ${summary.artworksResolved} album covers '
            'ready',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () =>
                ref.watch(scanControllerProvider.notifier).startScan(),
            child: const Text('Scan again'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => startPlaybackOfWholeLibrary(ref),
            icon: const Icon(Icons.play_circle_fill_rounded),
            label: const Text('Play all (dev)'),
          ),
        ],
      ),
    );
  }
}

class _FailureView extends ConsumerWidget {
  const _FailureView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 56,
            color: theme.colorScheme.error,
            semanticLabel: 'Scan failed',
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () =>
                ref.read(scanControllerProvider.notifier).startScan(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _ImportReadyView extends ConsumerWidget {
  const _ImportReadyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () =>
                ref.read(importControllerProvider.notifier).startImport(),
            icon: const Icon(Icons.library_add_rounded),
            label: const Text('Import Music'),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Pick audio files from your device. VoraTube copies them into '
              'its own library so they always stay available.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportingView extends StatelessWidget {
  const _ImportingView({
    required this.phase,
    required this.processedCount,
    required this.totalCount,
    required this.importedCount,
    required this.skippedCount,
    required this.failedCount,
  });

  final ImportPhase phase;
  final int processedCount;
  final int totalCount;
  final int importedCount;
  final int skippedCount;
  final int failedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = phase == ImportPhase.artwork
        ? 'Preparing artwork\u2026'
        : 'Importing\u2026';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 20),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$processedCount / $totalCount files \u00b7 '
            '$importedCount imported'
            '${skippedCount > 0 ? ' \u00b7 $skippedCount duplicates' : ''}'
            '${failedCount > 0 ? ' \u00b7 $failedCount failed' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportCompleteView extends ConsumerWidget {
  const _ImportCompleteView({required this.summary});

  final ImportSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.done_all_rounded,
              size: 56,
              color: theme.colorScheme.primary,
              semanticLabel: 'Import complete',
            ),
            const SizedBox(height: 16),
            Text(
              '${summary.importedSongs} songs imported',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${summary.totalSelected} selected \u00b7 '
              '${summary.skippedDuplicates} duplicates skipped \u00b7 '
              '${summary.failedCount} failed',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            for (final failure in summary.failures.take(3)) ...[
              const SizedBox(height: 4),
              Text(
                '${failure.fileName}: ${failure.reason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (summary.failures.length > 3)
              Text(
                '+${summary.failures.length - 3} more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(importControllerProvider.notifier).startImport(),
              icon: const Icon(Icons.library_add_rounded),
              label: const Text('Import more'),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => startPlaybackOfWholeLibrary(ref),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: const Text('Play all (dev)'),
            ),
            TextButton(
              onPressed: () async {
                final removed = await ref
                    .read(importControllerProvider.notifier)
                    .reconcileMissingFiles();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$removed missing imports removed')),
                  );
                }
              },
              child: const Text('Clean up missing files'),
            ),
          ],
        ),
      ),
    );
  }
}
