import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../platform/keystore.dart';
import '../l10n/gen/app_localizations.dart';
import '../mobilepass/mobilepass.dart';
import '../models/profile.dart';
import '../models/settings.dart';
import '../otpauth/base32.dart';
import '../otpauth/standard_otp.dart';
import '../platform/sensitive_clipboard.dart';
import '../storage/profile_store.dart';
import '../storage/settings_store.dart';
import 'app_snack_bar.dart';

/// Null when stored data can't produce a code, so the screen can still offer edit and delete, or while
/// [clockBeforeEpoch]. Time-based profiles use [now] and ignore the counter.
String? otpForProfile(Profile profile, {DateTime? now}) {
  now ??= DateTime.now();
  // Before the epoch there's no step to count; integer division would round up to step 0.
  if (clockBeforeEpoch(profile, now)) return null;
  try {
    if (profile.isStandardOtp) return _standardOtp(profile, now);
    final key = profile.holdsKey ? _storedKey(profile) : null;
    if (profile.isTimeBased) {
      final seconds = now.millisecondsSinceEpoch ~/ 1000;
      return key != null
          ? generateKeyTimeOtp(key, profile.policy, seconds)
          : generateMobilePassTimeOtp(profile.activationCode, profile.policy, seconds);
    }
    return key != null
        ? generateKeyOtp(key, profile.counter, policy: profile.policy)
        : generateMobilePassOtp(profile.activationCode, profile.counter, policy: profile.policy);
  } on MobilePassException {
    return null;
  }
}

// HOTP counts from the profile's own counter: the link's counter is only where it started.
String? _standardOtp(Profile profile, DateTime now) {
  final credential = profile.oathCredential;
  if (credential == null) return null;
  if (profile.isTimeBased) {
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    return generateStandardTotp(
      credential.secret,
      seconds,
      algorithm: credential.algorithm,
      digits: credential.digits,
      period: credential.period,
      epochSeconds: profile.timeEpochSeconds,
    );
  }
  return generateStandardHotp(
    credential.secret,
    profile.counter,
    algorithm: credential.algorithm,
    digits: credential.digits,
  );
}

/// Whether [now] is before the epoch a time-based [profile] counts its steps from (a clock not set yet,
/// still at 1970): there's no code yet, but nothing is wrong with the profile either.
bool clockBeforeEpoch(Profile profile, DateTime now) =>
    profile.isTimeBased && now.millisecondsSinceEpoch ~/ 1000 < profile.timeEpochSeconds;

// An empty or undecodable key can't produce codes, like a bad activation code.
Uint8List _storedKey(Profile profile) {
  try {
    final key = base64.decode(profile.key);
    if (key.isNotEmpty) return key;
  } on FormatException {
    // Reported below.
  }
  throw const MobilePassException(MobilePassErrorCode.invalidActivationCode, 'No usable key');
}

/// Response to [challenge] for a challenge-response [profile]; null until [challenge] has exactly the
/// policy's number of digits, or when stored data can't produce a code.
String? challengeResponseForProfile(Profile profile, String challenge) {
  try {
    return profile.holdsKey
        ? generateKeyChallengeResponse(_storedKey(profile), profile.policy, challenge)
        : generateMobilePassChallengeResponse(profile.activationCode, profile.policy, challenge);
  } on MobilePassException {
    return null;
  }
}

/// Seconds until a time-based code with [timeStep]-second codes counted from [epochSeconds] changes at [now].
int secondsUntilNextCode(DateTime now, int timeStep, {int epochSeconds = timeCounterEpochSeconds}) {
  final seconds = now.millisecondsSinceEpoch ~/ 1000;
  return timeStep - (seconds - epochSeconds) % timeStep;
}

/// [secondsUntilNextCode] for a time-based [profile].
int secondsUntilProfileCode(Profile profile, DateTime now) =>
    secondsUntilNextCode(now, profile.timeStep!, epochSeconds: profile.timeEpochSeconds);

