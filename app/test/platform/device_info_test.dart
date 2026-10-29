import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/platform/device_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(DeviceInfo.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns the Android release from the platform', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'osRelease' ? '16' : null);
    expect(await const DeviceInfo().osRelease(), '16');
  });

  test('empty without a platform binding or on a platform error', () async {
    expect(await const DeviceInfo().osRelease(), '');
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'x'));
    expect(await const DeviceInfo().osRelease(), '');
  });
}
