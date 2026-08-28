import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// Small, visually secondary disclaimer shown on recommendation surfaces.
///
/// Recommendations are generated from local metadata and listening history and
/// may not always be accurate — we never claim better than that.
class RecommendationDisclaimer extends StatelessWidget {
  const RecommendationDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: AppTokens.s2),
          Expanded(
            child: Text(
              'Recommendations are generated automatically and may not be 100% accurate.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
