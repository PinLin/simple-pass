import 'dart:math';

import 'mobilepass_registration.dart';

import '../mobilepass/mobilepass.dart' show timeCounterEpochSeconds;
import '../mobilepass/policy.dart';
import '../otpauth/otpauth_uri.dart';
import '../otpauth/standard_otp.dart';

/// Largest counter the app stores: 2^53 - 1, matching the JS MobilePASS safe-integer limit.
const int maxCounter = 9007199254740991;

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Null unless [input] is plain ASCII digits within `0..maxCounter` (`int.tryParse` alone accepts `0x10`).
int? parseCounterInput(String input) {
  final trimmed = input.trim();
  if (!_digitsOnly.hasMatch(trimmed)) return null;
  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed > maxCounter) return null;
  return parsed;
}

bool isValidCounter(int counter) => counter >= 0 && counter <= maxCounter;

/// PIN length bounds.
const int minPinLength = 4;
const int maxPinLength = 16;

final RegExp _pinPattern = RegExp('^[0-9]{$minPinLength,$maxPinLength}\$');

/// True for an empty PIN or [minPinLength]..[maxPinLength] ASCII digits.
bool isValidPin(String pin) => pin.isEmpty || _pinPattern.hasMatch(pin);

/// Where a profile's OTP key comes from. Kinds other than [activationCode] hold the key itself
/// in [Profile.key], so another key-holding kind only needs its own parameters next to it.
enum ProfileKind {
  /// Key derived from [Profile.activationCode] and [Profile.policy].
  activationCode,

  /// Raw key from an Enrollment String registration; [Profile.policy] is the one the server sent.
  mobilePassKey,

  /// RFC 6238 time-based token (otpauth://totp); [Profile.policy] is unused.
  totp,

  /// RFC 4226 event-based token (otpauth://hotp) driven by [Profile.counter]; [Profile.policy] is unused.
  hotp,
}

