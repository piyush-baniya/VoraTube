import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/ads/premium_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/screens/ringtone_cutter_screen.dart';
import 'package:vora_tube/features/ringtones/data/audio_util_providers.dart';
import 'package:vora_tube/features/ringtones/data/audio_util_service.dart';

import 'fakes/fake_player.dart';

const _song = SongRef(
  identityKey: 'ms:1',
  uri: 'content://media/external/audio/media/1',
  title: 'Test Song',
  artist: 'Artist',
  durationMs: 120000,
);

class _FakeAudioUtilService implements AudioUtilService {
  bool canWrite = false;
  bool failSetDefault = false;
  int requestWriteSettingsCalls = 0;
  final List<String> setRingtoneCalls = [];

  @override
  Future<bool> supportsCutting() async => true;

  @override
  Future<double> cutProgress() async => 0;

  @override
  Future<AudioCutResult> cutAudio({
    required String sourceUri,
    required int startMs,
    required int endMs,
    required String songTitle,
  }) async {
    return AudioCutResult(
      path: '/data/ringtones/$songTitle - Ringtone.m4a',
      contentUri: 'content://media/external/audio/media/9',
      durationMs: endMs - startMs,
    );
  }

  @override
  Future<void> setDefaultRingtone(String contentUri) async {
    setRingtoneCalls.add(contentUri);
    if (failSetDefault) {
      throw const RingtoneOperationException('set_failed', 'boom');
    }
  }

  @override
  Future<bool> canWriteSettings() async => canWrite;

  @override
  Future<bool> requestWriteSettings() async {
    requestWriteSettingsCalls++;
    return canWrite;
  }
}

Future<void> _pumpCutter(
  WidgetTester tester,
  _FakeAudioUtilService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(FakePlayerController()),
        isPremiumProvider.overrideWithValue(true),
        audioUtilServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(
        home: RingtoneCutterScreen(song: _song),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'asks for the modify-system-settings permission when it is not granted',
    (tester) async {
      final service = _FakeAudioUtilService();
      await _pumpCutter(tester, service);

      await tester.tap(find.widgetWithText(FilledButton, 'Set as ringtone'));
      await tester.pumpAndSettle();

      // The dialog appears instead of an immediate failure.
      expect(find.text('Permission needed'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      // No assignment was attempted without the permission.
      expect(service.setRingtoneCalls, isEmpty);

      // Accepting the prompt opens the system settings screen.
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(service.requestWriteSettingsCalls, 1);
      expect(find.text('Permission needed'), findsNothing);
    },
  );

  testWidgets(
    'dismissing the permission prompt leaves the ringtone unset',
    (tester) async {
      final service = _FakeAudioUtilService();
      await _pumpCutter(tester, service);

      await tester.tap(find.widgetWithText(FilledButton, 'Set as ringtone'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(service.requestWriteSettingsCalls, 0);
      expect(service.setRingtoneCalls, isEmpty);
      expect(find.text('Permission needed'), findsNothing);
    },
  );

  testWidgets(
    'returning from settings with the permission granted sets the ringtone '
    'without re-exporting',
    (tester) async {
      final service = _FakeAudioUtilService();
      await _pumpCutter(tester, service);

      await tester.tap(find.widgetWithText(FilledButton, 'Set as ringtone'));
      await tester.pumpAndSettle();
      expect(find.text('Permission needed'), findsOneWidget);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(service.requestWriteSettingsCalls, 1);
      expect(service.setRingtoneCalls, isEmpty);

      // The user grants the permission and returns to the app.
      service.canWrite = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(service.setRingtoneCalls, hasLength(1));
      expect(find.text('Ringtone set successfully.'), findsOneWidget);
    },
  );

  testWidgets('set as ringtone succeeds when the permission is already held',
      (tester) async {
    final service = _FakeAudioUtilService()..canWrite = true;
    await _pumpCutter(tester, service);

    await tester.tap(find.widgetWithText(FilledButton, 'Set as ringtone'));
    await tester.pumpAndSettle();

    expect(find.text('Permission needed'), findsNothing);
    expect(service.setRingtoneCalls, hasLength(1));
    expect(find.text('Ringtone set successfully.'), findsOneWidget);
  });
}