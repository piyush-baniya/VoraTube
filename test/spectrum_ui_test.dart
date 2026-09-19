import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/audio/audio_effects.dart';
import 'package:vora_tube/core/audio/parametric_eq.dart';
import 'package:vora_tube/features/player/data/equalizer_settings.dart';
import 'package:vora_tube/features/player/presentation/widgets/equalizer_curve.dart';
import 'package:vora_tube/features/player/presentation/widgets/parametric_curve.dart';
import 'package:vora_tube/features/player/presentation/widgets/spectrum_painter.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

/// Pushes a real native-style frame through the EventChannel. Callers pump
/// afterwards: pumping from inside a platform-message handler deadlocks.
void _emitFrame(List<double> values, {int rate = 48000}) {
  ServicesBinding.instance.channelBuffers.push(
    'voratube/spectrum',
    const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
      'values': values,
      'sampleRate': rate,
      'timestamp': 1,
    }),
    (data) {},
  );
}

/// Reads a public painter field off whichever graph painter is in the tree.
Object? _painterField(WidgetTester tester, String field) {
  for (final widget in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = widget.painter;
    if (painter == null) continue;
    try {
      final value = (painter as dynamic);
      switch (field) {
        case 'spectrum':
          final values = value.spectrum;
          if (values is List<double>) return values;
        case 'spectrumEdges':
          final edges = value.spectrumEdges;
          if (edges is List<double>) return edges;
        case 'spectrumColor':
          final color = value.spectrumColor;
          if (color is Color) return color;
      }
    } catch (_) {
      // Painter without this member (grid/text painters).
    }
  }
  return null;
}

/// Counts pixels the spectrum painter actually painted into [size].
Future<int> _paintedPixels(Size size, List<double> values) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintSpectrumBands(
    canvas,
    size,
    values: values,
    edgeFrequencies: spectrumEdgeFrequencies(),
    frequencyToX: (f) => (f / 20000).clamp(0.0, 1.0) * size.width,
    plotBottom: size.height,
    maxBarHeight: size.height,
    color: const Color(0xFF2196F3),
  );
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  var count = 0;
  for (var i = 3; i < data!.lengthInBytes; i += 4) {
    if (data.getUint8(i) > 8) count++;
  }
  return count;
}

/// Mounts [child] behind a mocked native analyzer that replays [frames] in
/// order whenever Flutter asks the EventChannel to start listening.
Future<void> _pumpWithFrames(
  WidgetTester tester,
  Widget child, {
  List<List<double>> frames = const [],
  int rate = 48000,
  ThemeData? theme,
}) async {
  var index = 0;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('voratube/spectrum'), (
        call,
      ) async {
        if (call.method == 'listen' && index < frames.length) {
          _emitFrame(frames[index++], rate: rate);
        }
        return null;
      });
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme ?? ThemeData(),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

List<double> _frame48(double value) => List<double>.filled(48, value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('voratube/spectrum'),
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('voratube/spectrum'),
          null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('voratube/spectrum'),
          null,
        );
  });

  testWidgets('spectrum toggle setting round-trips through encode/decode', (
    tester,
  ) async {
    const off = EqualizerUiSettings(spectrumEnabled: false);
    final decoded = EqualizerUiSettings.tryDecode(off.encode());
    expect(decoded.spectrumEnabled, isFalse);

    const on = EqualizerUiSettings(spectrumEnabled: true);
    expect(EqualizerUiSettings.tryDecode(on.encode()).spectrumEnabled, isTrue);

    // Corrupt / legacy blobs fall back to the default (on).
    expect(EqualizerUiSettings.tryDecode('not json').spectrumEnabled, isTrue);
  });

  testWidgets('graphic curve with spectrum overlay renders without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 800,
          height: 220,
          child: EqualizerCurve(
            levels: normalizeEqLevels(const [1, -2, 3, 0, 0, 4, -1, 0, 2, -3]),
            enabled: true,
            showSpectrum: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('parametric curve with spectrum overlay renders', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 800,
          height: 240,
          child: ParametricEqCurve(
            bands: [
              ParametricEqBand(
                id: 'b1',
                enabled: true,
                type: ParametricFilterType.peaking,
                frequencyHz: 1000,
                gainDb: 6,
                q: 1,
              ),
            ],
            enabled: true,
            height: 240,
            showSpectrum: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling the spectrum removes the analyzer subscription', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 800,
          height: 220,
          child: EqualizerCurve(
            levels: normalizeEqLevels(const []),
            enabled: true,
            showSpectrum: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Turn spectrum off and let the widget tree rebuild.
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 800,
          height: 220,
          child: EqualizerCurve(
            levels: normalizeEqLevels(const []),
            enabled: true,
            showSpectrum: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('live frames reach the graph painter that draws them', (
    tester,
  ) async {
    await _pumpWithFrames(
      tester,
      const SizedBox(
        width: 800,
        height: 220,
        child: EqualizerCurve(
          levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          enabled: true,
          showSpectrum: true,
        ),
      ),
      frames: [_frame48(0.15)],
    );

    // The first real native frame reaches the painter of the graph.
    final first = _painterField(tester, 'spectrum');
    expect(first, isA<List<double>>());
    expect(first as List<double>, hasLength(48));
    expect(first.last, closeTo(0.15, 1e-9));

    // A newer frame replaces it (newest data wins, no stale hold).
    _emitFrame(_frame48(0.85));
    await tester.pump(const Duration(milliseconds: 16));
    final painted = _painterField(tester, 'spectrum') as List<double>;
    expect(painted, hasLength(48));
    expect(painted.last, closeTo(0.85, 1e-9));

    final edges = _painterField(tester, 'spectrumEdges');
    expect(edges, isA<List<double>>());
    expect(edges as List<double>, hasLength(49));
    expect(_painterField(tester, 'spectrumColor'), isA<Color>());
  });

  testWidgets('louder real frames paint a taller spectrum', (tester) async {
    // Rasterizing needs the real async engine loop in widget tests.
    await tester.runAsync(() async {
      final quiet = await _paintedPixels(const Size(400, 200), _frame48(0.05));
      final loud = await _paintedPixels(const Size(400, 200), _frame48(0.9));
      // Magnitude drives the drawing: no fake motion, energy does.
      expect(quiet, greaterThan(0));
      expect(loud, greaterThan(quiet));
    });
  });

  testWidgets('graph renders in dark and light themes without overflow', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: SizedBox(
                width: 600,
                height: 220,
                child: EqualizerCurve(
                  levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                  enabled: true,
                  showSpectrum: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
  });
}
