import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/update/play_update.dart';
import 'package:vora_tube/core/update/play_update_controller.dart';
import 'package:vora_tube/core/update/play_update_host.dart';

class FakePlayUpdateApi implements PlayUpdateApi {
  FakePlayUpdateApi(this.info);

  PlayUpdateInfo info;
  PlayUpdateStatus startResult = PlayUpdateStatus.downloading;
  int checks = 0;
  int starts = 0;
  int completes = 0;
  void Function(PlayUpdateInfo state)? _callback;

  @override
  set onStateChange(void Function(PlayUpdateInfo state)? callback) {
    _callback = callback;
  }

  @override
  Future<PlayUpdateInfo> checkForUpdate() async {
    checks++;
    return info;
  }

  @override
  Future<PlayUpdateStatus> startFlexibleUpdate() async {
    starts++;
    if (startResult == PlayUpdateStatus.downloading) {
      info = info.copyWith(status: PlayUpdateStatus.downloading);
    }
    return startResult;
  }

  @override
  Future<void> completeUpdate() async {
    completes++;
  }

  void emit(PlayUpdateInfo state) => _callback?.call(state);
}

class FakePlayUpdateStore implements PlayUpdateStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const availableUpdate = PlayUpdateInfo(
  status: PlayUpdateStatus.available,
  availableVersionCode: 42,
  isFlexibleAllowed: true,
);

const downloadingUpdate = PlayUpdateInfo(
  status: PlayUpdateStatus.downloading,
  downloadedBytes: 4 * 1024 * 1024,
  totalBytes: 8 * 1024 * 1024,
);

({
  ProviderContainer container,
  FakePlayUpdateApi api,
  FakePlayUpdateStore store,
})
setUpUpdate({PlayUpdateInfo? info, FakePlayUpdateStore? store}) {
  final api = FakePlayUpdateApi(info ?? const PlayUpdateInfo());
  final resolvedStore = store ?? FakePlayUpdateStore();
  final container = ProviderContainer(
    overrides: [
      playUpdateApiProvider.overrideWithValue(api),
      playUpdateStoreProvider.overrideWithValue(resolvedStore),
    ],
  );
  return (container: container, api: api, store: resolvedStore);
}

Widget host(
  FakePlayUpdateApi api,
  FakePlayUpdateStore store, {
  ProviderContainer? container,
}) {
  const home = MaterialApp(home: PlayUpdateHost(child: _ManualCheckScaffold()));
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: home);
  }
  return ProviderScope(
    overrides: [
      playUpdateApiProvider.overrideWithValue(api),
      playUpdateStoreProvider.overrideWithValue(store),
    ],
    child: home,
  );
}

class _ManualCheckScaffold extends ConsumerWidget {
  const _ManualCheckScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => ref
              .read(playUpdateControllerProvider.notifier)
              .checkForUpdate(manual: true),
          child: const Text('Check for updates'),
        ),
      ),
    );
  }
}

