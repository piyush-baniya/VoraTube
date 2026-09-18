import 'package:flutter/animation.dart';

import 'artwork_palette.dart';

/// [Tween] adapter over [ArtworkPalette.lerp] so a palette can drive
/// [TweenAnimationBuilder] for a smooth song-to-song color transition.
class ArtworkPaletteTween extends Tween<ArtworkPalette> {
  ArtworkPaletteTween({super.begin, super.end});

  @override
  ArtworkPalette lerp(double t) {
    final b = begin;
    final e = end;
    if (b == null) {
      if (e == null) {
        throw StateError('No palette to lerp');
      }
      return e;
    }
    if (e == null) return b;
    return ArtworkPalette.lerp(b, e, t);
  }
}
