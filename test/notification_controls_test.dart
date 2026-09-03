import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/just_audio_controller.dart';

void main() {
  group('buildNotificationControls', () {
    test('shows Favorite, Previous, Play, Next, Close in order with a track',
        () {
      final controls = buildNotificationControls(
        hasTrack: true,
        playing: false,
        canStep: true,
        isFavorite: false,
      );

      expect(controls.length, 5);
      expect(controls[0].customAction?.name, kNotificationFavoriteAction);
      expect(controls[1].action, MediaAction.skipToPrevious);
      expect(controls[2].action, MediaAction.play);
      expect(controls[3].action, MediaAction.skipToNext);
      expect(controls[4].customAction?.name, kNotificationCloseAction);
    });

    test('uses the pause control while playing', () {
      final controls = buildNotificationControls(
        hasTrack: true,
        playing: true,
        canStep: true,
        isFavorite: false,
      );
      expect(controls[2].action, MediaAction.pause);
    });

    test('heart reflects the favourite state and label', () {
      final on = buildNotificationControls(
        hasTrack: true,
        playing: false,
        canStep: true,
        isFavorite: true,
      );
      expect(on[0].androidIcon, kFavoriteIconOn);
      expect(on[0].label, 'Unfavorite');

      final off = buildNotificationControls(
        hasTrack: true,
        playing: false,
        canStep: true,
        isFavorite: false,
      );
      expect(off[0].androidIcon, kFavoriteIconOff);
      expect(off[0].label, 'Favorite');
    });

    test('hides favourite, transport and close when no track is loaded', () {
      final controls = buildNotificationControls(
        hasTrack: false,
        playing: false,
        canStep: false,
        isFavorite: false,
      );
      expect(controls, isEmpty);
    });

    test('keeps only step controls when no track but a queue can step', () {
      final controls = buildNotificationControls(
        hasTrack: false,
        playing: false,
        canStep: true,
        isFavorite: false,
      );
      expect(controls.length, 2);
      expect(controls[0].action, MediaAction.skipToPrevious);
      expect(controls[1].action, MediaAction.skipToNext);
    });

    test('favourite and close are dispatched as the expected custom actions',
        () {
      final controls = buildNotificationControls(
        hasTrack: true,
        playing: false,
        canStep: false,
        isFavorite: false,
      );
      expect(controls[0].customAction?.name, 'favorite');
      expect(controls[1].action, MediaAction.play);
      expect(controls[2].customAction?.name, 'close');
    });
  });
}
