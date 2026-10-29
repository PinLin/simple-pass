import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Shown in place of a screen's content when stored data failed to load.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.onRetry, this.extra});

  final VoidCallback onRetry;

  /// Shown below the retry button, e.g. a way out when retrying can't help.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(l10n.loadErrorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.retryButton)),
            if (extra case final extra?) ...[const SizedBox(height: 24), extra],
          ],
        ),
      ),
    );
  }
}
