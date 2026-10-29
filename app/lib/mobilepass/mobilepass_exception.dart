/// Error codes for [MobilePassException].
enum MobilePassErrorCode {
  /// Not a 20-character base32 activation code.
  invalidActivationCode,

  /// Counter passed to the HOTP algorithm is negative.
  invalidCounter,

  /// Policy string is malformed or fails its check value.
  invalidPolicy,

  /// Policy string is well formed but uses a version whose fields are unknown.
  unsupportedPolicyVersion,

  /// Policy string asks for an OTP type this app can't generate, or the wrong type for the call.
  unsupportedOtpType,

  /// Challenge code isn't exactly the policy's number of ASCII digits.
  invalidChallenge,
}

class MobilePassException implements Exception {
  const MobilePassException(this.code, this.message);

  final MobilePassErrorCode code;
  final String message;

  @override
  String toString() => 'MobilePassException: $message';
}
