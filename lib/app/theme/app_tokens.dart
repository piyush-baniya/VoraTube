import 'package:flutter/material.dart';

/// VoraTube design tokens.
///
/// Central source of truth for spacing, radius, animation, and surface
/// values. All UI components reference these tokens rather than
/// hard-coded values, ensuring visual consistency across screens.
abstract final class AppTokens {
  AppTokens._();

  // ── Spacing scale (4px base) ───────────────────────────────────────
  static const double s0 = 0;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;
  static const double s8 = 40;
  static const double s9 = 48;
  static const double s10 = 64;

  // ── Radius scale ───────────────────────────────────────────────────
  static const double rXs = 6;
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 20;
  static const double rXxl = 24;

  // ── Animation durations ────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 380);

  // ── Animation curves ───────────────────────────────────────────────
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
  static const Curve spring = Curves.easeOutBack;

  // ── Elevation / shadow ─────────────────────────────────────────────
  static List<BoxShadow> shadowSm(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowMd(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.12),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowLg(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.18),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  // ── Artwork sizes ──────────────────────────────────────────────────
  static const double artworkXs = 40;
  static const double artworkSm = 48;
  static const double artworkMd = 56;
  static const double artworkLg = 64;
  static const double artworkXl = 120;

  // ── Touch target minimum ───────────────────────────────────────────
  static const double touchTarget = 48;
}
