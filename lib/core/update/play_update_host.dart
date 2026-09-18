import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import 'play_update.dart';
import 'play_update_controller.dart';

/// App-lifetime host for the Google Play in-app update experience.
///
/// Wraps the home shell: checks Play once per launch after the first frame,
/// shows the update sheet for available flexible updates and a persistent
/// banner once the update is downloaded. Re-queries on resume so an update
/// that finished downloading in the background restores the restart prompt.
class PlayUpdateHost extends ConsumerStatefulWidget {
  const PlayUpdateHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlayUpdateHost> createState() => _PlayUpdateHostState();
}

class _PlayUpdateHostState extends ConsumerState<PlayUpdateHost>
    with WidgetsBindingObserver {
  bool _prompting = false;
  bool _bannerVisible = false;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(playUpdateControllerProvider.notifier).checkForUpdate();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(playUpdateControllerProvider.notifier).syncOnResume();
    }
  }

  void _onState(PlayUpdateInfo? previous, PlayUpdateInfo next) {
    final requested = next.promptToken > (previous?.promptToken ?? 0);
    if (requested && !_prompting) {
      _prompting = true;
      _showSheet();
    }
    if (next.status == PlayUpdateStatus.downloaded) {
      _maybeShowReadyBanner();
    } else if (_bannerVisible) {
      _bannerVisible = false;
      ScaffoldMessenger.maybeOf(context)?.clearMaterialBanners();
    }
  }

  Future<void> _showSheet() async {
    await showPlayUpdateSheet(context);
    if (!mounted) return;
    _prompting = false;
    switch (ref.read(playUpdateControllerProvider).status) {
      case PlayUpdateStatus.available:
        // Closed without updating ("Not now" or the barrier tap): persist the
        // dismissal so the prompt does not return today.
        await ref.read(playUpdateControllerProvider.notifier).dismiss();
      case PlayUpdateStatus.downloaded:
        _maybeShowReadyBanner();
      case _:
        break;
    }
  }

  void _maybeShowReadyBanner() {
    if (_bannerVisible || _bannerDismissed || _prompting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _bannerVisible = true;
    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          content: const Text('Update ready - restart VoraTube to install.'),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          actions: [
            TextButton(
              onPressed: () {
                _bannerVisible = false;
                _bannerDismissed = true;
                messenger.clearMaterialBanners();
              },
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                _bannerVisible = false;
                messenger.clearMaterialBanners();
                ref
                    .read(playUpdateControllerProvider.notifier)
                    .completeUpdate();
              },
              child: const Text('Restart & Update'),
            ),
          ],
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playUpdateControllerProvider, _onState);
    return widget.child;
  }
}

/// Shows the VoraTube in-app update sheet.
Future<void> showPlayUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const PlayUpdateSheet(),
  );
}

// Sheet UI

class PlayUpdateSheet extends ConsumerWidget {
  const PlayUpdateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = ref.watch(playUpdateControllerProvider);
    final controller = ref.read(playUpdateControllerProvider.notifier);

    final Widget body = switch (info.status) {
      PlayUpdateStatus.downloading => _DownloadingBody(info: info),
      PlayUpdateStatus.downloaded => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetTitle(title: 'Update ready'),
          const SizedBox(height: AppTokens.s1),
          const Text('Restart VoraTube to finish installing the update.'),
          const SizedBox(height: AppTokens.s4),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              controller.completeUpdate();
            },
            child: const Text('Restart & Update'),
          ),
        ],
      ),
      PlayUpdateStatus.failed => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetTitle(title: 'Update failed'),
          const SizedBox(height: AppTokens.s1),
          const Text(
            'The update could not be completed. Try again later from '
            'Settings > Check for updates.',
          ),
          const SizedBox(height: AppTokens.s4),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetTitle(title: 'Update available'),
          const SizedBox(height: AppTokens.s1),
          const Text('A new version of VoraTube is ready.'),
          if (info.availableVersionCode != null) ...[
            const SizedBox(height: AppTokens.s1),
            Text(
              'Version ${info.availableVersionCode}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.s5),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    controller.dismiss();
                  },
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: FilledButton(
                  onPressed: () => controller.startUpdate(),
                  child: const Text('Update'),
                ),
              ),
            ],
          ),
        ],
      ),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s5,
          AppTokens.s5,
          AppTokens.s5,
          AppTokens.s4,
        ),
        child: body,
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _DownloadingBody extends ConsumerWidget {
  const _DownloadingBody({required this.info});

  final PlayUpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = info.progress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetTitle(title: 'Downloading update'),
        const SizedBox(height: AppTokens.s3),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.rFull),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        if (info.totalBytes > 0) ...[
          const SizedBox(height: AppTokens.s2),
          Text(
            '${(info.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB of '
            '${(info.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
