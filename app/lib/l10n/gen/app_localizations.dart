import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SimplePASS'**
  String get appTitle;

  /// No description provided for @profileListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No profiles yet. Tap + to add one.'**
  String get profileListEmpty;

  /// No description provided for @profileCounterCompactLabel.
  ///
  /// In en, this message translates to:
  /// **'#{counter}'**
  String profileCounterCompactLabel(int counter);

  /// No description provided for @addProfileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get addProfileTooltip;

  /// No description provided for @addProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get addProfileTitle;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get fieldNameRequired;

  /// No description provided for @fieldActivationCode.
  ///
  /// In en, this message translates to:
  /// **'Activation Code'**
  String get fieldActivationCode;

  /// No description provided for @activationCodeHint.
  ///
  /// In en, this message translates to:
  /// **'XXXXX-XXXXX-XXXXX-XXXXX'**
  String get activationCodeHint;

  /// No description provided for @activationCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Activation Code is required'**
  String get activationCodeRequired;

  /// No description provided for @activationCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid Activation Code'**
  String get activationCodeInvalid;

  /// No description provided for @activationCodePolicyMismatch.
  ///
  /// In en, this message translates to:
  /// **'This Activation Code\'s format doesn\'t match the Policy String version'**
  String get activationCodePolicyMismatch;

  /// No description provided for @regenerateActivationCodeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Generate a new Activation Code'**
  String get regenerateActivationCodeTooltip;

  /// No description provided for @copyActivationCodeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy Activation Code'**
  String get copyActivationCodeTooltip;

  /// No description provided for @copiedActivationCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'Activation Code copied'**
  String get copiedActivationCodeMessage;

  /// No description provided for @fieldPolicy.
  ///
  /// In en, this message translates to:
  /// **'Policy String'**
  String get fieldPolicy;

  /// No description provided for @fieldPolicyOptional.
  ///
  /// In en, this message translates to:
  /// **'Policy String (optional)'**
  String get fieldPolicyOptional;

  /// No description provided for @policyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid Policy String'**
  String get policyInvalid;

  /// No description provided for @policyUnsupportedVersion.
  ///
  /// In en, this message translates to:
  /// **'This Policy String version isn\'t supported'**
  String get policyUnsupportedVersion;

  /// No description provided for @policyUnsupportedOtpType.
  ///
  /// In en, this message translates to:
  /// **'This Policy String\'s passcode type isn\'t supported'**
  String get policyUnsupportedOtpType;

  /// No description provided for @codeRefreshCountdown.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{New passcode in 1 second} other{New passcode in {seconds} seconds}}'**
  String codeRefreshCountdown(int seconds);

  /// No description provided for @fieldCounter.
  ///
  /// In en, this message translates to:
  /// **'Counter'**
  String get fieldCounter;

  /// No description provided for @counterInvalid.
  ///
  /// In en, this message translates to:
  /// **'Counter must be a non-negative integer'**
  String get counterInvalid;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @markUsedButton.
  ///
  /// In en, this message translates to:
  /// **'Mark as used'**
  String get markUsedButton;

  /// No description provided for @markedUsedMessage.
  ///
  /// In en, this message translates to:
  /// **'Marked #{counter} as used'**
  String markedUsedMessage(int counter);

  /// No description provided for @undoButton.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoButton;

  /// No description provided for @undoUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Can\'t undo: the counter has changed since.'**
  String get undoUnavailableMessage;

  /// No description provided for @deleteProfileButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteProfileButton;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete profile?} other{Delete {count} profiles?}}'**
  String deleteConfirmTitle(int count);

  /// No description provided for @deleteConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteConfirmButton;

  /// No description provided for @openSourceLicensesLabel.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get openSourceLicensesLabel;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @authNotAvailableMessage.
  ///
  /// In en, this message translates to:
  /// **'No fingerprint, face, or PIN is set up on this device.'**
  String get authNotAvailableMessage;

  /// No description provided for @authFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed'**
  String get authFailedMessage;

  /// No description provided for @counterTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Counter cannot exceed {max}'**
  String counterTooLarge(int max);

  /// No description provided for @authCanceledMessage.
  ///
  /// In en, this message translates to:
  /// **'Authentication canceled'**
  String get authCanceledMessage;

  /// No description provided for @authLockedOutMessage.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again later.'**
  String get authLockedOutMessage;

  /// No description provided for @loadErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not read the saved data. Nothing will be changed until it loads successfully.'**
  String get loadErrorMessage;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @saveFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not save changes'**
  String get saveFailedMessage;

  /// No description provided for @copyCodeAction.
  ///
  /// In en, this message translates to:
  /// **'Copy passcode'**
  String get copyCodeAction;

  /// No description provided for @fieldPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get fieldPin;

  /// No description provided for @pinHint.
  ///
  /// In en, this message translates to:
  /// **'Optional, {min}–{max} digits'**
  String pinHint(int min, int max);

  /// No description provided for @pinInvalid.
  ///
  /// In en, this message translates to:
  /// **'PIN must be {min}–{max} digits'**
  String pinInvalid(int min, int max);

  /// No description provided for @appendPinOnCopyLabel.
  ///
  /// In en, this message translates to:
  /// **'Append PIN when copying'**
  String get appendPinOnCopyLabel;

  /// No description provided for @appendPinOnCopySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Copies the PIN followed by the passcode'**
  String get appendPinOnCopySubtitle;

  /// No description provided for @copiedPinAndCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'PIN + passcode copied'**
  String get copiedPinAndCodeMessage;

  /// No description provided for @copiedCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'Passcode copied'**
  String get copiedCodeMessage;

  /// No description provided for @clipboardClearLabel.
  ///
  /// In en, this message translates to:
  /// **'Clear clipboard automatically'**
  String get clipboardClearLabel;

  /// No description provided for @clipboardClearNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get clipboardClearNever;

  /// No description provided for @clipboardClearSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds'**
  String clipboardClearSeconds(int seconds);

  /// No description provided for @clipboardClearMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute} other{{minutes} minutes}}'**
  String clipboardClearMinutes(int minutes);

  /// No description provided for @unlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// No description provided for @editButton.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editButton;

  /// No description provided for @keysInvalidatedMessage.
  ///
  /// In en, this message translates to:
  /// **'The phone\'s screen lock was removed, so profiles that require authentication can no longer be unlocked. They can only be deleted.'**
  String get keysInvalidatedMessage;

  /// No description provided for @deleteUnrecoverableButton.
  ///
  /// In en, this message translates to:
  /// **'Delete these profiles'**
  String get deleteUnrecoverableButton;

  /// No description provided for @requireAuthLabel.
  ///
  /// In en, this message translates to:
  /// **'Require authentication to open the app'**
  String get requireAuthLabel;

  /// No description provided for @requireAuthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock with fingerprint, face, or screen lock'**
  String get requireAuthSubtitle;

  /// No description provided for @requireAuthWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'If the phone\'s screen lock is removed later, protected profiles can no longer be unlocked; they can only be deleted. Keep a separate copy of your Activation Codes and secret keys (or the services\' recovery codes); registered profiles would then need a new Enrollment String.'**
  String get requireAuthWarningMessage;

  /// No description provided for @requireAuthConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get requireAuthConfirmButton;

  /// No description provided for @challengeCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Challenge Code'**
  String get challengeCodeLabel;

  /// No description provided for @challengeCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter {length} digits'**
  String challengeCodeHint(int length);

  /// No description provided for @enterChallengeCodeAction.
  ///
  /// In en, this message translates to:
  /// **'Enter Challenge Code'**
  String get enterChallengeCodeAction;

  /// No description provided for @okButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButton;

  /// No description provided for @addKindActivationCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generate or enter an Activation Code'**
  String get addKindActivationCodeSubtitle;

  /// No description provided for @addKindEnrollmentString.
  ///
  /// In en, this message translates to:
  /// **'MobilePASS – Auto enrollment'**
  String get addKindEnrollmentString;

  /// No description provided for @addKindEnrollmentStringSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the Enrollment String'**
  String get addKindEnrollmentStringSubtitle;

  /// No description provided for @enrollTitle.
  ///
  /// In en, this message translates to:
  /// **'MobilePASS – Auto enrollment'**
  String get enrollTitle;

  /// No description provided for @fieldEnrollmentString.
  ///
  /// In en, this message translates to:
  /// **'Enrollment String'**
  String get fieldEnrollmentString;

  /// No description provided for @enrollmentStringRequired.
  ///
  /// In en, this message translates to:
  /// **'Enrollment String is required'**
  String get enrollmentStringRequired;

  /// No description provided for @enrollmentStringInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid Enrollment String'**
  String get enrollmentStringInvalid;

  /// No description provided for @enrollmentStringNotHttps.
  ///
  /// In en, this message translates to:
  /// **'The enrollment server must use https'**
  String get enrollmentStringNotHttps;

  /// No description provided for @pasteFromClipboardTooltip.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get pasteFromClipboardTooltip;

  /// No description provided for @clipboardEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'The clipboard has no text'**
  String get clipboardEmptyMessage;

  /// No description provided for @enrollServerLabel.
  ///
  /// In en, this message translates to:
  /// **'Registers with {host}'**
  String enrollServerLabel(String host);

  /// No description provided for @fieldUserId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get fieldUserId;

  /// No description provided for @userIdRequired.
  ///
  /// In en, this message translates to:
  /// **'User ID is required'**
  String get userIdRequired;

  /// No description provided for @fieldPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get fieldPassphrase;

  /// No description provided for @passphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'Passphrase is required'**
  String get passphraseRequired;

  /// No description provided for @enrollButton.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get enrollButton;

  /// No description provided for @enrollStepContacting.
  ///
  /// In en, this message translates to:
  /// **'Contacting the server…'**
  String get enrollStepContacting;

  /// No description provided for @enrollStepRegistering.
  ///
  /// In en, this message translates to:
  /// **'Registering…'**
  String get enrollStepRegistering;

  /// No description provided for @otpPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Set OTP PIN'**
  String get otpPinTitle;

  /// No description provided for @otpPinMessage.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN of {min}–{max} digits.'**
  String otpPinMessage(int min, int max);

  /// No description provided for @otpPinMessageAlphanumeric.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN of {min}–{max} letters or digits.'**
  String otpPinMessageAlphanumeric(int min, int max);

  /// No description provided for @otpPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'PIN doesn\'t meet the requirements'**
  String get otpPinInvalid;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @enrollErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the enrollment server. Check the connection and try again.'**
  String get enrollErrorNetwork;

  /// No description provided for @enrollErrorHttp.
  ///
  /// In en, this message translates to:
  /// **'The enrollment server returned HTTP {status}.'**
  String enrollErrorHttp(String status);

  /// No description provided for @enrollErrorBadResponse.
  ///
  /// In en, this message translates to:
  /// **'The server\'s reply isn\'t a valid enrollment response.'**
  String get enrollErrorBadResponse;

  /// No description provided for @enrollErrorRejected.
  ///
  /// In en, this message translates to:
  /// **'The server refused the registration ({status}). Check the user ID and passphrase, or ask for a new Enrollment String.'**
  String enrollErrorRejected(String status);

  /// No description provided for @enrollErrorMac.
  ///
  /// In en, this message translates to:
  /// **'The server\'s key confirmation failed. Nothing was saved.'**
  String get enrollErrorMac;

  /// No description provided for @enrollErrorPolicy.
  ///
  /// In en, this message translates to:
  /// **'The server sent a Policy String this app doesn\'t support. The server may already have completed the registration; ask your administrator for a new Enrollment String.'**
  String get enrollErrorPolicy;

  /// No description provided for @enrollSaveFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Registered, but the profile couldn\'t be saved. Tap Save to try again.'**
  String get enrollSaveFailedMessage;

  /// No description provided for @fieldSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial number'**
  String get fieldSerial;

  /// No description provided for @profileKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid stored key'**
  String get profileKeyInvalid;

  /// No description provided for @enrollErrorCertificate.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the enrollment server\'s certificate.'**
  String get enrollErrorCertificate;

  /// No description provided for @addKindTotpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a QR code or enter the secret key'**
  String get addKindTotpSubtitle;

  /// No description provided for @fieldSecret.
  ///
  /// In en, this message translates to:
  /// **'Secret key'**
  String get fieldSecret;

  /// No description provided for @secretRequired.
  ///
  /// In en, this message translates to:
  /// **'Secret key is required'**
  String get secretRequired;

  /// No description provided for @secretInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a valid Base32 secret key'**
  String get secretInvalid;

  /// No description provided for @copiedSecretMessage.
  ///
  /// In en, this message translates to:
  /// **'Secret key copied'**
  String get copiedSecretMessage;

  /// No description provided for @scanQrButton.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrButton;

  /// No description provided for @importQrPhotoButton.
  ///
  /// In en, this message translates to:
  /// **'From photo'**
  String get importQrPhotoButton;

  /// No description provided for @scanQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrTitle;

  /// No description provided for @cameraUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'The camera couldn\'t be started. Use \"From photo\" or enter the secret key by hand.'**
  String get cameraUnavailableMessage;

  /// No description provided for @cameraPermissionDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Scanning needs camera access. You can still enter the secret key by hand.'**
  String get cameraPermissionDeniedMessage;

  /// No description provided for @cameraPermissionBlockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Camera access is turned off for SimplePASS. Turn it on in system settings to scan, or enter the secret key by hand.'**
  String get cameraPermissionBlockedMessage;

  /// No description provided for @openSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettingsButton;

  /// No description provided for @qrNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'No QR code found in that photo'**
  String get qrNotFoundMessage;

  /// No description provided for @otpauthImportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Filled in from the link'**
  String get otpauthImportedMessage;

  /// No description provided for @otpauthNotLinkMessage.
  ///
  /// In en, this message translates to:
  /// **'Not an otpauth:// link'**
  String get otpauthNotLinkMessage;

  /// No description provided for @otpauthMigrationMessage.
  ///
  /// In en, this message translates to:
  /// **'Google Authenticator export codes (otpauth-migration://) aren\'t supported. Use each account\'s own QR code instead.'**
  String get otpauthMigrationMessage;

  /// No description provided for @otpauthUnsupportedTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Only TOTP and HOTP links are supported'**
  String get otpauthUnsupportedTypeMessage;

  /// No description provided for @otpauthInvalidSecretMessage.
  ///
  /// In en, this message translates to:
  /// **'The link\'s secret is missing or invalid'**
  String get otpauthInvalidSecretMessage;

  /// No description provided for @otpauthUnsupportedParametersMessage.
  ///
  /// In en, this message translates to:
  /// **'The link uses an algorithm, digit count, period or counter this app doesn\'t support'**
  String get otpauthUnsupportedParametersMessage;

  /// No description provided for @cameraNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'No camera this app can use was found. Use \"From photo\" or enter the secret key by hand.'**
  String get cameraNotFoundMessage;

  /// No description provided for @scanBackButton.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get scanBackButton;

  /// No description provided for @addKindActivationCode.
  ///
  /// In en, this message translates to:
  /// **'MobilePASS – Manual enrollment'**
  String get addKindActivationCode;

  /// No description provided for @otpauthEnrollmentStringMessage.
  ///
  /// In en, this message translates to:
  /// **'This is an Enrollment String. Add it with \"MobilePASS – Auto enrollment\" instead.'**
  String get otpauthEnrollmentStringMessage;

  /// No description provided for @tapToRevealLabel.
  ///
  /// In en, this message translates to:
  /// **'Tap to reveal passcodes'**
  String get tapToRevealLabel;

  /// No description provided for @tapToRevealSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Passcodes are masked with dots; tap a profile to reveal them'**
  String get tapToRevealSubtitle;

  /// No description provided for @revealCodeAction.
  ///
  /// In en, this message translates to:
  /// **'Show and copy passcode'**
  String get revealCodeAction;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @selectAction.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectAction;

  /// No description provided for @deleteSelectedConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This permanently deletes 1 profile.} other{This permanently deletes {count} profiles.}}'**
  String deleteSelectedConfirmMessage(int count);

  /// No description provided for @deselectAction.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get deselectAction;

  /// No description provided for @parameterTimeBased.
  ///
  /// In en, this message translates to:
  /// **'Time-based'**
  String get parameterTimeBased;

  /// No description provided for @parameterCounterBased.
  ///
  /// In en, this message translates to:
  /// **'Counter-based'**
  String get parameterCounterBased;

  /// No description provided for @parameterDigits.
  ///
  /// In en, this message translates to:
  /// **'{digits} digits'**
  String parameterDigits(int digits);

  /// No description provided for @protectedProfilesBanner.
  ///
  /// In en, this message translates to:
  /// **'Authentication is off, but some profiles are still protected.'**
  String get protectedProfilesBanner;

  /// No description provided for @unprotectNowButton.
  ///
  /// In en, this message translates to:
  /// **'Remove protection'**
  String get unprotectNowButton;

  /// No description provided for @appLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'SimplePASS is locked'**
  String get appLockedMessage;

  /// No description provided for @allowScreenshotsLockNote.
  ///
  /// In en, this message translates to:
  /// **'With the app lock on, Android 12 and older always block screenshots, so the recent apps screen can\'t show your profiles.'**
  String get allowScreenshotsLockNote;

  /// No description provided for @blockScreenshotsLabel.
  ///
  /// In en, this message translates to:
  /// **'Block screenshots'**
  String get blockScreenshotsLabel;

  /// No description provided for @blockScreenshotsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prevent other apps from capturing the screen'**
  String get blockScreenshotsSubtitle;

  /// No description provided for @showSecretTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showSecretTooltip;

  /// No description provided for @hideSecretTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideSecretTooltip;

  /// No description provided for @challengeCodeSemanticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Challenge Code {code}'**
  String challengeCodeSemanticsLabel(String code);

  /// No description provided for @unsavedChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChangesTitle;

  /// No description provided for @discardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardButton;

  /// No description provided for @keepEditingButton.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditingButton;

  /// No description provided for @typeStandardTotp.
  ///
  /// In en, this message translates to:
  /// **'TOTP'**
  String get typeStandardTotp;

  /// No description provided for @typeStandardHotp.
  ///
  /// In en, this message translates to:
  /// **'HOTP'**
  String get typeStandardHotp;

  /// No description provided for @typeChallengeResponse.
  ///
  /// In en, this message translates to:
  /// **'Challenge-response'**
  String get typeChallengeResponse;

  /// No description provided for @notSetValue.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSetValue;

  /// No description provided for @copiedEquivalentLinkMessage.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get copiedEquivalentLinkMessage;

  /// No description provided for @copyOtpauthLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Copy otpauth link'**
  String get copyOtpauthLinkButton;

  /// No description provided for @moreOptionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptionsTooltip;

  /// No description provided for @copiedFieldMessage.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedFieldMessage;

  /// No description provided for @copyFieldTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyFieldTooltip;

  /// No description provided for @otpChallengeLengthLabel.
  ///
  /// In en, this message translates to:
  /// **'Challenge Code length'**
  String get otpChallengeLengthLabel;

  /// No description provided for @otpTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'OTP type'**
  String get otpTypeLabel;

  /// No description provided for @otpDigitsLabel.
  ///
  /// In en, this message translates to:
  /// **'Code length'**
  String get otpDigitsLabel;

  /// No description provided for @otpAlgorithmLabel.
  ///
  /// In en, this message translates to:
  /// **'Algorithm'**
  String get otpAlgorithmLabel;

  /// No description provided for @otpPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period (seconds)'**
  String get otpPeriodLabel;

  /// No description provided for @otpPeriodInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a period from 1 to 3600 seconds'**
  String get otpPeriodInvalid;

  /// No description provided for @deleteProfileMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete this profile from this phone? This does not remove the authenticator from the service.'**
  String get deleteProfileMessage;

  /// No description provided for @profileDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'{type} profile'**
  String profileDetailsTitle(String type, String spacing);

  /// No description provided for @openCameraButton.
  ///
  /// In en, this message translates to:
  /// **'Open camera'**
  String get openCameraButton;

  /// No description provided for @addKindTotpMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get addKindTotpMenuTitle;

  /// No description provided for @mobilePassFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'Use MobilePASS format'**
  String get mobilePassFormatLabel;

  /// No description provided for @registrationInfoMenuItem.
  ///
  /// In en, this message translates to:
  /// **'MobilePASS registration info'**
  String get registrationInfoMenuItem;

  /// No description provided for @mobilePassFormatLine.
  ///
  /// In en, this message translates to:
  /// **'MobilePASS format'**
  String get mobilePassFormatLine;

  /// No description provided for @addTotpScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get addTotpScreenTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
