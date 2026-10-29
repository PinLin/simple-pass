import 'package:flutter/services.dart';

enum CameraPermissionStatus {
  granted,
  denied,

  /// Android won't show the dialog again; only the app's system settings can grant it.
  permanentlyDenied,

  /// Another request's dialog is still up; that one gets the answer.
  busy,
}

/// Runtime camera permission, asked only when the user starts a scan.
abstract interface class CameraPermission {
  /// Shows the system dialog unless already granted.
  Future<CameraPermissionStatus> request();

  /// Opens this app's page in system settings.
  Future<void> openSettings();
}

/// Dart side of the `me.pinlin.simple_pass/camera_permission` channel.
class PlatformCameraPermission implements CameraPermission {
  PlatformCameraPermission({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'me.pinlin.simple_pass/camera_permission';

  final MethodChannel _channel;

  @override
  Future<CameraPermissionStatus> request() async {
    try {
      final status = await _channel.invokeMethod<String>('request');
      return CameraPermissionStatus.values.firstWhere(
        (s) => s.name == status,
        orElse: () => CameraPermissionStatus.denied,
      );
    } on PlatformException catch (e) {
      return e.code == 'IN_PROGRESS' ? CameraPermissionStatus.busy : CameraPermissionStatus.denied;
    } on MissingPluginException {
      return CameraPermissionStatus.denied;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Nothing more to offer; the message already says where the setting lives.
    } on MissingPluginException {
      // No platform binding (e.g. widget tests).
    }
  }
}
