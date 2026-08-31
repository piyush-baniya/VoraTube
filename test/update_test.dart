import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:vora_tube/core/update/update_config.dart';
import 'package:vora_tube/core/update/update_dialog.dart';
import 'package:vora_tube/core/update/update_models.dart';
import 'package:vora_tube/core/update/update_providers.dart';
import 'package:vora_tube/core/update/update_service.dart';
import 'package:vora_tube/core/update/update_url_launcher.dart';
import 'package:vora_tube/core/update/version_compare.dart';

/// Convenience: build an UpdateInfo for tests.
UpdateInfo _info(String latest, String minimum, [List<String>? notes]) =>
    UpdateInfo(
      latestVersion: latest,
      minimumVersion: minimum,
      releaseNotes: notes ?? const <String>[],
    );

void main() {
  setUp(() {
    UpdateConfig.testConfigured = true;
    UpdateConfig.testVersionJsonUrl =
        'https://test.example/voratube/version.json';
    UpdateConfig.testUpdateUrl = 'https://test.example/voratube/download';
  });

  tearDown(() {
    UpdateConfig.testConfigured = false;
  });

  // ── Tests 1–5: semantic version comparison ──
  group('AppVersion semantic comparison', () {
    test('Test 1: 1.0.0 == 1.0.0 → no update', () {
      final installed = AppVersion.tryParse('1.0.0');
      expect(
        decideUpdate(installed: installed, info: _info('1.0.0', '1.0.0')),
        equals(UpdateDecision.none),
      );
    });

    test('Test 2: 1.0.0 < 1.1.0, min 1.0.0 → optional', () {
      final installed = AppVersion.tryParse('1.0.0');
      expect(
        decideUpdate(installed: installed, info: _info('1.1.0', '1.0.0')),
        equals(UpdateDecision.optional),
      );
    });

    test('Test 3: 1.0.0 < 1.1.0, min 1.1.0 → required', () {
      final installed = AppVersion.tryParse('1.0.0');
      expect(
        decideUpdate(installed: installed, info: _info('1.1.0', '1.1.0')),
        equals(UpdateDecision.required),
      );
    });

    test('Test 4: 1.2.0 > 1.1.0 → no update', () {
      final installed = AppVersion.tryParse('1.2.0');
      expect(
        decideUpdate(installed: installed, info: _info('1.1.0', '1.0.0')),
        equals(UpdateDecision.none),
      );
    });

    test('Test 5: 1.9.0 < 1.10.0 → update available', () {
      final installed = AppVersion.tryParse('1.9.0');
      expect(
        decideUpdate(installed: installed, info: _info('1.10.0', '1.0.0')),
        equals(UpdateDecision.optional),
      );
    });

    test('compareVersions: 1.9.0 < 1.10.0', () {
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
    });

    test('compareVersions: 1.9.9 < 1.10.0', () {
      expect(compareVersions('1.9.9', '1.10.0'), lessThan(0));
    });

    test('compareVersions: 1.10.0 > 1.9.0', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('AppVersion: strips build suffix 1.0.0+1 → 1.0.0', () {
      expect(AppVersion.tryParse('1.0.0+1').parts, equals([1, 0, 0]));
    });

    test('AppVersion: strips pre-release 1.1.0-beta → 1.1.0', () {
      expect(AppVersion.tryParse('1.1.0-beta').parts, equals([1, 1, 0]));
    });
  });

  // ── Test 6: malformed / partial JSON ──
  group('parseUpdateInfo', () {
    final service = UpdateService(
      client: MockClient((_) async => http.Response('{}', 200)),
      installedVersionResolver: () async => '1.0.0',
    );

    test('malformed JSON → null', () {
      expect(service.parseUpdateInfo('not json at all'), isNull);
    });

    test('non-object JSON (array) → null', () {
      expect(service.parseUpdateInfo('["not", "an", "object"]'), isNull);
    });

    test('missing latestVersion → null', () {
      expect(service.parseUpdateInfo('{"minimumVersion": "1.0.0"}'), isNull);
    });

    test('empty latestVersion → null', () {
      expect(service.parseUpdateInfo('{"latestVersion": ""}'), isNull);
    });

    test('missing minimumVersion → defaults to 0.0.0', () {
      final info = service.parseUpdateInfo('{"latestVersion": "1.1.0"}')!;
      expect(info.latestVersion, equals('1.1.0'));
      expect(info.minimumVersion, equals('0.0.0'));
    });

    test('release notes parsed and trimmed', () {
      final info = service.parseUpdateInfo(
        jsonEncode({
          'latestVersion': '1.1.0',
          'minimumVersion': '1.0.0',
          'releaseNotes': ['  Improved playback  ', 'Fixed bug'],
        }),
      )!;
      expect(info.releaseNotes, equals(['Improved playback', 'Fixed bug']));
    });

    test('release notes capped at maxReleaseNotes', () {
      final notes = List<String>.generate(20, (i) => 'Note $i');
      final info = service.parseUpdateInfo(
        jsonEncode({
          'latestVersion': '1.1.0',
          'minimumVersion': '1.0.0',
          'releaseNotes': notes,
        }),
      )!;
      expect(info.releaseNotes.length, equals(8));
    });

    test('blank release notes excluded', () {
      final info = service.parseUpdateInfo(
        jsonEncode({
          'latestVersion': '1.1.0',
          'minimumVersion': '1.0.0',
          'releaseNotes': ['', 'Real note', '  ', 'Another'],
        }),
      )!;
      expect(info.releaseNotes, equals(['Real note', 'Another']));
    });
  });

  // ── Test 7: network / service failures ──
  group('UpdateService.check', () {
    test('HTTP 500 → failed outcome', () async {
      final service = UpdateService(
        client: MockClient((_) async => http.Response('nope', 500)),
        installedVersionResolver: () async => '1.0.0',
      );
      final outcome = await service.check();
      expect(outcome.isFailure, isTrue);
    });

    test('timeout → failed outcome', () async {
      final service = UpdateService(
        client: MockClient((_) async {
          await Future.delayed(Duration(seconds: 30));
          return http.Response('{}', 200);
        }),
        installedVersionResolver: () async => '1.0.0',
        requestTimeout: Duration(milliseconds: 1),
      );
      final outcome = await service.check();
      expect(outcome.isFailure, isTrue);
    });

    test('malformed JSON body → failed outcome', () async {
      final service = UpdateService(
        client: MockClient((_) async => http.Response('not json', 200)),
        installedVersionResolver: () async => '1.0.0',
      );
      final outcome = await service.check();
      expect(outcome.isFailure, isTrue);
    });

    test('optional update found with release notes', () async {
      final service = UpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'latestVersion': '1.1.0',
              'minimumVersion': '1.0.0',
              'releaseNotes': ['New feature'],
            }),
            200,
          ),
        ),
        installedVersionResolver: () async => '1.0.0',
      );
      final outcome = await service.check();
      expect(outcome.isFailure, isFalse);
      expect(outcome.decision, equals(UpdateDecision.optional));
      expect(outcome.info!.latestVersion, equals('1.1.0'));
      expect(outcome.info!.releaseNotes, equals(['New feature']));
    });

    test('no update needed', () async {
      final service = UpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'latestVersion': '1.0.0', 'minimumVersion': '1.0.0'}),
            200,
          ),
        ),
        installedVersionResolver: () async => '1.0.0',
      );
      final outcome = await service.check();
      expect(outcome.isFailure, isFalse);
      expect(outcome.decision, equals(UpdateDecision.none));
    });

    test('required update found', () async {
      final service = UpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'latestVersion': '1.1.0', 'minimumVersion': '1.1.0'}),
            200,
          ),
        ),
        installedVersionResolver: () async => '1.0.0',
      );
      final outcome = await service.check();
      expect(outcome.isFailure, isFalse);
      expect(outcome.decision, equals(UpdateDecision.required));
    });
  });

  // ── Controller: throttle, dismiss, not-configured ──
  group('UpdateCheckerController', () {
    late Map<String, String> store;
    late int requestCount;

    setUp(() {
      store = {};
      requestCount = 0;
    });

    UpdateCheckerController _build({
      required String installedVersion,
      required String jsonResponse,
      int statusCode = 200,
    }) {
      final service = UpdateService(
        client: MockClient((_) async {
          requestCount++;
          return http.Response(jsonResponse, statusCode);
        }),
        installedVersionResolver: () async => installedVersion,
      );
      return UpdateCheckerController(
        service,
        kvGet: (key) async => store[key],
        kvSet: (key, value) async => store[key] = value,
      );
    }

    test('optional update → emits prompt', () async {
      final controller = _build(
        installedVersion: '1.0.0',
        jsonResponse: jsonEncode(_info('1.1.0', '1.0.0', ['Fixed bug'])),
      );

      await controller.run(now: DateTime(2024, 1, 1));

      expect(controller.state, isNotNull);
      expect(controller.state!.decision, equals(UpdateDecision.optional));
      expect(requestCount, equals(1));
    });

    test(
      'Test 8: dismiss (Later) clears prompt and not re-shown this session',
      () async {
        final controller = _build(
          installedVersion: '1.0.0',
          jsonResponse: jsonEncode(_info('1.1.0', '1.0.0')),
        );

        await controller.run(now: DateTime(2024, 1, 1));
        expect(controller.state, isNotNull);

        controller.dismiss();
        expect(controller.state, isNull);

        // Within 24 h → throttled (no second request).
        await controller.run(now: DateTime(2024, 1, 1, 6, 0));
        expect(controller.state, isNull);
        expect(requestCount, equals(1));

        // After 24 h → requests again, but same version was dismissed
        // this session so it is not re-prompted.
        await controller.run(now: DateTime(2024, 1, 3, 0, 0));
        expect(controller.state, isNull);
        expect(requestCount, equals(2));
      },
    );

    test('throttle: second run within 24 h does not re-fetch', () async {
      final controller = _build(
        installedVersion: '1.0.0',
        jsonResponse: jsonEncode(_info('1.1.0', '1.0.0')),
      );

      await controller.run(now: DateTime(2024, 1, 1, 12, 0));
      expect(requestCount, equals(1));

      await controller.run(now: DateTime(2024, 1, 1, 18, 0));
      expect(requestCount, equals(1));

      await controller.run(now: DateTime(2024, 1, 3, 0, 0));
      expect(requestCount, equals(2));
    });

    test('failed check does not advance throttle', () async {
      final controller = _build(
        installedVersion: '1.0.0',
        jsonResponse: 'nope',
        statusCode: 500,
      );

      await controller.run(now: DateTime(2024, 1, 1));
      expect(controller.state, isNull);
      expect(requestCount, equals(1));

      await controller.run(now: DateTime(2024, 1, 1, 0, 1));
      expect(requestCount, equals(2));
    });

    test('no update → no prompt but throttle advances', () async {
      final controller = _build(
        installedVersion: '1.0.0',
        jsonResponse: jsonEncode(_info('1.0.0', '1.0.0')),
      );

      await controller.run(now: DateTime(2024, 1, 1));
      expect(controller.state, isNull);
      expect(requestCount, equals(1));

      await controller.run(now: DateTime(2024, 1, 1, 6, 0));
      expect(requestCount, equals(1));
    });

    test('not configured → no network request', () async {
      UpdateConfig.testConfigured = false;
      final controller = _build(
        installedVersion: '1.0.0',
        jsonResponse: jsonEncode(_info('1.1.0', '1.0.0')),
      );

      await controller.run(now: DateTime(2024, 1, 1));

      expect(controller.state, isNull);
      expect(requestCount, equals(0));
    });
  });

  // ── Tests 9: URL launch validation ──
  group('UpdateUrlLauncher', () {
    tearDown(() {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test('Test 9a: non-HTTPS URL → false', () async {
      UpdateConfig.testConfigured = true;
      UpdateConfig.testUpdateUrl = 'http://test.example/download';
      final result = await const UpdateUrlLauncher().open();
      expect(result, isFalse);
    });

    test('Test 9b: invalid URL → false', () async {
      UpdateConfig.testConfigured = true;
      UpdateConfig.testUpdateUrl = 'not-a-url';
      final result = await const UpdateUrlLauncher().open();
      expect(result, isFalse);
    });

    test('Test 9c: launch throws → false (graceful)', () async {
      UpdateConfig.testConfigured = true;
      UpdateConfig.testUpdateUrl = 'https://test.example/download';

      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            throw PlatformException(code: 'error', message: 'launch failed'),
      );

      final result = await const UpdateUrlLauncher().open();
      expect(result, isFalse);
    });

    test('Test 9d: valid launch → true', () async {
      UpdateConfig.testConfigured = true;
      UpdateConfig.testUpdateUrl = 'https://test.example/download';

      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => true,
      );

      final result = await const UpdateUrlLauncher().open();
      expect(result, isTrue);
    });
  });

  // ── Dialog behaviour ──
  group('UpdateAvailableDialog', () {
    testWidgets('Test 8: Later button dismisses optional update dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showUpdateDialog(
                  context,
                  decision: UpdateDecision.optional,
                  info: _info('1.1.0', '1.0.0', ['Improved playback']),
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Improved playback'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateAvailableDialog), findsNothing);
    });

    testWidgets('required update dialog has no Later button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showUpdateDialog(
                  context,
                  decision: UpdateDecision.required,
                  info: _info('1.1.0', '1.1.0', ['Critical fix']),
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(find.text('Critical fix'), findsOneWidget);
    });

    testWidgets('release notes section hidden when empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showUpdateDialog(
                  context,
                  decision: UpdateDecision.optional,
                  info: _info('1.1.0', '1.0.0'),
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(find.text("What's new"), findsNothing);
    });
  });
}
