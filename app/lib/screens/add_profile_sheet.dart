import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/profile.dart';

/// Asks which kind of profile to add; null when dismissed.
Future<ProfileKind?> showAddProfileSheet(BuildContext context) => showModalBottomSheet<ProfileKind>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) {
    final l10n = AppLocalizations.of(sheetContext);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l10n.addProfileTitle, style: Theme.of(sheetContext).textTheme.titleLarge),
          ),
          ListTile(
            key: const ValueKey('addKindActivationCode'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.key),
            title: Text(l10n.addKindActivationCode),
            subtitle: Text(l10n.addKindActivationCodeSubtitle),
            onTap: () => Navigator.of(sheetContext).pop(ProfileKind.activationCode),
          ),
          ListTile(
            key: const ValueKey('addKindEnrollmentString'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(l10n.addKindEnrollmentString),
            subtitle: Text(l10n.addKindEnrollmentStringSubtitle),
            onTap: () => Navigator.of(sheetContext).pop(ProfileKind.mobilePassKey),
          ),
          ListTile(
            key: const ValueKey('addKindTotp'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.qr_code_2),
            title: Text(l10n.addKindTotpMenuTitle),
            subtitle: Text(l10n.addKindTotpSubtitle),
            onTap: () => Navigator.of(sheetContext).pop(ProfileKind.totp),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  },
);
