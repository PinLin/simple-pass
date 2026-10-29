// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SimplePASS';

  @override
  String get profileListEmpty => 'No profiles yet. Tap + to add one.';

  @override
  String profileCounterCompactLabel(int counter) {
    return '#$counter';
  }

  @override
  String get addProfileTooltip => 'Add profile';

  @override
  String get addProfileTitle => 'Add profile';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldNameRequired => 'Name is required';

  @override
  String get fieldActivationCode => 'Activation Code';

  @override
  String get activationCodeHint => 'XXXXX-XXXXX-XXXXX-XXXXX';

  @override
  String get activationCodeRequired => 'Activation Code is required';

  @override
  String get activationCodeInvalid => 'Invalid Activation Code';

  @override
  String get activationCodePolicyMismatch =>
      'This Activation Code\'s format doesn\'t match the Policy String version';

  @override
  String get regenerateActivationCodeTooltip =>
      'Generate a new Activation Code';

  @override
  String get copyActivationCodeTooltip => 'Copy Activation Code';

  @override
  String get copiedActivationCodeMessage => 'Activation Code copied';

  @override
  String get fieldPolicy => 'Policy String';

  @override
  String get fieldPolicyOptional => 'Policy String (optional)';

  @override
  String get policyInvalid => 'Invalid Policy String';

  @override
  String get policyUnsupportedVersion =>
      'This Policy String version isn\'t supported';

  @override
  String get policyUnsupportedOtpType =>
      'This Policy String\'s passcode type isn\'t supported';

  @override
  String codeRefreshCountdown(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'New passcode in $seconds seconds',
      one: 'New passcode in 1 second',
    );
    return '$_temp0';
  }

  @override
  String get fieldCounter => 'Counter';

  @override
  String get counterInvalid => 'Counter must be a non-negative integer';

  @override
  String get saveButton => 'Save';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get markUsedButton => 'Mark as used';

  @override
  String markedUsedMessage(int counter) {
    return 'Marked #$counter as used';
  }

  @override
  String get undoButton => 'Undo';

  @override
  String get undoUnavailableMessage =>
      'Can\'t undo: the counter has changed since.';

  @override
  String get deleteProfileButton => 'Delete';

  @override
  String deleteConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count profiles?',
      one: 'Delete profile?',
    );
    return '$_temp0';
  }

  @override
  String get deleteConfirmButton => 'Delete';

  @override
  String get openSourceLicensesLabel => 'Open-source licenses';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get authNotAvailableMessage =>
      'No fingerprint, face, or PIN is set up on this device.';

  @override
  String get authFailedMessage => 'Authentication failed';

  @override
  String counterTooLarge(int max) {
    return 'Counter cannot exceed $max';
  }

  @override
  String get authCanceledMessage => 'Authentication canceled';

  @override
  String get authLockedOutMessage => 'Too many attempts. Try again later.';

  @override
  String get loadErrorMessage =>
      'Could not read the saved data. Nothing will be changed until it loads successfully.';

  @override
  String get retryButton => 'Retry';

  @override
  String get saveFailedMessage => 'Could not save changes';

  @override
  String get copyCodeAction => 'Copy passcode';

  @override
  String get fieldPin => 'PIN';

  @override
  String pinHint(int min, int max) {
    return 'Optional, $min–$max digits';
  }

  @override
  String pinInvalid(int min, int max) {
    return 'PIN must be $min–$max digits';
  }

  @override
  String get appendPinOnCopyLabel => 'Append PIN when copying';

  @override
  String get appendPinOnCopySubtitle =>
      'Copies the PIN followed by the passcode';

  @override
  String get copiedPinAndCodeMessage => 'PIN + passcode copied';

  @override
  String get copiedCodeMessage => 'Passcode copied';

  @override
  String get clipboardClearLabel => 'Clear clipboard automatically';

  @override
  String get clipboardClearNever => 'Never';

  @override
  String clipboardClearSeconds(int seconds) {
    return '$seconds seconds';
  }

  @override
  String clipboardClearMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get unlockButton => 'Unlock';

  @override
  String get editButton => 'Edit';

  @override
  String get keysInvalidatedMessage =>
      'The phone\'s screen lock was removed, so profiles that require authentication can no longer be unlocked. They can only be deleted.';

  @override
  String get deleteUnrecoverableButton => 'Delete these profiles';

  @override
  String get requireAuthLabel => 'Require authentication to open the app';

  @override
  String get requireAuthSubtitle =>
      'Unlock with fingerprint, face, or screen lock';

  @override
  String get requireAuthWarningMessage =>
      'If the phone\'s screen lock is removed later, protected profiles can no longer be unlocked; they can only be deleted. Keep a separate copy of your Activation Codes and secret keys (or the services\' recovery codes); registered profiles would then need a new Enrollment String.';

  @override
  String get requireAuthConfirmButton => 'Turn on';

  @override
  String get challengeCodeLabel => 'Challenge Code';

  @override
  String challengeCodeHint(int length) {
    return 'Enter $length digits';
  }

  @override
  String get enterChallengeCodeAction => 'Enter Challenge Code';

  @override
  String get okButton => 'OK';

  @override
  String get addKindActivationCodeSubtitle =>
      'Generate or enter an Activation Code';

  @override
  String get addKindEnrollmentString => 'MobilePASS – Auto enrollment';

  @override
  String get addKindEnrollmentStringSubtitle => 'Enter the Enrollment String';

  @override
  String get enrollTitle => 'MobilePASS – Auto enrollment';

  @override
  String get fieldEnrollmentString => 'Enrollment String';

  @override
  String get enrollmentStringRequired => 'Enrollment String is required';

  @override
  String get enrollmentStringInvalid => 'Invalid Enrollment String';

  @override
  String get enrollmentStringNotHttps => 'The enrollment server must use https';

  @override
  String get pasteFromClipboardTooltip => 'Paste from clipboard';

  @override
  String get clipboardEmptyMessage => 'The clipboard has no text';

  @override
  String enrollServerLabel(String host) {
    return 'Registers with $host';
  }

  @override
  String get fieldUserId => 'User ID';

  @override
  String get userIdRequired => 'User ID is required';

  @override
  String get fieldPassphrase => 'Passphrase';

  @override
  String get passphraseRequired => 'Passphrase is required';

  @override
  String get enrollButton => 'Register';

  @override
  String get enrollStepContacting => 'Contacting the server…';

  @override
  String get enrollStepRegistering => 'Registering…';

  @override
  String get otpPinTitle => 'Set OTP PIN';

  @override
  String otpPinMessage(int min, int max) {
    return 'Set a PIN of $min–$max digits.';
  }

  @override
  String otpPinMessageAlphanumeric(int min, int max) {
    return 'Set a PIN of $min–$max letters or digits.';
  }

  @override
  String get otpPinInvalid => 'PIN doesn\'t meet the requirements';

  @override
  String get continueButton => 'Continue';

  @override
  String get enrollErrorNetwork =>
      'Couldn\'t reach the enrollment server. Check the connection and try again.';

  @override
  String enrollErrorHttp(String status) {
    return 'The enrollment server returned HTTP $status.';
  }

  @override
  String get enrollErrorBadResponse =>
      'The server\'s reply isn\'t a valid enrollment response.';

  @override
  String enrollErrorRejected(String status) {
    return 'The server refused the registration ($status). Check the user ID and passphrase, or ask for a new Enrollment String.';
  }

  @override
  String get enrollErrorMac =>
      'The server\'s key confirmation failed. Nothing was saved.';

  @override
  String get enrollErrorPolicy =>
      'The server sent a Policy String this app doesn\'t support. The server may already have completed the registration; ask your administrator for a new Enrollment String.';

  @override
  String get enrollSaveFailedMessage =>
      'Registered, but the profile couldn\'t be saved. Tap Save to try again.';

  @override
  String get fieldSerial => 'Serial number';

  @override
  String get profileKeyInvalid => 'Invalid stored key';

  @override
  String get enrollErrorCertificate =>
      'Couldn\'t verify the enrollment server\'s certificate.';

  @override
  String get addKindTotpSubtitle => 'Scan a QR code or enter the secret key';

  @override
  String get fieldSecret => 'Secret key';

  @override
  String get secretRequired => 'Secret key is required';

  @override
  String get secretInvalid => 'Not a valid Base32 secret key';

  @override
  String get copiedSecretMessage => 'Secret key copied';

  @override
  String get scanQrButton => 'Scan QR code';

  @override
  String get importQrPhotoButton => 'From photo';

  @override
  String get scanQrTitle => 'Scan QR code';

  @override
  String get cameraUnavailableMessage =>
      'The camera couldn\'t be started. Use \"From photo\" or enter the secret key by hand.';

  @override
  String get cameraPermissionDeniedMessage =>
      'Scanning needs camera access. You can still enter the secret key by hand.';

  @override
  String get cameraPermissionBlockedMessage =>
      'Camera access is turned off for SimplePASS. Turn it on in system settings to scan, or enter the secret key by hand.';

  @override
  String get openSettingsButton => 'Open settings';

  @override
  String get qrNotFoundMessage => 'No QR code found in that photo';

  @override
  String get otpauthImportedMessage => 'Filled in from the link';

  @override
  String get otpauthNotLinkMessage => 'Not an otpauth:// link';

  @override
  String get otpauthMigrationMessage =>
      'Google Authenticator export codes (otpauth-migration://) aren\'t supported. Use each account\'s own QR code instead.';

  @override
  String get otpauthUnsupportedTypeMessage =>
      'Only TOTP and HOTP links are supported';

  @override
  String get otpauthInvalidSecretMessage =>
      'The link\'s secret is missing or invalid';

  @override
  String get otpauthUnsupportedParametersMessage =>
      'The link uses an algorithm, digit count, period or counter this app doesn\'t support';

  @override
  String get cameraNotFoundMessage =>
      'No camera this app can use was found. Use \"From photo\" or enter the secret key by hand.';

  @override
  String get scanBackButton => 'Back';

  @override
  String get addKindActivationCode => 'MobilePASS – Manual enrollment';

  @override
  String get otpauthEnrollmentStringMessage =>
      'This is an Enrollment String. Add it with \"MobilePASS – Auto enrollment\" instead.';

  @override
  String get tapToRevealLabel => 'Tap to reveal passcodes';

  @override
  String get tapToRevealSubtitle =>
      'Passcodes are masked with dots; tap a profile to reveal them';

  @override
  String get revealCodeAction => 'Show and copy passcode';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get selectAction => 'Select';

  @override
  String deleteSelectedConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This permanently deletes $count profiles.',
      one: 'This permanently deletes 1 profile.',
    );
    return '$_temp0';
  }

  @override
  String get deselectAction => 'Deselect';

  @override
  String get parameterTimeBased => 'Time-based';

  @override
  String get parameterCounterBased => 'Counter-based';

  @override
  String parameterDigits(int digits) {
    return '$digits digits';
  }

  @override
  String get protectedProfilesBanner =>
      'Authentication is off, but some profiles are still protected.';

  @override
  String get unprotectNowButton => 'Remove protection';

  @override
  String get appLockedMessage => 'SimplePASS is locked';

  @override
  String get allowScreenshotsLockNote =>
      'With the app lock on, Android 12 and older always block screenshots, so the recent apps screen can\'t show your profiles.';

  @override
  String get blockScreenshotsLabel => 'Block screenshots';

  @override
  String get blockScreenshotsSubtitle =>
      'Prevent other apps from capturing the screen';

  @override
  String get showSecretTooltip => 'Show';

  @override
  String get hideSecretTooltip => 'Hide';

  @override
  String challengeCodeSemanticsLabel(String code) {
    return 'Challenge Code $code';
  }

  @override
  String get unsavedChangesTitle => 'Unsaved changes';

  @override
  String get discardButton => 'Discard';

  @override
  String get keepEditingButton => 'Keep editing';

  @override
  String get typeStandardTotp => 'TOTP';

  @override
  String get typeStandardHotp => 'HOTP';

  @override
  String get typeChallengeResponse => 'Challenge-response';

  @override
  String get notSetValue => 'Not set';

  @override
  String get copiedEquivalentLinkMessage => 'Link copied';

  @override
  String get copyOtpauthLinkButton => 'Copy otpauth link';

  @override
  String get moreOptionsTooltip => 'More options';

  @override
  String get copiedFieldMessage => 'Copied';

  @override
  String get copyFieldTooltip => 'Copy';

  @override
  String get otpChallengeLengthLabel => 'Challenge Code length';

  @override
  String get otpTypeLabel => 'OTP type';

  @override
  String get otpDigitsLabel => 'Code length';

  @override
  String get otpAlgorithmLabel => 'Algorithm';

  @override
  String get otpPeriodLabel => 'Period (seconds)';

  @override
  String get otpPeriodInvalid => 'Enter a period from 1 to 3600 seconds';

  @override
  String get deleteProfileMessage =>
      'Delete this profile from this phone? This does not remove the authenticator from the service.';

  @override
  String profileDetailsTitle(String type, String spacing) {
    return '$type profile';
  }

  @override
  String get openCameraButton => 'Open camera';

  @override
  String get addKindTotpMenuTitle => 'Add manually';

  @override
  String get mobilePassFormatLabel => 'Use MobilePASS format';

  @override
  String get registrationInfoMenuItem => 'MobilePASS registration info';

  @override
  String get mobilePassFormatLine => 'MobilePASS format';

  @override
  String get addTotpScreenTitle => 'Add manually';
}