/// Splits a 6- or 8-digit OTP in half ("246 805", "2468 0513"); other input is returned unchanged.
String formatOtpForDisplay(String otp) {
  if (otp.length != 6 && otp.length != 8) return otp;
  final half = otp.length ~/ 2;
  return '${otp.substring(0, half)} ${otp.substring(half)}';
}

/// What a mark-as-used attempt did to the stored profile.
class MarkUsedOutcome {
  const MarkUsedOutcome({required this.profile, required this.marked});

  final Profile? profile;

  /// False when the guards refused (stale row or max counter).
  final bool marked;
}

/// Consumes [shownCounter] (the one the user saw) against the latest stored
/// profile, so a stale view can't burn the wrong counter.
Future<MarkUsedOutcome> markCounterUsed(ProfileStore store, String profileId, int shownCounter) async {
  var marked = false;
  final updated = await store.updateProfile(profileId, (p) {
    if (p.counter != shownCounter || p.isAtMaxCounter) return p;
    marked = true;
    return p.copyWith(counter: p.counter + 1);
  });
  return MarkUsedOutcome(profile: updated, marked: marked);
}

/// Puts the counter back to [counter] only while the stored counter is still counter + 1.
Future<({Profile? profile, bool restored})> undoMarkCounterUsed(
  ProfileStore store,
  String profileId,
  int counter,
) async {
  var restored = false;
  final updated = await store.updateProfile(profileId, (p) {
    if (p.counter != counter + 1) return p;
    restored = true;
    return p.copyWith(counter: counter);
  });
  return (profile: updated, restored: restored);
}

/// Shows "Marked #N as used" with Undo. Messenger and strings are captured up front, so
/// [onUpdated] and [onSaveFailed] must guard on `mounted`. Undo neither runs nor reports once
/// [active] turns false (the app relocked).
void showMarkedUsedSnackBar(
  BuildContext context, {
  required ProfileStore store,
  required String profileId,
  required int counter,
  required bool Function() active,
  required void Function(Profile updated) onUpdated,
  required VoidCallback onSaveFailed,
}) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  Future<void> undo() async {
    if (!active()) return;
    try {
      final result = await undoMarkCounterUsed(store, profileId, counter);
      if (!active()) return;
      final updated = result.profile;
      if (updated != null) onUpdated(updated);
      if (!result.restored) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(appSnackBar(messenger, l10n.undoUnavailableMessage));
      }
    } catch (_) {
      if (!active()) return;
      messenger.showSnackBar(appSnackBar(messenger, l10n.saveFailedMessage));
      onSaveFailed();
    }
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      appSnackBar(
        messenger,
        l10n.markedUsedMessage(counter),
        action: SnackBarAction(label: l10n.undoButton, onPressed: undo),
      ),
    );
}

/// What copying [otp] for [profile] puts on the clipboard: PIN + OTP when
/// the profile asks for it and has a PIN, otherwise just the OTP.
bool copiesPin(Profile profile) => profile.appendPinOnCopy && profile.pin.isNotEmpty;

String clipboardTextFor(Profile profile, String otp) => copiesPin(profile) ? '${profile.pin}$otp' : otp;

/// Copies [otp] (with the PIN if configured) as sensitive, clears it after
/// the delay from Settings, and confirms with a short snackbar.
Future<void> copyCodeWithSnackBar(BuildContext context, SettingsStore settingsStore, Profile profile, String otp) {
  final l10n = AppLocalizations.of(context);
  return copySensitiveWithSnackBar(
    context,
    settingsStore,
    clipboardTextFor(profile, otp),
    copiesPin(profile) ? l10n.copiedPinAndCodeMessage : l10n.copiedCodeMessage,
  );
}

/// Copies [text] as sensitive, clears it after the delay from Settings, and shows [message] briefly.
Future<void> copySensitiveWithSnackBar(
  BuildContext context,
  SettingsStore settingsStore,
  String text,
  String message,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var clear = const Settings().clipboardClear;
  try {
    clear = (await settingsStore.load()).clipboardClear;
  } catch (_) {}
  await SensitiveClipboard.instance.copy(text, clearAfter: clear.delay);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(messenger, message, duration: const Duration(seconds: 2)));
}

