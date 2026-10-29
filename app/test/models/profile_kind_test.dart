import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/storage_exceptions.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';
// K_TOKEN of a recorded registration (test/fixtures/dskpp_vectors.json) under its time-based policy.
const _tokenKeyHex = 'caa663cb6bc4a154a68ff4c72142e0df2b237ccd0be81a3a4332e582f037a105';

Uint8List _hex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

final _key = base64.encode(_hex(_tokenKeyHex));

Profile _enrolled({String policy = '9381', String pin = '2468'}) => Profile(
  id: 'k1',
  name: 'Enrolled',
  activationCode: '',
  kind: ProfileKind.mobilePassKey,
  key: _key,
  serial: '123456789',
  policy: policy,
  pin: pin,
  counter: 0,
  createdAt: DateTime.utc(2026, 10, 1),
);

List<Map<String, dynamic>> _stored(MemoryKeyValueBackend backend) => [
  for (final e in (jsonDecode(backend.rawValue(ProfileStore.storageKey)!) as Map)['profiles'] as List)
    e as Map<String, dynamic>,
];

void main() {
  group('JSON', () {
    test('an activation code profile is written exactly as before kinds existed', () {
      final json = Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 3).toJson();
      expect(json.containsKey('kind'), isFalse);
      expect(json.containsKey('key'), isFalse);
      expect(json.containsKey('serial'), isFalse);
    });

    test('a stored profile without a kind loads as an activation code profile', () {
      final p = Profile.fromJson({
        'id': 'a1',
        'name': 'Work',
        'activationCode': _code,
        'counter': 3,
        'pin': '',
        'policy': '',
        'createdAt': '2026-01-01T00:00:00.000Z',
      });
      expect(p.kind, ProfileKind.activationCode);
      expect(p.holdsKey, isFalse);
      expect(p.key, '');
      expect(p.hasSecret, isTrue);
    });

    test('a key profile round-trips kind, key, serial and policy', () {
      final json = jsonDecode(jsonEncode(_enrolled().toJson())) as Map<String, dynamic>;
      expect(json['kind'], 'mobilePassKey');
      final p = Profile.fromJson(json);
      expect(p.kind, ProfileKind.mobilePassKey);
      expect(p.key, _key);
      expect(p.serial, '123456789');
      expect(p.policy, '9381');
      expect(p.pin, '2468');
      expect(p.activationCode, '');
      expect(p.hasSecret, isTrue);
      expect(p.copyWith(name: 'x').key, _key);
      expect(p.copyWith(name: 'x').kind, ProfileKind.mobilePassKey);
    });

    test('a kind from a newer version is refused rather than misread', () {
      expect(
        () => Profile.fromJson({
          'id': 'a1',
          'name': 'Work',
          'activationCode': '',
          'kind': 'somethingNew',
          'counter': 0,
          'createdAt': '2026-01-01T00:00:00.000Z',
        }),
        throwsFormatException,
      );
    });

    test('a key profile with an out-of-range counter is refused', () {
      final json = _enrolled(policy: '9346').toJson()..['counter'] = -1;
      expect(() => Profile.fromJson(json), throwsFormatException);
    });
  });

  group('codes', () {
    test('the key is used as is, under the server policy', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000010 * 1000);
      expect(otpForProfile(_enrolled(), now: now), '891699');
      expect(otpForProfile(_enrolled(policy: '9346').copyWith(counter: 2)), '658163');
    });

    test('challenge-response policies answer with the key', () {
      final p = _enrolled(policy: '38039554');
      final response = challengeResponseForProfile(p, '123456');
      expect(response, generateKeyChallengeResponse(_hex(_tokenKeyHex), '38039554', '123456'));
    });

    test('no code without a usable key', () {
      expect(otpForProfile(_enrolled().copyWith(key: '')), isNull);
      expect(otpForProfile(_enrolled().copyWith(key: '!!!')), isNull);
      expect(_enrolled().copyWith(key: '').hasSecret, isFalse);
    });
  });

  group('ProfileStore', () {
    test('an unprotected key profile survives a reload', () async {
      final backend = MemoryKeyValueBackend();
      await ProfileStore(backend).saveAll([_enrolled()]);
      final loaded = (await ProfileStore(backend).loadAll()).single;
      expect(loaded.key, _key);
      expect(loaded.kind, ProfileKind.mobilePassKey);
    });

    test('protection seals the key with the PIN and nothing secret stays in the clear', () async {
      final backend = MemoryKeyValueBackend();
      final keystore = FakeKeystore();
      final store = ProfileStore(backend, keystore: keystore);
      await store.saveAll([_enrolled()]);
      await store.updateProfile('k1', (p) => p.copyWith(protected: true));

      final raw = _stored(backend).single;
      expect(raw.containsKey('key'), isFalse);
      expect(raw.containsKey('pin'), isFalse);
      expect(raw['kind'], 'mobilePassKey');
      expect(raw['serial'], '123456789');
      expect(jsonEncode(raw), isNot(contains(_key)));
      final sealed = raw['sealed'] as String;
      final secret = jsonDecode(await keystore.decrypt('profile_secrets', sealed.substring(sealed.indexOf(':') + 1)));
      expect(secret, {'a': '', 'k': _key, 'p': '2468'});

      await store.forget();
      keystore.expire();
      final locked = (await store.loadAll()).single;
      expect(locked.locked, isTrue);
      expect(locked.key, '');
      expect(locked.hasSecret, isFalse);
      expect(otpForProfile(locked), isNull);

      // Saving while locked carries the sealed key through untouched.
      await store.updateProfile('k1', (p) => p.copyWith(name: 'Renamed'));
      expect(_stored(backend).single['sealed'], sealed);

      final unlocked = (await store.unlockApp(sealUnprotected: false)).single;
      expect(unlocked.key, _key);
      expect(unlocked.pin, '2468');
      expect(unlocked.name, 'Renamed');
    });

    test('turning protection off puts the key back in the clear', () async {
      final backend = MemoryKeyValueBackend();
      final store = ProfileStore(backend, keystore: FakeKeystore());
      await store.saveAll([_enrolled()]);
      await store.updateProfile('k1', (p) => p.copyWith(protected: true));
      await store.updateProfile('k1', (p) => p.copyWith(protected: false));
      final raw = _stored(backend).single;
      expect(raw['key'], _key);
      expect(raw.containsKey('sealed'), isFalse);
    });

    test('activation code profiles seal exactly what they sealed before', () async {
      final backend = MemoryKeyValueBackend();
      final keystore = FakeKeystore();
      final store = ProfileStore(backend, keystore: keystore);
      await store.saveAll([Profile(id: 'a1', name: 'W', activationCode: _code, counter: 0, pin: '1234')]);
      await store.updateProfile('a1', (p) => p.copyWith(protected: true));
      final sealed = _stored(backend).single['sealed'] as String;
      final secret = jsonDecode(await keystore.decrypt('profile_secrets', sealed.substring(sealed.indexOf(':') + 1)));
      expect(secret, {'a': _code, 'p': '1234'});
    });

    test('an auth failure while protecting a key profile writes nothing', () async {
      final backend = MemoryKeyValueBackend();
      final keystore = FakeKeystore()..authResults.add(AuthResult.canceled);
      final store = ProfileStore(backend, keystore: keystore);
      await store.saveAll([_enrolled()]);
      final before = backend.rawValue(ProfileStore.storageKey);
      await expectLater(
        store.updateProfile('k1', (p) => p.copyWith(protected: true)),
        throwsA(isA<AuthFailedException>()),
      );
      expect(backend.rawValue(ProfileStore.storageKey), before);
    });
  });
}
