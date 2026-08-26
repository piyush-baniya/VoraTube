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

  // Dark palette.
  static const Color voidBlack = Color(0xFF09090B);
  static const Color surfaceDark = Color(0xFF121214);
  static const Color surfaceRaisedDark = Color(0xFF1A1A1E);
  static const Color surfaceHighDark = Color(0xFF232329);
  static const Color outlineDark = Color(0xFF2C2C33);
  static const Color textPrimaryDark = Color(0xFFF2F2F4);
  static const Color textSecondaryDark = Color(0xFF9C9CA6);

  // Light palette (warm neutrals).
  static const Color paperLight = Color(0xFFF7F6F4);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceRaisedLight = Color(0xFFF1EFEC);
  static const Color surfaceHighLight = Color(0xFFE8E5E1);
  static const Color outlineLight = Color(0xFFDDDACF);
  static const Color textPrimaryLight = Color(0xFF1A191D);
  static const Color textSecondaryLight = Color(0xFF6B6972);

  // ── Semantic surfaces (dark) ──────────────────────────────────────
  static const Color cardDark = Color(0xFF141416);
  static const Color cardElevatedDark = Color(0xFF1C1C20);
  static const Color dividerDark = Color(0xFF1E1E22);
  static const Color borderSubtleDark = Color(0xFF222228);

  // ── Semantic surfaces (light) ─────────────────────────────────────
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardElevatedLight = Color(0xFFF8F7F5);
  static const Color dividerLight = Color(0xFFEDEBE8);
  static const Color borderSubtleLight = Color(0xFFE0DDD8);
}