/// A single token: its key source, parameters and counter state.
class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.activationCode,
    required this.counter,
    this.kind = ProfileKind.activationCode,
    this.key = '',
    this.serial = '',
    this.registration,
    this.pin = '',
    this.policy = '',
    this.appendPinOnCopy = false,
    this.protected = false,
    this.locked = false,
    this.mobilePassTime = false,
    DateTime? createdAt,
  }) : assert(counter >= 0, 'counter must not be negative'),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;

  /// Empty for kinds that hold [key] instead.
  final String activationCode;

  final ProfileKind kind;

  /// For [ProfileKind.mobilePassKey], Base64 of the raw OTP key; for TOTP and HOTP, the credential as
  /// entered (see [oathCredential]); empty for activation code profiles. As secret as [activationCode].
  final String key;

  /// Token serial number the server assigned; empty for activation code profiles. Not secret.
  final String serial;

  /// Auto-enrollment inputs; absent unless the profile was auto-enrolled, and while locked. Stored with the secrets.
  final MobilePassRegistration? registration;

  bool get holdsKey => kind != ProfileKind.activationCode;

  /// A standard (RFC 4226 / RFC 6238) token rather than a MobilePASS one.
  bool get isStandardOtp => kind == ProfileKind.totp || kind == ProfileKind.hotp;

  /// For standard kinds, [key] is the credential exactly as entered: an otpauth:// link or a Base32
  /// secret. Null while locked, for other kinds, or when it doesn't parse.
  late final OtpauthUri? oathCredential = isStandardOtp && key.isNotEmpty ? tryParseOathCredential(key) : null;

  /// Whether a standard token's stored credential can produce codes; always true for other kinds and
  /// while there's no credential to check (locked).
  bool get hasValidOtpParameters => !isStandardOtp || key.isEmpty || oathCredential != null;

  /// Digits in this profile's codes (6 while a standard token's credential is unknown).
  int get codeDigits => isStandardOtp ? (oathCredential?.digits ?? defaultOtpDigits) : (otpPolicy?.digits ?? 6);

  /// For [ProfileKind.totp]: codes count from 2000-01-01 UTC like MobilePASS time-based tokens, instead of
  /// the Unix epoch. Not secret.
  final bool mobilePassTime;

  /// Unix time a time-based profile's steps are counted from.
  int get timeEpochSeconds => isStandardOtp && !mobilePassTime ? 0 : timeCounterEpochSeconds;

  /// Seconds per code for time-based profiles; null otherwise.
  int? get timeStep => kind == ProfileKind.totp ? oathCredential?.period : (isStandardOtp ? null : otpPolicy?.timeStep);

  /// Whether the stored secret this profile's codes come from is present (it isn't while [locked]).
  bool get hasSecret => holdsKey ? key.isNotEmpty : activationCode.isNotEmpty;

  /// Empty when no PIN is stored. As secret as [activationCode].
  final String pin;

  /// Policy string as entered (trimmed); empty for the default 6-digit event-based token. Not secret.
  final String policy;

  /// Null when [policy] doesn't parse; such a profile must not generate codes.
  late final OtpPolicy? otpPolicy = tryParsePolicy(policy);

  bool get isTimeBased => kind == ProfileKind.totp || (!isStandardOtp && otpPolicy?.type == OtpType.time);

  /// Codes answer a typed challenge code instead of following the counter or the clock.
  bool get isChallengeResponse => !isStandardOtp && otpPolicy?.type == OtpType.challenge;

  /// Whether [counter] drives the codes.
  bool get usesCounter => !isTimeBased && !isChallengeResponse;

  /// When true and [pin] is set, copying a code copies PIN + OTP.
  final bool appendPinOnCopy;

  /// The activation code or key, and the PIN, are sealed with an auth-bound key.
  final bool protected;

  /// [protected] and not unlocked yet: [activationCode], [key] and [pin] are empty
  /// placeholders. Never persisted.
  final bool locked;

  final int counter;
  final DateTime createdAt;

  bool get isAtMaxCounter => counter >= maxCounter;

  Profile copyWith({
    String? name,
    String? activationCode,
    String? key,
    int? counter,
    String? pin,
    String? policy,
    bool? appendPinOnCopy,
    bool? protected,
    bool? locked,
  }) {
    final newCounter = counter ?? this.counter;
    assert(newCounter >= 0, 'counter must not be negative');
    return Profile(
      id: id,
      name: name ?? this.name,
      activationCode: activationCode ?? this.activationCode,
      kind: kind,
      key: key ?? this.key,
      serial: serial,
      registration: registration,
      counter: newCounter,
      pin: pin ?? this.pin,
      policy: policy ?? this.policy,
      appendPinOnCopy: appendPinOnCopy ?? this.appendPinOnCopy,
      protected: protected ?? this.protected,
      locked: locked ?? this.locked,
      mobilePassTime: mobilePassTime,
      createdAt: createdAt,
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final name = json['name'] as String;
    final activationCode = json['activationCode'] as String;
    final kind = _kindFromJson(json['kind']);
    final rawKey = json['key'];
    final key = rawKey is String ? rawKey : '';
    final rawSerial = json['serial'];
    final serial = rawSerial is String ? rawSerial : '';
    final rawRegistration = json['registration'];
    final registration = rawRegistration == null
        ? null
        : MobilePassRegistration.fromJson(Map<String, dynamic>.from(rawRegistration as Map));
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final pin = json['pin'] as String;
    final policy = json['policy'] as String;
    final appendPinOnCopy = json['appendPinOnCopy'] == true;
    final protected = json['protected'] == true;
    final mobilePassTime = json['mobilePassTime'] == true;
    final counter = json['counter'];
    if (counter is! int || !isValidCounter(counter)) throw FormatException('Invalid counter $counter');
    return Profile(
      id: id,
      name: name,
      activationCode: activationCode,
      kind: kind,
      key: key,
      serial: serial,
      registration: registration,
      counter: counter,
      pin: pin,
      policy: policy,
      appendPinOnCopy: appendPinOnCopy,
      protected: protected,
      mobilePassTime: mobilePassTime,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'activationCode': activationCode,
    // Absent for activation code profiles.
    if (holdsKey) ...{'kind': kind.name, 'key': key, 'serial': serial},
    'counter': counter,
    if (registration != null) 'registration': registration!.toJson(),
    'pin': pin,
    'policy': policy,
    'appendPinOnCopy': appendPinOnCopy,
    'protected': protected,
    if (mobilePassTime) 'mobilePassTime': true,
    'createdAt': createdAt.toIso8601String(),
  };
}

// A missing kind is an activation code profile; an unknown one is data from a newer version this one
// can't use, and fails loudly instead of being read as something else.
ProfileKind _kindFromJson(Object? raw) {
  if (raw == null) return ProfileKind.activationCode;
  return ProfileKind.values.firstWhere(
    (k) => k.name == raw,
    orElse: () => throw FormatException('Unknown profile kind $raw'),
  );
}

/// Random 128-bit hex id (collision avoidance only; the activation code is the secret).
String generateProfileId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
