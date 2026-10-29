import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../mobilepass/dskpp_client.dart';
import '../mobilepass/enrollment_string.dart';
import '../models/profile.dart';
import '../models/mobilepass_registration.dart';
import '../platform/device_info.dart';
import '../storage/storage_exceptions.dart';
import '../storage/profile_store.dart';
import '../storage/settings_store.dart';
import 'app_snack_bar.dart';
import 'otp_helpers.dart';

/// Adds a profile by registering an Enrollment String with its server. Pops true once saved; a
/// failed registration saves nothing.
class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({
    super.key,
    required this.profileStore,
    this.settingsStore,
    this.pending,
    this.deviceInfo = const DeviceInfo(),
    @visibleForTesting this.transport,
  });

  final ProfileStore profileStore;

  /// Source of the app-wide protection setting a new profile follows; none means unprotected.
  final SettingsStore? settingsStore;

  /// True while a registration runs or its result isn't saved yet: the Enrollment String is single
  /// use, so the app lock covers this page then instead of closing it.
  final ValueNotifier<bool>? pending;
  final DeviceInfo deviceInfo;

  /// Stand-in for the network in tests.
  final DskppTransport? transport;

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _stringController = TextEditingController();
  final _nameController = TextEditingController();
  final _userIdController = TextEditingController();
  final _passphraseController = TextEditingController();

  EnrollmentString? _parsed;
  EnrollmentStep? _step;
  bool _busy = false;
  String? _error;

  // Registered but not yet saved: the server won't hand out this key again, so a failed save is
  // retried from here instead of registering anew.
  EnrolledToken? _enrolled;
  MobilePassRegistration? _registration;

  @override
  void initState() {
    super.initState();
    _stringController.addListener(_onStringChanged);
  }

  @override
  void dispose() {
    _stringController.dispose();
    _nameController.dispose();
    _userIdController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  void _onStringChanged() {
    EnrollmentString? parsed;
    try {
      parsed = parseEnrollmentString(_stringController.text);
    } on EnrollmentStringException {
      parsed = null;
    }
    if (parsed?.url != _parsed?.url || parsed?.userId != _parsed?.userId || parsed?.passphrase != _parsed?.passphrase) {
      setState(() => _parsed = parsed);
    }
  }

  String? _stringError(AppLocalizations l10n, String value) {
    if (value.trim().isEmpty) return l10n.enrollmentStringRequired;
    try {
      parseEnrollmentString(value);
      return null;
    } on EnrollmentStringException catch (e) {
      return switch (e.error) {
        EnrollmentStringError.notHttps => l10n.enrollmentStringNotHttps,
        EnrollmentStringError.invalidFormat => l10n.enrollmentStringInvalid,
      };
    }
  }

  Future<void> _paste() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      messenger.showSnackBar(appSnackBar(messenger, l10n.clipboardEmptyMessage));
      return;
    }
    _stringController.text = text;
  }

  // The app lock may cover this page meanwhile; the prompt must not show above the cover.
  Future<bool> _untilOnTop() async {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    while (mounted) {
      if (route == null || route.isCurrent) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  // Only this page's own route: a lock cover above it must stay.
  void _close([bool? result]) {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    route.isCurrent ? navigator.pop(result) : navigator.removeRoute(route, result);
  }

  Future<String?> _askPin(SoftPinPolicy policy) async {
    if (mounted) setState(() => _step = null);
    if (!await _untilOnTop() || !mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpPinDialog(policy: policy),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    final enrolled = _enrolled;
    if (enrolled != null) return _save(enrolled);
    if (!_formKey.currentState!.validate()) return;
    final parsed = _parsed!;
    final originalString = _stringController.text;
    final enrollment = parsed.copyWith(
      userId: parsed.userId.isEmpty ? _userIdController.text.trim() : null,
      passphrase: parsed.passphrase.isEmpty ? _passphraseController.text : null,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final osVersion = await widget.deviceInfo.osRelease();
      final token = await DskppClient(transport: widget.transport, osVersion: osVersion).enroll(
        enrollment,
        tokenName: _nameController.text.trim(),
        requestPin: _askPin,
        onStep: (step) {
          if (mounted) setState(() => _step = step);
        },
      );
      if (!mounted) return;
      setState(() {
        _enrolled = token;
        _registration = MobilePassRegistration(
          enrollmentString: originalString,
          url: enrollment.url,
          userId: enrollment.userId,
          passphrase: enrollment.passphrase,
        );
      });
      await _save(token);
    } on EnrollmentException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = null;
        _error = e.code == EnrollmentErrorCode.canceled ? null : _errorMessage(AppLocalizations.of(context), e);
      });
    } catch (_) {
      // Anything unforeseen must still give the page back to the user.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = null;
        _error = AppLocalizations.of(context).enrollErrorBadResponse;
      });
    }
  }

  // A registered but unsaved key can't be fetched again, so leaving then needs confirmation.
  Future<void> _leave() async {
    if (_busy) return;
    final enrolled = _enrolled;
    if (enrolled != null) {
      // Registered but not saved: the Enrollment String can't be used again, so ask as any form does.
      final choice = await askAboutUnsavedChanges(context);
      if (!mounted) return;
      switch (choice) {
        case UnsavedChoice.discard:
          break;
        case UnsavedChoice.keepEditing:
          return;
      }
    }
    if (mounted) _close();
  }

  Future<void> _save(EnrolledToken token) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final profile = Profile(
      id: generateProfileId(),
      name: _nameController.text.trim(),
      activationCode: '',
      kind: ProfileKind.mobilePassKey,
      key: base64.encode(token.key),
      serial: token.serial,
      registration: _registration,
      policy: token.policy,
      pin: token.pin,
      counter: 0,
      protected: await requireAuthSetting(widget.settingsStore),
    );
    try {
      await widget.profileStore.update((current) => [...current, profile]);
      if (mounted) _close(true);
      return;
    } on AuthFailedException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _error = authResultMessage(l10n, e.result) ?? l10n.enrollSaveFailedMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context).enrollSaveFailedMessage);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _step = null;
      });
    }
  }

  // The status comes from the server as is; a long one mustn't take over the page.
  static String _shortened(String text, {int max = 200}) {
    final characters = text.characters;
    return characters.length <= max ? text : '${characters.take(max)}…';
  }

  String _errorMessage(AppLocalizations l10n, EnrollmentException e) => switch (e.code) {
    EnrollmentErrorCode.network => l10n.enrollErrorNetwork,
    EnrollmentErrorCode.certificate => l10n.enrollErrorCertificate,
    EnrollmentErrorCode.httpStatus => l10n.enrollErrorHttp(e.detail ?? ''),
    EnrollmentErrorCode.badResponse => l10n.enrollErrorBadResponse,
    EnrollmentErrorCode.rejected => l10n.enrollErrorRejected(_shortened(e.detail ?? '')),
    EnrollmentErrorCode.macMismatch => l10n.enrollErrorMac,
    EnrollmentErrorCode.unsupportedPolicy => l10n.enrollErrorPolicy,
    EnrollmentErrorCode.canceled => '',
  };

  @override
  Widget build(BuildContext context) {
    widget.pending?.value = _busy || _enrolled != null;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parsed = _parsed;
    final locked = _busy || _enrolled != null;
    final step = _step;
    return PopScope(
      canPop: !_busy && _enrolled == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.enrollTitle)),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                key: const ValueKey('enrollmentStringField'),
                controller: _stringController,
                readOnly: locked,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.fieldEnrollmentString,
                  suffixIcon: IconButton(
                    key: const ValueKey('pasteEnrollmentStringButton'),
                    tooltip: l10n.pasteFromClipboardTooltip,
                    icon: const Icon(Icons.content_paste),
                    onPressed: locked ? null : _paste,
                  ),
                ),
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.visiblePassword,
                validator: (value) => _stringError(l10n, value ?? ''),
              ),
              if (parsed != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.enrollServerLabel(parsed.uri.host),
                  key: const ValueKey('enrollServerLabel'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (parsed.userId.isEmpty) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('userIdField'),
                    controller: _userIdController,
                    readOnly: locked,
                    decoration: InputDecoration(labelText: l10n.fieldUserId),
                    autocorrect: false,
                    validator: (value) => (value ?? '').trim().isEmpty ? l10n.userIdRequired : null,
                  ),
                ],
                if (parsed.passphrase.isEmpty) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('passphraseField'),
                    controller: _passphraseController,
                    readOnly: locked,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l10n.fieldPassphrase),
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    validator: (value) => (value ?? '').isEmpty ? l10n.passphraseRequired : null,
                  ),
                ],
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('enrollNameField'),
                controller: _nameController,
                readOnly: locked,
                decoration: InputDecoration(labelText: l10n.fieldName),
                validator: (value) => (value == null || value.trim().isEmpty) ? l10n.fieldNameRequired : null,
              ),
              if (_busy && step != null) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(key: ValueKey('enrollProgress')),
                const SizedBox(height: 8),
                Text(switch (step) {
                  EnrollmentStep.contactingServer => l10n.enrollStepContacting,
                  EnrollmentStep.registering => l10n.enrollStepRegistering,
                }),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 24),
                Text(
                  error,
                  key: const ValueKey('enrollError'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _busy ? null : _leave, child: Text(l10n.cancelButton)),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('enrollSubmitButton'),
                    onPressed: _busy ? null : _submit,
                    child: Text(_enrolled != null ? l10n.saveButton : l10n.enrollButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpPinDialog extends StatefulWidget {
  const _OtpPinDialog({required this.policy});

  final SoftPinPolicy policy;

  @override
  State<_OtpPinDialog> createState() => _OtpPinDialogState();
}

class _OtpPinDialogState extends State<_OtpPinDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_formKey.currentState!.validate()) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final policy = widget.policy;
    return AlertDialog(
      title: Text(l10n.otpPinTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              policy.alphanumeric
                  ? l10n.otpPinMessageAlphanumeric(policy.minLength, policy.maxLength)
                  : l10n.otpPinMessage(policy.minLength, policy.maxLength),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('otpPinField'),
              controller: _controller,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.fieldPin),
              keyboardType: policy.alphanumeric ? TextInputType.visiblePassword : TextInputType.number,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              validator: (value) => policy.accepts(value ?? '') ? null : l10n.otpPinInvalid,
              onFieldSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        TextButton(key: const ValueKey('otpPinConfirmButton'), onPressed: _confirm, child: Text(l10n.continueButton)),
      ],
    );
  }
}
