import 'package:flutter/material.dart';

/// A circular avatar showing the initials of a person/artist name, with the
/// background colour derived deterministically from the name so different
/// names get different, stable colours.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 52});

  final String name;
  final double size;

  /// Palette used round-robin by name hash. Chosen to read well on both light
  /// and dark surfaces (solid mid-tone backgrounds with white text).
  static const List<Color> _palette = [
    Color(0xFFE05260), // red
    Color(0xFFE08A3C), // orange
    Color(0xFFD4A72C), // amber
    Color(0xFF5FAE55), // green
    Color(0xFF2FA8A0), // teal
    Color(0xFF4A8FE0), // blue
    Color(0xFF7A6AE0), // violet
    Color(0xFFC45CB4), // magenta
    Color(0xFF6B8F71), // sage
    Color(0xFFB0673F), // brown
  ];

  static Color colorFor(String name) {
    final trimmed = name.trim();
    var hash = 0;
    for (final code in trimmed.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  /// Up to two leading initials of the significant words in [name].
  static String initialsFor(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    final first = words.first.substring(0, 1).toUpperCase();
    final last = words.last.substring(0, 1).toUpperCase();
    return '$first$last';
  }

  @override
  Widget build(BuildContext context) {
    final base = colorFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base.withValues(alpha: 0.95), base.withValues(alpha: 0.6)],
        ),
      ),
      child: Text(
        initialsFor(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
