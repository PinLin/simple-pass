import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/profile.dart';

/// Asks for [profile]'s challenge code; returns it once all digits are in and confirmed, or null on cancel.
Future<String?> showChallengeDialog(BuildContext context, {required Profile profile}) {
  return showDialog<String>(
    context: context,
    builder: (_) => ChallengeDialog(profile: profile),
  );
}

class ChallengeDialog extends StatefulWidget {
  const ChallengeDialog({super.key, required this.profile});

  final Profile profile;

  @override
  State<ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<ChallengeDialog> {
  final _controller = TextEditingController();

  int get _length => widget.profile.otpPolicy?.challengeLength ?? 0;
  bool get _complete => _controller.text.length == _length;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_complete) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.profile.name, overflow: TextOverflow.ellipsis),
      content: TextField(
        key: const ValueKey('challengeField'),
        controller: _controller,
        autofocus: true,
        maxLength: _length,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _confirm(),
        decoration: InputDecoration(labelText: l10n.challengeCodeLabel, hintText: l10n.challengeCodeHint(_length)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          key: const ValueKey('challengeConfirmButton'),
          onPressed: _complete ? _confirm : null,
          child: Text(l10n.okButton),
        ),
      ],
    );
  }
}
