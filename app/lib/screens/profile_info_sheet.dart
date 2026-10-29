import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/profile.dart';
import '../storage/settings_store.dart';
import 'otp_helpers.dart';

/// A MobilePASS profile's registration data, in a route so the app lock can dismiss it along with the
/// editor.
Future<void> showRegistrationInfoSheet(
  BuildContext context, {
  required Profile profile,
  required SettingsStore settingsStore,
}) async {
  if (profile.locked) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final data = profile.registration;
      Widget field(String id, String label, String value, {bool sensitive = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ReadOnlyInfoField(
          id: id,
          label: label,
          value: value,
          sensitive: sensitive,
          settingsStore: settingsStore,
        ),
      );
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: ListView(
              key: const ValueKey('registrationInfoSheet'),
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        profile.kind == ProfileKind.mobilePassKey
                            ? l10n.addKindEnrollmentString
                            : l10n.addKindActivationCode,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('closeProfileInfoButton'),
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (data != null) field('enrollmentStringField', l10n.fieldEnrollmentString, data.enrollmentString),
                if (!profile.holdsKey) field('activationCodeField', l10n.fieldActivationCode, profile.activationCode),
                if (profile.serial.isNotEmpty) field('serialField', l10n.fieldSerial, profile.serial, sensitive: false),
                field('policyField', l10n.fieldPolicy, profile.policy, sensitive: false),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A read-only value with a copy button; a [sensitive] one starts hidden behind an eye.
class ReadOnlyInfoField extends StatefulWidget {
  const ReadOnlyInfoField({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.sensitive,
    required this.settingsStore,
  });
  final String id;
  final String label;
  final String value;
  final bool sensitive;
  final SettingsStore settingsStore;

  @override
  State<ReadOnlyInfoField> createState() => _ReadOnlyInfoFieldState();
}

class _ReadOnlyInfoFieldState extends State<ReadOnlyInfoField> {
  bool _shown = false;

  String get _toggleKey => switch (widget.id) {
    'activationCodeField' => 'toggleActivationCodeVisibility',
    'mobilePassSecretField' => 'toggleMobilePassSecretVisibility',
    'secretField' => 'toggleSecretVisibility',
    _ => 'toggle-${widget.id}',
  };
  String get _copyKey => switch (widget.id) {
    'activationCodeField' => 'copyActivationCodeButton',
    'mobilePassSecretField' => 'copyMobilePassSecretButton',
    'secretField' => 'copySecretButton',
    _ => 'copy-${widget.id}',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      key: ValueKey(widget.id),
      initialValue: widget.value,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.value.isEmpty ? l10n.notSetValue : null,
        hintStyle: TextStyle(color: readOnlyValueColor(Theme.of(context).colorScheme)),
        floatingLabelBehavior: widget.value.isEmpty ? FloatingLabelBehavior.always : null,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.sensitive)
              IconButton(
                key: ValueKey(_toggleKey),
                tooltip: _shown ? l10n.hideSecretTooltip : l10n.showSecretTooltip,
                icon: Icon(_shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _shown = !_shown),
              ),
            if (widget.value.isNotEmpty)
              IconButton(
                key: ValueKey(_copyKey),
                tooltip: l10n.copyFieldTooltip,
                icon: const Icon(Icons.copy),
                onPressed: () => copySensitiveWithSnackBar(
                  context,
                  widget.settingsStore,
                  widget.value,
                  widget.id == 'activationCodeField'
                      ? l10n.copiedActivationCodeMessage
                      : widget.id.endsWith('SecretField') || widget.id == 'secretField'
                      ? l10n.copiedSecretMessage
                      : l10n.copiedFieldMessage,
                ),
              ),
          ],
        ),
      ),
      obscureText: widget.sensitive && !_shown,
      readOnly: true,
      canRequestFocus: false,
      showCursor: false,
      style: TextStyle(color: readOnlyValueColor(Theme.of(context).colorScheme)),
    );
  }
}
