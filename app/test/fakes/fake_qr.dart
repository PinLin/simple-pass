import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:simple_pass/platform/camera_permission.dart';
import 'package:simple_pass/platform/qr_reader.dart';

/// Answers [request] with [status] and counts calls, like the system dialog.
class FakeCameraPermission implements CameraPermission {
  FakeCameraPermission([this.status = CameraPermissionStatus.granted]);

  CameraPermissionStatus status;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<CameraPermissionStatus> request() async {
    requests++;
    return status;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

/// Hands out [scanned] from the camera and [photo] from the picker without either.
class FakeQrReader implements QrReader {
  String? scanned;

  /// When set, [scan] waits for it instead of answering [scanned] right away.
  Completer<String?>? scanGate;
  String? photo;
  Object? photoError;
  int scans = 0;
  int photos = 0;

  @override
  Future<String?> scan(BuildContext context) async {
    scans++;
    return scanGate != null ? scanGate!.future : scanned;
  }

  @override
  Future<String?> readFromPhoto() async {
    photos++;
    if (photoError case final error?) throw error;
    return photo;
  }
}
