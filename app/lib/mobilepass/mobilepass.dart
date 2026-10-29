import 'dart:typed_data';

import 'activation_code.dart';
import 'hotp.dart';
import 'mobilepass_exception.dart';
import 'ocra.dart';
import 'policy.dart';

export 'activation_code.dart'
    show
        ActivationCodeFormat,
        DecodedActivationCode,
        decodeActivationCode,
        encodeLegacyActivationCode,
        encodeVersionedActivationCode,
        generateActivationSeed,
        isValidActivationCode,
        normalizeActivationCode;
export 'mobilepass_exception.dart';
export 'policy.dart';

/// Start of the time-based counter: 2000-01-01T00:00:00Z.
const int timeCounterEpochSeconds = 946684800;

/// Counter for a time-based code at [unixSeconds] with [timeStep]-second codes.
int timeBasedCounter(int unixSeconds, int timeStep) => (unixSeconds - timeCounterEpochSeconds) ~/ timeStep;

/// OTP for [activationCode] at [counter] under [policy] (empty: 6-digit, no policy in the key);
/// throws [MobilePassException] if any input is invalid.
String generateMobilePassOtp(String activationCode, int counter, {String policy = ''}) {
  final parsed = parsePolicy(policy);
  _checkNotChallenge(parsed);
  return generateKeyOtp(_keyFor(activationCode, parsed, policy), counter, policy: policy);
}

/// Like [generateMobilePassOtp] for a key used as is, as an Enrollment String registration delivers it.
String generateKeyOtp(Uint8List key, int counter, {String policy = ''}) {
  final parsed = parsePolicy(policy);
  _checkNotChallenge(parsed);
  return generateHotp(key, counter, digits: parsed.digits);
}

void _checkNotChallenge(OtpPolicy parsed) {
  if (parsed.type == OtpType.challenge) {
    throw const MobilePassException(MobilePassErrorCode.unsupportedOtpType, 'Policy is challenge-response');
  }
}

/// The key [activationCode]'s codes are computed with under [policy]; throws [MobilePassException] if
/// either is invalid.
Uint8List mobilePassKeyFor(String activationCode, {String policy = ''}) =>
    _keyFor(activationCode, parsePolicy(policy), policy);

Uint8List _keyFor(String activationCode, OtpPolicy parsed, String policy) {
  final seed = activationCodeToKey(activationCode);
  return deriveHotpKey(seed, parsed.version == 1 ? '' : policy.trim());
}

/// Time-based OTP at [unixSeconds]; [policy] must parse to [OtpType.time].
String generateMobilePassTimeOtp(String activationCode, String policy, int unixSeconds) {
  _timeStepOf(policy);
  return generateKeyTimeOtp(_keyFor(activationCode, parsePolicy(policy), policy), policy, unixSeconds);
}

/// Like [generateMobilePassTimeOtp] for a key used as is.
String generateKeyTimeOtp(Uint8List key, String policy, int unixSeconds) =>
    generateKeyOtp(key, timeBasedCounter(unixSeconds, _timeStepOf(policy)), policy: policy);

int _timeStepOf(String policy) {
  final timeStep = parsePolicy(policy).timeStep;
  if (timeStep == null) {
    throw const MobilePassException(MobilePassErrorCode.unsupportedOtpType, 'Policy is not time-based');
  }
  return timeStep;
}

/// True when [challenge] is exactly [length] ASCII digits; leading zeros count.
bool isValidChallenge(String challenge, int length) => RegExp('^[0-9]{$length}\$').hasMatch(challenge);

/// Response to [challenge]; [policy] must parse to [OtpType.challenge] and [challenge] must be
/// exactly its challenge length in digits.
String generateMobilePassChallengeResponse(String activationCode, String policy, String challenge) {
  final parsed = parsePolicy(policy);
  _checkChallenge(parsed, challenge);
  return generateKeyChallengeResponse(_keyFor(activationCode, parsed, policy), policy, challenge);
}

/// Like [generateMobilePassChallengeResponse] for a key used as is.
String generateKeyChallengeResponse(Uint8List key, String policy, String challenge) {
  final parsed = parsePolicy(policy);
  final length = _checkChallenge(parsed, challenge);
  return generateOcra(key, ocraSuite(parsed.digits, length), challenge, digits: parsed.digits);
}

int _checkChallenge(OtpPolicy parsed, String challenge) {
  final length = parsed.challengeLength;
  if (length == null) {
    throw const MobilePassException(MobilePassErrorCode.unsupportedOtpType, 'Policy is not challenge-response');
  }
  if (!isValidChallenge(challenge, length)) {
    throw MobilePassException(MobilePassErrorCode.invalidChallenge, 'Challenge must be $length digits');
  }
  return length;
}
