import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/screens/settings_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';

Profile _work() => Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5, pin: '1234');
Profile _home() => Profile(id: 'b2', name: 'Home', activationCode: _code, counter: 7);

/// Reads can be held back or made to fail per store, like a slow or broken Keystore.
class _Backend extends MemoryKeyValueBackend {
  bool failProfileReads = false;
  bool failSettingsReads = false;
  Completer<void>? profileGate;

  @override
  Future<String?> read(String key) async {
    if (key == ProfileStore.storageKey) {
      await profileGate?.future;
      if (failProfileReads) throw PlatformException(code: 'decrypt', message: 'bad key');
    }
    if (key == SettingsStore.storageKey && failSettingsReads) {
      throw PlatformException(code: 'decrypt', message: 'bad key');
    }
    return super.read(key);
  }
}

void main() {
  late _Backend backend;
  late FakeKeystore keystore;
  late ProfileStore store;
  late List<MethodCall> guardCalls;

  setUp(() async {
    backend = _Backend();
    keystore = FakeKeystore();
    store = ProfileStore(backend, keystore: keystore);
    await store.saveAll([_work(), _home()]);
    guardCalls = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), (call) async {
      guardCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel(SensitiveClipboard.channelName),
      (call) async => call.method == 'clearIfMatches' ? 'cleared' : null,
    );
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), null);
    messenger.setMockMethodCallHandler(const MethodChannel(SensitiveClipboard.channelName), null);
  });

  String raw() => backend.rawValue(ProfileStore.storageKey)!;
  Map<String, dynamic> entry(String id) =>
      ((jsonDecode(raw()) as Map)['profiles'] as List).cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == id);
  bool sealed(String id) => entry(id).containsKey('sealed');
  Future<bool?> storedRequireAuth() async => (await SettingsStore(backend).load()).requireAuth;

  Future<void> protect(String id) => store.updateProfile(id, (p) => p.copyWith(protected: true));

  /// The app went to the background and the key's validity window ran out.
  void away() {
    store.forget();
    keystore.expire();
  }

  /// Protected profiles whose window ran out, the way a cold start finds them.
  Future<void> coldStart({bool? auth, bool sealWork = true}) async {
    if (sealWork) await protect('a1');
    if (auth != null) await SettingsStore(backend).save(Settings(requireAuth: auth));
    away();
    keystore.authenticateCalls = 0;
  }

  Future<void> pumpList(WidgetTester tester, {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLocalized(
      tester,
      ProfileListScreen(profileStore: store, settingsStore: SettingsStore(backend), screenGuard: ScreenGuard()),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> background(WidgetTester tester) async {
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
  }

  /// The system prompt pauses the app while it is up, the way the real one can.
  void pauseDuringPrompt(WidgetTester tester) {
    keystore.duringPrompt = () async {
      keystore.duringPrompt = null;
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
    };
  }

  String otp(int counter) => formatOtpForDisplay(generateMobilePassOtp(_code, counter));
  final settingsButton = find.byTooltip('Settings');
  final unlockButton = find.byKey(const ValueKey('unlockAppButton'));
  final lockedText = find.text('SimplePASS is locked');

  void expectLockScreen() {
    expect(lockedText, findsOneWidget);
    expect(unlockButton, findsOneWidget);
    expect(find.text('Work'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(settingsButton, findsNothing);
  }

  bool lastSecure() => guardCalls.lastWhere((c) => c.method == 'setSecure').arguments['secure'] as bool;

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  Future<void> turnLockOn(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('requireAuthSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Turn on')));
    await tester.pumpAndSettle();
  }

  group('the Settings button does not open a way around the lock', () {
    testWidgets('the lock screen has no Settings button, whether requireAuth is on or only a profile is sealed', (
      tester,
    ) async {
      await coldStart(auth: true);
      keystore.authResults.add(AuthResult.canceled);
      await pumpList(tester);
      expectLockScreen();

      await tester.pumpWidget(const SizedBox());
      await coldStart(auth: null, sealWork: false);
      await SettingsStore(backend).save(const Settings());
      keystore.authResults.add(AuthResult.canceled);
      await pumpList(tester);
      expectLockScreen();
    });

    testWidgets('while the profiles are still loading there is no Settings button', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      backend.profileGate = Completer<void>();
      await pumpList(tester, settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(settingsButton, findsNothing);

      backend.profileGate!.complete();
      await tester.pumpAndSettle();
      expect(settingsButton, findsOneWidget);
    });

    testWidgets('after a failed load there is no Settings button until a retry succeeds', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      backend.failProfileReads = true;
      await pumpList(tester);
      expect(find.text('Work'), findsNothing);
      expect(settingsButton, findsNothing);

      backend.failProfileReads = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
      expect(settingsButton, findsOneWidget);
    });

    testWidgets('an unlocked app that opens Settings and comes back stays unlocked, with no new prompt', (
      tester,
    ) async {
      await coldStart(auth: true);
      await pumpList(tester);
      expect(keystore.authenticateCalls, 1);
      expect(find.text(otp(5)), findsOneWidget);

      await openSettings(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(lockedText, findsNothing);
      expect(find.text(otp(5)), findsOneWidget);
      expect(keystore.authenticateCalls, 1);
    });

    testWidgets('with the lock off, opening Settings and coming back changes nothing', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      await pumpList(tester);
      await openSettings(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(otp(5)), findsOneWidget);
      expect(keystore.authenticateCalls, 0);
      expect(await storedRequireAuth(), isFalse);
    });

    for (final auth in [true, false]) {
      testWidgets('requireAuth=$auth: backgrounding inside Settings relocks, and closing Settings does not unlock', (
        tester,
      ) async {
        // With the lock off the sealed profile is what keeps the app locked (a switch-off that didn't finish).
        await coldStart(auth: auth);
        await pumpList(tester);
        expect(find.text(otp(5)), findsOneWidget);
        await openSettings(tester);

        keystore.authResults.add(AuthResult.canceled);
        await background(tester);
        await resume(tester);

        expect(find.byType(SettingsScreen), findsNothing, reason: 'the relock closed the page');
        expectLockScreen();
        expect(keystore.authenticateCalls, 2, reason: 'one by itself on the first open, one on resuming');
        await tester.pumpAndSettle(const Duration(seconds: 5));
        expectLockScreen();
      });
    }

    testWidgets('turning the lock on in Settings and coming back: unlocked, and no second prompt', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      await pumpList(tester);
      await openSettings(tester);
      await turnLockOn(tester);
      expect(keystore.authenticateCalls, 1);
      expect(await storedRequireAuth(), isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(lockedText, findsNothing);
      expect(find.text(otp(5)), findsOneWidget);
      expect(keystore.authenticateCalls, 1);
      expect(sealed('a1') && sealed('b2'), isTrue);
    });

    testWidgets('turning the lock on, then backgrounding inside Settings: relocked, closing Settings does not unlock', (
      tester,
    ) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      await pumpList(tester);
      await openSettings(tester);
      await turnLockOn(tester);
      expect(await storedRequireAuth(), isTrue);

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      await resume(tester);
      expectLockScreen();
    });

    testWidgets('a canceled authentication while turning the lock on leaves the app as it was', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      await pumpList(tester);
      await openSettings(tester);
      keystore.authResults.add(AuthResult.canceled);
      await turnLockOn(tester);
      expect(find.text('Authentication canceled'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(await storedRequireAuth(), isFalse);
      expect(lockedText, findsNothing);
      expect(find.text(otp(5)), findsOneWidget);
      expect(raw(), contains(_code), reason: 'nothing was sealed');
      expect(keystore.authenticateCalls, 1);
    });

    testWidgets('a failed enable that could not put the setting back is not an unlock: the lock screen shows', (
      tester,
    ) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      await pumpList(tester);
      await openSettings(tester);
      // The prompt is canceled and, as it ends, settings can no longer be written: the setting stays on.
      keystore.authResults.addAll([AuthResult.canceled, AuthResult.canceled]);
      keystore.duringPrompt = () async {
        backend.failWritesFor.add(SettingsStore.storageKey);
      };
      await turnLockOn(tester);
      expect(await storedRequireAuth(), isTrue, reason: 'the restore failed');
      expect(keystore.authenticateCalls, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expectLockScreen();
      expect(keystore.authenticateCalls, 2, reason: 'the lock prompted by itself, and was canceled');
    });
  });

  group('failing closed', () {
    testWidgets('requireAuth undecided: unlocking seals the profile that was still in the clear', (tester) async {
      await coldStart(auth: null);
      await pumpList(tester);
      expect(keystore.authenticateCalls, 1);
      expect(sealed('a1') && sealed('b2'), isTrue);
      expect(raw(), isNot(contains(_code)));
      expect(find.text(otp(7)), findsOneWidget);
    });

    testWidgets('unreadable settings: the sealed profile locks the app, and unlocking seals the rest', (tester) async {
      await coldStart(auth: true);
      backend.failSettingsReads = true;
      keystore.authResults.add(AuthResult.canceled);
      await pumpList(tester);
      expectLockScreen();
      expect(raw(), contains(_code), reason: 'a canceled prompt seals nothing');

      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      expect(keystore.authenticateCalls, 2);
      expect(sealed('a1') && sealed('b2'), isTrue);
      expect(raw(), allOf(isNot(contains(_code)), isNot(contains('1234'))));
      expect(find.text(otp(7)), findsOneWidget);
    });

    testWidgets('requireAuth off with a profile left sealed: unlocking opens it but seals nothing more', (
      tester,
    ) async {
      await coldStart(auth: false);
      await pumpList(tester);
      expect(keystore.authenticateCalls, 1);
      expect(find.text(otp(5)), findsOneWidget);
      expect(sealed('a1'), isTrue);
      expect(sealed('b2'), isFalse);
      expect(entry('b2')['activationCode'], _code);
    });
  });

  group('no screen lock or a dead key behind the lock screen', () {
    for (final (what, setup) in <(String, void Function())>[
      ('no credentials set up', () => keystore.authResults.add(AuthResult.noCredentials)),
      ('an invalidated key', () => keystore.invalidate()),
    ]) {
      for (final auth in <bool?>[true, null]) {
        testWidgets('$what, requireAuth=$auth: offers deleting; Cancel keeps everything and stays locked', (
          tester,
        ) async {
          await coldStart(auth: auth);
          setup();
          await pumpList(tester);

          expect(find.textContaining('screen lock was removed'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(sealed('a1'), isTrue);
          expect(await storedRequireAuth(), auth);
          expectLockScreen();
        });

        testWidgets('$what, requireAuth=$auth: deleting removes the sealed profiles, keeps the clear ones', (
          tester,
        ) async {
          await coldStart(auth: auth);
          await SettingsStore(backend).update((s) => s.copyWith(allowScreenshots: true));
          setup();
          await pumpList(tester);

          await tester.tap(find.text('Delete these profiles'));
          await tester.pumpAndSettle();

          expect((await store.loadAll()).map((p) => p.id), ['b2']);
          expect(entry('b2')['activationCode'], _code);
          expect(await storedRequireAuth(), isFalse, reason: 'the lock is off, the profile in the clear is reachable');
          expect(lastSecure(), isFalse, reason: 'FLAG_SECURE follows allowScreenshots again');
          expect(lockedText, findsNothing);
          expect(find.text('Work'), findsNothing);
          expect(find.text('Home'), findsOneWidget);
          expect(find.text(otp(7)), findsOneWidget);
          expect(settingsButton, findsOneWidget);
        });
      }
    }

    testWidgets('deleting keeps FLAG_SECURE on when screenshots are not allowed', (tester) async {
      await coldStart(auth: true);
      await SettingsStore(backend).update((s) => s.copyWith(allowScreenshots: false));
      keystore.authResults.add(AuthResult.noCredentials);
      await pumpList(tester);
      await tester.tap(find.text('Delete these profiles'));
      await tester.pumpAndSettle();
      expect(await storedRequireAuth(), isFalse);
      expect(lastSecure(), isTrue);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('with every profile sealed, deleting leaves the empty list and the lock off', (tester) async {
      await protect('b2');
      await coldStart(auth: true);
      keystore.authResults.add(AuthResult.noCredentials);
      await pumpList(tester);
      await tester.tap(find.text('Delete these profiles'));
      await tester.pumpAndSettle();
      expect(await store.loadAll(), isEmpty);
      expect(await storedRequireAuth(), isFalse);
      expect(lockedText, findsNothing);
      expect(find.text('Work'), findsNothing);
    });
  });

  group('going to the background', () {
    testWidgets('a prompt that is canceled while the app is paused relocks, and resuming prompts once more', (
      tester,
    ) async {
      await coldStart(auth: true);
      keystore.authResults.add(AuthResult.canceled);
      pauseDuringPrompt(tester);
      await pumpList(tester);

      expect(keystore.authenticateCalls, 1);
      expectLockScreen();
      expect(store.lastPromptSucceeded, isFalse);

      await resume(tester);
      expect(keystore.authenticateCalls, 2, reason: 'resuming prompts by itself again');
      expect(lockedText, findsNothing);
      expect(find.text(otp(5)), findsOneWidget);
    });

    testWidgets('a canceled prompt that pauses the app, then a second cancel: still locked, prompts once per resume', (
      tester,
    ) async {
      await coldStart(auth: true);
      keystore.authResults.addAll([AuthResult.canceled, AuthResult.canceled]);
      pauseDuringPrompt(tester);
      await pumpList(tester);
      await resume(tester);
      expect(keystore.authenticateCalls, 2);
      expectLockScreen();
      await resume(tester);
      expect(keystore.authenticateCalls, 2, reason: 'no third prompt without a new lock');
    });

    testWidgets('a prompt that succeeds while the app is paused does not lock', (tester) async {
      await coldStart(auth: true);
      pauseDuringPrompt(tester);
      await pumpList(tester);
      expect(store.lastPromptSucceeded, isTrue);
      expect(lockedText, findsNothing);
      expect(find.text(otp(5)), findsOneWidget);

      await resume(tester);
      expect(keystore.authenticateCalls, 1);
      expect(find.text(otp(5)), findsOneWidget);
    });

    testWidgets('the Unlock button\'s prompt that succeeds while the app is paused does not lock either', (
      tester,
    ) async {
      await coldStart(auth: true);
      keystore.authResults.add(AuthResult.canceled);
      await pumpList(tester);
      expectLockScreen();

      pauseDuringPrompt(tester);
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      expect(keystore.authenticateCalls, 2);
      expect(lockedText, findsNothing);
      expect(find.text(otp(5)), findsOneWidget);
    });

    testWidgets('relocking clears a snackbar, so an Undo can not outlive the lock', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await tester.tap(find.byIcon(Icons.check).first);
      await tester.pumpAndSettle();
      expect(find.text('Marked #5 as used'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      // No frames are drawn in the background, so what is on screen only changes once the app is back.
      await resume(tester);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Marked #5 as used'), findsNothing);
      expectLockScreen();
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('with nothing sealed and the lock off, backgrounding neither relocks nor clears a snackbar', (
      tester,
    ) async {
      await SettingsStore(backend).save(const Settings(requireAuth: false));
      await pumpList(tester);
      await tester.tap(find.byIcon(Icons.check).first);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      await background(tester);
      await resume(tester);
      expect(lockedText, findsNothing);
      expect(find.text('Undo'), findsOneWidget);
      expect(keystore.authenticateCalls, 0);
    });
  });

  group('unlock racing a trip to the background', () {
    test('a decryption that finishes after forget() keeps nothing in memory', () async {
      final gated = _GatedKeystore();
      final raced = ProfileStore(backend, keystore: gated);
      await raced.saveAll([_work(), _home()]);
      await raced.setAllProtected(true);
      await raced.forget();
      gated.expire();

      gated.gate = Completer<void>();
      final unlocking = raced.unlockApp();
      await gated.waiting.future;
      expect(await raced.forget(), isFalse, reason: 'nothing was open yet');
      gated.gate!.complete();
      final profiles = await unlocking;

      expect(profiles.every((p) => p.locked), isTrue);
      expect((await raced.loadAll()).every((p) => p.locked), isTrue, reason: 'no plaintext cached');
    });

    testWidgets('going to the background mid-unlock leaves the app locked', (tester) async {
      final gated = _GatedKeystore();
      store = ProfileStore(backend, keystore: gated);
      await store.setAllProtected(true);
      await SettingsStore(backend).save(const Settings(requireAuth: true));
      await store.forget();
      gated
        ..expire()
        ..gate = Completer<void>();

      await pumpList(tester, settle: false);
      await tester.runAsync(() => gated.waiting.future);
      await background(tester);
      // The next automatic prompt on return is canceled, so only the raced unlock could open the list.
      gated.authResults.add(AuthResult.canceled);
      gated.gate!.complete();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await resume(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(lockedText, findsOneWidget);
      expect(find.text('Work'), findsNothing);
      expect((await store.loadAll()).every((p) => p.locked), isTrue);
    });
  });

  group('only a dead key or a missing screen lock offers deletion', () {
    for (final result in [AuthResult.lockedOut, AuthResult.failed, AuthResult.canceled]) {
      testWidgets('${result.name}: a message, no delete dialog, still locked', (tester) async {
        await coldStart(auth: true);
        keystore.authResults.add(result);
        await pumpList(tester);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(keystore.authenticateCalls, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Delete these profiles'), findsNothing);
        expect(lockedText, findsOneWidget);
        expect(sealed('a1'), isTrue);
      });
    }
  });
}

/// Holds every decryption until [gate] completes, signalling [waiting] when one starts.
class _GatedKeystore extends FakeKeystore {
  Completer<void>? gate;
  Completer<void> waiting = Completer<void>();

  @override
  Future<String> decrypt(String alias, String ciphertext) async {
    final gate = this.gate;
    if (gate != null) {
      if (!waiting.isCompleted) waiting.complete();
      await gate.future;
    }
    return super.decrypt(alias, ciphertext);
  }
}
