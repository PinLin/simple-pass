import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/settings.dart';
import '../platform/screen_guard.dart';
import '../platform/device_info.dart';
import '../platform/keystore.dart';
import '../storage/profile_store.dart';
import '../storage/settings_store.dart';
import '../storage/storage_exceptions.dart';
import 'app_snack_bar.dart';
import 'load_error_view.dart';
import 'otp_helpers.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsStore,
    required this.screenGuard,
    required this.profileStore,
    this.deviceInfo = const DeviceInfo(),
    this.onLockEnabled,
  });

  final SettingsStore settingsStore;
  final ScreenGuard screenGuard;

  /// Sealed or unsealed all at once by "Require authentication to open the app".
  final ProfileStore profileStore;

  /// API level source, for whether the app lock has to block screenshots too.
  final DeviceInfo deviceInfo;

  /// Called after the app lock was switched on with a successful authentication, the only way leaving
  /// this page may count as unlocked.
  final VoidCallback? onLockEnabled;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Null while loading or after a failed load; the switches (the only
  // writers) are hidden in both cases.
  Settings? _settings;
  bool _loadFailed = false;
  bool _changingAuth = false;
  int? _sdkInt;
  bool _sdkKnown = false;
  // Whether anything is still sealed, as last seen; unreadable counts as sealed.
  bool _anySealed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Not awaited: until it answers the API level counts as unknown, which errs on the secure side.
    if (!_sdkKnown) {
      _sdkKnown = true;
      unawaited(
        widget.deviceInfo.sdkInt().then((sdkInt) {
          if (mounted) setState(() => _sdkInt = sdkInt);
        }),
      );
    }
    try {
      final settings = await widget.settingsStore.load();
      final anySealed = await _loadAnySealed();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _anySealed = anySealed;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _settings = null;
        _loadFailed = true;
      });
    }
  }

  Future<void> _retry() async {
    setState(() => _loadFailed = false);
    await _load();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(appSnackBar(messenger, message));
  }

  /// Applies [mutate] to the store's latest value (not the stale [_settings]); null if the save failed.
  Future<Settings?> _save(Settings Function(Settings current) mutate) async {
    Settings updated;
    try {
      updated = await widget.settingsStore.update(mutate);
    } catch (_) {
      if (mounted) _showMessage(AppLocalizations.of(context).saveFailedMessage);
      return null;
    }
    if (!mounted) return null;
    setState(() => _settings = updated);
    return updated;
  }

  Future<void> _setAllowScreenshots(bool value) async {
    final updated = await _save((current) => current.copyWith(allowScreenshots: value));
    // FLAG_SECURE must match what actually got saved, not the tapped value,
    // in case a later overlapping toggle changed allowScreenshots again.
    if (updated != null) await _applySecure(updated);
  }

  bool _lockBlocksScreenshots(Settings settings) => secureWindow(
    allowScreenshots: true,
    appLock: appLockActive(requireAuth: settings.requireAuth, anySealed: _anySealed),
    sdkInt: _sdkInt,
  );

  Future<bool> _loadAnySealed() =>
      widget.profileStore.loadAll().then((all) => all.any((p) => p.protected), onError: (_) => true);

  // Same rule as at startup: anything still sealed keeps the lock, and with it the window, secure.
  Future<void> _applySecure(Settings settings) async {
    final anySealed = await _loadAnySealed();
    if (mounted) setState(() => _anySealed = anySealed);
    await widget.screenGuard.setSecure(
      secureWindow(
        allowScreenshots: settings.allowScreenshots,
        appLock: appLockActive(requireAuth: settings.requireAuth, anySealed: anySealed),
        sdkInt: _sdkInt,
      ),
    );
  }

  /// Seals or unseals every profile after one authentication, then records the choice. Turning it
  /// on warns first that removing the screen lock would make the profiles unrecoverable.
  Future<void> _setRequireAuth(bool value) async {
    if (_changingAuth) return;
    final l10n = AppLocalizations.of(context);
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(l10n.requireAuthWarningMessage),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.cancelButton)),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.requireAuthConfirmButton),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _changingAuth = true);
    final before = _settings?.requireAuth;
    // The setting goes first, so a crash in between leaves profiles that disagree with it, which the
    // list offers to fix; a failure to reseal puts the setting back.
    if (await _save((s) => s.copyWith(requireAuth: value)) == null) {
      if (mounted) setState(() => _changingAuth = false);
      return;
    }
    try {
      await widget.profileStore.setAllProtected(value);
      if (_settings case final settings?) await _applySecure(settings);
      if (value) widget.onLockEnabled?.call();
    } on AuthFailedException catch (e) {
      await _restoreRequireAuth(before);
      final message = authResultMessage(l10n, e.result);
      if (mounted && message != null) _showMessage(message);
    } on KeyInvalidatedException {
      await _restoreRequireAuth(before);
      if (mounted) await offerToDeleteUnrecoverable(context, widget.profileStore);
    } catch (_) {
      await _restoreRequireAuth(before);
      if (mounted) _showMessage(l10n.saveFailedMessage);
    }
    if (mounted) setState(() => _changingAuth = false);
  }

  Future<void> _restoreRequireAuth(bool? before) async {
    try {
      final restored = await widget.settingsStore.update(
        (s) => Settings.fromJson({...s.toJson(), 'requireAuth': before}),
      );
      if (mounted) setState(() => _settings = restored);
    } catch (_) {
      // Left to the list's mismatch banner.
    }
  }

  Future<void> _pickClipboardClear(ClipboardClear current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<ClipboardClear>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.clipboardClearLabel),
        children: [
          for (final option in ClipboardClear.values)
            ListTile(
              title: Text(clipboardClearLabel(l10n, option)),
              trailing: option == current
                  ? Icon(Icons.check, color: Theme.of(dialogContext).colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(option),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await _save((s) => s.copyWith(clipboardClear: picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = _settings;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: _loadFailed
          ? LoadErrorView(onRetry: _retry)
          : settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  key: const ValueKey('requireAuthSwitch'),
                  title: Text(l10n.requireAuthLabel),
                  subtitle: Text(l10n.requireAuthSubtitle),
                  value: settings.requireAuth ?? false,
                  onChanged: _changingAuth ? null : _setRequireAuth,
                ),
                // Shown as "Block screenshots" over the stored allowScreenshots, so saved choices keep
                // their meaning.
                SwitchListTile(
                  key: const ValueKey('blockScreenshotsSwitch'),
                  title: Text(l10n.blockScreenshotsLabel),
                  subtitle: Text(
                    _lockBlocksScreenshots(settings)
                        ? '${l10n.blockScreenshotsSubtitle}\n${l10n.allowScreenshotsLockNote}'
                        : l10n.blockScreenshotsSubtitle,
                  ),
                  value: !settings.allowScreenshots,
                  onChanged: (block) => _setAllowScreenshots(!block),
                ),
                SwitchListTile(
                  key: const ValueKey('tapToRevealSwitch'),
                  title: Text(l10n.tapToRevealLabel),
                  subtitle: Text(l10n.tapToRevealSubtitle),
                  value: settings.tapToReveal,
                  onChanged: (value) => _save((s) => s.copyWith(tapToReveal: value)),
                ),
                ListTile(
                  key: const ValueKey('clipboardClearTile'),
                  title: Text(l10n.clipboardClearLabel),
                  subtitle: Text(clipboardClearLabel(l10n, settings.clipboardClear)),
                  onTap: () => _pickClipboardClear(settings.clipboardClear),
                ),
                ListTile(
                  key: const ValueKey('licensesTile'),
                  title: Text(l10n.openSourceLicensesLabel),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: l10n.appTitle,
                    applicationLegalese: '© 2026 Pin Lin',
                  ),
                ),
              ],
            ),
    );
  }
}

String clipboardClearLabel(AppLocalizations l10n, ClipboardClear value) => switch (value) {
  ClipboardClear.never => l10n.clipboardClearNever,
  ClipboardClear.thirtySeconds => l10n.clipboardClearSeconds(30),
  ClipboardClear.oneMinute => l10n.clipboardClearMinutes(1),
  ClipboardClear.twoMinutes => l10n.clipboardClearMinutes(2),
  ClipboardClear.fiveMinutes => l10n.clipboardClearMinutes(5),
};
