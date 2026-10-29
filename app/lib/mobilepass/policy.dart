import 'activation_code.dart' show checkCharacter;
import 'mobilepass_exception.dart';

enum OtpType { event, time, challenge }

/// A parsed policy string. Only [version], [type], [digits], [timeStep] and [challengeLength] affect
/// code generation.
class OtpPolicy {
  const OtpPolicy({
    required this.version,
    required this.type,
    required this.digits,
    this.timeStep,
    this.challengeLength,
    this.pinLength = 0,
    this.maxAttacks = 0,
    this.pinUseChanges = 0,
    this.attackDelay = 0,
    this.secureMode = false,
    this.transactionSigning = false,
  });

  /// Used when no policy string is set.
  static const defaults = OtpPolicy(version: 1, type: OtpType.event, digits: 6);

  final int version;
  final OtpType type;
  final int digits;

  /// Seconds per code; non-null exactly when [type] is [OtpType.time].
  final int? timeStep;

  /// Digits in a challenge code; non-null exactly when [type] is [OtpType.challenge].
  final int? challengeLength;

  final int pinLength;
  final int maxAttacks;
  final int pinUseChanges;
  final int attackDelay;
  final bool secureMode;
  final bool transactionSigning;
}

const _supportedVersions = {1, 2};
const _knownVersions = {1, 2, 3, 4, 5, 6};

// Field bits per mode, including the 4 mode bits.
const _fieldBitsByMode = {0: 15, 1: 17, 2: 16, 3: 18};

const _pwdLengths = [6, 8];
const _pinLengths = [0, 4, 6, 8];
const _maxAttacks = [0, 3, 6, 10];
const _pinUseChanges = [0, 128, 256, 384];
const _attackDelays = [0, 2, 4, 8];
const _timeSteps = [20, 30, 60];
const _challengeLengths = [6, 8];

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Parses a policy string (decimal digits; surrounding whitespace ignored). An empty string gives
/// [OtpPolicy.defaults]. Throws [MobilePassException] with [MobilePassErrorCode.invalidPolicy],
/// [MobilePassErrorCode.unsupportedPolicyVersion] or [MobilePassErrorCode.unsupportedOtpType].
OtpPolicy parsePolicy(String input) {
  final text = input.trim();
  if (text.isEmpty) return OtpPolicy.defaults;
  final value = _digitsOnly.hasMatch(text) ? int.tryParse(text) : null;
  if (value == null || value <= 0) throw _invalid('not a positive 64-bit integer');

  final bits = value.toRadixString(2);
  // Leading 1, 4 version bits, 4 mode bits, 5 check bits.
  if (bits.length < 14) throw _invalid('too short');
  final body = bits.substring(0, bits.length - 5);
  if (_checkValue(checkCharacter(int.parse(body, radix: 2).toString())) != _read(bits, bits.length - 5, 5)) {
    throw _invalid('check value mismatch');
  }

  final version = _read(bits, 1, 4);
  if (!_knownVersions.contains(version)) throw _invalid('unknown version $version');
  if (!_supportedVersions.contains(version)) {
    throw MobilePassException(MobilePassErrorCode.unsupportedPolicyVersion, 'Unsupported policy version $version');
  }

  final mode = _read(bits, 5, 4);
  switch (mode) {
    case 4:
      return OtpPolicy(version: version, type: OtpType.event, digits: 6);
    case 5:
      return OtpPolicy(version: version, type: OtpType.time, digits: 6, timeStep: 30);
    case 6:
      return OtpPolicy(version: version, type: OtpType.challenge, digits: 8, challengeLength: 8);
  }
  final expectedBits = _fieldBitsByMode[mode];
  if (expectedBits == null) throw _invalid('unknown mode $mode');
  if (body.length - 5 != expectedBits) throw _invalid('field length ${body.length - 5} for mode $mode');
  if (mode == 3) throw _unsupportedType(mode);

  var pos = 9;
  int field(int width) {
    final v = _read(bits, pos, width);
    pos += width;
    return v;
  }

  final digits = _pwdLengths[field(1)];
  final pinLength = _pinLengths[field(2)];
  final maxAttacks = _maxAttacks[field(2)];
  final pinUseChanges = _pinUseChanges[field(2)];
  final attackDelay = _attackDelays[field(2)];
  final secureMode = field(1) == 1;
  final transactionSigning = field(1) == 1;
  int? timeStep;
  if (mode == 1) {
    final index = field(2);
    if (index >= _timeSteps.length) throw _invalid('time step index $index');
    timeStep = _timeSteps[index];
  }
  final challengeLength = mode == 2 ? _challengeLengths[field(1)] : null;
  return OtpPolicy(
    version: version,
    type: switch (mode) {
      1 => OtpType.time,
      2 => OtpType.challenge,
      _ => OtpType.event,
    },
    digits: digits,
    timeStep: timeStep,
    challengeLength: challengeLength,
    pinLength: pinLength,
    maxAttacks: maxAttacks,
    pinUseChanges: pinUseChanges,
    attackDelay: attackDelay,
    secureMode: secureMode,
    transactionSigning: transactionSigning,
  );
}

/// [parsePolicy], or null if it throws.
OtpPolicy? tryParsePolicy(String input) {
  try {
    return parsePolicy(input);
  } on MobilePassException {
    return null;
  }
}

int _read(String bits, int start, int width) => int.parse(bits.substring(start, start + width), radix: 2);

// '2'–'7' are their digit; letters count down from 'Z' = 0, wrapping to 'A' = 31 past 7.
int _checkValue(String char) {
  final code = char.codeUnitAt(0);
  if (code >= 0x32 && code <= 0x37) return code - 0x30;
  final fromZ = 0x5A - code;
  return fromZ > 7 ? 0x60 - code : fromZ;
}

MobilePassException _invalid(String reason) =>
    MobilePassException(MobilePassErrorCode.invalidPolicy, 'Invalid policy: $reason');

MobilePassException _unsupportedType(int mode) =>
    MobilePassException(MobilePassErrorCode.unsupportedOtpType, 'Unsupported OTP type (mode $mode)');
