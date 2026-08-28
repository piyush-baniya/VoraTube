import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../features/library/presentation/providers/library_view_providers.dart';
import '../../../../../shared/widgets/empty_state.dart' show EmptyState;
import '../../../../../shared/widgets/skeleton_list.dart';
import '../../data/smart_mix_service.dart';
import '../providers/smart_music_providers.dart';
import '../widgets/mix_card.dart';
import 'smart_mix_detail_screen.dart';

class SmartMixesScreen extends ConsumerWidget {
  const SmartMixesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncMixes = ref.watch(smartMixesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Mixes'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: asyncMixes.when(
        loading: () => _buildSkeleton(),
        error: (error, stack) => _buildError(context, ref, error),
        data: (mixes) {
          if (mixes.isEmpty || mixes.every((m) => m.songs.isEmpty)) {
            final hasSongs = ref.watch(libraryHasSongsProvider).value ?? true;
            return _buildEmpty(context, hasSongs);
          }
          return _buildMixesList(context, mixes);
        },
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.s4),
      itemCount: 7,
      itemBuilder: (context, __) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s3),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.rMd),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Could not load mixes',
      message: 'Try again later',
      actionLabel: 'Retry',
      onAction: () => ref.invalidate(smartMixesProvider),
    );
  }

  Widget _buildEmpty(BuildContext context, bool hasSongs) {
    if (!hasSongs) {
      return EmptyState(
        icon: Icons.auto_awesome_mosaic,
        title: 'No mixes available',
        message: 'Add songs to your library to build mood mixes.',
      );
    }
    // The library has songs, but none matched a mix yet (e.g. classification
    // produced no strong candidates). Never tell the user to add music when
    // music already exists.
    return EmptyState(
      icon: Icons.auto_awesome_mosaic,
      title: 'No recommendations yet',
      message: 'We couldn\'t build mood mixes from your library yet. Try again later.',
    );
  }

  Widget _buildMixesList(BuildContext context, List<SmartMix> mixes) {
    final nonEmptyMixes = mixes.where((m) => m.songs.isNotEmpty).toList();

    return ListView.separated(
      padding: const EdgeInsets.all(AppTokens.s4),
      itemCount: nonEmptyMixes.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTokens.s3),
      itemBuilder: (context, index) {
        final mix = nonEmptyMixes[index];
        return MixCard(
          mix: mix,
          onTap: () =>
              Navigator.of(context).push(_SmartMixDetailRoute(mix: mix)),
        );
      },
    );
  }
}

class _SmartMixDetailRoute extends PageRouteBuilder {
  final SmartMix mix;

  _SmartMixDetailRoute({required this.mix})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SmartMixDetailScreen(mix: mix),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 280),
      );
}
