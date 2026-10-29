import 'dart:async';

import 'package:camera/camera.dart' show availableCameras;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../l10n/gen/app_localizations.dart';

/// Lens directions of the device's cameras.
typedef CameraLister = Future<List<CameraLensDirection>> Function();

/// Live preview on the camera facing [lens]: calls [onReady] once it streams, [onError] if it can't
/// start, and [onCode] with the text of each QR code it reads.
typedef ScanPreviewBuilder =
    Widget Function({
      required CameraLensDirection lens,
      required VoidCallback onReady,
      required ValueChanged<Object> onError,
      required ValueChanged<String> onCode,
    });

/// Full-screen camera that pops with the text of the first QR code it reads. Tries the back camera
/// first, then any other; says so when none starts, instead of leaving an empty preview.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    @visibleForTesting this.listCameras = _platformCameras,
    @visibleForTesting this.buildPreview = _zxingPreview,
    @visibleForTesting this.startTimeout = const Duration(seconds: 8),
  });

  final CameraLister listCameras;
  final ScanPreviewBuilder buildPreview;

  /// How long a camera may take to start before the next one is tried. Some failures
  /// surface only in the platform log and never reach Dart.
  final Duration startTimeout;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

Future<List<CameraLensDirection>> _platformCameras() async => [
  for (final camera in await availableCameras()) camera.lensDirection,
];

Widget _zxingPreview({
  required CameraLensDirection lens,
  required VoidCallback onReady,
  required ValueChanged<Object> onError,
  required ValueChanged<String> onCode,
}) => ReaderWidget(
  lensDirection: lens,
  codeFormat: Format.qrCode,
  tryInverted: true,
  showGallery: false,
  showToggleCamera: false,
  cropPercent: 0.7,
  scanDelay: const Duration(milliseconds: 200),
  scanDelaySuccess: Duration.zero,
  onScan: (code) {
    final text = code.text;
    if (code.isValid && text != null && text.isNotEmpty) onCode(text);
  },
  onControllerCreated: (controller, error) {
    if (error != null) {
      onError(error);
    } else if (controller != null) {
      onReady();
    }
  },
);

const _lensPreference = [CameraLensDirection.back, CameraLensDirection.front, CameraLensDirection.external];

enum _Failure { noCamera, cameraFailed }

class _QrScanScreenState extends State<QrScanScreen> {
  List<CameraLensDirection>? _lenses;
  int _attempt = 0;
  _Failure? _failure;
  Timer? _watchdog;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _findCameras();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  Future<void> _findCameras() async {
    List<CameraLensDirection> found;
    try {
      found = await widget.listCameras();
    } catch (_) {
      found = const [];
    }
    if (!mounted) return;
    final lenses = {
      for (final lens in [..._lensPreference, ...CameraLensDirection.values])
        if (found.contains(lens)) lens,
    }.toList();
    setState(() {
      _lenses = lenses;
      if (lenses.isEmpty) _failure = _Failure.noCamera;
    });
    if (lenses.isNotEmpty) _armWatchdog();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    final attempt = _attempt;
    _watchdog = Timer(widget.startTimeout, () => _onError(attempt));
  }

  void _onReady(int attempt) {
    if (attempt == _attempt) _watchdog?.cancel();
  }

  // A late error from a camera already given up on is ignored.
  void _onError(int attempt) {
    if (!mounted || attempt != _attempt || _failure != null) return;
    _watchdog?.cancel();
    setState(() {
      if (_attempt + 1 < _lenses!.length) {
        _attempt++;
      } else {
        _failure = _Failure.cameraFailed;
      }
    });
    if (_failure == null) _armWatchdog();
  }

  void _onCode(String text) {
    // Frames keep arriving until the route is gone.
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lenses = _lenses;
    final failure = _failure;
    final attempt = _attempt;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanQrTitle)),
      body: failure != null
          ? _ScanError(
              message: failure == _Failure.noCamera ? l10n.cameraNotFoundMessage : l10n.cameraUnavailableMessage,
            )
          : lenses == null
          ? const Center(child: CircularProgressIndicator())
          : KeyedSubtree(
              key: ValueKey('scanPreview-$attempt'),
              child: widget.buildPreview(
                lens: lenses[attempt],
                onReady: () => _onReady(attempt),
                onError: (_) => _onError(attempt),
                onCode: _onCode,
              ),
            ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(message, key: const ValueKey('scanErrorMessage'), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context).scanBackButton),
            ),
          ],
        ),
      ),
    );
  }
}
