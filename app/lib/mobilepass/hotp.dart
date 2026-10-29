import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'mobilepass_exception.dart';

/// Derives the HOTP key: `SHA256(seed ‖ suffix ‖ 00 00 00 00)`, a single-block KDF1. [suffix] is the
/// policy string's ASCII for policy versions other than 1, empty otherwise.
Uint8List deriveHotpKey(Uint8List seed, [String suffix = '']) {
  final suffixBytes = ascii.encode(suffix);
  final input = Uint8List(seed.length + suffixBytes.length + 4)
    ..setRange(0, seed.length, seed)
    ..setRange(seed.length, seed.length + suffixBytes.length, suffixBytes);
  return Uint8List.fromList(sha256.convert(input).bytes);
}

/// [digits]-digit HOTP for [counter]: RFC 4226 truncation over HMAC-SHA256.
String generateHotp(Uint8List key, int counter, {int digits = 6}) {
  if (counter < 0) {
    throw MobilePassException(MobilePassErrorCode.invalidCounter, 'counter must not be negative: $counter');
  }

  final counterBytes = ByteData(8)..setUint64(0, counter, Endian.big);
  return truncateMac(Hmac(sha256, key).convert(counterBytes.buffer.asUint8List()).bytes, digits);
}

/// RFC 4226 dynamic truncation of [mac] to a zero-padded [digits]-digit code.
String truncateMac(List<int> mac, int digits) {
  final offset = mac[mac.length - 1] & 0x0f;
  final truncated = ((mac[offset] & 0x7f) << 24) | (mac[offset + 1] << 16) | (mac[offset + 2] << 8) | mac[offset + 3];

  var modulus = 1;
  for (var i = 0; i < digits; i++) {
    modulus *= 10;
  }
  return (truncated % modulus).toString().padLeft(digits, '0');
}
