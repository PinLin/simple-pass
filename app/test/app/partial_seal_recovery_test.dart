import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';
const _otherCode = 'WMPX4-TD2BV-QZM7C-QX4J4';
const _key = 'yqZjy2vEoVSmj/THIULg3ysjfM0L6Bo6QzLlgvA3oQU=';

// requireAuth never chosen, which reads as off.
const _lockUnset = '{"allowScreenshots":true,"clipboardClearSeconds":60,"tapToReveal":false}';
const _lockOn = '{"allowScreenshots":true,"clipboardClearSeconds":60,"tapToReveal":false,"requireAuth":true}';

void main() {
  late MemoryKeyValueBackend backend;
  late FakeKeystore keystore;
  late ProfileStore store;
  late SettingsStore settingsStore;
  late List<MethodCall> guardCalls;

  setUp(() {
    backend = MemoryKeyValueBackend();
    keystore = FakeKeystore();
    store = ProfileStore(backend, keystore: keystore);
    settingsStore = SettingsStore(backend);
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

  Profile activation(String id, String name, {String code = _code, String pin = '', int counter = 3}) =>
      Profile(id: id, name: name, activationCode: code, counter: counter, pin: pin);

  Profile enrolled() => Profile(
    id: 'k1',
    name: 'Enrolled',
    activationCode: '',
    kind: ProfileKind.mobilePassKey,
    key: _key,
    serial: '123456789',
    policy: '9346',
    pin: '4321',
    counter: 4,
  );

  /// A profiles blob where [sealed] ones hold only "sealed" and the others still hold their secrets in
  /// the clear, as a run that stopped partway through sealing leaves it.
  Future<String> partlySealedBlob({required List<Profile> sealed, required List<Profile> plain}) async {
    keystore.authenticated = true;
    final entries = <Map<String, dynamic>>[];
    for (final p in sealed) {
      final secret = jsonEncode({'a': p.activationCode, if (p.key.isNotEmpty) 'k': p.key, 'p': p.pin});
      final ciphertext = await keystore.encrypt('profile_secrets', keyValiditySeconds, secret, keyInUse: false);
      entries.add(
        p.toJson()
          ..remove('activationCode')
          ..remove('key')
          ..remove('pin')
          ..['protected'] = true
          ..['sealed'] = 'profile_secrets:$ciphertext',
      );
    }
    for (final p in plain) {
      entries.add(p.toJson());
    }
    keystore.expire();
    return jsonEncode({'profiles': entries});
  }

  void seed(String profiles, {String settings = _lockUnset}) {
    backend
      ..seedRaw(ProfileStore.storageKey, profiles)
      ..seedRaw(SettingsStore.storageKey, settings);
  }

  String rawProfiles() => backend.rawValue(ProfileStore.storageKey)!;
  List<Map<String, dynamic>> entries() =>
      ((jsonDecode(rawProfiles()) as Map)['profiles'] as List).cast<Map<String, dynamic>>();

  group('a store left partly sealed', () {
    String otp(Profile p) => formatOtpForDisplay(otpForProfile(p)!);

    Future<void> pumpList(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLocalized(
        tester,
        ProfileListScreen(profileStore: store, settingsStore: settingsStore, screenGuard: ScreenGuard()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('plain profiles stay in the clear until the first unlock, which seals them all in one prompt', (
      tester,
    ) async {
      final work = activation('a1', 'Work', pin: '1234', counter: 5);
      final home = activation('b2', 'Home', code: _otherCode, pin: '5555', counter: 7);
      final enrolledProfile = enrolled();
      seed(
        await partlySealedBlob(sealed: [work], plain: [home, enrolledProfile]),
        settings: _lockOn,
      );
      expect(entries().where((e) => e.containsKey('sealed')).map((e) => e['id']), ['a1']);
      expect(rawProfiles(), allOf(contains(_otherCode), contains(_key), contains('5555'), contains('4321')));
      keystore.authenticateCalls = 0;
      keystore.authResults.add(AuthResult.canceled);

      await pumpList(tester);
      // The app lock comes first: no row shows until it is opened.
      expect(keystore.authenticateCalls, 1);
      expect(find.text('Home'), findsNothing);
      expect(rawProfiles(), contains(_otherCode), reason: 'a canceled unlock seals nothing');

      await tester.tap(find.byKey(const ValueKey('unlockAppButton')));
      await tester.pumpAndSettle();

      expect(keystore.authenticateCalls, 2, reason: 'one prompt unlocks and seals everything');
      expect(find.text(otp(work)), findsOneWidget);
      expect(find.text(otp(home.copyWith(counter: 7))), findsOneWidget);
      expect(find.text(otp(enrolledProfile)), findsOneWidget);

      expect(entries().map((e) => e.containsKey('sealed')), [true, true, true]);
      for (final e in entries()) {
        for (final field in ['activationCode', 'key', 'pin']) {
          expect(e.containsKey(field), isFalse, reason: '${e['id']} $field');
        }
      }
      expect(rawProfiles(), allOf(isNot(contains(_code)), isNot(contains(_otherCode)), isNot(contains(_key))));
      expect(rawProfiles(), allOf(isNot(contains('5555')), isNot(contains('4321'))));

      // Everything is protected from now on: once the window runs out every row is locked.
      store.forget();
      keystore.expire();
      expect((await store.loadAll()).map((p) => (p.protected, p.locked)), [(true, true), (true, true), (true, true)]);
      keystore.authenticateCalls = 0;
      await store.unlockApp(sealUnprotected: false);
      expect(keystore.authenticateCalls, 1);
      expect((await store.loadAll()).map((p) => p.pin), ['1234', '5555', '4321']);
    });

    testWidgets('with requireAuth unset (off) the list leaves plain data alone', (tester) async {
      final blob = await partlySealedBlob(
        sealed: [],
        plain: [activation('a1', 'Work', pin: '1234')],
      );
      seed(blob);
      final writes = backend.writeCount;
      await pumpList(tester);
      expect(find.text(otp(activation('a1', 'Work', counter: 3))), findsOneWidget);
      expect(backend.writeCount, writes);
      expect(rawProfiles(), blob);
      expect(keystore.authenticateCalls, 0);
    });
  });
}
