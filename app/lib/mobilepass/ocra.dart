import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'hotp.dart';

/// RFC 6287 suite for a numeric challenge of [challengeLength] digits and a [digits]-digit response.
String ocraSuite(int digits, int challengeLength) => 'OCRA-1:HOTP-SHA256-$digits:QN0$challengeLength';

/// The 128-byte Q field for a decimal [challenge]: its hex form, padded with '0' on the right to
/// 256 hex characters (an odd-length hex string ends in a half byte).
Uint8List encodeNumericChallenge(String challenge) {
  final hex = BigInt.parse(challenge).toRadixString(16).toUpperCase().padRight(256, '0');
  return Uint8List.fromList([for (var i = 0; i < 256; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}

/// OCRA response for [challenge] under [suite]: no counter, PIN, session or timestamp inputs.
String generateOcra(Uint8List key, String suite, String challenge, {required int digits}) {
  final suiteBytes = utf8.encode(suite);
  final data = Uint8List(suiteBytes.length + 1 + 128)
    ..setRange(0, suiteBytes.length, suiteBytes)
    ..setRange(suiteBytes.length + 1, suiteBytes.length + 129, encodeNumericChallenge(challenge));
  return truncateMac(Hmac(sha256, key).convert(data).bytes, digits);
}
