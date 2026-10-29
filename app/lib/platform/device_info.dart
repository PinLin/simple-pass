import 'package:flutter/services.dart';

/// Dart side of the `me.pinlin.simple_pass/device` channel.
class DeviceInfo {
  const DeviceInfo({MethodChannel channel = const MethodChannel(channelName)}) : _channel = channel;

  static const String channelName = 'me.pinlin.simple_pass/device';

  final MethodChannel _channel;

  /// Android version as users know it (`Build.VERSION.RELEASE`, e.g. "16"); empty when unavailable.
  Future<String> osRelease() async {
    try {
      return await _channel.invokeMethod<String>('osRelease') ?? '';
    } on MissingPluginException {
      // No platform binding (e.g. widget tests).
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// `Build.VERSION.SDK_INT`; null when unavailable.
  Future<int?> sdkInt() async {
    try {
      return await _channel.invokeMethod<int>('sdkInt');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
