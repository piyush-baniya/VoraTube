import 'package:flutter/material.dart';

import '../../data/library_models.dart';
import '../../../../app/theme/app_tokens.dart';

/// Library section selector with animated pill transitions.
///
/// Uses a smooth AnimatedContainer for the selected state, providing
/// clear visual feedback with the accent color.
class SectionSelector extends StatelessWidget {
  const SectionSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final LibrarySection selected;
  final ValueChanged<LibrarySection> onChanged;

  static const _labels = {
    LibrarySection.songs: 'Songs',
    LibrarySection.albums: 'Albums',
    LibrarySection.artists: 'Artists',
    LibrarySection.genres: 'Genres',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
        itemCount: _labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppTokens.s2),
        itemBuilder: (context, index) {
          final section = _labels.keys.elementAt(index);
          final isSelected = section == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: _labels[section],
            child: GestureDetector(
              onTap: () => onChanged(section),
              child: AnimatedContainer(
                duration: AppTokens.normal,
                curve: AppTokens.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTokens.rXl),
                ),
                child: Text(
                  _labels[section]!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