void main() {
  group('PlayUpdateController', () {
    test('no update available does not expose a prompt', () async {
      final t = setUpUpdate();
      addTearDown(t.container.dispose);

      await t.container
          .read(playUpdateControllerProvider.notifier)
          .checkForUpdate();

      final state = t.container.read(playUpdateControllerProvider);
      expect(state.canPrompt, isFalse);
      expect(state.status, PlayUpdateStatus.notAvailable);
    });

    test('available flexible update exposes a prompt', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);

      await t.container
          .read(playUpdateControllerProvider.notifier)
          .checkForUpdate();

      final state = t.container.read(playUpdateControllerProvider);
      expect(state.canPrompt, isTrue);
      expect(state.availableVersionCode, 42);
    });

    test('automatic check runs at most once per launch', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.checkForUpdate();

      expect(t.api.checks, 1);
    });

    test('dev/unsupported environment stays silent', () async {
      final t = setUpUpdate(
        info: const PlayUpdateInfo(status: PlayUpdateStatus.unsupported),
      );
      addTearDown(t.container.dispose);

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.syncOnResume();

      expect(t.container.read(playUpdateControllerProvider).canPrompt, isFalse);
    });

    test('dismissal persists for the rest of the day', () async {
      final store = FakePlayUpdateStore();
      final first = setUpUpdate(info: availableUpdate, store: store);
      addTearDown(first.container.dispose);

      final notifier = first.container.read(
        playUpdateControllerProvider.notifier,
      );
      await notifier.checkForUpdate();
      await notifier.dismiss();
      expect(store.values, isNotEmpty);

      final second = setUpUpdate(info: availableUpdate, store: store);
      addTearDown(second.container.dispose);
      await second.container
          .read(playUpdateControllerProvider.notifier)
          .checkForUpdate();

      expect(second.api.checks, 0);
      expect(
        second.container.read(playUpdateControllerProvider).canPrompt,
        isFalse,
      );
    });

    test('manual check ignores the session gates', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.dismiss();
      await notifier.checkForUpdate(manual: true);

      expect(t.api.checks, 2);
    });

    test(
      'manual check reports no-update so Settings can say up to date',
      () async {
        final t = setUpUpdate(
          info: const PlayUpdateInfo(status: PlayUpdateStatus.notAvailable),
        );
        addTearDown(t.container.dispose);

        final info = await t.container
            .read(playUpdateControllerProvider.notifier)
            .checkForUpdate(manual: true);

        expect(info.status, PlayUpdateStatus.notAvailable);
      },
    );

    test('Update starts the flexible flow and reports downloading', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.startUpdate();

      expect(t.api.starts, 1);
      expect(
        t.container.read(playUpdateControllerProvider).status,
        PlayUpdateStatus.downloading,
      );
    });

    test('declined Play confirmation keeps the prompt', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);
      t.api.startResult = PlayUpdateStatus.canceled;

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.startUpdate();

      expect(t.container.read(playUpdateControllerProvider).canPrompt, isTrue);
    });

    test('failed flexible start surfaces a failure without crashing', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);
      t.api.startResult = PlayUpdateStatus.unsupported;

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.startUpdate();

      expect(
        t.container.read(playUpdateControllerProvider).status,
        PlayUpdateStatus.failed,
      );
    });

    test('native download progress is forwarded', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);

      await t.container
          .read(playUpdateControllerProvider.notifier)
          .checkForUpdate();
      t.api.emit(downloadingUpdate);

      final state = t.container.read(playUpdateControllerProvider);
      expect(state.status, PlayUpdateStatus.downloading);
      expect(state.progress, closeTo(0.5, 1e-9));
    });

    test('resume restores a downloaded update', () async {
      final t = setUpUpdate(
        info: const PlayUpdateInfo(status: PlayUpdateStatus.downloaded),
      );
      addTearDown(t.container.dispose);

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.syncOnResume();

      expect(
        t.container.read(playUpdateControllerProvider).status,
        PlayUpdateStatus.downloaded,
      );
    });

    test('resume does not re-prompt after dismissal', () async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);

      final notifier = t.container.read(playUpdateControllerProvider.notifier);
      await notifier.checkForUpdate();
      await notifier.dismiss();
      await notifier.syncOnResume();

      expect(t.api.checks, 2);
      expect(t.container.read(playUpdateControllerProvider).canPrompt, isFalse);
    });

    test('Restart & Update forwards completeUpdate to Play', () async {
      final t = setUpUpdate(
        info: const PlayUpdateInfo(status: PlayUpdateStatus.downloaded),
      );
      addTearDown(t.container.dispose);

      await t.container
          .read(playUpdateControllerProvider.notifier)
          .completeUpdate();

      expect(t.api.completes, 1);
    });
  });

  group('PlayUpdateHost', () {
    testWidgets('no update shows no sheet', (tester) async {
      await tester.pumpWidget(
        host(FakePlayUpdateApi(const PlayUpdateInfo()), FakePlayUpdateStore()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('unsupported environment shows nothing', (tester) async {
      await tester.pumpWidget(
        host(
          FakePlayUpdateApi(
            const PlayUpdateInfo(status: PlayUpdateStatus.unsupported),
          ),
          FakePlayUpdateStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('available update shows the sheet', (tester) async {
      await tester.pumpWidget(
        host(FakePlayUpdateApi(availableUpdate), FakePlayUpdateStore()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Version 42'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('Update starts the flexible download and shows progress', (
      tester,
    ) async {
      final api = FakePlayUpdateApi(availableUpdate);
      await tester.pumpWidget(host(api, FakePlayUpdateStore()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pump();
      api.emit(downloadingUpdate);
      await tester.pump();

      expect(api.starts, 1);
      expect(find.text('Downloading update'), findsOneWidget);
      expect(find.text('4.0 MB of 8.0 MB'), findsOneWidget);
    });

    testWidgets('Not now dismisses and does not return on resume', (
      tester,
    ) async {
      final api = FakePlayUpdateApi(availableUpdate);
      await tester.pumpWidget(host(api, FakePlayUpdateStore()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('downloaded update on launch shows the restart sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FakePlayUpdateApi(
            const PlayUpdateInfo(status: PlayUpdateStatus.downloaded),
          ),
          FakePlayUpdateStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update ready'), findsOneWidget);
      expect(find.text('Restart & Update'), findsOneWidget);
    });

    testWidgets('resume with a downloaded update raises the restart banner', (
      tester,
    ) async {
      final api = FakePlayUpdateApi(const PlayUpdateInfo());
      await tester.pumpWidget(host(api, FakePlayUpdateStore()));
      await tester.pumpAndSettle();
      expect(find.text('Restart & Update'), findsNothing);

      api.info = const PlayUpdateInfo(status: PlayUpdateStatus.downloaded);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.text('Update ready - restart VoraTube to install.'),
        findsOneWidget,
      );
      expect(find.text('Restart & Update'), findsOneWidget);
    });

    testWidgets('Restart & Update on the sheet completes the update', (
      tester,
    ) async {
      final api = FakePlayUpdateApi(
        const PlayUpdateInfo(status: PlayUpdateStatus.downloaded),
      );
      await tester.pumpWidget(host(api, FakePlayUpdateStore()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restart & Update'));
      await tester.pumpAndSettle();

      expect(api.completes, 1);
      expect(find.text('Restart & Update'), findsNothing);
    });

    testWidgets('Restart & Update on the banner completes the update', (
      tester,
    ) async {
      final api = FakePlayUpdateApi(const PlayUpdateInfo());
      await tester.pumpWidget(host(api, FakePlayUpdateStore()));
      await tester.pumpAndSettle();

      api.info = const PlayUpdateInfo(status: PlayUpdateStatus.downloaded);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restart & Update'));
      await tester.pump();

      expect(api.completes, 1);
    });

    testWidgets('a manual check with no update shows no sheet', (tester) async {
      final api = FakePlayUpdateApi(const PlayUpdateInfo());
      await tester.pumpWidget(host(api, FakePlayUpdateStore()));
      await tester.pumpAndSettle();

      api.info = const PlayUpdateInfo(status: PlayUpdateStatus.notAvailable);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('a manual check re-opens the sheet after a dismissal', (
      tester,
    ) async {
      final api = FakePlayUpdateApi(availableUpdate);
      await tester.pumpWidget(host(api, FakePlayUpdateStore()));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
    });
    testWidgets('a repeated check does not stack a second sheet', (
      tester,
    ) async {
      final t = setUpUpdate(info: availableUpdate);
      addTearDown(t.container.dispose);
      await tester.pumpWidget(host(t.api, t.store, container: t.container));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);

      await t.container
          .read(playUpdateControllerProvider.notifier)
          .checkForUpdate(manual: true);
      await tester.pumpAndSettle();

      expect(t.api.checks, 2);
      expect(find.text('Update available'), findsOneWidget);
    });
  });
}
