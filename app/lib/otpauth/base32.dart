import 'dart:typed_data';

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

// Leftover characters after the last full 8-character block that can't come from whole bytes.
const _impossibleTailLengths = {1, 3, 6};

/// RFC 4648 Base32 of [bytes]; [padding] adds the trailing `=`.
String base32Encode(List<int> bytes, {bool padding = false}) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | (b & 0xff);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(buffer >> bits) & 0x1f]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  if (padding) {
    while (out.length % 8 != 0) {
      out.write('=');
    }
  }
  return out.toString();
}

/// Decodes RFC 4648 Base32 the way people type and paste secrets: whitespace anywhere, lowercase
/// and missing or present trailing padding are all accepted. Leftover bits after the last byte are
/// ignored even when not zero, as other authenticators do for secrets made of random characters.
/// Null for anything else.
Uint8List? base32Decode(String input) {
  final text = input.replaceAll(RegExp(r'\s'), '').toUpperCase().replaceFirst(RegExp(r'=+$'), '');
  if (_impossibleTailLengths.contains(text.length % 8)) return null;
  final out = BytesBuilder(copy: false);
  var buffer = 0;
  var bits = 0;
  for (final char in text.split('')) {
    final value = _alphabet.indexOf(char);
    if (value < 0) return null;
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((buffer >> bits) & 0xff);
    }
    buffer &= (1 << bits) - 1;
  }
  return out.toBytes();
}
