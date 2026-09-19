import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/audio/spectrum_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Future<Object?> Function(MethodCall call)? handler;

  setUp(() {
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('voratube/spectrum'),
          (call) => handler?.call(call),
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('voratube/spectrum'),
          null,
        );
  });

  void emitFrame(Map<String, Object?> data) {
    ServicesBinding.instance.channelBuffers.push(
      'voratube/spectrum',
      const StandardMethodCodec().encodeSuccessEnvelope(data),
      (data) {},
    );
  }

  Map<String, Object> frame(List<double> values) => {
    'values': values,
    'sampleRate': 48000,
    'timestamp': 42,
  };

  testWidgets('subscribe receives parsed 48-band frames', (tester) async {
    final received = <List<double>>[];
    handler = (call) async {
      if (call.method == 'listen') {
        emitFrame(frame(List.filled(48, 0.5)));
      }
      return null;
    };

    final sub = SpectrumService.instance.subscribe(received.add);
    await tester.pump(const Duration(milliseconds: 10));
    expect(received, hasLength(1));
    expect(received.first, hasLength(SpectrumService.bandCount));
    expect(received.first.first, 0.5);
    expect(SpectrumService.instance.isActive, isTrue);

    await sub.cancel();
    expect(SpectrumService.instance.isActive, isFalse);
  });

  testWidgets('malformed frames are ignored gracefully', (tester) async {
    final received = <List<double>>[];
    handler = (call) async {
      if (call.method == 'listen') {
        emitFrame({
          'values': <double>[1, 2, 3],
          'sampleRate': 48000,
        });
      }
      return null;
    };

    final sub = SpectrumService.instance.subscribe(received.add);
    await tester.pump(const Duration(milliseconds: 10));
    expect(received, isEmpty);

    await sub.cancel();
  });

  testWidgets('native errors do not crash the stream', (tester) async {
    // The services library reports the stream activation failure through
    // FlutterError; the service itself must survive it (handled via onError).
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {};
    addTearDown(() => FlutterError.onError = previousOnError);

    final received = <List<double>>[];
    handler = (call) async => throw PlatformException(code: 'boom');

    final sub = SpectrumService.instance.subscribe(received.add);
    await tester.pump(const Duration(milliseconds: 10));
    expect(received, isEmpty);
    expect(SpectrumService.instance.isActive, isTrue);

    await sub.cancel();
    expect(SpectrumService.instance.isActive, isFalse);
  });

  testWidgets('frame sample rate tracks the analyzed audio rate', (
    tester,
  ) async {
    handler = (call) async {
      if (call.method == 'listen') {
        emitFrame({
          'values': List<double>.filled(48, 0.25),
          'sampleRate': 44100,
        });
      }
      return null;
    };

    final received = <List<double>>[];
    final sub = SpectrumService.instance.subscribe(received.add);
    await tester.pump(const Duration(milliseconds: 10));
    expect(SpectrumService.instance.sampleRateHz, 44100);
    expect(received, hasLength(1));
    await sub.cancel();
  });

  testWidgets('cancelling twice never releases the analyzer twice', (
    tester,
  ) async {
    var listenCalls = 0;
    var cancelCalls = 0;
    handler = (call) async {
      if (call.method == 'listen') listenCalls++;
      if (call.method == 'cancel') cancelCalls++;
      return null;
    };

    final sub = SpectrumService.instance.subscribe((_) {});
    await sub.cancel();
    await sub.cancel();
    expect(listenCalls, 1);
    expect(cancelCalls, 1);
    expect(SpectrumService.instance.isActive, isFalse);

    final again = SpectrumService.instance.subscribe((_) {});
    await again.cancel();
    expect(listenCalls, 2);
    expect(SpectrumService.instance.isActive, isFalse);
  });

  testWidgets('multiple listeners share one platform subscription', (
    tester,
  ) async {
    final a = <List<double>>[];
    final b = <List<double>>[];
    var listenCalls = 0;
    handler = (call) async {
      if (call.method == 'listen') listenCalls++;
      return null;
    };

    final subA = SpectrumService.instance.subscribe(a.add);
    final subB = SpectrumService.instance.subscribe(b.add);
    expect(listenCalls, 1);

    await subA.cancel();
    await subB.cancel();
    expect(SpectrumService.instance.isActive, isFalse);
  });
}
