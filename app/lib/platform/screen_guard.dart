import 'package:flutter/services.dart';

/// Dart side of the `me.pinlin.simple_pass/screen_guard` channel (toggles `FLAG_SECURE`).
class ScreenGuard {
  ScreenGuard({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'me.pinlin.simple_pass/screen_guard';

  final MethodChannel _channel;

  Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // No platform binding (e.g. widget tests); nothing to guard.
    }
  }

  /// Android 13+: whether the recent-apps switcher may show a screenshot of
  /// the app. Older versions ignore it.
  Future<void> setRecentsScreenshotEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setRecentsScreenshotEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // See setSecure.
    }
  }
}
