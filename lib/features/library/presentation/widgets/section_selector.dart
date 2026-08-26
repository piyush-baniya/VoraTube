import 'package:flutter/material.dart';

import '../../data/library_models.dart';

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
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final section = _labels.keys.elementAt(index);
          final isSelected = section == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: _labels[section],
            child: InkWell(
              onTap: () => onChanged(section),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _labels[section]!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
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
