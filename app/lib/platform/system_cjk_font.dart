import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';

/// Family the app's text falls back to for CJK once [loadSystemCjkFont] has registered it.
const systemCjkFontFamily = 'SimplePassSystemCJK';

/// The vendor CJK collection whose presence marks the affected devices (Samsung).
const samsungCjkFontFile = '/system/fonts/SECCJK-Regular.ttc';

/// Sans-serif CJK collections to borrow a face from, most preferred first.
const systemCjkFontFiles = [samsungCjkFontFile, '/system/fonts/NotoSansCJK-Regular.ttc'];

/// Registers the device's own sans-serif CJK face as [systemCjkFontFamily], for devices whose vendor
/// CJK fonts Flutter never loads (CJK falls to serif). Only devices with [marker] pay the ~14 MB copy.
/// Returns the file used, or null when not affected or anything fails.
Future<String?> loadSystemCjkFont(
  List<Locale> locales, {
  String marker = samsungCjkFontFile,
  List<String> files = systemCjkFontFiles,
  Future<void> Function(Uint8List font)? register,
}) async {
  final region = cjkRegionFor(locales);
  if (region == null) return null;
  try {
    if (!await File(marker).exists()) return null;
  } catch (_) {
    return null;
  }
  for (final path in files) {
    try {
      final collection = await File(path).readAsBytes();
      final face = extractCollectionFace(collection, (name) => _isRegularFaceFor(name, region));
      if (face == null) continue;
      await (register ?? _register)(face);
      return path;
    } catch (_) {
      // Unreadable or malformed; try the next one.
    }
  }
  return null;
}

Future<void> _register(Uint8List font) =>
    (FontLoader(systemCjkFontFamily)..addFont(Future.value(ByteData.sublistView(font)))).load();

/// Region suffix of the CJK face matching the first CJK locale ("tc", "hk", "sc", "jp", "kr");
/// null when no locale uses CJK.
String? cjkRegionFor(List<Locale> locales) {
  for (final l in locales) {
    switch (l.languageCode) {
      case 'zh':
        if (l.scriptCode == 'Hans' || const {'CN', 'SG'}.contains(l.countryCode)) return 'sc';
        if (l.countryCode == 'HK' || l.countryCode == 'MO') return 'hk';
        return 'tc';
      case 'ja':
        return 'jp';
      case 'ko':
        return 'kr';
    }
  }
  return null;
}

// "SECCJKtc-Regular", "NotoSansCJKTC-Regular", but not the monospaced faces.
bool _isRegularFaceFor(String postScriptName, String region) {
  final name = postScriptName.toLowerCase();
  return !name.contains('mono') && name.endsWith('cjk$region-regular');
}

/// The first face of TrueType/OpenType collection [ttc] whose PostScript name satisfies [pick], as a
/// standalone font file; null when [ttc] isn't a collection or no face matches.
/// A damaged or truncated collection gives null rather than an error.
Uint8List? extractCollectionFace(Uint8List ttc, bool Function(String postScriptName) pick) {
  final data = ByteData.sublistView(ttc);
  if (ttc.length < 12 || data.getUint32(0) != 0x74746366) return null; // 'ttcf'
  final faceCount = data.getUint32(8);
  if (12 + 4 * faceCount > ttc.length) return null;
  for (var i = 0; i < faceCount; i++) {
    final offset = data.getUint32(12 + 4 * i);
    final tables = _tableRecords(data, offset);
    if (tables == null) return null;
    final name = tables['name'];
    if (name == null) continue;
    final postScriptName = _postScriptName(data, name.offset, name.length);
    if (postScriptName != null && pick(postScriptName)) return _buildFont(ttc, data, offset, tables);
  }
  return null;
}

typedef _Table = ({int tag, int checksum, int offset, int length});

// Null when the directory or any table it lists runs past the end of [data].
Map<String, _Table>? _tableRecords(ByteData data, int faceOffset) {
  if (faceOffset + 12 > data.lengthInBytes) return null;
  final count = data.getUint16(faceOffset + 4);
  if (faceOffset + 12 + 16 * count > data.lengthInBytes) return null;
  final tables = {
    for (var t = 0; t < count; t++)
      _tagName(data.getUint32(faceOffset + 12 + 16 * t)): (
        tag: data.getUint32(faceOffset + 12 + 16 * t),
        checksum: data.getUint32(faceOffset + 16 + 16 * t),
        offset: data.getUint32(faceOffset + 20 + 16 * t),
        length: data.getUint32(faceOffset + 24 + 16 * t),
      ),
  };
  return tables.values.every((t) => t.offset + t.length <= data.lengthInBytes) ? tables : null;
}

String _tagName(int tag) => String.fromCharCodes([tag >> 24, (tag >> 16) & 0xff, (tag >> 8) & 0xff, tag & 0xff]);

// Name ID 6, from a Windows (UTF-16BE) or Macintosh Roman record.
String? _postScriptName(ByteData data, int tableOffset, int tableLength) {
  final end = tableOffset + tableLength;
  if (tableLength < 6) return null;
  final count = data.getUint16(tableOffset + 2);
  final strings = tableOffset + data.getUint16(tableOffset + 4);
  for (var r = 0; r < count; r++) {
    final record = tableOffset + 6 + 12 * r;
    if (record + 12 > end) break;
    final platform = data.getUint16(record);
    if (data.getUint16(record + 6) != 6) continue;
    final length = data.getUint16(record + 8);
    final start = strings + data.getUint16(record + 10);
    if (start + length > end) return null;
    if (platform == 3) {
      return String.fromCharCodes([for (var c = 0; c + 1 < length; c += 2) data.getUint16(start + c)]);
    }
    if (platform == 1) return String.fromCharCodes([for (var c = 0; c < length; c++) data.getUint8(start + c)]);
  }
  return null;
}

// sfnt header and table directory as in the collection, with each table copied after it (4-byte
// aligned) and the offsets pointing there.
Uint8List _buildFont(Uint8List ttc, ByteData data, int faceOffset, Map<String, _Table> tables) {
  final records = tables.values.toList()..sort((a, b) => a.tag.compareTo(b.tag));
  final headerLength = 12 + 16 * records.length;
  var size = headerLength;
  for (final t in records) {
    size += (t.length + 3) & ~3;
  }
  final out = Uint8List(size);
  final view = ByteData.sublistView(out);
  out.setRange(0, 12, ttc, faceOffset);
  view.setUint16(4, records.length);
  var cursor = headerLength;
  for (final (i, t) in records.indexed) {
    final record = 12 + 16 * i;
    view
      ..setUint32(record, t.tag)
      ..setUint32(record + 4, t.checksum)
      ..setUint32(record + 8, cursor)
      ..setUint32(record + 12, t.length);
    out.setRange(cursor, cursor + t.length, ttc, t.offset);
    cursor += (t.length + 3) & ~3;
  }
  return out;
}