/// Validation message for counter text typed by the user, or null if
/// [parseCounterInput] accepts it.
String? counterInputError(AppLocalizations l10n, String value) {
  if (parseCounterInput(value) != null) return null;
  final trimmed = value.trim();
  // All digits but still rejected means it's above the limit.
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return l10n.counterTooLarge(maxCounter);
  return l10n.counterInvalid;
}

/// Validation message for a typed PIN, or null if [isValidPin] accepts it.
String? pinInputError(AppLocalizations l10n, String value) =>
    isValidPin(value) ? null : l10n.pinInvalid(minPinLength, maxPinLength);

/// Validation message for a typed activation code, or null if it passes its check characters.
String? activationCodeInputError(AppLocalizations l10n, String value) {
  if (value.trim().isEmpty) return l10n.activationCodeRequired;
  if (!isValidActivationCode(value)) return l10n.activationCodeInvalid;
  return null;
}

/// Validation message for a typed policy string, or null if it's empty or supported.
String? policyInputError(AppLocalizations l10n, String value) {
  try {
    parsePolicy(value);
    return null;
  } on MobilePassException catch (e) {
    return switch (e.code) {
      MobilePassErrorCode.unsupportedPolicyVersion => l10n.policyUnsupportedVersion,
      MobilePassErrorCode.unsupportedOtpType => l10n.policyUnsupportedOtpType,
      _ => l10n.policyInvalid,
    };
  }
}

/// True when [code]'s format doesn't match [policy]'s version: a legacy code with a version-2
/// policy, or a versioned code whose embedded version differs.
bool activationCodeMismatchesPolicy(String code, String policy) {
  final decoded = decodeActivationCode(code);
  final parsed = tryParsePolicy(policy);
  if (decoded == null || parsed == null) return false;
  return switch (decoded.format) {
    ActivationCodeFormat.legacy => parsed.version != 1,
    ActivationCodeFormat.versioned => decoded.version != parsed.version,
  };
}

/// A MobilePASS profile's own key: worked out from the Activation Code, or the registered one; null
/// for standard tokens or data that can't produce codes.
Uint8List? mobilePassKeyOf(Profile profile) {
  if (profile.isStandardOtp) return null;
  try {
    final key = profile.holdsKey
        ? base64.decode(profile.key)
        : mobilePassKeyFor(profile.activationCode, policy: profile.policy);
    return key.isEmpty ? null : key;
  } on FormatException {
    return null;
  } on MobilePassException {
    return null;
  }
}

/// For an event-based MobilePASS profile, an `otpauth://hotp` link standard HOTP apps that support
/// SHA-256 compute the same codes from (they're RFC 4226 over HMAC-SHA256), starting at [counter];
/// null for other kinds. Time-based MobilePASS codes count from 2000, which no link can express.
String? equivalentHotpLink(Profile profile, {required String name, required int counter}) {
  if (profile.isStandardOtp || !profile.usesCounter) return null;
  final key = mobilePassKeyOf(profile);
  final digits = profile.otpPolicy?.digits;
  if (key == null || digits == null || !isValidCounter(counter)) return null;
  return 'otpauth://hotp/${Uri.encodeComponent(name)}?secret=${base32Encode(key)}'
      '&algorithm=SHA256&digits=$digits&counter=$counter';
}

/// An export link using the current form's name and counter, without changing the original credential.
String? equivalentOtpLink(Profile profile, {required String name, required int counter}) {
  if (!profile.isStandardOtp) {
    return equivalentHotpLink(profile, name: name, counter: counter);
  }
  final credential = profile.oathCredential;
  // A link can't say the steps count from 2000.
  if (profile.mobilePassTime) return null;
  if (credential == null || (profile.usesCounter && !isValidCounter(counter))) {
    return null;
  }
  final type = profile.isTimeBased ? 'totp' : 'hotp';
  final query = <String, String>{
    'secret': base32Encode(credential.secret),
    'algorithm': credential.algorithm.label,
    'digits': '${credential.digits}',
    if (credential.issuer.isNotEmpty) 'issuer': credential.issuer,
    if (profile.isTimeBased) 'period': '${credential.period}' else 'counter': '$counter',
  };
  return 'otpauth://$type/${Uri.encodeComponent(name)}?${Uri(queryParameters: query).query}';
}

