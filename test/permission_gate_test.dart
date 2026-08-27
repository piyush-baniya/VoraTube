import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/permissions/permission_gate.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';

/// Scripted fake so the gate's Android flow is testable.
class _FakePermissionService extends PermissionService {
  _FakePermissionService(this.initial, {MediaPermissionStatus? afterRequest})
    : _afterRequest = afterRequest;

  final MediaPermissionStatus initial;
  final MediaPermissionStatus? _afterRequest;

  @override
  Future<MediaPermissionStatus> audioStatus() async => initial;

  @override
  Future<MediaPermissionStatus> requestAudio() async =>
      _afterRequest ?? initial;
}

Widget _harness(_FakePermissionService service) {
  return ProviderScope(
    overrides: [permissionServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(
      home: PermissionGate(child: SizedBox(key: ValueKey('app-child'))),
    ),
  );
}

void main() {
  // Force the Android code path regardless of the host OS. The override must
  // be cleared before each test body returns, otherwise the framework's
  // foundation-variable invariant check fails.
  testWidgets('shows permission screen when audio permission is denied', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      _harness(_FakePermissionService(MediaPermissionStatus.denied)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to VoraTube'), findsOneWidget);
    expect(find.text('Allow access to music'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-child')), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('opens settings flow when permanently denied', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      _harness(_FakePermissionService(MediaPermissionStatus.permanentlyDenied)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open settings'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reveals app after granting permission', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = _FakePermissionService(
      MediaPermissionStatus.denied,
      afterRequest: MediaPermissionStatus.granted,
    );
    await tester.pumpWidget(_harness(service));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-child')), findsNothing);

    await tester.tap(find.text('Allow access to music'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-child')), findsOneWidget);
    expect(find.text('Welcome to VoraTube'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reveals app immediately when permission already granted', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      _harness(_FakePermissionService(MediaPermissionStatus.granted)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-child')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
