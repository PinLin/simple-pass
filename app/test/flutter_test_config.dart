// Loads real fonts so golden tests render glyphs instead of "Ahem" boxes.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _loadFlutterSdkFonts();
  await testMain();
}

/// Family registered for CJK glyphs; screens fall back to it via [testTheme].
const cjkFontFamily = 'NotoSansTC';

// Subset of Noto Sans TC (SIL OFL 1.1, test/fonts/OFL.txt) covering zh arb chars and intl date
// words. Regenerate with pyftsubset (NotoSansTC-Regular.otf 2.004, notofonts/noto-cjk) when new zh
// strings appear, keeping every existing code point.
Future<void> _loadCjkFont() async {
  final file = File('test/fonts/NotoSansTC-Subset.otf');
  if (!file.existsSync()) return;
  final loader = FontLoader(cjkFontFamily)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

Future<void> _loadFlutterSdkFonts() async {
  await _loadCjkFont();
  final flutterRoot = _resolveFlutterRoot();
  if (flutterRoot == null) return;

  final fontDir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final candidates = <String, List<String>>{
    'Roboto': [
      '$fontDir/Roboto-Regular.ttf',
      '$fontDir/Roboto-Medium.ttf',
      '$fontDir/Roboto-Light.ttf',
      '$fontDir/Roboto-Bold.ttf',
    ],
    'MaterialIcons': ['$fontDir/MaterialIcons-Regular.otf'],
  };

  for (final entry in candidates.entries) {
    final loader = FontLoader(entry.key);
    var loadedAny = false;
    for (final path in entry.value) {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
        loadedAny = true;
      }
    }
    if (loadedAny) await loader.load();
  }
}

String? _resolveFlutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && Directory(env).existsSync()) return env;
  // Try common install locations.
  for (final p in [
    '/opt/homebrew/share/flutter',
    '/usr/local/share/flutter',
    '${Platform.environment['HOME']}/development/flutter',
    '${Platform.environment['HOME']}/flutter',
  ]) {
    if (Directory(p).existsSync()) return p;
  }
  return null;
}
