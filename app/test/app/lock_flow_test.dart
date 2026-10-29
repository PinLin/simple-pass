import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
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
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';
import 'package:simple_pass/storage/storage_exceptions.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';

Profile _work({int counter = 5}) =>
    Profile(id: 'a1', name: 'Work', activationCode: _code, counter: counter, pin: '1234');
Profile _home() => Profile(id: 'b2', name: 'Home', activationCode: _code, counter: 7);

/// Fails every write once [failWrites] is set, like a crash right before
/// the write lands.
class _CrashingBackend extends MemoryKeyValueBackend {
  bool failWrites = false;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('crash');
    await super.write(key, value);
  }
}

void main() {
  late _CrashingBackend backend;
  late FakeKeystore keystore;
  late ProfileStore store;

  setUp(() async {
    backend = _CrashingBackend();
    keystore = FakeKeystore();
    store = ProfileStore(backend, keystore: keystore);
    await store.saveAll([_work(), _home()]);
  });

  String raw() => backend.rawValue(ProfileStore.storageKey)!;
  Map<String, dynamic> entry(String id) =>
      ((jsonDecode(raw()) as Map)['profiles'] as List).cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == id);

  Future<void> protect(String id) => store.updateProfile(id, (p) => p.copyWith(protected: true));
  Future<Profile> load(String id) async => (await store.loadAll()).firstWhere((p) => p.id == id);

  /// The app went to the background and the validity window ran out.
  void away() {
    store.forget();
    keystore.expire();
  }

  group('ProfileStore, per-profile protection', () {
    test('seals only the protected profile; the rest of it and other profiles stay readable', () async {
      await protect('a1');
      expect(entry('a1').keys, containsAll(['sealed', 'name', 'counter']));
      expect(entry('a1').keys, isNot(contains('activationCode')));
      expect(entry('a1').keys, isNot(contains('pin')));
      expect(entry('b2')['activationCode'], _code);
      expect((await load('a1')).activationCode, _code, reason: 'still open right after sealing');
    });

    test('after forget a protected profile loads locked with empty secrets; others are unaffected', () async {
      await protect('a1');
      away();
      final work = await load('a1');
      expect((work.locked, work.protected, work.activationCode, work.pin), (true, true, '', ''));
      expect((work.name, work.counter), ('Work', 5));
      expect((await load('b2')).locked, isFalse);
    });

    test('unlockApp after the window ran out prompts once and opens every sealed profile', () async {
      await protect('a1');
      await store.updateProfile('b2', (p) => p.copyWith(protected: true));
      away();
      keystore.authenticateCalls = 0;
      final unlocked = await store.unlockApp(sealUnprotected: false);
      expect(keystore.authenticateCalls, 1);
      final work = unlocked.firstWhere((p) => p.id == 'a1');
      expect((work.activationCode, work.pin, work.locked), (_code, '1234', false));
      expect((await load('b2')).locked, isFalse);
    });

    test('a canceled unlock stays locked and writes nothing', () async {
      await protect('a1');
      away();
      final before = raw();
      final writes = backend.writeCount;
      keystore.authResults.add(AuthResult.canceled);
      await expectLater(
        store.unlockApp(sealUnprotected: false),
        throwsA(isA<AuthFailedException>().having((e) => e.result, 'result', AuthResult.canceled)),
      );
      expect((await load('a1')).locked, isTrue);
      expect((raw(), backend.writeCount), (before, writes));
    });

    test('writes while a profile is locked keep its ciphertext verbatim and never need the key', () async {
      await protect('a1');
      away();
      final sealed = entry('a1')['sealed'];
      keystore.authenticateCalls = 0;
      await store.updateProfile('a1', (p) => p.copyWith(counter: 9));
      await store.update((c) => [...c, Profile(id: 'c3', name: 'New', activationCode: _code, counter: 0)]);
      await store.update((c) => c.where((p) => p.id != 'b2').toList());
      expect(keystore.authenticateCalls, 0);
      expect(entry('a1')['sealed'], sealed);
      expect(entry('a1')['counter'], 9);
      await store.unlockApp(sealUnprotected: false);
      expect((await load('a1')).pin, '1234');
    });

    test('reordering moves a locked profile without the key and keeps its ciphertext', () async {
      await protect('a1');
      away();
      final sealed = entry('a1')['sealed'];
      keystore.authenticateCalls = 0;
      await store.reorder(['b2', 'a1']);
      expect(keystore.authenticateCalls, 0);
      expect((await store.loadAll()).map((p) => (p.id, p.locked)), [('b2', false), ('a1', true)]);
      expect(entry('a1')['sealed'], sealed);
      await store.unlockApp(sealUnprotected: false);
      expect((await load('a1')).activationCode, _code);
    });

    test('a locked entry with a usage log from older versions loads, and writes keep only its ciphertext', () async {
      await protect('a1');
      away();
      final sealed = entry('a1')['sealed'];
      final profiles = ((jsonDecode(raw()) as Map)['profiles'] as List).cast<Map<String, dynamic>>();
      profiles.first['usedLog'] = [
        {'counter': 4, 'usedAt': '2026-01-01T00:00:00.000Z'},
      ];
      backend.seedRaw(ProfileStore.storageKey, jsonEncode({'profiles': profiles}));

      expect((await load('a1')).locked, isTrue);
      await store.updateProfile('b2', (p) => p.copyWith(counter: 8));
      expect(entry('a1').containsKey('usedLog'), isFalse);
      expect(entry('a1')['sealed'], sealed);
      await store.unlockApp(sealUnprotected: false);
      expect(((await load('a1')).activationCode, (await load('a1')).counter), (_code, 5));
    });

    test('counter writes on an open profile reuse the ciphertext', () async {
      await protect('a1');
      keystore.expire();
      final sealed = entry('a1')['sealed'];
      keystore.authenticateCalls = 0;
      await store.updateProfile('a1', (p) => p.copyWith(counter: 6));
      expect(keystore.authenticateCalls, 0);
      expect(entry('a1')['sealed'], sealed);
    });

    test('a changed secret after the window ran out prompts, then seals', () async {
      await protect('a1');
      keystore.expire();
      keystore.authenticateCalls = 0;
      await store.updateProfile('a1', (p) => p.copyWith(pin: '9999'));
      expect(keystore.authenticateCalls, 1);
      expect(raw(), isNot(contains('9999')));
    });

    test('changing protection always prompts, even inside the window', () async {
      keystore.authenticated = true;
      await protect('a1');
      expect(keystore.authenticateCalls, 1);
      await store.updateProfile('a1', (p) => p.copyWith(protected: false));
      expect(keystore.authenticateCalls, 2);
      expect(entry('a1')['activationCode'], _code);
      expect(entry('a1').containsKey('sealed'), isFalse);
    });

    test('a prompt that succeeds keeps the secrets, since the prompt itself may pause the app', () async {
      Future<bool>? forgotten;
      keystore.duringPrompt = () async {
        forgotten = store.forget();
      };
      await protect('a1');
      await protect('b2');
      expect(await forgotten, isFalse);
      expect((await store.loadAll()).map((p) => p.locked), [false, false]);
    });

    test('a forget during a prompt that fails drops the secrets once it ends', () async {
      await protect('a1');
      Future<bool>? forgotten;
      keystore.duringPrompt = () async {
        forgotten = store.forget();
      };
      keystore.authResults.add(AuthResult.canceled);
      await expectLater(protect('b2'), throwsA(isA<AuthFailedException>()));
      expect(await forgotten, isTrue);
      expect((await load('a1')).locked, isTrue);
    });

    test('a crash before the write lands leaves the old form intact', () async {
      final before = raw();
      backend.failWrites = true;
      await expectLater(protect('a1'), throwsStateError);
      backend.failWrites = false;
      expect(raw(), before);
      expect((await load('a1')).activationCode, _code);
    });

    group('reading stored data', () {
      test('entries without "protected" or without "sealed" load as unprotected', () async {
        final plain = [_work().toJson()..remove('protected'), _home().toJson()..['protected'] = true];
        backend.seedRaw(ProfileStore.storageKey, jsonEncode({'lock': 'stale', 'profiles': plain}));
        expect((await store.loadAll()).map((p) => (p.protected, p.locked)), [(false, false), (false, false)]);
      });

      test('an entry with "sealed" is protected and locked', () async {
        keystore.authenticated = true;
        final secret = jsonEncode({'a': _code, 'p': '1234'});
        final sealed =
            'profile_secrets:${await keystore.encrypt('profile_secrets', keyValiditySeconds, secret, keyInUse: false)}';
        final work = _work().toJson()
          ..remove('protected')
          ..remove('activationCode')
          ..remove('pin')
          ..['sealed'] = sealed;
        backend.seedRaw(
          ProfileStore.storageKey,
          jsonEncode({
            'lock': 60,
            'profiles': [work, _home().toJson()],
          }),
        );
        expect((await store.loadAll()).map((p) => (p.protected, p.locked)), [(true, true), (false, false)]);
        await store.unlockApp(sealUnprotected: false);
        expect((await load('a1')).pin, '1234');
      });

      test('a stale "lock" field is ignored and no longer written', () async {
        backend.seedRaw(
          ProfileStore.storageKey,
          jsonEncode({
            'lock': 300,
            'profiles': [_work().toJson()],
          }),
        );
        await protect('a1');
        expect((jsonDecode(raw()) as Map).containsKey('lock'), isFalse);
        expect(entry('a1')['sealed'], startsWith('profile_secrets:'));
        expect(keystore.keys, {'profile_secrets': keyValiditySeconds});
      });
    });

    test('invalidated key: unlock reports it; deleting removes only the protected profiles, never silently', () async {
      await protect('a1');
      await store.updateProfile('a1', (p) => p.copyWith(counter: 6));
      away();
      keystore.invalidate();
      await expectLater(store.unlockApp(sealUnprotected: false), throwsA(isA<KeyInvalidatedException>()));
      expect(entry('a1').containsKey('sealed'), isTrue, reason: 'nothing is deleted by the failure itself');

      await store.deleteUnrecoverable();

      final profiles = await store.loadAll();
      expect(profiles.map((p) => p.id), ['b2']);
      expect(profiles.single.activationCode, _code);
      expect(raw(), isNot(contains('"a1"')));
      expect(keystore.keys, isEmpty);

      // With a new screen lock another profile can be protected again.
      await protect('b2');
      expect(entry('b2').containsKey('sealed'), isTrue);
    });

    test('deleting unrecoverable profiles removes every sealed one and leaves an unprotected store alone', () async {
      await protect('a1');
      await protect('b2');
      away();
      keystore.invalidate();
      await store.deleteUnrecoverable();
      expect(await store.loadAll(), isEmpty);

      await store.saveAll([_home()]);
      final before = raw();
      await store.deleteUnrecoverable();
      expect(raw(), before);
    });

    test('a new key never replaces a dead one other profiles are still sealed with', () async {
      await protect('a1');
      away();
      keystore.invalidate();
      await expectLater(protect('b2'), throwsA(isA<KeyInvalidatedException>()));
      expect(entry('b2').containsKey('sealed'), isFalse);

      await store.deleteUnrecoverable();
      await protect('b2');
      store.forget();
      await store.unlockApp(sealUnprotected: false);
      expect((await load('b2')).activationCode, _code);
    });

    test('a dead key left behind by an interrupted attempt does not block protecting', () async {
      keystore.authenticated = true;
      await keystore.encrypt('profile_secrets', keyValiditySeconds, 'x', keyInUse: false);
      keystore.invalidate();
      await protect('a1');
      store.forget();
      await store.unlockApp(sealUnprotected: false);
      expect((await load('a1')).activationCode, _code);
    });
  });

  group('ProfileStore, setAllProtected and unlocking everything', () {
    bool allSealed() => RegExp('"sealed"').allMatches(raw()).length == 2;
    bool noPlaintext() => !raw().contains(_code) && !raw().contains('1234');

    test('unlockApp without sealing opens every sealed profile with a single prompt and writes nothing', () async {
      await protect('a1');
      await protect('b2');
      away();
      final before = raw();
      final writes = backend.writeCount;
      keystore.authenticateCalls = 0;
      final all = await store.unlockApp(sealUnprotected: false);
      expect(keystore.authenticateCalls, 1);
      expect(all.map((p) => (p.locked, p.activationCode)), [(false, _code), (false, _code)]);
      expect((await store.loadAll()).map((p) => p.locked), [false, false]);
      expect((raw(), backend.writeCount), (before, writes));
    });

    test('unlockApp prompts even inside the validity window, there is no prompt-free unlock of everything', () async {
      await protect('a1');
      await protect('b2');
      store.forget();
      keystore.authenticateCalls = 0;
      await store.unlockApp(sealUnprotected: false);
      expect(keystore.authenticateCalls, 1);
    });

    test('a canceled unlockApp leaves everything locked and writes nothing', () async {
      await protect('a1');
      await protect('b2');
      away();
      final before = raw();
      final writes = backend.writeCount;
      keystore.authResults.add(AuthResult.canceled);
      await expectLater(store.unlockApp(sealUnprotected: false), throwsA(isA<AuthFailedException>()));
      expect((await store.loadAll()).map((p) => p.locked), [true, true]);
      expect((raw(), backend.writeCount), (before, writes));
    });

    test('lastPromptSucceeded follows the most recent prompt', () async {
      await protect('a1');
      away();
      expect(store.lastPromptSucceeded, isTrue, reason: 'the protect prompt before');
      keystore.authResults.add(AuthResult.canceled);
      await expectLater(store.unlockApp(), throwsA(isA<AuthFailedException>()));
      expect(store.lastPromptSucceeded, isFalse);
      await store.unlockApp();
      expect(store.lastPromptSucceeded, isTrue);
    });

    test('unlockApp(sealUnprotected) seals the profiles still in the clear in the same prompt', () async {
      await protect('a1');
      away();
      keystore.authenticateCalls = 0;
      final all = await store.unlockApp(sealUnprotected: true);
      expect(keystore.authenticateCalls, 1, reason: 'opening and sealing share one authentication');
      expect(all.map((p) => (p.protected, p.locked)), [(true, false), (true, false)]);
      expect(allSealed(), isTrue);
      expect(noPlaintext(), isTrue);
      store.forget();
      expect((await store.loadAll()).map((p) => (p.protected, p.locked)), [(true, true), (true, true)]);
    });

    test('unlockApp(sealUnprotected) on an all-sealed store writes nothing', () async {
      await protect('a1');
      await protect('b2');
      away();
      final writes = backend.writeCount;
      await store.unlockApp(sealUnprotected: true);
      expect(backend.writeCount, writes);
    });

    test('setAllProtected(true) seals everything after one prompt, even inside the window', () async {
      keystore.authenticated = true;
      final all = await store.setAllProtected(true);
      expect(keystore.authenticateCalls, 1);
      expect(all.map((p) => (p.protected, p.locked)), [(true, false), (true, false)]);
      expect(allSealed(), isTrue);
      expect(noPlaintext(), isTrue);
    });

    test('setAllProtected(true) with one profile already sealed and locked keeps one prompt', () async {
      await protect('a1');
      away();
      keystore.authenticateCalls = 0;
      await store.setAllProtected(true);
      expect(keystore.authenticateCalls, 1);
      expect(allSealed(), isTrue);
      expect((await load('a1')).pin, '1234');
    });

    test('setAllProtected(false) unseals everything after one prompt', () async {
      await protect('a1');
      await protect('b2');
      away();
      keystore.authenticateCalls = 0;
      final all = await store.setAllProtected(false);
      expect(keystore.authenticateCalls, 1);
      expect(all.map((p) => (p.protected, p.locked)), [(false, false), (false, false)]);
      expect(raw(), isNot(contains('"sealed"')));
      expect((entry('a1')['activationCode'], entry('a1')['pin']), (_code, '1234'));
      expect(entry('b2')['activationCode'], _code);
    });

    test('a canceled prompt changes nothing, in either direction', () async {
      final plain = raw();
      keystore.authResults.add(AuthResult.canceled);
      await expectLater(store.setAllProtected(true), throwsA(isA<AuthFailedException>()));
      expect(raw(), plain);

      await store.setAllProtected(true);
      away();
      final sealed = raw();
      keystore.authResults.add(AuthResult.lockedOut);
      await expectLater(store.setAllProtected(false), throwsA(isA<AuthFailedException>()));
      expect(raw(), sealed);
      expect((await store.loadAll()).map((p) => p.locked), [true, true]);
    });

    test('a dead key makes setAllProtected(false) fail before anything is written', () async {
      await protect('a1');
      away();
      keystore.invalidate();
      final before = raw();
      final writes = backend.writeCount;
      await expectLater(store.setAllProtected(false), throwsA(isA<KeyInvalidatedException>()));
      expect((raw(), backend.writeCount), (before, writes));
    });

    test('a crash before the write lands leaves the old form intact', () async {
      final before = raw();
      backend.failWrites = true;
      await expectLater(store.setAllProtected(true), throwsStateError);
      backend.failWrites = false;
      expect(raw(), before);
    });

    test('runs on the same queue as other operations: a concurrent counter write is not lost', () async {
      await Future.wait([store.setAllProtected(true), store.updateProfile('b2', (p) => p.copyWith(counter: 8))]);
      expect(entry('b2')['counter'], 8);
      expect(allSealed(), isTrue);
    });
  });

  group('ProfileStore, unlockApp', () {
    test('always prompts, even inside the validity window', () async {
      await protect('a1');
      store.forget();
      expect(keystore.authenticated, isTrue);
      keystore.authenticateCalls = 0;
      final all = await store.unlockApp();
      expect(keystore.authenticateCalls, 1);
      expect(all.map((p) => (p.protected, p.locked)), [(true, false), (true, false)]);
    });

    test('opens every sealed profile and seals the plain ones under that one prompt', () async {
      await protect('a1');
      away();
      keystore.authenticateCalls = 0;
      final all = await store.unlockApp();
      expect(keystore.authenticateCalls, 1);
      expect(all.map((p) => p.activationCode), [_code, _code]);
      expect(RegExp('"sealed"').allMatches(raw()), hasLength(2));
      expect(raw(), allOf(isNot(contains(_code)), isNot(contains('1234'))));
      expect((await store.loadAll()).map((p) => p.locked), [false, false]);
      store.forget();
      expect((await store.loadAll()).map((p) => p.locked), [true, true]);
    });

    test('sealUnprotected: false leaves plain profiles in the clear', () async {
      await protect('a1');
      away();
      await store.unlockApp(sealUnprotected: false);
      expect(entry('b2')['activationCode'], _code);
      expect(entry('b2').containsKey('sealed'), isFalse);
    });

    test('a damaged sealed secret stays locked while the others open', () async {
      await protect('a1');
      await protect('b2');
      final blob = jsonDecode(raw()) as Map<String, dynamic>;
      final first = (blob['profiles'] as List).cast<Map<String, dynamic>>().first;
      final sealed = first['sealed'] as String;
      first['sealed'] = '${sealed.substring(0, sealed.lastIndexOf(':'))}:!!!not base64';
      backend.seedRaw(ProfileStore.storageKey, jsonEncode(blob));
      away();
      final all = await store.unlockApp();
      expect(all.map((p) => (p.id, p.locked)), [('a1', true), ('b2', false)]);
      expect(all.last.activationCode, _code);
    });

    test('a canceled prompt throws and changes nothing', () async {
      await protect('a1');
      away();
      final before = raw();
      final writes = backend.writeCount;
      keystore.authResults.add(AuthResult.canceled);
      await expectLater(store.unlockApp(), throwsA(isA<AuthFailedException>()));
      expect((raw(), backend.writeCount), (before, writes));
      expect((await store.loadAll()).map((p) => p.locked), [true, false]);
    });

    test('a dead key is reported and nothing is deleted', () async {
      await protect('a1');
      away();
      keystore.invalidate();
      await expectLater(store.unlockApp(), throwsA(isA<KeyInvalidatedException>()));
      expect(entry('a1').containsKey('sealed'), isTrue);
    });

    test('prompting is true only while the system prompt is up', () async {
      await protect('a1');
      away();
      final seen = <bool>[];
      keystore.duringPrompt = () async => seen.add(store.prompting);
      expect(store.prompting, isFalse);
      await store.unlockApp();
      expect(seen, [true]);
      expect(store.prompting, isFalse);
    });

    test('a forget during the unlock prompt that succeeds keeps the secrets', () async {
      await protect('a1');
      away();
      Future<bool>? forgotten;
      keystore.duringPrompt = () async {
        forgotten = store.forget();
      };
      await store.unlockApp();
      expect(await forgotten, isFalse);
      expect((await store.loadAll()).map((p) => p.locked), [false, false]);
    });
  });

  group('ProfileStore, adding a protected profile', () {
    Profile fresh() => Profile(id: 'c3', name: 'New', activationCode: _code, counter: 0, protected: true);

    test('inside the validity window it is sealed without another prompt', () async {
      await protect('a1');
      expect(keystore.authenticated, isTrue);
      keystore.authenticateCalls = 0;
      await store.update((c) => [...c, fresh()]);
      expect(keystore.authenticateCalls, 0);
      expect(entry('c3').containsKey('sealed'), isTrue);
      expect(entry('c3').containsKey('activationCode'), isFalse);
    });

    test('once the window ran out the key itself asks, once', () async {
      await protect('a1');
      keystore.expire();
      keystore.authenticateCalls = 0;
      await store.update((c) => [...c, fresh()]);
      expect(keystore.authenticateCalls, 1);
      expect(entry('c3').containsKey('sealed'), isTrue);
    });

    test('changing an existing profile\'s protection still prompts inside the window', () async {
      await protect('a1');
      keystore.authenticateCalls = 0;
      await protect('b2');
      expect(keystore.authenticateCalls, 1);
    });
  });

  group('list screen', () {
    late List<MethodCall> guardCalls;

    setUp(() {
      guardCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(ScreenGuard.channelName),
        (call) async {
          guardCalls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(ScreenGuard.channelName),
        null,
      );
    });

    Future<void> pumpList(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLocalized(
        tester,
        ProfileListScreen(profileStore: store, settingsStore: SettingsStore(backend), screenGuard: ScreenGuard()),
      );
      await tester.pumpAndSettle();
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

    String otp(int counter) => formatOtpForDisplay(generateMobilePassOtp(_code, counter));
    final workRow = find.byKey(const ValueKey('profileRowCopy-a1'));
    final unlockButton = find.byKey(const ValueKey('unlockAppButton'));
    final lockedText = find.text('SimplePASS is locked');
    final editButton = find.byKey(const ValueKey('profileEdit-a1'));

    bool? lastRecentsEnabled() =>
        guardCalls.lastWhere((c) => c.method == 'setRecentsScreenshotEnabled').arguments['enabled'] as bool?;

    Future<void> requireAuth(bool? value) async {
      if (value != null) await SettingsStore(backend).save(Settings(requireAuth: value));
    }

    /// Protected profiles whose window ran out, the way a cold start finds them.
    Future<void> coldStart({bool? auth, bool sealWork = true}) async {
      if (sealWork) await protect('a1');
      await requireAuth(auth);
      away();
      keystore.authenticateCalls = 0;
    }

    Future<void> edit(WidgetTester tester) async {
      await tester.tap(editButton);
      await tester.pumpAndSettle();
    }

    void expectLockScreen() {
      expect(lockedText, findsOneWidget);
      expect(unlockButton, findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('Work'), findsNothing);
      expect(find.text('Home'), findsNothing);
      expect(find.byTooltip('Settings'), findsNothing);
      expect(find.byTooltip('Add profile'), findsNothing);
      expect(find.text('SimplePASS'), findsOneWidget);
    }

    group('app lock', () {
      testWidgets('a cold start with requireAuth shows only the lock screen, and prompts once by itself', (
        tester,
      ) async {
        await coldStart(auth: true);
        keystore.authResults.add(AuthResult.canceled);
        await pumpList(tester);
        expectLockScreen();
        expect(find.textContaining('2'), findsNothing, reason: 'no profile count either');
        expect(keystore.authenticateCalls, 1);
        expect(find.text('Authentication canceled'), findsOneWidget);
        expect(lastRecentsEnabled(), isFalse);
      });

      testWidgets('canceled: stays locked and does not prompt again; Unlock prompts and shows the list', (
        tester,
      ) async {
        await coldStart(auth: true);
        keystore.authResults.add(AuthResult.canceled);
        await pumpList(tester);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        expect(keystore.authenticateCalls, 1);
        expectLockScreen();

        await tester.tap(unlockButton);
        await tester.pumpAndSettle();
        expect(keystore.authenticateCalls, 2);
        expect(lockedText, findsNothing);
        expect(find.text('Work'), findsOneWidget);
        expect(find.text(otp(5)), findsOneWidget);
        expect(find.text(otp(7)), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);
        expect(find.byTooltip('Add profile'), findsOneWidget);
        expect(lastRecentsEnabled(), isFalse);
      });

      testWidgets('a successful automatic prompt goes straight to the list, with no lock icon on any row', (
        tester,
      ) async {
        await coldStart(auth: true);
        await pumpList(tester);
        expect(keystore.authenticateCalls, 1);
        expect(lockedText, findsNothing);
        expect(find.text(otp(5)), findsOneWidget);
        expect(find.byKey(const ValueKey('profileLocked-a1')), findsNothing);
        expect(find.byIcon(Icons.lock_outline), findsNothing);
      });

      testWidgets('without requireAuth, a protected profile still locks the app', (tester) async {
        await coldStart(auth: null);
        keystore.authResults.add(AuthResult.canceled);
        await pumpList(tester);
        expectLockScreen();
        expect(keystore.authenticateCalls, 1);
      });

      testWidgets('requireAuth off and nothing sealed: the list shows at once, nothing prompts', (tester) async {
        await coldStart(auth: false, sealWork: false);
        await pumpList(tester);
        expect(keystore.authenticateCalls, 0);
        expect(lockedText, findsNothing);
        expect(find.text(otp(5)), findsOneWidget);
        expect(lastRecentsEnabled(), isTrue);
      });

      testWidgets('requireAuth on with nothing sealed locks, and unlocking seals everything under that one prompt', (
        tester,
      ) async {
        await coldStart(auth: true, sealWork: false);
        keystore.authResults.add(AuthResult.canceled);
        await pumpList(tester);
        expectLockScreen();
        expect(raw(), contains(_code), reason: 'a canceled prompt seals nothing');

        await tester.tap(unlockButton);
        await tester.pumpAndSettle();
        expect(keystore.authenticateCalls, 2);
        expect(entry('a1').containsKey('sealed'), isTrue);
        expect(entry('b2').containsKey('sealed'), isTrue);
        expect(raw(), allOf(isNot(contains(_code)), isNot(contains('1234'))));
        expect(find.text(otp(5)), findsOneWidget);
        expect(lastRecentsEnabled(), isFalse);
      });

      testWidgets('a mixed store seals the plain profile during the unlock, with a single prompt', (tester) async {
        await coldStart(auth: true);
        await pumpList(tester);
        expect(keystore.authenticateCalls, 1);
        expect(raw(), allOf(isNot(contains(_code)), isNot(contains('1234'))));
        expect(RegExp('"sealed"').allMatches(raw()), hasLength(2));
        expect(find.text(otp(7)), findsOneWidget);
      });

      testWidgets('a damaged sealed secret leaves just that row without a code; it can neither be tapped nor edited', (
        tester,
      ) async {
        await protect('a1');
        await protect('b2');
        await requireAuth(true);
        final blob = jsonDecode(raw()) as Map<String, dynamic>;
        final sealed = (blob['profiles'] as List).cast<Map<String, dynamic>>().first['sealed'] as String;
        (blob['profiles'] as List).cast<Map<String, dynamic>>().first['sealed'] =
            '${sealed.substring(0, sealed.lastIndexOf(':'))}:!!!not base64';
        backend.seedRaw(ProfileStore.storageKey, jsonEncode(blob));
        away();
        keystore.authenticateCalls = 0;
        await pumpList(tester);

        expect(keystore.authenticateCalls, 1);
        expect(find.text(otp(7)), findsOneWidget, reason: 'the sound profile opened');
        expect(find.text('Work'), findsOneWidget);
        expect(find.text('Invalid Activation Code'), findsOneWidget);
        expect(find.byKey(const ValueKey('lockedCodePlaceholder')), findsNothing);
        await tester.tap(workRow);
        await tester.pumpAndSettle();
        await edit(tester);
        expect(find.byType(ProfileEditScreen), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(keystore.authenticateCalls, 1);
      });

      testWidgets('after unlocking, a protected row can be edited, selected, reordered and deleted without prompts', (
        tester,
      ) async {
        await coldStart(auth: true);
        await pumpList(tester);
        keystore.authenticateCalls = 0;

        await edit(tester);
        expect(find.byType(ProfileEditScreen), findsOneWidget);
        await openRegistrationInfo(tester);
        expect(find.text(_code), findsOneWidget);
        await closeProfileInfo(tester);
        // The key worked out from the Activation Code is only on the page once unlocked.
        expect(find.byKey(const ValueKey('mobilePassSecretField')), findsOneWidget);
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final copies = <MethodCall>[];
        messenger.setMockMethodCallHandler(const MethodChannel(SensitiveClipboard.channelName), (call) async {
          copies.add(call);
          return call.method == 'clearIfMatches' ? 'cleared' : null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(const MethodChannel(SensitiveClipboard.channelName), null),
        );
        await copyExportLink(tester);
        expect((copies.single.arguments as Map)['sensitive'], isTrue);
        expect((copies.single.arguments as Map)['text'], startsWith('otpauth://'));
        expect(find.text('Link copied'), findsOneWidget);
        await settleCopy(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.longPress(workRow);
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        final rowHeight = tester.getSize(find.byKey(const ValueKey('selectRow-a1'))).height;
        final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('profileRowSelect-a1'))));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(Offset(0, rowHeight / 10));
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect((await store.loadAll()).map((p) => p.id), ['b2', 'a1']);

        await tester.tap(find.byKey(const ValueKey('deleteSelectedButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();
        expect(keystore.authenticateCalls, 0);
        expect(find.text('Work'), findsNothing);
        expect((await store.loadAll()).map((p) => p.id), ['b2']);
      });

      testWidgets('going to the background drops the secrets and closes the editor; coming back prompts', (
        tester,
      ) async {
        await coldStart(auth: true);
        await pumpList(tester);
        await edit(tester);
        expect(find.byType(ProfileEditScreen), findsOneWidget);
        await openRegistrationInfo(tester);
        expect(find.text(_code), findsOneWidget);

        keystore.expire();
        keystore.authResults.add(AuthResult.canceled);
        await background(tester);
        expect((await load('a1')).locked, isTrue);
        expect(keystore.authenticateCalls, 1, reason: 'no prompt while in the background');

        await resume(tester);
        expect(keystore.authenticateCalls, 2, reason: 'resuming prompts once by itself');
        expect(find.byKey(const ValueKey('registrationInfoSheet')), findsNothing);
        expect(find.byType(ProfileEditScreen), findsNothing);
        expect(find.text(_code), findsNothing);
        expectLockScreen();
        await resume(tester);
        expect(keystore.authenticateCalls, 2);

        await tester.tap(unlockButton);
        await tester.pumpAndSettle();
        expect(keystore.authenticateCalls, 3);
        expect(find.text(otp(5)), findsOneWidget);
        expect(find.byKey(const ValueKey('registrationInfoSheet')), findsNothing);
        expect(find.byType(ProfileEditScreen), findsNothing);
      });

      testWidgets('with requireAuth on, going to the background locks even if the secrets were still held', (
        tester,
      ) async {
        await coldStart(auth: true, sealWork: false);
        await pumpList(tester);
        store.forget();
        keystore.authResults.add(AuthResult.canceled);
        await background(tester);
        expectLockScreen();
      });

      testWidgets('a ✓ whose save lands after the app relocked shows no snackbar and offers no Undo', (tester) async {
        await coldStart(auth: true);
        await pumpList(tester);
        expect(find.text(otp(5)), findsOneWidget);

        backend.writeGate = Completer<void>();
        await tester.tap(find.byIcon(Icons.check).first);
        await tester.pump();
        for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
          tester.binding.handleAppLifecycleStateChanged(s);
        }
        await tester.pump();

        backend.writeGate!.complete();
        backend.writeGate = null;
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        keystore.authResults.add(AuthResult.canceled);
        await resume(tester);

        expectLockScreen();
        expect(find.text('Marked #5 as used'), findsNothing);
        expect(find.text('Undo'), findsNothing);
        expect((await load('a1')).counter, 6, reason: 'the ✓ itself was saved');
      });

      testWidgets('a successful prompt that pauses the app does not lock it', (tester) async {
        await coldStart(auth: true);
        keystore.duringPrompt = () async {
          for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
            tester.binding.handleAppLifecycleStateChanged(s);
          }
        };
        await pumpList(tester);
        expect(keystore.authenticateCalls, 1);
        expect(lockedText, findsNothing);
        expect(find.text(otp(5)), findsOneWidget);

        keystore.duringPrompt = null;
        await resume(tester);
        expect(keystore.authenticateCalls, 1);
        expect(find.text(otp(5)), findsOneWidget);
      });

      testWidgets('leaving during a prompt that then fails drops the secrets and closes the editor', (tester) async {
        await coldStart(auth: true);
        await pumpList(tester);
        await edit(tester);
        keystore.authResults.addAll([AuthResult.canceled, AuthResult.canceled]);
        keystore.duringPrompt = () async {
          keystore.duringPrompt = null;
          for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
            tester.binding.handleAppLifecycleStateChanged(s);
          }
        };
        // The window ran out while the editor was open, so changing the PIN prompts.
        keystore.expire();
        await tester.enterText(find.byKey(const ValueKey('pinField')), '5678');
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(keystore.authResults, hasLength(1), reason: 'the prompt really ran');
        expect((await load('a1')).locked, isTrue);
        await resume(tester);
        expect(find.byType(ProfileEditScreen), findsNothing);
        expectLockScreen();
      });

      testWidgets('with nothing protected and requireAuth off, backgrounding keeps the editor open', (tester) async {
        await requireAuth(false);
        await pumpList(tester);
        await edit(tester);
        await background(tester);
        await resume(tester);
        expect(find.byType(ProfileEditScreen), findsOneWidget);
        expect(keystore.authenticateCalls, 0);
        expect(lastRecentsEnabled(), isTrue);
      });

      testWidgets('turning protection on in Settings and coming back does not lock the app', (tester) async {
        await pumpList(tester);
        expect(keystore.authenticateCalls, 0);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('requireAuthSwitch')));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Turn on')));
        await tester.pumpAndSettle();
        expect(keystore.authenticateCalls, 1);
        expect((await SettingsStore(backend).load()).requireAuth, isTrue);
        expect(RegExp('"sealed"').allMatches(raw()), hasLength(2));

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(lockedText, findsNothing);
        expect(find.text(otp(5)), findsOneWidget);
        expect(keystore.authenticateCalls, 1, reason: 'no second prompt on return');
      });

      testWidgets('invalidated key: explains; Cancel deletes nothing and stays locked, deleting removes the profile', (
        tester,
      ) async {
        await coldStart(auth: null);
        keystore.invalidate();
        await pumpList(tester);

        expect(find.textContaining('screen lock was removed'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(entry('a1').containsKey('sealed'), isTrue);
        expectLockScreen();

        await tester.tap(unlockButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete these profiles'));
        await tester.pumpAndSettle();

        expect(entry('b2')['activationCode'], _code);
        expect((await store.loadAll()).map((p) => p.id), ['b2']);
        expect(find.text('Work'), findsNothing);
        expect(find.text('Home'), findsOneWidget);
        expect(lastRecentsEnabled(), isTrue);
      });
    });
  });
}
