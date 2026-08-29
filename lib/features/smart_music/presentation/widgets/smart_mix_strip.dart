import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/transitions.dart';
import '../providers/smart_music_providers.dart';
import '../screens/smart_mixes_screen.dart';
import 'mix_card.dart';

/// Horizontal strip of Smart Mix cards — mirrors [CollectionsStrip] placement.
class SmartMixStrip extends ConsumerWidget {
  const SmartMixStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(smartMixesProvider);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (mixes) {
        final visible = mixes.where((m) => m.songs.isNotEmpty).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(
                context,
              ).push(pushSharedAxis<void>(context, const SmartMixesScreen())),
              child: SectionLabel(
                title: 'Smart Mixes',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${visible.length}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s4,
                  vertical: AppTokens.s1,
                ),
                itemCount: visible.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppTokens.s2),
                itemBuilder: (context, index) {
                  final mix = visible[index];
                  return SizedBox(
                    width: 160,
                    child: MixCard(mix: mix, showActions: false),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
