import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/profile.dart';
import '../platform/keystore.dart';
import '../platform/screen_guard.dart';
import '../storage/profile_store.dart';
import '../storage/settings_store.dart';
import '../storage/storage_exceptions.dart';
import 'add_profile_sheet.dart';
import 'app_snack_bar.dart';
import 'challenge_dialog.dart';
import 'enrollment_screen.dart';
import 'load_error_view.dart';
import 'otp_helpers.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';

/// A challenge the user entered on a row and the response it produced; kept only in memory.
typedef _ChallengeAnswer = ({String challenge, String response});

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({
    super.key,
    required this.profileStore,
    required this.settingsStore,
    required this.screenGuard,
    @visibleForTesting this.now = DateTime.now,
  });

  final ProfileStore profileStore;
  final SettingsStore settingsStore;
  final ScreenGuard screenGuard;

  /// Clock for time-based codes.
  final DateTime Function() now;

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> with WidgetsBindingObserver {
  /// FAB height (56) + its bottom margin (16) + breathing room.
  static const _fabClearance = 88.0;

  // Null until a load succeeds; adding is disabled until then so a failed
  // or pending load can never be mistaken for "no profiles".
  List<Profile>? _profiles;
  bool _loadFailed = false;
  bool _unlocking = false;

  // App lock: the list shows only after one authentication per stay in the foreground.
  bool _appUnlocked = false;
  bool _autoPrompted = false;
  // Bumped whenever going to the background relocks, so work that resumes afterwards can tell.
  int _lockGeneration = 0;
  final _scrollController = ScrollController();

  // Set by an Enrollment page with a registration running or unsaved; relocking then covers it with
  // [_lockCover] instead of closing it.
  final _enrollmentPending = ValueNotifier<bool>(false);
  Route<void>? _lockCover;

  // Ids picked in selection mode; the mode is on exactly while this isn't empty.
  final _selected = <String>{};
  final _answers = <String, _ChallengeAnswer>{};
  int _reordersSaving = 0;
  bool _reorderFailed = false;

  static const _minimumReveal = Duration(seconds: 3);

  // With "Tap to reveal" on, codes stay masked except on these rows, each until its timer runs out.
  bool _tapToReveal = false;

  // App-wide protection as last loaded; null when undecided or unreadable.
  bool? _requireAuthSetting;
  final _revealed = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideAll();
    _scrollController.dispose();
    _enrollmentPending.dispose();
    super.dispose();
  }

  // Decrypted secrets only live while the app is in front. Pages and sheets
  // above this one may hold them too, so they go as well.
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    // From inactive on: the recents thumbnail is captured while the app is being paused.
    if (state != AppLifecycleState.resumed && state != AppLifecycleState.detached && _revealed.isNotEmpty) {
      setState(_hideAll);
    }
    if (state == AppLifecycleState.resumed) {
      _promptIfLocked();
      return;
    }
    if (state != AppLifecycleState.paused) return;
    final store = widget.profileStore;
    final duringPrompt = store.prompting;
    final dropped = await store.forget();
    if (!mounted) return;
    // Our own prompt can pause the app; only one that succeeded keeps it unlocked.
    if (duringPrompt && store.lastPromptSucceeded) return;
    final lockable = dropped || _requireAuthSetting == true || (_profiles?.any((p) => p.protected) ?? false);
    if (!lockable) return;
    final keepEnrollment = _enrollmentPending.value;
    if (!keepEnrollment) Navigator.of(context).popUntil((route) => route.isFirst);
    // An Undo or other snackbar must not outlive the lock.
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _profiles = null;
      _selected.clear();
      _appUnlocked = false;
      _autoPrompted = false;
      _lockGeneration++;
    });
    if (keepEnrollment && !(_lockCover?.isActive ?? false)) _pushLockCover();
    // No frames are drawn in the background, so popped pages would linger.
    SchedulerBinding.instance.scheduleForcedFrame();
    _load();
  }

  Future<void> _load() async {
    try {
      final profiles = await widget.profileStore.loadAll();
      final tapToReveal = await _loadTapToReveal();
      final requireAuth = await _loadRequireAuth();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _loadFailed = false;
        // Relocked and removed profiles drop theirs; an unlocked one keeps it across reloads.
        _answers.removeWhere((id, _) => !profiles.any((p) => p.id == id && !p.locked));
        _selected.removeWhere((id) => !profiles.any((p) => p.id == id));
        _tapToReveal = tapToReveal;
        _requireAuthSetting = requireAuth;
        if (!tapToReveal) _hideAll();
        for (final id in [..._revealed.keys]) {
          if (!profiles.any((p) => p.id == id && !p.locked)) _revealed.remove(id)?.cancel();
        }
      });
      // Before the platform call, so a slow or missing screen guard can't hold the prompt back.
      _promptIfLocked();
      await widget.screenGuard.setRecentsScreenshotEnabled(!profiles.any((p) => p.protected));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profiles = null;
        _loadFailed = true;
      });
    }
  }

  // An unreadable settings blob leaves codes shown, as they were before the option existed.
  Future<bool> _loadTapToReveal() async {
    try {
      return (await widget.settingsStore.load()).tapToReveal;
    } catch (_) {
      return false;
    }
  }

  Future<bool?> _loadRequireAuth() async {
    try {
      return (await widget.settingsStore.load()).requireAuth;
    } catch (_) {
      return null;
    }
  }

  /// Some profiles still sealed while app-wide protection is off: a switch-off that didn't finish.
  bool get _leftSealed => _requireAuthSetting == false && (_profiles?.any((p) => p.protected) ?? false);

  /// Unseals what an interrupted switch-off left sealed, after one authentication.
  Future<void> _unprotectAll() async {
    if (_unlocking) return;
    _unlocking = true;
    final l10n = AppLocalizations.of(context);
    try {
      final all = await widget.profileStore.setAllProtected(false);
      if (mounted) setState(() => _profiles = all);
    } on AuthFailedException catch (e) {
      final message = authResultMessage(l10n, e.result);
      if (mounted && message != null) _showMessage(message);
    } on KeyInvalidatedException {
      if (mounted) await offerToDeleteUnrecoverable(context, widget.profileStore);
    } catch (_) {
      if (mounted) _showMessage(l10n.saveFailedMessage);
    } finally {
      _unlocking = false;
    }
    await _load();
  }

  void _hideAll() {
    for (final timer in _revealed.values) {
      timer.cancel();
    }
    _revealed.clear();
  }

  /// Shows [profile]'s code until it changes (time-based) or for 30 seconds. A time-based code
  /// tapped in its last seconds stays shown through the next one too, so the reveal doesn't
  /// vanish right away; the copy is still the code valid at the tap, as without the option.
  void _reveal(Profile profile) {
    _revealed.remove(profile.id)?.cancel();
    final now = widget.now();
    var shownFor = const Duration(seconds: 30);
    if (profile.isTimeBased && profile.hasValidOtpParameters) {
      shownFor = Duration(seconds: secondsUntilProfileCode(profile, now), milliseconds: -now.millisecond);
      if (shownFor < _minimumReveal) shownFor += Duration(seconds: profile.timeStep!);
    }
    _revealed[profile.id] = Timer(shownFor, () {
      if (mounted) setState(() => _revealed.remove(profile.id));
    });
    setState(() {});
  }

  Future<void> _retry() async {
    setState(() => _loadFailed = false);
    await _load();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(appSnackBar(messenger, message));
  }

  /// Covers the page stack with the lock screen, without closing anything under it.
  void _pushLockCover() {
    final l10n = AppLocalizations.of(context);
    final route = PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => PopScope(
        canPop: false,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.appTitle), automaticallyImplyLeading: false),
          body: _LockScreen(onUnlock: _unlockApp),
        ),
      ),
    );
    _lockCover = route;
    Navigator.of(context).push(route);
  }

  void _removeLockCover() {
    final cover = _lockCover;
    if (cover == null || !mounted) return;
    _lockCover = null;
    if (cover.isActive) Navigator.of(context).removeRoute(cover);
  }

  /// After the screen lock was removed: deleting the sealed profiles (as offered for invalidated keys)
  /// also turns the app lock off, so the profiles in the clear are reachable again.
  Future<void> _offerLockReset() async {
    if (!await offerToDeleteUnrecoverable(context, widget.profileStore)) return;
    try {
      final settings = await widget.settingsStore.update((s) => s.copyWith(requireAuth: false));
      await widget.screenGuard.setSecure(!settings.allowScreenshots);
    } catch (_) {
      if (mounted) _showMessage(AppLocalizations.of(context).saveFailedMessage);
    }
  }

  // The system prompt shows once by itself per lock, and only with the app in front.
  void _promptIfLocked() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted || !_locked || _autoPrompted || (state != null && state != AppLifecycleState.resumed)) return;
    _autoPrompted = true;
    unawaited(_unlockApp());
  }

  /// Locked while app-wide protection is on, or anything is sealed (a switch-off that didn't finish),
  /// until [_unlockApp] succeeds.
  bool get _locked =>
      !_appUnlocked &&
      appLockActive(requireAuth: _requireAuthSetting, anySealed: _profiles?.any((p) => p.protected) ?? false);

  /// One authentication opens every profile (and seals any still in the clear) until the app goes to
  /// the background. A canceled or failed prompt leaves the lock screen up.
  Future<void> _unlockApp() async {
    if (_unlocking) return;
    _unlocking = true;
    final l10n = AppLocalizations.of(context);
    final generation = _lockGeneration;
    try {
      // Unreadable settings (null) seal too: a failure never leaves a secret in the clear.
      await widget.profileStore.unlockApp(sealUnprotected: _requireAuthSetting != false);
      if (!mounted) return;
      if (generation != _lockGeneration) {
        // The app went to the background while this was finishing; that lock stands.
        await widget.profileStore.forget();
        return;
      }
      setState(() => _appUnlocked = true);
      _removeLockCover();
    } on AuthFailedException catch (e) {
      // No screen lock any more: nothing can authenticate, so the lock can't stay.
      if (e.result == AuthResult.noCredentials) {
        if (mounted) await _offerLockReset();
      } else {
        final message = authResultMessage(l10n, e.result);
        if (mounted && message != null) _showMessage(message);
      }
    } on KeyInvalidatedException {
      if (mounted) await _offerLockReset();
    } catch (_) {
      if (mounted) _showMessage(l10n.saveFailedMessage);
    } finally {
      _unlocking = false;
    }
    if (mounted) await _load();
    if (mounted && !_locked) _removeLockCover();
  }

  /// Asks for the challenge code and puts the response on the row.
  Future<void> _openChallenge(Profile profile) async {
    final current = profile;
    final length = current.otpPolicy?.challengeLength;
    if (length == null || challengeResponseForProfile(current, '0' * length) == null) return;
    final challenge = await showChallengeDialog(context, profile: current);
    if (challenge == null || !mounted) return;
    final latest = _latest(current.id);
    if (latest == null || latest.locked) return;
    final response = challengeResponseForProfile(latest, challenge);
    if (response == null) return;
    setState(() => _answers[latest.id] = (challenge: challenge, response: response));
  }

  void _clearChallenge(String id) => setState(() => _answers.remove(id));

  Future<void> _add() async {
    final kind = await showAddProfileSheet(context);
    if (kind == null || !mounted) return;
    await _openEditor(null, kind);
  }

  Future<void> _openEditor([Profile? profile, ProfileKind kind = ProfileKind.activationCode]) async {
    // An Undo snackbar belongs to the list; left up across a route change it
    // could undo against a profile the editor just changed.
    final messenger = ScaffoldMessenger.of(context)..removeCurrentSnackBar();
    final saved = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => profile == null && kind == ProfileKind.mobilePassKey
            ? EnrollmentScreen(
                profileStore: widget.profileStore,
                settingsStore: widget.settingsStore,
                pending: _enrollmentPending,
              )
            : ProfileEditScreen(
                profileStore: widget.profileStore,
                settingsStore: widget.settingsStore,
                profile: profile,
                kind: kind,
              ),
      ),
    );
    // The page is gone; the flag's owner clears it, since the page can outlive this state at teardown.
    if (mounted) _enrollmentPending.value = false;
    messenger.removeCurrentSnackBar();
    if (saved == true && profile != null) _answers.remove(profile.id);
    await _load();
  }

  /// Consumes only the counter this row showed, against the latest stored
  /// profile, so a stale row can't burn the wrong counter.
  Future<void> _markUsed(Profile profile) async {
    final shownCounter = profile.counter;
    final generation = _lockGeneration;
    // A relock meanwhile cleared the list; nothing about this row may show on the lock screen.
    bool active() => mounted && generation == _lockGeneration;
    MarkUsedOutcome outcome;
    try {
      outcome = await markCounterUsed(widget.profileStore, profile.id, shownCounter);
    } catch (_) {
      if (!mounted || !active()) return;
      _showMessage(AppLocalizations.of(context).saveFailedMessage);
      await _load();
      return;
    }
    if (!mounted || !active()) return;
    final updated = outcome.profile;
    if (updated == null) return;
    _replaceProfile(updated);
    if (!outcome.marked) return;
    // The next code stays masked until asked for.
    if (_revealed.remove(profile.id) case final timer?) setState(timer.cancel);
    showMarkedUsedSnackBar(
      context,
      store: widget.profileStore,
      profileId: profile.id,
      counter: shownCounter,
      active: active,
      onUpdated: (p) {
        if (mounted) _replaceProfile(p);
      },
      onSaveFailed: () {
        if (mounted) _load();
      },
    );
  }

  void _replaceProfile(Profile updated) {
    final profiles = _profiles;
    if (profiles == null) return;
    final index = profiles.indexWhere((p) => p.id == updated.id);
    if (index == -1) return;
    setState(() => profiles[index] = updated);
  }

  Profile? _latest(String id) => _profiles?.where((p) => p.id == id).firstOrNull;

  /// Works from the latest loaded profile, since a ✓ may have landed.
  Future<void> _edit(String id) async {
    final profile = _latest(id);
    if (profile == null || profile.locked) return;
    await _openEditor(profile);
  }

  void _startSelecting(String id) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _selected.add(id));
  }

  void _toggleSelected(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _stopSelecting() => setState(_selected.clear);

  /// Deletes every selected profile in one write, locked ones included, after confirming.
  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final ids = {..._selected};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle(ids.length)),
        content: Text(l10n.deleteSelectedConfirmMessage(ids.length)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.deleteConfirmButton)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.profileStore.update((current) => current.where((p) => !ids.contains(p.id)).toList());
      if (!mounted) return;
      setState(() {
        _selected.removeAll(ids);
        for (final id in ids) {
          _answers.remove(id);
          _revealed.remove(id)?.cancel();
        }
      });
    } catch (_) {
      if (mounted) _showMessage(l10n.saveFailedMessage);
    }
    await _load();
  }

  Future<void> _openSettings() async {
    final generation = _lockGeneration;
    var lockEnabled = false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settingsStore: widget.settingsStore,
          screenGuard: widget.screenGuard,
          profileStore: widget.profileStore,
          onLockEnabled: () => lockEnabled = true,
        ),
      ),
    );
    // Coming back never unlocks by itself; switching the lock on there authenticated, unless the app
    // relocked meanwhile (which also closed Settings).
    if (lockEnabled && generation == _lockGeneration) _appUnlocked = true;
    await _load();
  }

  /// Saves right away, against the latest stored list. After a failed save the rows are reloaded once
  /// every pending drag's save is done: a later drag may still change what's stored.
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final profiles = _profiles;
    if (profiles == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    setState(() => profiles.insert(newIndex, profiles.removeAt(oldIndex)));
    _reordersSaving++;
    try {
      await widget.profileStore.reorder([for (final p in profiles) p.id]);
    } catch (_) {
      _reorderFailed = true;
      if (mounted) _showMessage(AppLocalizations.of(context).saveFailedMessage);
    } finally {
      _reordersSaving--;
    }
    if (_reordersSaving > 0 || !_reorderFailed || !mounted) return;
    _reorderFailed = false;
    await _load();
  }

  // Not while selecting: the banner's button would act on profiles the user is busy rearranging.
  Widget _withBanner(AppLocalizations l10n, Widget body) {
    if (_selected.isNotEmpty || !_leftSealed) return body;
    return Column(
      children: [
        MaterialBanner(
          key: const ValueKey('protectionBanner'),
          content: Text(l10n.protectedProfilesBanner),
          leading: const Icon(Icons.lock_outline),
          actions: [
            TextButton(
              key: const ValueKey('protectionBannerButton'),
              onPressed: _unprotectAll,
              child: Text(l10n.unprotectNowButton),
            ),
          ],
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _row(Profile profile) {
    // A challenge response is shown as soon as the user asks for it.
    final masked = _tapToReveal && !profile.isChallengeResponse && !_revealed.containsKey(profile.id);
    Widget row() => _ProfileRow(
      profile: profile,
      now: widget.now(),
      masked: masked,
      answer: _answers[profile.id],
      onChallenge: () => _openChallenge(profile),
      onSelect: () => _startSelecting(profile.id),
      onEdit: () => _edit(profile.id),
      onCopy: (otp) {
        if (masked) _reveal(profile);
        copyCodeWithSnackBar(context, widget.settingsStore, profile, otp);
      },
      onMarkUsed: profile.isChallengeResponse ? () => _clearChallenge(profile.id) : () => _markUsed(profile),
    );
    return profile.isTimeBased && !profile.locked
        ? _EverySecond(key: ValueKey('ticker-${profile.id}'), now: widget.now, builder: row)
        : row();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profiles = _profiles;
    final selecting = _selected.isNotEmpty && profiles != null;

    // Nothing about the profiles shows, not even how many there are.
    if (profiles != null && !_loadFailed && _locked) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: _LockScreen(onUnlock: _unlockApp),
      );
    }

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  key: const ValueKey('endSelectionButton'),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: _stopSelecting,
                ),
                title: Text(l10n.selectedCount(_selected.length)),
                actions: [
                  IconButton(
                    key: const ValueKey('deleteSelectedButton'),
                    tooltip: l10n.deleteProfileButton,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _deleteSelected,
                  ),
                ],
              )
            : AppBar(
                title: Text(l10n.appTitle),
                // Only from the list itself: never while loading, after a failed load, or locked.
                actions: [
                  if (profiles != null && !_loadFailed)
                    IconButton(tooltip: l10n.settingsTitle, icon: const Icon(Icons.settings), onPressed: _openSettings),
                ],
              ),
        body: _withBanner(
          l10n,
          _loadFailed
              ? LoadErrorView(onRetry: _retry)
              : profiles == null
              ? const Center(child: CircularProgressIndicator())
              : profiles.isEmpty
              ? _EmptyState(message: l10n.profileListEmpty)
              // One list in both modes, so entering or leaving selection keeps the scroll position. Rows
              // get a drag listener only while selecting: long-press then drag moves a row, a plain drag
              // scrolls, and a tap toggles selection.
              : ReorderableListView.builder(
                  scrollController: _scrollController,
                  buildDefaultDragHandles: false,
                  // Keeps the last row's trailing control clear of the FAB.
                  padding: const EdgeInsets.only(bottom: _fabClearance),
                  itemCount: profiles.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final item = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        selecting
                            ? _ProfileRow.select(
                                profile: profile,
                                selected: _selected.contains(profile.id),
                                onToggle: () => _toggleSelected(profile.id),
                              )
                            : _row(profile),
                        if (index < profiles.length - 1) const Divider(height: 1),
                      ],
                    );
                    return selecting
                        ? ReorderableDelayedDragStartListener(
                            key: ValueKey('selectRow-${profile.id}'),
                            index: index,
                            child: item,
                          )
                        : KeyedSubtree(key: ValueKey('row-${profile.id}'), child: item);
                  },
                ),
        ),
        floatingActionButton: selecting
            ? null
            : FloatingActionButton(
                tooltip: l10n.addProfileTooltip,
                onPressed: profiles == null ? null : _add,
                child: const Icon(Icons.add),
              ),
      ),
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(l10n.appLockedMessage, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('unlockAppButton'),
              onPressed: onUnlock,
              icon: const Icon(Icons.fingerprint),
              label: Text(l10n.unlockButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// One list row: tap copies the code (or unlocks, or asks for a challenge), long press selects, › edits.
/// The [select] variant masks the code and drops the buttons.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.now,
    required this.masked,
    required this.answer,
    required VoidCallback this.onSelect,
    required VoidCallback this.onEdit,
    required ValueChanged<String> this.onCopy,
    required VoidCallback this.onMarkUsed,
    required VoidCallback this.onChallenge,
  }) : selecting = false,
       selected = false,
       onToggle = null;

  _ProfileRow.select({required this.profile, required this.selected, required VoidCallback this.onToggle})
    : selecting = true,
      now = DateTime.fromMillisecondsSinceEpoch(0),
      masked = false,
      answer = null,
      onSelect = null,
      onEdit = null,
      onCopy = null,
      onMarkUsed = null,
      onChallenge = null;

  final Profile profile;
  final DateTime now;

  /// Hides an available code behind dots until the row is tapped ("Tap to reveal").
  final bool masked;
  final _ChallengeAnswer? answer;
  final VoidCallback? onSelect;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onCopy;
  final VoidCallback? onMarkUsed;
  final VoidCallback? onChallenge;

  /// Selection mode: codes are masked, buttons hidden, and a tap calls [onToggle].
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Codes are masked in selection mode; a profile still sealed after unlocking (damaged) simply has none.
    final locked = selecting;
    final challengeLength = profile.otpPolicy?.challengeLength;
    // A probe answer tells whether the stored data can answer challenges at all.
    final challengeReady =
        !locked && challengeLength != null && challengeResponseForProfile(profile, '0' * challengeLength) != null;
    final answer = challengeReady ? this.answer : null;
    final awaitingChallenge = challengeReady && answer == null;
    final otp = locked
        ? null
        : challengeLength != null
        ? answer?.response
        : otpForProfile(profile, now: now);
    final notYet = !locked && clockBeforeEpoch(profile, now);
    final timeStep = profile.isTimeBased && profile.hasValidOtpParameters ? profile.timeStep : null;
    final hideCode = masked && !locked && otp != null;
    final atMax = profile.usesCounter && profile.isAtMaxCounter;
    final subtleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
    );

    final codeStyle = theme.textTheme.displayMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // Loose, so the counter stays right after the name, yet the name may take every bit of width
            // the counter and the buttons leave; the ellipsis only when it really doesn't fit.
            Flexible(
              child: Text(
                profile.name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if ((otp != null || (selecting && !profile.locked)) && profile.usesCounter) ...[
              const SizedBox(width: 8),
              Text(l10n.profileCounterCompactLabel(profile.counter), style: subtleStyle),
            ] else if (answer != null) ...[
              const SizedBox(width: 8),
              Semantics(
                label: l10n.challengeCodeSemanticsLabel(answer.challenge),
                child: ExcludeSemantics(
                  child: Text(answer.challenge, key: ValueKey('challengeLabel-${profile.id}'), style: subtleStyle),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        if (locked || awaitingChallenge || hideCode)
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _LockedCodePlaceholder(
                key: hideCode ? ValueKey('maskedCode-${profile.id}') : const ValueKey('lockedCodePlaceholder'),
                digits: profile.codeDigits,
                style: codeStyle,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          )
        // The clock isn't set yet: no code, and no error either; the row fills in once it is.
        else if (notYet)
          Padding(
            key: ValueKey('codeNotYet-${profile.id}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('', style: codeStyle),
          )
        else if (otp == null)
          Text(
            profile.holdsKey ? l10n.profileKeyInvalid : l10n.activationCodeInvalid,
            style: TextStyle(color: theme.colorScheme.error),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(formatOtpForDisplay(otp), style: codeStyle?.copyWith(color: theme.colorScheme.onSurface)),
          ),
      ],
    );

    final status = challengeLength != null && answer == null
        ? SizedBox.square(
            dimension: 48,
            child: Icon(
              Icons.dialpad,
              key: ValueKey('profileChallenge-${profile.id}'),
              size: 32,
              color: challengeReady ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          )
        : notYet
        ? const SizedBox.square(dimension: 48)
        : timeStep != null
        ? _Countdown(
            key: ValueKey('profileCountdown-${profile.id}'),
            remaining: secondsUntilProfileCode(profile, now),
            timeStep: timeStep,
          )
        // Swallows the tap when ✓ is disabled, so it doesn't fall through to copying.
        : GestureDetector(
            onTap: () {},
            excludeFromSemantics: true,
            child: IconButton(
              tooltip: l10n.markUsedButton,
              icon: const Icon(Icons.check),
              iconSize: 32,
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                disabledForegroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.38),
              ),
              onPressed: (otp == null || atMax) ? null : onMarkUsed,
            ),
          );

    final layout = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 112),
      child: Row(
        children: [
          Expanded(
            child: Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14), child: content),
          ),
          if (!selecting) ...[
            status,
            IconButton(
              key: ValueKey('profileEdit-${profile.id}'),
              tooltip: l10n.editButton,
              icon: const Icon(Icons.chevron_right),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: onEdit,
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
    if (selecting) {
      // Opaque, so a dragged row doesn't show the rows beneath it.
      return Semantics(
        button: true,
        selected: selected,
        onTapHint: selected ? l10n.deselectAction : l10n.selectAction,
        child: Material(
          color: selected ? theme.colorScheme.secondaryContainer : theme.colorScheme.surface,
          child: InkWell(key: ValueKey('profileRowSelect-${profile.id}'), onTap: onToggle, child: layout),
        ),
      );
    }

    final VoidCallback? onTap = awaitingChallenge ? onChallenge : (otp == null ? null : () => onCopy!(otp));
    return Semantics(
      button: true,
      onTapHint: awaitingChallenge
          ? l10n.enterChallengeCodeAction
          : (otp == null ? null : (hideCode ? l10n.revealCodeAction : l10n.copyCodeAction)),
      onLongPressHint: l10n.selectAction,
      child: InkWell(key: ValueKey('profileRowCopy-${profile.id}'), onTap: onTap, onLongPress: onSelect, child: layout),
    );
  }
}

/// Rebuilds [builder] on every second boundary of [now], for rows whose code follows the clock.
class _EverySecond extends StatefulWidget {
  const _EverySecond({super.key, required this.now, required this.builder});

  final DateTime Function() now;
  final Widget Function() builder;

  @override
  State<_EverySecond> createState() => _EverySecondState();
}

class _EverySecondState extends State<_EverySecond> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer = Timer(Duration(milliseconds: 1000 - widget.now().millisecond), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}

/// Seconds left on a time-based code, in the 48 dp slot the ✓ button takes on event-based rows.
class _Countdown extends StatelessWidget {
  const _Countdown({super.key, required this.remaining, required this.timeStep});

  final int remaining;
  final int timeStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: AppLocalizations.of(context).codeRefreshCountdown(remaining),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: SizedBox.square(
              dimension: 32,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: remaining / timeStep,
                    strokeWidth: 3,
                    color: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                  ),
                  Center(
                    child: Text(
                      '$remaining',
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One dot per digit, each laid over an invisible "0" so the placeholder is
/// exactly as wide as the code it stands in for ("000 000" or "0000 0000").
class _LockedCodePlaceholder extends StatelessWidget {
  const _LockedCodePlaceholder({super.key, required this.digits, required this.style, required this.color});

  final int digits;
  final TextStyle? style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hidden = style?.copyWith(color: Colors.transparent);
    final dotSize = (style?.fontSize ?? 45) * 0.26;
    Widget slot(String char) => Stack(
      alignment: Alignment.center,
      children: [
        Text(char, style: hidden),
        if (char != ' ')
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    );
    final pattern = formatOtpForDisplay('0' * digits);
    return Row(mainAxisSize: MainAxisSize.min, children: pattern.split('').map(slot).toList());
  }
}
