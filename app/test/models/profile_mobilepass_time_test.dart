import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/otpauth/base32.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/storage/profile_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

// A versioned (v2) Activation Code, as the time-based MobilePASS tests elsewhere use.
const _timeCode = 'VTH7N-PZJYN-M3TMH-QBACP';

DateTime _at(int unixSeconds) => DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

const _times = [946684800, 946684859, 1000000000, 1700000000, 1700000029, 1791875555, 1791875640, 2000000000];

Profile _mobilePass(String policy) =>
    Profile(id: 'm', name: 'Work', activationCode: _timeCode, policy: policy, counter: 0);

// What a "Use MobilePASS format" TOTP stores for the same key: SHA-256 with the policy's digits and period.
Profile _manualTotp(String secret, {required int digits, required int period, required bool mobilePassTime}) => Profile(
  id: 't',
  name: 'Work',
  activationCode: '',
  counter: 0,
  kind: ProfileKind.totp,
  key: 'otpauth://totp/Work?secret=$secret&algorithm=SHA256&digits=$digits&period=$period',
  mobilePassTime: mobilePassTime,
);

void main() {
  group('equivalence with a MobilePASS time-based profile', () {
    for (final policy in ['75817049', '75948051', '9381', '75890738']) {
      test('policy $policy', () {
        final original = _mobilePass(policy);
        final parsed = original.otpPolicy!;
        final secret = base32Encode(mobilePassKeyOf(original)!);
        final same = _manualTotp(secret, digits: parsed.digits, period: parsed.timeStep!, mobilePassTime: true);
        final unix = _manualTotp(secret, digits: parsed.digits, period: parsed.timeStep!, mobilePassTime: false);
        for (final t in _times) {
          final expected = otpForProfile(original, now: _at(t));
          expect(expected, isNotNull);
          expect(otpForProfile(same, now: _at(t)), expected, reason: 'at $t');
          expect(otpForProfile(unix, now: _at(t)), isNot(expected), reason: 'at $t');
          expect(secondsUntilProfileCode(same, _at(t)), secondsUntilProfileCode(original, _at(t)), reason: 'at $t');
        }
      });
    }
  });

  group('time origin', () {
    test('steps count from 2000-01-01 UTC only with the flag', () {
      final secret = base32Encode(mobilePassKeyOf(_mobilePass('75817049'))!);
      expect(_manualTotp(secret, digits: 6, period: 30, mobilePassTime: true).timeEpochSeconds, 946684800);
      expect(_manualTotp(secret, digits: 6, period: 30, mobilePassTime: false).timeEpochSeconds, 0);
      expect(_mobilePass('75817049').timeEpochSeconds, timeCounterEpochSeconds);
    });

    test('a clock still before 2000 gives no code instead of throwing', () {
      final secret = base32Encode(mobilePassKeyOf(_mobilePass('75817049'))!);
      final flagged = _manualTotp(secret, digits: 6, period: 30, mobilePassTime: true);
      expect(otpForProfile(flagged, now: _at(0)), isNull);
      expect(otpForProfile(flagged, now: _at(946684799)), isNull);
      expect(otpForProfile(flagged, now: _at(946684800)), isNotNull);
    });

    // 2000-01-01 is not a multiple of 7 s after 1970, so the two countdowns part ways.
    test('the countdown follows the same origin as the codes', () {
      final secret = base32Encode(mobilePassKeyOf(_mobilePass('75817049'))!);
      final flagged = _manualTotp(secret, digits: 6, period: 7, mobilePassTime: true);
      final plain = _manualTotp(secret, digits: 6, period: 7, mobilePassTime: false);
      expect(secondsUntilProfileCode(flagged, _at(946684800)), 7);
      expect(secondsUntilProfileCode(flagged, _at(946684806)), 1);
      expect(secondsUntilProfileCode(plain, _at(0)), 7);
      expect(secondsUntilProfileCode(plain, _at(946684800)), isNot(7));
    });

    test('a flagged profile has no export link', () {
      final secret = base32Encode(mobilePassKeyOf(_mobilePass('75817049'))!);
      final flagged = _manualTotp(secret, digits: 6, period: 60, mobilePassTime: true);
      expect(equivalentOtpLink(flagged, name: 'Work', counter: 0), isNull);
      expect(
        equivalentOtpLink(_manualTotp(secret, digits: 6, period: 60, mobilePassTime: false), name: 'Work', counter: 0),
        isNotNull,
      );
    });
  });

  group('JSON', () {
    test('round-trips the flag and keeps the credential as stored', () {
      final p = _manualTotp('JBSWY3DPEHPK3PXP', digits: 8, period: 45, mobilePassTime: true);
      final json = p.toJson();
      expect(json['mobilePassTime'], isTrue);
      final restored = Profile.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(restored.mobilePassTime, isTrue);
      expect(restored.key, p.key);
    });

    test('data without the field reads as a plain TOTP, and plain profiles keep writing nothing', () {
      final p = _manualTotp('JBSWY3DPEHPK3PXP', digits: 6, period: 30, mobilePassTime: false);
      final json = p.toJson();
      expect(json.containsKey('mobilePassTime'), isFalse);
      expect(Profile.fromJson(json).mobilePassTime, isFalse);
      final withoutFlag = {
        'id': 'old',
        'name': 'Old',
        'activationCode': '',
        'kind': 'totp',
        'key': 'JBSWY3DPEHPK3PXP',
        'serial': '',
        'counter': 0,
        'pin': '',
        'policy': '',
        'createdAt': '2026-01-01T00:00:00.000',
      };
      final read = Profile.fromJson(withoutFlag);
      expect((read.mobilePassTime, read.timeEpochSeconds), (false, 0));
    });

    test('copyWith keeps the flag', () {
      final p = _manualTotp('JBSWY3DPEHPK3PXP', digits: 6, period: 30, mobilePassTime: true);
      expect(p.copyWith(name: 'Other', protected: true).mobilePassTime, isTrue);
    });
  });

  group('ProfileStore', () {
    test('the flag is stored in the clear next to a sealed credential and survives lock and unlock', () async {
      final backend = MemoryKeyValueBackend();
      final store = ProfileStore(backend, keystore: FakeKeystore());
      final p = _manualTotp('JBSWY3DPEHPK3PXP', digits: 6, period: 30, mobilePassTime: true);
      await store.saveAll([p]);
      expect((await store.loadAll()).single.mobilePassTime, isTrue);

      await store.updateProfile('t', (p) => p.copyWith(protected: true));
      final raw = (jsonDecode(backend.rawValue(ProfileStore.storageKey)!) as Map)['profiles'] as List;
      expect((raw.single as Map)['mobilePassTime'], isTrue);
      expect((raw.single as Map).containsKey('key'), isFalse);

      await store.forget();
      final locked = (await store.loadAll()).single;
      expect((locked.locked, locked.mobilePassTime), (true, true));
      final unlocked = (await store.unlockApp(sealUnprotected: false)).single;
      expect((unlocked.key, unlocked.mobilePassTime), (p.key, true));
    });
  });
}
