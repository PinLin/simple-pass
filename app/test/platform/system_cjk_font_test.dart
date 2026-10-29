import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/platform/system_cjk_font.dart';

// Three copies of a tiny CJK face named SECCJKjp-Regular, SECMonoCJKtc-Regular, SECCJKtc-Regular.
const _fixture = 'test/fixtures/cjk_collection.ttc';

/// Table tag → bytes of a single font file or of face [face] in a collection.
Map<String, List<int>> _tables(Uint8List bytes, {int? face}) {
  final data = ByteData.sublistView(bytes);
  final start = face == null ? 0 : data.getUint32(12 + 4 * face);
  return {
    for (var t = 0; t < data.getUint16(start + 4); t++)
      String.fromCharCodes(bytes.sublist(start + 12 + 16 * t, start + 16 + 16 * t)): bytes.sublist(
        data.getUint32(start + 20 + 16 * t),
        data.getUint32(start + 20 + 16 * t) + data.getUint32(start + 24 + 16 * t),
      ),
  };
}

void main() {
  final ttc = File(_fixture).readAsBytesSync();

  test('picks the regular face for the region and copies its tables intact', () {
    final face = extractCollectionFace(ttc, (name) => name == 'SECCJKtc-Regular')!;
    final data = ByteData.sublistView(face);
    expect(data.getUint32(0), 0x4f54544f); // 'OTTO', as the face's own header
    final expected = _tables(ttc, face: 2);
    final actual = _tables(face);
    expect(actual.keys.toSet(), expected.keys.toSet());
    for (final tag in expected.keys) {
      expect(actual[tag], expected[tag], reason: tag);
    }
    // Every table starts 4-byte aligned, as the format requires.
    for (var t = 0; t < data.getUint16(4); t++) {
      expect(data.getUint32(20 + 16 * t) % 4, 0);
    }
  });

  test('null when no face matches or the data is not a collection', () {
    expect(extractCollectionFace(ttc, (_) => false), isNull);
    expect(extractCollectionFace(Uint8List.fromList([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), (_) => true), isNull);
    expect(extractCollectionFace(Uint8List(3), (_) => true), isNull);
  });

  test('a truncated or damaged collection gives null, never an error', () {
    bool pick(String name) => name == 'SECCJKtc-Regular';
    for (final length in [12, 16, 40, 200, ttc.length ~/ 2, ttc.length - 1]) {
      expect(
        () => extractCollectionFace(Uint8List.fromList(ttc.sublist(0, length)), pick),
        returnsNormally,
        reason: '$length',
      );
      expect(extractCollectionFace(Uint8List.fromList(ttc.sublist(0, length)), pick), isNull, reason: '$length');
    }
    // A face offset pointing past the end.
    final bad = Uint8List.fromList(ttc);
    ByteData.sublistView(bad).setUint32(12, 0x7fffffff);
    expect(extractCollectionFace(bad, (_) => true), isNull);
    // A table length running past the end.
    final longTable = Uint8List.fromList(ttc);
    final view = ByteData.sublistView(longTable);
    final face = view.getUint32(12 + 4 * 2);
    view.setUint32(face + 24, 0x7fffffff);
    expect(extractCollectionFace(longTable, pick), isNull);
  });

  test('regions follow the first CJK locale', () {
    expect(
      cjkRegionFor(const [Locale('en'), Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')]),
      'tc',
    );
    expect(cjkRegionFor(const [Locale('zh', 'TW')]), 'tc');
    expect(cjkRegionFor(const [Locale('zh', 'HK')]), 'hk');
    expect(cjkRegionFor(const [Locale('zh', 'CN')]), 'sc');
    expect(cjkRegionFor(const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')]), 'sc');
    expect(cjkRegionFor(const [Locale('ja')]), 'jp');
    expect(cjkRegionFor(const [Locale('ko')]), 'kr');
    expect(cjkRegionFor(const [Locale('en'), Locale('fr')]), isNull);
  });

  group('loadSystemCjkFont', () {
    late List<Uint8List> registered;
    setUp(() => registered = []);
    Future<void> register(Uint8List font) async => registered.add(font);

    test('registers the regular Traditional Chinese face, skipping the monospaced one', () async {
      final used = await loadSystemCjkFont(
        const [Locale('zh', 'TW')],
        marker: _fixture,
        files: ['/nonexistent/font.ttc', _fixture],
        register: register,
      );
      expect(used, _fixture);
      expect(registered.single, extractCollectionFace(ttc, (n) => n == 'SECCJKtc-Regular'));
    });

    test('does nothing without a CJK locale, a usable file or a matching face', () async {
      Future<String?> load(List<Locale> locales, {String marker = _fixture, List<String> files = const [_fixture]}) =>
          loadSystemCjkFont(locales, marker: marker, files: files, register: register);
      expect(await load(const [Locale('en')]), isNull);
      expect(await load(const [Locale('zh', 'TW')], files: ['/nonexistent']), isNull);
      expect(await load(const [Locale('ko')]), isNull);
      // Devices without the vendor collection keep the system fallback.
      expect(await load(const [Locale('zh', 'TW')], marker: '/nonexistent/SECCJK-Regular.ttc'), isNull);
      expect(registered, isEmpty);
    });

    test('a registration failure is swallowed', () async {
      final used = await loadSystemCjkFont(
        const [Locale('zh', 'TW')],
        marker: _fixture,
        files: [_fixture],
        register: (_) async => throw Exception('bad font'),
      );
      expect(used, isNull);
    });
  });
}
