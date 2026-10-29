import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/storage/profile_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

void main() {
  test('policy round-trips through JSON and copyWith', () {
    final profile = Profile(id: 'a1', name: 'Cloud', activationCode: 'AERUK-Z4JVP-G66AJ-DBACL', counter: 0);
    final timeBased = profile.copyWith(policy: '75817049');
    expect(timeBased.isTimeBased, isTrue);
    final restored = Profile.fromJson(jsonDecode(jsonEncode(timeBased.toJson())) as Map<String, dynamic>);
    expect((restored.policy, restored.isTimeBased, restored.otpPolicy!.timeStep), ('75817049', true, 60));
    expect(restored.copyWith(name: 'Other').policy, '75817049');
  });

  test('a challenge-response profile has no counter-driven code', () {
    final profile = Profile(
      id: 'c1',
      name: 'Portal',
      activationCode: 'HCF4B-47YNP-OVAPP-4BAE2',
      counter: 0,
      policy: '38039554',
    );
    expect((profile.isChallengeResponse, profile.isTimeBased, profile.usesCounter), (true, false, false));
    expect(otpForProfile(profile), isNull);
    expect(challengeResponseForProfile(profile, '123456'), '506945');
    expect(challengeResponseForProfile(profile, '12345'), isNull);
    final restored = Profile.fromJson(jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>);
    expect((restored.isChallengeResponse, restored.otpPolicy!.challengeLength), (true, 6));
  });

  test('an unparseable stored policy produces no code', () {
    final profile = Profile(id: 'a1', name: 'X', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 0, policy: '1');
    expect(profile.otpPolicy, isNull);
    expect(otpForProfile(profile), isNull);
  });

  test('time-based codes ignore the counter and use the clock', () {
    final profile = Profile(
      id: 'a1',
      name: 'Cloud',
      activationCode: 'VTH7N-PZJYN-M3TMH-QBACP',
      counter: 0,
      policy: '75817049',
    );
    expect(otpForProfile(profile, now: DateTime.fromMillisecondsSinceEpoch(1791875555 * 1000)), '672964');
    expect(otpForProfile(profile, now: DateTime.fromMillisecondsSinceEpoch(1791875580 * 1000)), '176058');
    expect(secondsUntilNextCode(DateTime.fromMillisecondsSinceEpoch(1791875555 * 1000), 60), 25);
  });

  test('the policy is stored in plain text and survives locking a protected profile', () async {
    final backend = MemoryKeyValueBackend();
    final store = ProfileStore(backend, keystore: FakeKeystore());
    await store.saveAll([
      Profile(
        id: 'a1',
        name: 'Cloud',
        activationCode: 'AERUK-Z4JVP-G66AJ-DBACL',
        counter: 0,
        policy: '75817049',
        protected: true,
      ),
    ]);
    final raw = backend.rawValue(ProfileStore.storageKey)!;
    expect(raw, contains('"policy":"75817049"'));
    expect(raw, isNot(contains('AERUK')));

    await store.forget();
    final locked = (await store.loadAll()).single;
    expect((locked.locked, locked.policy, locked.isTimeBased), (true, '75817049', true));
    await store.updateProfile('a1', (p) => p.copyWith(name: 'Renamed'));
    expect(backend.rawValue(ProfileStore.storageKey), contains('"policy":"75817049"'));
  });
}
