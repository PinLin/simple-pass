import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../mobilepass/enrollment_string.dart' show parseEnrollmentString;
import '../mobilepass/mobilepass.dart';
import '../models/profile.dart';
import '../otpauth/base32.dart';
import '../otpauth/otpauth_uri.dart';
import '../otpauth/standard_otp.dart';
import '../platform/camera_permission.dart';
import '../platform/keystore.dart';
import '../platform/qr_reader.dart';
import '../storage/profile_store.dart';
import '../storage/settings_store.dart';
import '../storage/storage_exceptions.dart';
import 'activation_code_input_formatter.dart';
import 'app_snack_bar.dart';
import 'otp_helpers.dart';
import 'profile_info_sheet.dart';

/// Adds a profile ([profile] null, of [kind]) or edits an unlocked one, saving through [profileStore];
/// pops true once saved. Activation code, policy and a standard token's secret are read-only once saved.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.profileStore,
    required this.settingsStore,
    this.profile,
    this.kind = ProfileKind.activationCode,
    this.cameraPermission,
    this.qrReader = const ZxingQrReader(),
    @visibleForTesting this.generateSeed = generateActivationSeed,
  });

  final ProfileStore profileStore;
  final SettingsStore settingsStore;
  final Profile? profile;

  /// Kind of a new profile; ignored when editing.
  final ProfileKind kind;

  /// Defaults to the platform channel.
  final CameraPermission? cameraPermission;
  final QrReader qrReader;

  /// Source of the seed behind a new profile's prefilled activation code.
  final Uint8List Function() generateSeed;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Profile? _initial = widget.profile;
  late final _nameController = TextEditingController(text: _initial?.name);
  // Seed behind the prefilled code of a new profile; null once the user types their own code.
  Uint8List? _seed;
  late final _activationCodeController = TextEditingController(text: _initial?.activationCode ?? _prefill());
  late final _policyController = TextEditingController(text: _initial?.policy);
  late final _initialCounter = '${_initial?.counter ?? 0}';
  late final _counterController = TextEditingController(text: _initialCounter);
  late final _pinController = TextEditingController(text: _initial?.pin);
  late bool _appendPinOnCopy = _initial?.appendPinOnCopy ?? false;
  // App-wide protection, read when a new profile is saved.
  bool _sealNew = false;
  late final bool _holdsKey = _initial?.holdsKey ?? false;
  bool _saving = false;
  OtpauthType _manualType = OtpauthType.totp;
  OtpAlgorithm _algorithm = defaultOtpAlgorithm;
  bool _mobilePassFormat = false;
  int _digits = defaultOtpDigits;
  final _periodController = TextEditingController(text: '$defaultOtpPeriod');
  final _linkPeriodController = TextEditingController();
  bool get _linkInput => looksLikeOtpauthLink(_secretController.text);

  // The switch only shows for a typed Base32 secret making TOTP; it's ignored once that no longer holds.
  bool get _mobilePassTime =>
      _initial?.mobilePassTime ?? (_mobilePassFormat && !_linkInput && _manualType == OtpauthType.totp);

  // MobilePASS time-based codes are always HMAC-SHA256.
  OtpAlgorithm get _effectiveAlgorithm => _mobilePassTime ? OtpAlgorithm.sha256 : _algorithm;

  String get _credentialText {
    final text = _secretController.text.trim();
    if (_initial != null || _linkInput) return text;
    final secret = base32Decode(text);
    final period = int.tryParse(_periodController.text) ?? 0;
    if (secret == null || secret.isEmpty || (_manualType == OtpauthType.totp && !isValidOtpPeriod(period))) return '';
    // Preserve existing bare-secret credentials when the defaults are used.
    if (_manualType == OtpauthType.totp &&
        _effectiveAlgorithm == defaultOtpAlgorithm &&
        _digits == defaultOtpDigits &&
        period == defaultOtpPeriod) {
      return text;
    }
    return 'otpauth://${_manualType.name}/${Uri.encodeComponent(_nameController.text.trim())}'
        '?secret=${base32Encode(secret)}&algorithm=${_effectiveAlgorithm.label}&digits=$_digits'
        '${_manualType == OtpauthType.totp ? '&period=$period' : '&counter=0'}';
  }

  // Secrets start hidden on an existing profile and shown while a new one is typed in.
  late bool _showActivationCode = _initial == null;
  late bool _showPin = _initial == null;

  // What the form held when it opened, to tell whether leaving would lose anything.
  // Taken in initState, before anything is typed.
  late final ({String name, String policy, String counter, String pin, bool appendPin, String secret}) _openedWith;

  ({String name, String policy, String counter, String pin, bool appendPin, String secret}) _formValues() => (
    name: _nameController.text,
    policy: _policyController.text,
    counter: _counterController.text,
    pin: _pinController.text,
    // Saved as soon as it's switched on an existing profile, so it never counts as unsaved there.
    appendPin: _initial == null && _appendPinOnCopy,
    secret: _secretController.text,
  );

  // The prefilled random Activation Code doesn't count; one the user typed (no seed behind it) does.
  bool get _changed =>
      _formValues() != _openedWith ||
      (_initial == null && !_standard && _seed == null) ||
      (_initial == null &&
          _standard &&
          (_manualType != OtpauthType.totp ||
              _mobilePassFormat ||
              _algorithm != defaultOtpAlgorithm ||
              _digits != defaultOtpDigits ||
              _periodController.text != '$defaultOtpPeriod'));

  /// On an existing profile the switch saves right away (only that field); a failure puts it back.
  Future<void> _setAppendPinOnCopy(bool value) async {
    final initial = _initial;
    setState(() => _appendPinOnCopy = value);
    if (initial == null) return;
    try {
      await widget.profileStore.updateProfile(initial.id, (p) => p.copyWith(appendPinOnCopy: value));
    } catch (_) {
      if (!mounted) return;
      setState(() => _appendPinOnCopy = !value);
      _showMessage(AppLocalizations.of(context).saveFailedMessage);
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    final choice = await askAboutUnsavedChanges(context);
    if (!mounted) return;
    switch (choice) {
      case UnsavedChoice.discard:
        Navigator.of(context).pop();
      case UnsavedChoice.keepEditing:
        break;
    }
  }

  // A new standard token is TOTP or HOTP by what the Secret field holds right now, so the saved kind
  // always matches the saved credential.
  String? _linkText;
  bool _importing = false;
  ProfileKind get _kind {
    final initial = _initial;
    if (initial != null) return initial.kind;
    if (widget.kind != ProfileKind.totp && widget.kind != ProfileKind.hotp) return widget.kind;
    final credential = _linkInput ? tryParseOathCredential(_secretController.text.trim()) : null;
    return (credential?.type ?? _manualType) == OtpauthType.hotp ? ProfileKind.hotp : ProfileKind.totp;
  }

  late final _secretController = TextEditingController(
    text: _initial != null && _initial.isStandardOtp ? _initial.key : null,
  );
  late final CameraPermission _cameraPermission = widget.cameraPermission ?? PlatformCameraPermission();

  @override
  void initState() {
    super.initState();
    if (_initial == null && widget.kind == ProfileKind.hotp) _manualType = OtpauthType.hotp;
    _periodController.addListener(() => setState(() {}));
    _activationCodeController.addListener(_onActivationCodeChanged);
    _secretController.addListener(_onSecretChanged);
    _openedWith = _formValues();
    _policyController.addListener(_onPolicyChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _activationCodeController.dispose();
    _policyController.dispose();
    _counterController.dispose();
    _linkPeriodController.dispose();
    _pinController.dispose();
    _secretController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  bool get _standard => _kind == ProfileKind.totp || _kind == ProfileKind.hotp;

  String _prefill() {
    final seed = _seed = widget.generateSeed();
    return _codeForSeed(seed);
  }

  // A version-2 policy gets the versioned layout; anything else (empty, v1, not parseable yet) legacy.
  String _codeForSeed(Uint8List seed) {
    final version = tryParsePolicy(_policyController.text)?.version ?? 1;
    return version == 1 ? encodeLegacyActivationCode(seed) : encodeVersionedActivationCode(seed, version);
  }

  void _regenerate() {
    _activationCodeController.text = _prefill();
  }

  void _onActivationCodeChanged() {
    final seed = _seed;
    if (seed != null && _activationCodeController.text != _codeForSeed(seed)) _seed = null;
    setState(() {});
  }

  void _onPolicyChanged() {
    final seed = _seed;
    if (seed != null) _activationCodeController.text = _codeForSeed(seed);
    setState(() {});
  }

  // A new profile starts at the counter its link carries (else 0); only editing shows it.
  bool get _usesCounter => _standard
      ? _kind == ProfileKind.hotp
      : (tryParsePolicy(_policyController.text)?.type ?? OtpType.event) == OtpType.event;

  String? _activationCodeError(AppLocalizations l10n, String value) {
    final error = activationCodeInputError(l10n, value);
    if (error != null) return error;
    return activationCodeMismatchesPolicy(value, _policyController.text) ? l10n.activationCodePolicyMismatch : null;
  }

  // [p] is the latest stored profile. A ✓ may have advanced its counter
  // since this page opened, so an untouched field must not roll it back.
  Profile _apply(Profile p) => p.copyWith(
    name: _nameController.text.trim(),
    activationCode: _initial == null && !_standard ? normalizeActivationCode(_activationCodeController.text) : null,
    counter: !_usesCounter || _counterController.text == _initialCounter
        ? null
        : parseCounterInput(_counterController.text)!,
    pin: _pinController.text,
    policy: _initial == null && !_standard ? _policyController.text.trim() : null,
    appendPinOnCopy: _appendPinOnCopy,
    protected: _initial == null ? _sealNew : null,
  );

  // A new standard token, with what's in the form; [_apply] then fills in the editable fields.
  Profile _newStandardProfile() => Profile(
    id: generateProfileId(),
    name: '',
    activationCode: '',
    counter: _linkText == null ? 0 : (tryParseOathCredential(_linkText!)?.counter ?? 0),
    kind: _kind,
    key: _credentialText,
    mobilePassTime: _mobilePassTime,
  );

  // The field keeps exactly what was entered. A new link in it also fills an empty name;
  // the kind follows the text on every rebuild.
  void _onSecretChanged() {
    if (_initial != null) return;
    final text = _secretController.text.trim();
    final link = looksLikeOtpauthLink(text) ? tryParseOathCredential(text) : null;
    final linkText = link == null ? null : text;
    if (linkText == _linkText) {
      setState(() {});
      return;
    }
    setState(() {
      _linkText = linkText;
      if (link == null) return;
      _linkPeriodController.text = '${link.period}';
      if (_nameController.text.trim().isEmpty) _nameController.text = defaultTokenName(link.issuer, link.account);
    });
  }

  String _otpauthMessage(AppLocalizations l10n, OtpauthException e, String text) => switch (e.code) {
    OtpauthErrorCode.notOtpauth when _isEnrollmentString(text) => l10n.otpauthEnrollmentStringMessage,
    OtpauthErrorCode.notOtpauth => l10n.otpauthNotLinkMessage,
    OtpauthErrorCode.migrationUnsupported => l10n.otpauthMigrationMessage,
    OtpauthErrorCode.unsupportedType => l10n.otpauthUnsupportedTypeMessage,
    OtpauthErrorCode.invalidSecret => l10n.otpauthInvalidSecretMessage,
    OtpauthErrorCode.unsupportedParameters => l10n.otpauthUnsupportedParametersMessage,
  };

  String? _secretError(AppLocalizations l10n, String value) {
    final text = value.trim();
    if (text.isEmpty) return l10n.secretRequired;
    try {
      parseOathCredential(text);
      return null;
    } on OtpauthException catch (e) {
      return looksLikeOtpauthLink(text) ? _otpauthMessage(l10n, e, text) : l10n.secretInvalid;
    }
  }

  void _showMessage(String message, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(appSnackBar(messenger, message, action: action));
  }

  /// Puts an otpauth link into the Secret field as is, or says why it can't; true when it did.
  bool _importLink(String text) {
    final l10n = AppLocalizations.of(context);
    try {
      parseOtpauthUri(text);
    } on OtpauthException catch (e) {
      _showMessage(_otpauthMessage(l10n, e, text));
      return false;
    }
    _secretController.text = text.trim();
    _showMessage(l10n.otpauthImportedMessage);
    return true;
  }

  static bool _isEnrollmentString(String text) {
    try {
      parseEnrollmentString(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Runs one import at a time; the buttons are disabled meanwhile.
  Future<void> _runImport(Future<void> Function() import) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      await import();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _scanQr() async {
    final l10n = AppLocalizations.of(context);
    final status = await _cameraPermission.request();
    if (!mounted) return;
    switch (status) {
      case CameraPermissionStatus.granted:
        final text = await widget.qrReader.scan(context);
        if (text != null && mounted) _importLink(text);
      case CameraPermissionStatus.denied:
        _showMessage(l10n.cameraPermissionDeniedMessage);
      case CameraPermissionStatus.permanentlyDenied:
        _showMessage(
          l10n.cameraPermissionBlockedMessage,
          action: SnackBarAction(label: l10n.openSettingsButton, onPressed: _cameraPermission.openSettings),
        );
      case CameraPermissionStatus.busy:
        break;
    }
  }

  Future<void> _importPhoto() async {
    final l10n = AppLocalizations.of(context);
    String? text;
    try {
      text = await widget.qrReader.readFromPhoto();
    } catch (_) {
      text = '';
    }
    if (text == null || !mounted) return;
    text.isEmpty ? _showMessage(l10n.qrNotFoundMessage) : _importLink(text);
  }

  Future<void> _chooseQrSource() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          key: const ValueKey('qrSourceSheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('scanQrCameraButton'),
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(l10n.openCameraButton),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              key: const ValueKey('importQrPhotoButton'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.importQrPhotoButton),
              onTap: () => Navigator.of(sheetContext).pop('photo'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'camera') {
      await _scanQr();
    } else {
      await _importPhoto();
    }
  }

  Future<void> _copyActivationCode() async {
    final l10n = AppLocalizations.of(context);
    final code = normalizeActivationCode(_activationCodeController.text);
    if (code.isEmpty) return;
    await copySensitiveWithSnackBar(context, widget.settingsStore, code, l10n.copiedActivationCodeMessage);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final initial = _initial;
    try {
      if (initial == null) {
        _sealNew = await requireAuthSetting(widget.settingsStore);
        final added = _apply(
          _standard
              ? _newStandardProfile()
              : Profile(id: generateProfileId(), name: '', activationCode: '', counter: 0),
        );
        await widget.profileStore.update((current) => [...current, added]);
      } else {
        await widget.profileStore.updateProfile(initial.id, _apply);
      }
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on AuthFailedException catch (e) {
      if (!mounted) return;
      if (authResultMessage(l10n, e.result) case final message?) {
        messenger.showSnackBar(appSnackBar(messenger, message));
      }
    } on KeyInvalidatedException {
      if (!mounted) return;
      await offerToDeleteUnrecoverable(context, widget.profileStore);
      // The profile being edited may have been one of those deleted.
      if (initial != null && initial.protected && mounted) {
        final remaining = await widget.profileStore.loadAll().catchError((_) => <Profile>[initial]);
        if (!remaining.any((p) => p.id == initial.id) && mounted) {
          Navigator.of(context).pop(true);
          return;
        }
      }
    } catch (_) {
      messenger.showSnackBar(appSnackBar(messenger, l10n.saveFailedMessage));
    }
    if (mounted) setState(() => _saving = false);
  }

  List<Widget> _standardFields(AppLocalizations l10n, bool editing) {
    if (editing) return _savedParameterFields(l10n);
    final link = _linkInput ? tryParseOathCredential(_secretController.text.trim()) : null;
    return [
      TextFormField(
        key: const ValueKey('secretField'),
        controller: _secretController,
        decoration: InputDecoration(
          labelText: l10n.fieldSecret,
          suffixIcon: IconButton(
            key: const ValueKey('scanQrButton'),
            tooltip: l10n.scanQrButton,
            onPressed: _importing ? null : () => _runImport(_chooseQrSource),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ),
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        validator: (value) => _secretError(l10n, value ?? ''),
      ),
      const SizedBox(height: 16),
      // A link carries its own parameters: they show in the same fields, locked.
      _lockedWhileLink(
        DropdownButtonFormField<OtpauthType>(
          key: const ValueKey('otpTypeField'),
          initialValue: link?.type ?? _manualType,
          isExpanded: true,
          style: _dropdownStyle(link != null),
          decoration: InputDecoration(labelText: l10n.otpTypeLabel),
          items: [
            DropdownMenuItem(value: OtpauthType.totp, child: Text(l10n.parameterTimeBased)),
            DropdownMenuItem(value: OtpauthType.hotp, child: Text(l10n.parameterCounterBased)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _manualType = value);
          },
        ),
        link != null,
      ),
      // MobilePASS event-based tokens are plain HOTP-SHA256, so only time-based ones need this.
      if (!_linkInput && _manualType == OtpauthType.totp) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('mobilePassFormatSwitch'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.mobilePassFormatLabel),
          value: _mobilePassFormat,
          onChanged: (value) => setState(() => _mobilePassFormat = value),
        ),
        const SizedBox(height: 8),
      ] else
        const SizedBox(height: 16),
      _lockedWhileLink(
        DropdownButtonFormField<int>(
          key: const ValueKey('otpDigitsField'),
          initialValue: link?.digits ?? _digits,
          style: _dropdownStyle(link != null),
          decoration: InputDecoration(labelText: l10n.otpDigitsLabel),
          items: [for (final n in supportedOtpDigits) DropdownMenuItem(value: n, child: Text(l10n.parameterDigits(n)))],
          onChanged: (value) {
            if (value != null) setState(() => _digits = value);
          },
        ),
        link != null,
      ),
      const SizedBox(height: 16),
      _lockedWhileLink(
        DropdownButtonFormField<OtpAlgorithm>(
          key: const ValueKey('otpAlgorithmField'),
          initialValue: link?.algorithm ?? _effectiveAlgorithm,
          style: _dropdownStyle(link != null || _mobilePassTime),
          decoration: InputDecoration(labelText: l10n.otpAlgorithmLabel),
          items: [
            for (final a in OtpAlgorithm.values) DropdownMenuItem(value: a, child: Text('SHA-${a.label.substring(3)}')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _algorithm = value);
          },
        ),
        link != null || _mobilePassTime,
      ),
      if ((link?.type ?? _manualType) == OtpauthType.totp) ...[
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('otpPeriodField'),
          controller: link != null ? _linkPeriodController : _periodController,
          decoration: InputDecoration(labelText: l10n.otpPeriodLabel),
          style: _fixedStyle(link != null),
          readOnly: link != null,
          showCursor: link == null,
          canRequestFocus: link == null,
          enableInteractiveSelection: link == null,
          keyboardType: TextInputType.number,
          validator: (value) =>
              link != null || (RegExp(r'^\d+$').hasMatch(value ?? '') && isValidOtpPeriod(int.tryParse(value!) ?? 0))
              ? null
              : l10n.otpPeriodInvalid,
        ),
      ],
      const SizedBox(height: 16),
    ];
  }

  // A dropdown's style replaces the theme's text style instead of merging into it.
  TextStyle? _dropdownStyle(bool fixed) =>
      fixed ? Theme.of(context).textTheme.titleMedium?.merge(_fixedStyle(true)) : null;

  Widget _lockedWhileLink(Widget field, bool locked) =>
      locked ? ExcludeFocus(child: IgnorePointer(child: field)) : field;

  List<Widget> _savedParameterFields(AppLocalizations l10n) {
    final profile = _initial!;
    final standard = _standard ? tryParseOathCredential(profile.key.trim()) : null;
    final mobilePassKey = _standard ? null : mobilePassKeyOf(profile);
    // A token saved from an otpauth link shows just its key; its other parameters have their own fields.
    final secret = _standard
        ? (standard == null ? profile.key : base32Encode(standard.secret))
        : (mobilePassKey == null ? null : base32Encode(mobilePassKey));
    final secretFields = [
      if (secret != null) ...[
        ReadOnlyInfoField(
          id: _standard ? 'secretField' : 'mobilePassSecretField',
          label: l10n.fieldSecret,
          value: secret,
          sensitive: true,
          settingsStore: widget.settingsStore,
        ),
        const SizedBox(height: 16),
      ],
    ];
    final policy = _standard ? null : tryParsePolicy(profile.policy);
    if (standard == null && policy == null) return secretFields;
    final timeBased = standard != null ? standard.type == OtpauthType.totp : policy!.type == OtpType.time;
    final challenge = policy?.type == OtpType.challenge;
    final digits = standard?.digits ?? policy!.digits;
    final algorithm = standard?.algorithm ?? OtpAlgorithm.sha256;
    final period = standard?.period ?? policy?.timeStep;
    return [
      ...secretFields,
      _savedParameter('otpDigitsField', l10n.otpDigitsLabel, l10n.parameterDigits(digits)),
      _savedParameter('otpAlgorithmField', l10n.otpAlgorithmLabel, 'SHA-${algorithm.label.substring(3)}'),
      if (timeBased && period != null) _savedParameter('otpPeriodField', l10n.otpPeriodLabel, '$period'),
      if (challenge)
        _savedParameter('otpChallengeLengthField', l10n.otpChallengeLengthLabel, '${policy!.challengeLength}'),
    ];
  }

  Widget _savedParameter(String key, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      style: _fixedStyle(true),
      readOnly: true,
      showCursor: false,
      canRequestFocus: false,
      enableInteractiveSelection: false,
    ),
  );

  // Fields fixed at creation look like the others, only with dimmed text (still
  // above 4.5:1), no cursor and no focus; copying goes through their copy button.
  TextStyle? _fixedStyle(bool fixed) =>
      fixed ? TextStyle(color: readOnlyValueColor(Theme.of(context).colorScheme)) : null;

  // Takes the name and counter as typed, so the link matches what Save would store.
  String? _exportLink() {
    final initial = _initial!;
    final counter = parseCounterInput(_counterController.text) ?? initial.counter;
    final name = _nameController.text.trim().isEmpty ? initial.name : _nameController.text.trim();
    return equivalentOtpLink(initial, name: name, counter: counter);
  }

  // Show/hide for a secret field; it sits before the copy button.
  Widget _eye(String key, bool shown, VoidCallback toggle, AppLocalizations l10n) => IconButton(
    key: ValueKey(key),
    tooltip: shown ? l10n.hideSecretTooltip : l10n.showSecretTooltip,
    icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
    onPressed: toggle,
  );

  Future<void> _delete() async {
    if (_saving) return;
    final profile = _initial!;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle(1)),
        content: Text('${profile.name}\n\n${l10n.deleteProfileMessage}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.cancelButton)),
          FilledButton(
            key: const ValueKey('confirmDeleteProfileButton'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.profileStore.update((current) => current.where((p) => p.id != profile.id).toList());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(l10n.saveFailedMessage);
    }
  }

  bool get _usesMobilePassAlgorithm => _initial != null && (!_initial.isStandardOtp || _initial.mobilePassTime);

  // Standard tokens, including a MobilePASS-format TOTP, have no enrollment data to show.
  bool get _hasRegistrationInfo => _initial != null && !_initial.isStandardOtp;

  Widget _profileMenu(AppLocalizations l10n) => PopupMenuButton<String>(
    key: const ValueKey('profileMenuButton'),
    tooltip: l10n.moreOptionsTooltip,
    enabled: !_saving,
    onSelected: (value) {
      switch (value) {
        case 'delete':
          _delete();
        case 'export':
          if (_exportLink() case final link?) {
            copySensitiveWithSnackBar(
              context,
              widget.settingsStore,
              link,
              AppLocalizations.of(context).copiedEquivalentLinkMessage,
            );
          }
        case 'registrationInfo':
          if (_initial case final profile?) {
            showRegistrationInfoSheet(context, profile: profile, settingsStore: widget.settingsStore);
          }
      }
    },
    itemBuilder: (_) => [
      if (_hasRegistrationInfo)
        PopupMenuItem(
          value: 'registrationInfo',
          key: const ValueKey('registrationInfoMenuItem'),
          child: Text(l10n.registrationInfoMenuItem),
        ),
      if (_exportLink() != null) ...[
        PopupMenuItem(
          value: 'export',
          key: const ValueKey('copyOtpauthLinkButton'),
          child: Text(l10n.copyOtpauthLinkButton),
        ),
      ],
      if (_exportLink() != null || _hasRegistrationInfo) const PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        key: const ValueKey('deleteProfileButton'),
        child: Text(l10n.deleteProfileButton, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = _initial != null;
    final copyButton = IconButton(
      key: const ValueKey('copyActivationCodeButton'),
      tooltip: l10n.copyActivationCodeTooltip,
      icon: const Icon(Icons.copy),
      onPressed: _copyActivationCode,
    );
    // Back (app bar, system button or gesture) asks first when something changed; Save's own pop and
    // the app lock closing pages bypass this.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [if (editing) _profileMenu(l10n)],
          title: Text(
            _initial != null
                ? l10n.profileDetailsTitle(
                    profileTypeLabel(l10n, _initial),
                    _initial.otpPolicy?.type == OtpType.challenge ? 'cjk' : 'other',
                  )
                : _standard
                ? l10n.addTotpScreenTitle
                : l10n.addKindActivationCode,
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_usesMobilePassAlgorithm) ...[
                // Same look as an enabled text button, but the registration info opens from the menu.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: null,
                    style: TextButton.styleFrom(
                      disabledForegroundColor: Theme.of(context).colorScheme.primary,
                      disabledIconColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: Text(
                      l10n.mobilePassFormatLine,
                      key: const ValueKey('sourceLine'),
                      // The CJK fallback font's taller metrics would otherwise push the text below the icon's center.
                      strutStyle: const StrutStyle(forceStrutHeight: true),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                key: const ValueKey('nameField'),
                controller: _nameController,
                decoration: InputDecoration(labelText: l10n.fieldName),
                validator: (value) => (value == null || value.trim().isEmpty) ? l10n.fieldNameRequired : null,
              ),
              const SizedBox(height: 16),
              if (_standard)
                ..._standardFields(l10n, editing)
              else if (!editing) ...[
                TextFormField(
                  key: const ValueKey('policyField'),
                  controller: _policyController,
                  decoration: InputDecoration(labelText: l10n.fieldPolicyOptional),
                  keyboardType: TextInputType.number,
                  validator: (value) => policyInputError(l10n, value ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('activationCodeField'),
                  controller: _activationCodeController,
                  decoration: InputDecoration(
                    labelText: l10n.fieldActivationCode,
                    hintText: l10n.activationCodeHint,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _eye(
                          'toggleActivationCodeVisibility',
                          _showActivationCode,
                          () => setState(() => _showActivationCode = !_showActivationCode),
                          l10n,
                        ),
                        copyButton,
                        IconButton(
                          key: const ValueKey('regenerateActivationCodeButton'),
                          tooltip: l10n.regenerateActivationCodeTooltip,
                          icon: const Icon(Icons.refresh),
                          onPressed: _regenerate,
                        ),
                      ],
                    ),
                  ),
                  obscureText: !_showActivationCode,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: const [ActivationCodeInputFormatter()],
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  validator: (value) => _activationCodeError(l10n, value ?? ''),
                ),
                const SizedBox(height: 16),
              ],
              if (editing && !_standard) ..._savedParameterFields(l10n),
              if (_usesCounter && editing) ...[
                TextFormField(
                  key: const ValueKey('counterField'),
                  controller: _counterController,
                  decoration: InputDecoration(labelText: l10n.fieldCounter),
                  keyboardType: TextInputType.number,
                  validator: (value) => counterInputError(l10n, value ?? ''),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                key: const ValueKey('pinField'),
                controller: _pinController,
                decoration: InputDecoration(
                  labelText: l10n.fieldPin,
                  hintText: l10n.pinHint(minPinLength, maxPinLength),
                  suffixIcon: _eye('togglePinVisibility', _showPin, () => setState(() => _showPin = !_showPin), l10n),
                ),
                obscureText: !_showPin,
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                // A PIN the enrollment server allowed letters in needs a full keyboard.
                keyboardType: RegExp(r'^[0-9]*$').hasMatch(_initial?.pin ?? '')
                    ? TextInputType.number
                    : TextInputType.visiblePassword,
                // A PIN the enrollment server set may fall outside this app's own PIN rules.
                validator: (value) => _holdsKey && value == _initial?.pin ? null : pinInputError(l10n, value ?? ''),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.appendPinOnCopyLabel),
                subtitle: Text(l10n.appendPinOnCopySubtitle),
                value: _appendPinOnCopy,
                onChanged: _setAppendPinOnCopy,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [FilledButton(onPressed: _saving ? null : _save, child: Text(l10n.saveButton))],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
