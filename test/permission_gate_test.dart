import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/permissions/permission_gate.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';

/// A scripted [PermissionService] that never touches the real Android
/// permission MethodChannel. [status] is mutable so tests can simulate the OS
/// granting or revoking access between app resumes.
class _FakePermissionService extends PermissionService {
  _FakePermissionService({this.status = MediaPermissionStatus.granted});

  MediaPermissionStatus status;
  int statusChecks = 0;
  int requests = 0;
  int settingsOpens = 0;

  @override
  Future<MediaPermissionStatus> audioStatus() async {
    statusChecks++;
    return status;
  }

  @override
  Future<MediaPermissionStatus> requestAudio() async {
    requests++;
    return status;
  }

  @override
  Future<void> openAppSettingsPage() async {
    settingsOpens++;
  }
}

const _mainAppProbe = Key('main-app-probe');

Widget _harness(_FakePermissionService service) {
  return ProviderScope(
    overrides: [permissionServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(
      home: PermissionGate(
        child: Scaffold(
          body: Center(child: Text('MAIN APP', key: _mainAppProbe)),
        ),
      ),
    ),
  );
}

/// Forces the Android platform branch so the gate's real permission flow is
/// driven through [service]. The platform override must be restored before the
/// test body returns (the framework verifies foundation vars at the end of the
/// body), so each test ends by calling [_resetPlatform].
Future<void> _pumpGate(
  WidgetTester tester,
  _FakePermissionService service,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await tester.pumpWidget(_harness(service));
  // Let the initial async audioStatus() microtask resolve and rebuild.
  await tester.pump();
  await tester.pumpAndSettle();
}

void _resetPlatform() {
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('1. granted permission enters the main app', (tester) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.granted,
    );
    await _pumpGate(tester, service);

    expect(find.byKey(_mainAppProbe), findsOneWidget);
    expect(find.text('Allow access to music'), findsNothing);
    // Granted status only needs a status check, never a permission request.
    expect(service.requests, 0);
    expect(service.statusChecks, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
    _resetPlatform();
  });

  testWidgets('2. denied permission shows the gate and blocks the main app', (
    tester,
  ) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.denied,
    );
    await _pumpGate(tester, service);

    expect(find.text('Allow access to music'), findsOneWidget);
    expect(find.byKey(_mainAppProbe), findsNothing);
    expect(tester.takeException(), isNull);
    _resetPlatform();
  });

  testWidgets('3. permanent denial shows a settings-oriented state', (
    tester,
  ) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.permanentlyDenied,
    );
    await _pumpGate(tester, service);

    expect(find.text('Open settings'), findsOneWidget);
    expect(find.byKey(_mainAppProbe), findsNothing);
    expect(tester.takeException(), isNull);
    _resetPlatform();
  });

  testWidgets('4. "Open settings" routes through the service', (tester) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.permanentlyDenied,
    );
    await _pumpGate(tester, service);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(service.settingsOpens, 1);
    // Opening settings must not itself trigger a permission request.
    expect(service.requests, 0);
    // And the user must remain on the gate until access is (re)granted.
    expect(find.byKey(_mainAppProbe), findsNothing);
    _resetPlatform();
  });

  testWidgets('5. permission granted after app resume lets the user in', (
    tester,
  ) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.denied,
    );
    await _pumpGate(tester, service);
    expect(find.byKey(_mainAppProbe), findsNothing);

    // User toggles audio access on in Settings, then returns to the app.
    service.status = MediaPermissionStatus.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(_mainAppProbe), findsOneWidget);
    // It re-checks the real OS status on resume (no cached boolean).
    expect(service.statusChecks, greaterThanOrEqualTo(2));
    _resetPlatform();
  });

  testWidgets('6. permission remains denied after resume', (tester) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.denied,
    );
    await _pumpGate(tester, service);
    final checksBeforeResume = service.statusChecks;
    expect(find.byKey(_mainAppProbe), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Allow access to music'), findsOneWidget);
    expect(find.byKey(_mainAppProbe), findsNothing);
    expect(service.statusChecks, greaterThan(checksBeforeResume));
    _resetPlatform();
  });

  testWidgets('7. startup never throws a Directionality exception', (
    tester,
  ) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.denied,
    );
    await _pumpGate(tester, service);

    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsWidgets);
    _resetPlatform();
  });

  testWidgets('8. startup does not crash', (tester) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.granted,
    );
    await _pumpGate(tester, service);

    expect(tester.takeException(), isNull);
    expect(find.byKey(_mainAppProbe), findsOneWidget);
    _resetPlatform();
  });

  testWidgets('9. PermissionGate never auto-requests; only on explicit tap', (
    tester,
  ) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.denied,
    );
    await _pumpGate(tester, service);

    // Building, resolving status, and idle time must never request permission.
    expect(service.requests, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.requests, 0);

    // Tapping Allow requests exactly once and the state updates.
    service.status = MediaPermissionStatus.granted;
    await tester.tap(find.text('Allow access to music'));
    await tester.pumpAndSettle();

    expect(service.requests, 1);
    expect(find.byKey(_mainAppProbe), findsOneWidget);
    _resetPlatform();
  });

  testWidgets('10. PermissionGate transitions between states', (tester) async {
    final service = _FakePermissionService(
      status: MediaPermissionStatus.denied,
    );
    await _pumpGate(tester, service);
    expect(find.byKey(_mainAppProbe), findsNothing);

    // Denied -> granted after the user taps Allow.
    service.status = MediaPermissionStatus.granted;
    await tester.tap(find.text('Allow access to music'));
    await tester.pumpAndSettle();
    expect(find.byKey(_mainAppProbe), findsOneWidget);

    // External revocation while running: returning to the foreground with
    // denied status drops the user back onto the gate.
    service.status = MediaPermissionStatus.denied;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Allow access to music'), findsOneWidget);
    expect(find.byKey(_mainAppProbe), findsNothing);
    _resetPlatform();
  });
}
