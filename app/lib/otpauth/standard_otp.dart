import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../mobilepass/hotp.dart' show truncateMac;

/// HMAC hash of an RFC 4226 / RFC 6238 token, named as in otpauth links.
enum OtpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const OtpAlgorithm(this.label);

  final String label;

  crypto.Hash get _hash => switch (this) {
    OtpAlgorithm.sha1 => crypto.sha1,
    OtpAlgorithm.sha256 => crypto.sha256,
    OtpAlgorithm.sha512 => crypto.sha512,
  };

  /// Case-insensitive [label] lookup; null for anything else.
  static OtpAlgorithm? fromLabel(String label) {
    final upper = label.toUpperCase();
    return values.where((a) => a.label == upper).firstOrNull;
  }
}

/// Code lengths the app accepts for standard tokens.
const supportedOtpDigits = [6, 8];

/// Defaults of RFC 6238 and the otpauth key URI format.
const defaultOtpAlgorithm = OtpAlgorithm.sha1;
const defaultOtpDigits = 6;
const defaultOtpPeriod = 30;

/// Longest accepted TOTP period, in seconds.
const maxOtpPeriod = 3600;

bool isValidOtpPeriod(int period) => period >= 1 && period <= maxOtpPeriod;

/// RFC 4226 HOTP over [algorithm].
String generateStandardHotp(
  Uint8List key,
  int counter, {
  OtpAlgorithm algorithm = defaultOtpAlgorithm,
  int digits = defaultOtpDigits,
}) {
  if (counter < 0) throw ArgumentError.value(counter, 'counter', 'must not be negative');
  final counterBytes = ByteData(8)..setUint64(0, counter, Endian.big);
  return truncateMac(crypto.Hmac(algorithm._hash, key).convert(counterBytes.buffer.asUint8List()).bytes, digits);
}

/// RFC 6238 TOTP at [unixSeconds], counting [period]-second steps from [epochSeconds] (the Unix epoch
/// unless given).
String generateStandardTotp(
  Uint8List key,
  int unixSeconds, {
  OtpAlgorithm algorithm = defaultOtpAlgorithm,
  int digits = defaultOtpDigits,
  int period = defaultOtpPeriod,
  int epochSeconds = 0,
}) => generateStandardHotp(key, (unixSeconds - epochSeconds) ~/ period, algorithm: algorithm, digits: digits);
