import 'package:flutter/material.dart';

/// VoraTube visual identity.
///
/// Dark-first, near-black neutral surfaces with a single restrained rose
/// accent used sparingly for interactive emphasis. Light theme is a warm
/// paper-neutral foundation — never pale pink washes.
abstract final class AppColors {
  AppColors._();

  // Brand accent — deeper rose, not candy pink.
  static const Color accent = Color(0xFFE85A83);
  static const Color accentBright = Color(0xFFFF7DA1);
  static const Color accentDeep = Color(0xFFB23B60);
  static const Color accentMuted = Color(0xFFE85A83);

  // Dark palette — near-black AMOLED-friendly.
  static const Color voidBlack = Color(0xFF09090B);
  static const Color surfaceDark = Color(0xFF0F0F11);
  static const Color surfaceRaisedDark = Color(0xFF18181B);
  static const Color surfaceHighDark = Color(0xFF232329);
  static const Color surfaceHighestDark = Color(0xFF2A2A30);
  static const Color outlineDark = Color(0xFF33333A);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFA8A8B3);
  static const Color textTertiaryDark = Color(0xFF71717A);
  static const Color inverseSurfaceDark = Color(0xFFF2F2F4);
  static const Color inverseOnSurfaceDark = Color(0xFF09090B);

  // Light palette (warm neutrals).
  static const Color paperLight = Color(0xFFF7F6F4);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceRaisedLight = Color(0xFFF1EFEC);
  static const Color surfaceHighLight = Color(0xFFE8E5E1);
  static const Color surfaceHighestLight = Color(0xFFDEDCD8);
  static const Color outlineLight = Color(0xFFD0CDC8);
  static const Color textPrimaryLight = Color(0xFF1A191D);
  static const Color textSecondaryLight = Color(0xFF6B6972);
  static const Color textTertiaryLight = Color(0xFF9A98A0);
  static const Color inverseSurfaceLight = Color(0xFF1A191D);
  static const Color inverseOnSurfaceLight = Color(0xFFF7F6F4);

  // ── Semantic surfaces (dark) ──────────────────────────────────────
  static const Color cardDark = Color(0xFF121214);
  static const Color cardElevatedDark = Color(0xFF1A1A1E);
  static const Color cardPressDark = Color(0xFF232329);
  static const Color dividerDark = Color(0xFF1E1E22);
  static const Color borderSubtleDark = Color(0xFF26262C);
  static const Color borderDark = Color(0xFF2C2C33);
  static const Color overlayDark = Color(0xCC09090B);

  // ── Semantic surfaces (light) ─────────────────────────────────────
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardElevatedLight = Color(0xFFF8F7F5);
  static const Color cardPressLight = Color(0xFFF1EFEC);
  static const Color dividerLight = Color(0xFFEDEBE8);
  static const Color borderSubtleLight = Color(0xFFE5E3DF);
  static const Color borderLight = Color(0xFFDCDAD5);
  static const Color overlayLight = Color(0xCCF7F6F4);

  // ── Status colors ──────────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ── Gradient stops ─────────────────────────────────────────────────
  static const List<Color> accentGradientDark = [
    Color(0x1AE85A83),
    Color(0x0AE85A83),
    Color(0x00000000),
  ];
  static const List<Color> accentGradientLight = [
    Color(0x1AE85A83),
    Color(0x0AE85A83),
    Color(0x00FFFFFF),
  ];
  static const List<Color> voidGradientDark = [
    Color(0xFF09090B),
    Color(0xFF121214),
    Color(0xFF1A1A1E),
  ];
  static const List<Color> voidGradientLight = [
    Color(0xFFF7F6F4),
    Color(0xFFFFFFFF),
    Color(0xFFF8F7F5),
  ];
}
