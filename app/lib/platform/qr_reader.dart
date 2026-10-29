import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../screens/qr_scan_screen.dart';

/// Where QR codes come from: the camera or a picked photo, both decoded on the device by ZXing.
abstract interface class QrReader {
  /// Text of the first QR code the camera sees; null if the user backs out. Camera permission
  /// must already be granted.
  Future<String?> scan(BuildContext context);

  /// Text of a QR code in a photo the user picks; null if they cancel, empty if none was found.
  Future<String?> readFromPhoto();
}

class ZxingQrReader implements QrReader {
  const ZxingQrReader();

  @override
  Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<String>(builder: (_) => const QrScanScreen()));

  @override
  Future<String?> readFromPhoto() async {
    final picker = ImagePickerPlatform.instance;
    // The system Photo Picker needs no storage permission; the plugin's default is a file chooser.
    if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
    final file = await picker.getImageFromSource(
      source: ImageSource.gallery,
      options: const ImagePickerOptions(requestFullMetadata: false),
    );
    if (file == null) return null;
    try {
      final code = await zx.readBarcodeImagePath(
        file,
        DecodeParams(format: Format.qrCode, tryHarder: true, tryInverted: true, maxSize: 1600),
      );
      return code.isValid ? (code.text ?? '') : '';
    } finally {
      // The picker copied the photo into the app's cache; the copy may show a secret.
      try {
        await File(file.path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }
}
