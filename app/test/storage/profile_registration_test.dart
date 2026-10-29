import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/mobilepass_registration.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/storage/profile_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

const _registration = MobilePassRegistration(
  enrollmentString: 'original enrollment string with vendor fields',
  url: 'https://enroll.example.test/path',
  userId: 'enrollment-user',
  passphrase: 'registration-password',
);

Profile _profile({bool protected = false}) => Profile(
  id: 'auto',
  name: 'Work',
  activationCode: '',
  kind: ProfileKind.mobilePassKey,
  key: 'dGVzdC1rZXk=',
  counter: 7,
  pin: '2468',
  registration: _registration,
  protected: protected,
);

void main() {
  test('JSON and copies preserve enrollment inputs', () {
    final original = _profile();
    final legacy = {..._registration.toJson(), 'pin': 'old-pin'};
    expect(MobilePassRegistration.fromJson(legacy).toJson(), isNot(contains('pin')));
    expect(Profile.fromJson(original.toJson()).registration, _registration);
    expect(original.copyWith(name: 'Renamed', counter: 2).registration, _registration);
    final old = original.toJson()..remove('registration');
    expect(Profile.fromJson(old).registration, isNull);
  });

  test('enrollment inputs are sealed, forgotten, passed through and restored with the OTP key', () async {
    final backend = MemoryKeyValueBackend();
    final keystore = FakeKeystore();
    final store = ProfileStore(backend, keystore: keystore);
    await store.saveAll([_profile(protected: true)]);
    final before = backend.rawValue(ProfileStore.storageKey)!;
    final entry = (jsonDecode(before)['profiles'] as List).single as Map;
    expect(entry.containsKey('registration'), isFalse);
    for (final secret in [
      _registration.enrollmentString,
      _registration.url,
      _registration.userId,
      _registration.passphrase,
    ]) {
      expect(before, isNot(contains(secret)));
    }
    expect((await store.loadAll()).single.registration, _registration);
    await store.forget();
    final locked = (await store.loadAll()).single;
    expect(locked.locked, isTrue);
    expect(locked.registration, isNull);
    await store.updateProfile('auto', (p) => p.copyWith(name: 'Renamed', counter: 8));
    final after = (jsonDecode(backend.rawValue(ProfileStore.storageKey)!)['profiles'] as List).single as Map;
    expect(after['sealed'], entry['sealed']);
    final reopened = (await store.unlockApp()).single;
    expect(reopened.registration, _registration);
    expect(reopened.counter, 8);
  });

  test('PIN edits and protection toggles preserve enrollment inputs', () async {
    final backend = MemoryKeyValueBackend();
    final store = ProfileStore(backend, keystore: FakeKeystore());
    await store.saveAll([_profile()]);
    await store.setAllProtected(true);
    await store.updateProfile('auto', (p) => p.copyWith(pin: '5678'));
    await store.forget();
    await store.unlockApp();
    final unsealed = (await store.setAllProtected(false)).single;
    expect(unsealed.registration, _registration);
    expect(unsealed.pin, '5678');
    expect((await store.loadAll()).single.registration, _registration);
  });
}
