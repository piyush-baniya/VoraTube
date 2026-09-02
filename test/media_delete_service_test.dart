import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/storage/media_delete_service.dart';

void main() {
  const channel = MethodChannel('voratube/media_delete_v1');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method != 'deleteMediaFile') {
          return MissingPluginException();
        }
        final uri = (call.arguments as Map<Object?, Object?>)['contentUri'];
        if (uri == 'cancel') {
          return {'deleted': false, 'cancelled': true};
        }
        if (uri == 'fail') {
          throw PlatformException(code: 'delete_request_failed');
        }
        return {'deleted': true};
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('successful deletion reports deleted=true', () async {
    final service = MediaDeleteService(channel: channel);
    final result = await service.deleteMediaFile('content://media/1');
    expect(result.deleted, isTrue);
    expect(result.cancelled, isFalse);
  });

  test('user cancellation reports cancelled=true, deleted=false', () async {
    final service = MediaDeleteService(channel: channel);
    final result = await service.deleteMediaFile('cancel');
    expect(result.deleted, isFalse);
    expect(result.cancelled, isTrue);
  });

  test('platform error reports deleted=false without throwing', () async {
    final service = MediaDeleteService(channel: channel);
    final result = await service.deleteMediaFile('fail');
    expect(result.deleted, isFalse);
    expect(result.cancelled, isFalse);
  });

  test('invokes the platform channel with the content URI', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return {'deleted': true};
          },
        );

    final service = MediaDeleteService(channel: channel);
    await service.deleteMediaFile('content://media/audio/42');

    expect(calls, hasLength(1));
    final call = calls.single;
    expect(call.method, 'deleteMediaFile');
    expect((call.arguments as Map<Object?, Object?>)['contentUri'],
        'content://media/audio/42');
  });
}