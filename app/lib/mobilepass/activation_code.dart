import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'mobilepass_exception.dart';

const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Length of an activation code without hyphens, in either format.
const int activationCodeLength = 20;

/// Length of the seed an activation code carries.
const int activationSeedLength = 10;

/// The two activation code layouts.
enum ActivationCodeFormat {
  /// `XXXXC-XXXXC-XXXXC-XXXXC`: 16 base32 seed characters, each group followed by its check character.
  legacy,

  /// 100 bits: seed, policy version and a SHA-256 check byte, in five groups of five.
  versioned,
}

/// A strictly validated activation code.
class DecodedActivationCode {
  const DecodedActivationCode({required this.seed, required this.format, this.version});

  final Uint8List seed;
  final ActivationCodeFormat format;

  /// Policy version embedded in a [ActivationCodeFormat.versioned] code; null for legacy.
  final int? version;
}

/// Uppercases and keeps only ASCII letters and digits, dropping hyphens, whitespace and zero-width
/// characters pasted from chat apps. Digits outside base32 (0, 1, 8, 9) are kept so validation rejects
/// them visibly instead of the code silently losing characters.
String activationCodeCharacters(String input) {
  final buffer = StringBuffer();
  for (final char in input.toUpperCase().split('')) {
    if (_alphanumeric.hasMatch(char)) buffer.write(char);
  }
  return buffer.toString();
}

final _alphanumeric = RegExp(r'^[A-Z0-9]$');

bool _isBase32(String chars) => chars.split('').every(_base32Alphabet.contains);

/// [activationCodeCharacters] with a hyphen every 5 characters. Does not validate.
String normalizeActivationCode(String input) => _group(activationCodeCharacters(input));

String _group(String chars) {
  final buffer = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    if (i > 0 && i % 5 == 0) buffer.write('-');
    buffer.write(chars[i]);
  }
  return buffer.toString();
}

/// Check character: alphabet[Σ code(s[i]) × (i + 1) mod 32].
String checkCharacter(String s) {
  var sum = 0;
  for (var i = 0; i < s.length; i++) {
    sum += s.codeUnitAt(i) * (i + 1);
  }
  return _base32Alphabet[sum % 32];
}

/// True if [input] decodes in either format, check characters included.
bool isValidActivationCode(String input) => decodeActivationCode(input) != null;

/// Strict decoding: legacy first, then versioned; null if neither format's checks pass.
DecodedActivationCode? decodeActivationCode(String input) {
  final chars = activationCodeCharacters(input);
  if (chars.length != activationCodeLength || !_isBase32(chars)) return null;
  return _decodeLegacy(chars) ?? _decodeVersioned(chars);
}

DecodedActivationCode? _decodeLegacy(String chars) {
  final data = StringBuffer();
  for (var i = 0; i < activationCodeLength; i += 5) {
    final group = chars.substring(i, i + 4);
    if (chars[i + 4] != checkCharacter(group)) return null;
    data.write(group);
  }
  return DecodedActivationCode(seed: _base32Decode(data.toString()), format: ActivationCodeFormat.legacy);
}

DecodedActivationCode? _decodeVersioned(String chars) {
  final bits = _toBits(chars);
  final payload = bits.substring(0, 92);
  if (bits.substring(92, 100) != _checkByteBits(payload)) return null;
  final seed = Uint8List(activationSeedLength);
  for (var i = 0; i < activationSeedLength; i++) {
    seed[i] = int.parse(bits.substring(i * 8, i * 8 + 8), radix: 2);
  }
  return DecodedActivationCode(
    seed: seed,
    format: ActivationCodeFormat.versioned,
    version: int.parse(bits.substring(80, 85), radix: 2) + 1,
  );
}

/// Legacy code for a 10-byte [seed].
String encodeLegacyActivationCode(Uint8List seed) {
  _checkSeed(seed);
  final data = _base32Encode(seed.map((b) => b.toRadixString(2).padLeft(8, '0')).join());
  return [
    for (var i = 0; i < 16; i += 4) '${data.substring(i, i + 4)}${checkCharacter(data.substring(i, i + 4))}',
  ].join('-');
}

/// Versioned code for a 10-byte [seed] and policy [version] (1–32).
String encodeVersionedActivationCode(Uint8List seed, int version) {
  _checkSeed(seed);
  RangeError.checkValueInInterval(version, 1, 32, 'version');
  final seedBits = seed.map((b) => b.toRadixString(2).padLeft(8, '0')).join();
  final payload = '$seedBits${(version - 1).toRadixString(2).padLeft(5, '0')}0000000';
  return _group(_base32Encode('$payload${_checkByteBits(payload)}'));
}

/// Random seed for a new activation code.
Uint8List generateActivationSeed([Random? random]) {
  final source = random ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(activationSeedLength, (_) => source.nextInt(256)));
}

/// Seed bytes for OTP generation. Accepts every strictly valid code, and otherwise falls back to
/// ignoring the check characters of a 20-character code, so codes stored before check characters
/// were enforced keep working. Throws [MobilePassException] if neither applies.
Uint8List activationCodeToKey(String code) {
  final decoded = decodeActivationCode(code);
  if (decoded != null) return decoded.seed;
  final chars = activationCodeCharacters(code);
  if (chars.length != activationCodeLength || !_isBase32(chars)) {
    throw const MobilePassException(MobilePassErrorCode.invalidActivationCode, 'Invalid activation code');
  }
  final data = [for (var i = 0; i < activationCodeLength; i += 5) chars.substring(i, i + 4)].join();
  return _base32Decode(data);
}

void _checkSeed(Uint8List seed) {
  if (seed.length != activationSeedLength) {
    throw ArgumentError.value(seed.length, 'seed.length', 'must be $activationSeedLength');
  }
}

// Last byte of SHA-256 over the 92 payload bits padded with 4 zero bits to 12 bytes.
String _checkByteBits(String payload92) {
  final padded = '${payload92}0000';
  final bytes = Uint8List(12);
  for (var i = 0; i < 12; i++) {
    bytes[i] = int.parse(padded.substring(i * 8, i * 8 + 8), radix: 2);
  }
  return sha256.convert(bytes).bytes.last.toRadixString(2).padLeft(8, '0');
}

String _toBits(String chars) =>
    chars.split('').map((c) => _base32Alphabet.indexOf(c).toRadixString(2).padLeft(5, '0')).join();

// [bits] length must be a multiple of 5.
String _base32Encode(String bits) =>
    [for (var i = 0; i < bits.length; i += 5) _base32Alphabet[int.parse(bits.substring(i, i + 5), radix: 2)]].join();

/// Decodes unpadded RFC 4648 base32; [input] must already be in [_base32Alphabet].
Uint8List _base32Decode(String input) {
  final output = BytesBuilder();
  var bitBuffer = 0;
  var bitCount = 0;
  for (final rune in input.runes) {
    final index = _base32Alphabet.indexOf(String.fromCharCode(rune));
    bitBuffer = (bitBuffer << 5) | index;
    bitCount += 5;
    if (bitCount >= 8) {
      bitCount -= 8;
      output.addByte((bitBuffer >> bitCount) & 0xff);
    }
  }
  return output.toBytes();
}