/// What kind of code [profile] makes, by algorithm rather than by how it was added.
String profileTypeLabel(AppLocalizations l10n, Profile profile) => switch (profile.kind) {
  ProfileKind.totp => l10n.typeStandardTotp,
  ProfileKind.hotp => l10n.typeStandardHotp,
  _ => switch (profile.otpPolicy?.type) {
    OtpType.time => l10n.typeStandardTotp,
    OtpType.challenge => l10n.typeChallengeResponse,
    _ => l10n.typeStandardHotp,
  },
};

/// Value text of a read-only field: a step below secondary text so it reads as not editable.
Color readOnlyValueColor(ColorScheme scheme) => scheme.onSurfaceVariant.withValues(alpha: 0.6);

/// The app-wide protection a new profile follows. Settings that can't be read count as on, so a
/// failure never leaves a secret in the clear.
Future<bool> requireAuthSetting(SettingsStore? settingsStore) async {
  if (settingsStore == null) return false;
  try {
    return (await settingsStore.load()).requireAuth ?? false;
  } catch (_) {
    return true;
  }
}

/// Whether the app lock applies: switched on, or something is still sealed (a switch-off that didn't
/// finish), which only an authentication can open.
bool appLockActive({required bool? requireAuth, required bool anySealed}) => requireAuth == true || anySealed;

/// Whether the window must be FLAG_SECURE: screenshots are off, or the app lock is on where Android
/// can't keep the app out of the recents thumbnails (before 13, API 33; unknown counts as older).
bool secureWindow({required bool allowScreenshots, required bool appLock, required int? sdkInt}) =>
    !allowScreenshots || (appLock && (sdkInt == null || sdkInt < 33));

enum UnsavedChoice { discard, keepEditing }

/// Asks before leaving a form with unsaved edits; dismissing it keeps editing.
Future<UnsavedChoice> askAboutUnsavedChanges(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final choice = await showDialog<UnsavedChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.unsavedChangesTitle),
      actions: [
        TextButton(
          key: const ValueKey('discardChangesButton'),
          onPressed: () => Navigator.of(dialogContext).pop(UnsavedChoice.discard),
          child: Text(l10n.discardButton),
        ),
        FilledButton(
          key: const ValueKey('keepEditingButton'),
          onPressed: () => Navigator.of(dialogContext).pop(UnsavedChoice.keepEditing),
          child: Text(l10n.keepEditingButton),
        ),
      ],
    ),
  );
  return choice ?? UnsavedChoice.keepEditing;
}

/// Message for a gate result other than success, or null on success.
String? authResultMessage(AppLocalizations l10n, AuthResult result) => switch (result) {
  AuthResult.success => null,
  AuthResult.canceled => l10n.authCanceledMessage,
  AuthResult.noCredentials => l10n.authNotAvailableMessage,
  AuthResult.lockedOut => l10n.authLockedOutMessage,
  AuthResult.failed => l10n.authFailedMessage,
};

/// After [KeyInvalidatedException]: explains, and deletes the profiles that can
/// no longer be unlocked only if the user chooses to; true when it did.
Future<bool> offerToDeleteUnrecoverable(BuildContext context, ProfileStore store) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final delete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(l10n.keysInvalidatedMessage),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.cancelButton)),
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.deleteUnrecoverableButton)),
      ],
    ),
  );
  if (delete != true) return false;
  try {
    await store.deleteUnrecoverable();
    return true;
  } catch (_) {
    messenger.showSnackBar(appSnackBar(messenger, l10n.saveFailedMessage));
    return false;
  }
}
