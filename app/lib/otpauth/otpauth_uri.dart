import 'dart:typed_data';

import '../models/profile.dart' show maxCounter;
import 'base32.dart';
import 'standard_otp.dart';

enum OtpauthErrorCode {
  /// Not an `otpauth://` link at all.
  notOtpauth,

  /// An `otpauth-migration://` export, which bundles several tokens in an encoded payload.
  migrationUnsupported,

  /// `otpauth://` with a type other than `totp` or `hotp`.
  unsupportedType,

  /// The secret is missing, empty or not Base32.
  invalidSecret,

  /// Algorithm, digits, period or counter outside what the app supports.
  unsupportedParameters,
}

class OtpauthException implements Exception {
  const OtpauthException(this.code, this.message);

  final OtpauthErrorCode code;
  final String message;

  @override
  String toString() => 'OtpauthException(${code.name}): $message';
}

enum OtpauthType { totp, hotp }

/// A parsed `otpauth://` key URI (Google Authenticator Key Uri Format).
class OtpauthUri {
  const OtpauthUri({
    required this.type,
    required this.secret,
    this.issuer = '',
    this.account = '',
    this.algorithm = defaultOtpAlgorithm,
    this.digits = defaultOtpDigits,
    this.period = defaultOtpPeriod,
    this.counter = 0,
  });

  final OtpauthType type;
  final Uint8List secret;
  final String issuer;
  final String account;
  final OtpAlgorithm algorithm;
  final int digits;

  /// Seconds per code; meaningful for [OtpauthType.totp] only.
  final int period;

  /// Initial counter; meaningful for [OtpauthType.hotp] only, where the link must give it.
  final int counter;
}

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Parses an `otpauth://totp/...` or `otpauth://hotp/...` link (surrounding whitespace ignored).
/// Throws [OtpauthException].
OtpauthUri parseOtpauthUri(String input) {
  final text = input.trim();
  final schemeEnd = text.indexOf(':');
  final scheme = schemeEnd < 0 ? '' : text.substring(0, schemeEnd).toLowerCase();
  if (scheme == 'otpauth-migration') {
    throw const OtpauthException(OtpauthErrorCode.migrationUnsupported, 'Migration exports are not supported');
  }
  if (scheme != 'otpauth') throw const OtpauthException(OtpauthErrorCode.notOtpauth, 'Not an otpauth link');

  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    throw const OtpauthException(OtpauthErrorCode.notOtpauth, 'Malformed otpauth link');
  }
  final type = switch (uri.host.toLowerCase()) {
    'totp' => OtpauthType.totp,
    'hotp' => OtpauthType.hotp,
    _ => throw OtpauthException(OtpauthErrorCode.unsupportedType, 'Unsupported type ${uri.host}'),
  };

  final Map<String, String> query;
  try {
    query = uri.queryParameters;
  } on FormatException {
    throw const OtpauthException(OtpauthErrorCode.notOtpauth, 'Malformed query');
  }
  String? param(String name) {
    final value = query[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final secret = base32Decode(param('secret') ?? '');
  if (secret == null || secret.isEmpty) {
    throw const OtpauthException(OtpauthErrorCode.invalidSecret, 'Missing or invalid secret');
  }

  // The label is "issuer:account" or just "account"; the colon may be percent-encoded.
  final String label;
  try {
    label = Uri.decodeComponent(uri.path.replaceFirst(RegExp('^/'), '')).trim();
  } on FormatException {
    throw const OtpauthException(OtpauthErrorCode.notOtpauth, 'Malformed label');
  } on ArgumentError {
    throw const OtpauthException(OtpauthErrorCode.notOtpauth, 'Malformed label');
  }
  final colon = label.indexOf(':');
  final labelIssuer = colon < 0 ? '' : label.substring(0, colon).trim();
  final account = colon < 0 ? label : label.substring(colon + 1).trim();

  final algorithmText = param('algorithm');
  final algorithm = algorithmText == null ? defaultOtpAlgorithm : OtpAlgorithm.fromLabel(algorithmText);
  if (algorithm == null) throw _unsupported('algorithm $algorithmText');

  final digits = _intParam(param('digits'), defaultOtpDigits);
  if (digits == null || !supportedOtpDigits.contains(digits)) throw _unsupported('digits ${param('digits')}');

  var period = defaultOtpPeriod;
  var counter = 0;
  if (type == OtpauthType.totp) {
    final parsed = _intParam(param('period'), defaultOtpPeriod);
    if (parsed == null || !isValidOtpPeriod(parsed)) throw _unsupported('period ${param('period')}');
    period = parsed;
  } else {
    // Required for hotp by the key URI format; guessing 0 could put the token out of sync.
    final parsed = _intParam(param('counter'), -1);
    if (parsed == null || parsed < 0 || parsed > maxCounter) throw _unsupported('counter ${param('counter')}');
    counter = parsed;
  }

  return OtpauthUri(
    type: type,
    secret: secret,
    issuer: param('issuer') ?? labelIssuer,
    account: account,
    algorithm: algorithm,
    digits: digits,
    period: period,
    counter: counter,
  );
}

int? _intParam(String? value, int fallback) {
  if (value == null) return fallback;
  if (!_digitsOnly.hasMatch(value) || value.length > 16) return null;
  return int.parse(value);
}

OtpauthException _unsupported(String what) =>
    OtpauthException(OtpauthErrorCode.unsupportedParameters, 'Unsupported $what');

/// Name for an imported token, as Google Authenticator shows it: "issuer: account", or whichever
/// of the two is present.
String defaultTokenName(String issuer, String account) => [
  for (final part in [issuer.trim(), account.trim()])
    if (part.isNotEmpty) part,
].join(': ');

/// Whether [text] is meant as an otpauth link rather than a bare secret.
bool looksLikeOtpauthLink(String text) => text.trim().toLowerCase().startsWith('otpauth');

/// A TOTP or HOTP credential as stored: an otpauth link with its own parameters, or a bare Base32
/// secret, which means TOTP with SHA1, 6 digits and 30 seconds. Throws [OtpauthException].
OtpauthUri parseOathCredential(String credential) {
  if (looksLikeOtpauthLink(credential)) return parseOtpauthUri(credential);
  final secret = base32Decode(credential);
  if (secret == null || secret.isEmpty) {
    throw const OtpauthException(OtpauthErrorCode.invalidSecret, 'Not a Base32 secret');
  }
  return OtpauthUri(type: OtpauthType.totp, secret: secret);
}

/// [parseOathCredential], or null if it throws.
OtpauthUri? tryParseOathCredential(String credential) {
  try {
    return parseOathCredential(credential);
  } on OtpauthException {
    return null;
  }
}
