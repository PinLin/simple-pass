import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/storage/profile_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

// RFC 6238 appendix B seeds in Base32.
const _sha1Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const _sha256Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA';
const _link = 'otpauth://totp/Example:alice@example.com?secret=$_sha1Secret&issuer=Example&digits=8';

Profile _oath(String credential, {ProfileKind kind = ProfileKind.totp, int counter = 0, String pin = ''}) => Profile(
  id: 't1',
  name: 'Example: alice@example.com',
  activationCode: '',
  kind: kind,
  key: credential,
  pin: pin,
  counter: counter,
  createdAt: DateTime.utc(2026, 10, 1),
);

List<Map<String, dynamic>> _stored(MemoryKeyValueBackend backend) => [
  for (final e in (jsonDecode(backend.rawValue(ProfileStore.storageKey)!) as Map)['profiles'] as List)
    e as Map<String, dynamic>,
];

DateTime _at(int unixSeconds) => DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

void main() {
  group('JSON', () {
    test('the credential round-trips exactly as entered, link or Base32, with nothing else', () {
      for (final credential in [_link, _sha1Secret, 'gezd gnbv gy3t qojq gezd gnbv gy3t qojq']) {
        final json = _oath(credential).toJson();
        expect(json['kind'], 'totp');
        expect(json['key'], credential);
        for (final field in ['issuer', 'account', 'algorithm', 'digits', 'period']) {
          expect(json.containsKey(field), isFalse, reason: field);
        }
        final back = Profile.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
        expect(back.key, credential);
        expect(back.kind, ProfileKind.totp);
      }
    });

    test('parameters come from the link; a bare secret means SHA1, 6 digits, 30 seconds', () {
      final link = _oath('otpauth://totp/x?secret=$_sha256Secret&algorithm=SHA256&digits=8&period=60');
      expect(link.oathCredential!.algorithm, OtpAlgorithm.sha256);
      expect(link.codeDigits, 8);
      expect(link.timeStep, 60);
      final bare = _oath(_sha1Secret);
      expect(bare.oathCredential!.algorithm, OtpAlgorithm.sha1);
      expect(bare.codeDigits, 6);
      expect(bare.timeStep, 30);
      expect(bare.isTimeBased, isTrue);
      expect(bare.usesCounter, isFalse);
    });

    test('a HOTP profile uses its counter', () {
      final p = Profile.fromJson(
        _oath('otpauth://hotp/x?secret=$_sha1Secret&counter=5', kind: ProfileKind.hotp, counter: 9).toJson(),
      );
      expect(p.usesCounter, isTrue);
      expect(p.isTimeBased, isFalse);
      expect(p.timeStep, isNull);
      expect(p.counter, 9);
    });

    test('MobilePASS profiles are stored exactly as before', () {
      final json = Profile(id: 'a1', name: 'Work', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 3).toJson();
      expect(json.keys.toSet(), {
        'id',
        'name',
        'activationCode',
        'counter',
        'pin',
        'policy',
        'appendPinOnCopy',
        'protected',
        'createdAt',
      });
      final p = Profile.fromJson({
        'id': 'a1',
        'name': 'Work',
        'activationCode': 'APSCG-YKKAU-NEZGC-PRDSM',
        'counter': 3,
        'pin': '',
        'policy': '',
        'createdAt': '2026-01-01T00:00:00.000Z',
      });
      expect(p.kind, ProfileKind.activationCode);
      expect(p.hasValidOtpParameters, isTrue);
      expect(p.codeDigits, 6);
    });

    test('an unusable credential loads but produces no code', () {
      for (final bad in [
        'otpauth://totp/x?secret=$_sha1Secret&algorithm=MD5',
        'not base32!',
        'otpauth-migration://x',
      ]) {
        final p = Profile.fromJson(_oath(bad).toJson());
        expect(p.hasValidOtpParameters, isFalse, reason: bad);
        expect(otpForProfile(p, now: _at(59)), isNull, reason: bad);
        expect(p.copyWith(name: 'Renamed').toJson()['key'], bad);
      }
    });

    test('a kind from a newer version is still refused loudly', () {
      expect(() => Profile.fromJson({..._oath(_link).toJson(), 'kind': 'steam'}), throwsFormatException);
    });
  });

  group('codes', () {
    test('TOTP follows RFC 6238, from a link or a bare secret', () {
      expect(otpForProfile(_oath(_link), now: _at(59)), '94287082');
      expect(otpForProfile(_oath(_link), now: _at(1111111109)), '07081804');
      expect(otpForProfile(_oath(_sha1Secret), now: _at(1234567890)), '005924');
      expect(otpForProfile(_oath('gezd gnbv gy3t qojq gezd gnbv gy3t qojq'), now: _at(59)), '287082');
    });

    test('HOTP follows the profile counter, not the link counter, and ignores the clock', () {
      final p = _oath('otpauth://hotp/x?secret=$_sha1Secret&counter=0', kind: ProfileKind.hotp, counter: 1);
      expect(otpForProfile(p, now: _at(0)), '287082');
      expect(otpForProfile(p, now: _at(1234567890)), '287082');
      expect(otpForProfile(p.copyWith(counter: 2), now: _at(0)), '359152');
    });

    test('the countdown counts from the Unix epoch for every period', () {
      final p = _oath('otpauth://totp/x?secret=$_sha1Secret&period=45');
      expect(secondsUntilProfileCode(p, _at(0)), 45);
      expect(secondsUntilProfileCode(p, _at(44)), 1);
      expect(secondsUntilProfileCode(p, _at(45)), 45);
    });
  });

  group('ProfileStore', () {
    test('protection seals the credential (the whole link) with the PIN', () async {
      final backend = MemoryKeyValueBackend();
      final keystore = FakeKeystore();
      final store = ProfileStore(backend, keystore: keystore);
      await store.saveAll([_oath(_link, pin: '2468')]);
      await store.updateProfile('t1', (p) => p.copyWith(protected: true));

      final raw = _stored(backend).single;
      expect(raw.containsKey('key'), isFalse);
      expect(raw['kind'], 'totp');
      expect(jsonEncode(raw), isNot(contains(_sha1Secret)));
      expect(jsonEncode(raw), isNot(contains('otpauth')));
      final sealed = raw['sealed'] as String;
      final secret = jsonDecode(await keystore.decrypt('profile_secrets', sealed.substring(sealed.indexOf(':') + 1)));
      expect(secret, {'a': '', 'k': _link, 'p': '2468'});

      await store.forget();
      keystore.expire();
      final locked = (await store.loadAll()).single;
      expect(locked.locked, isTrue);
      expect(locked.key, '');
      expect(locked.hasValidOtpParameters, isTrue);
      expect(otpForProfile(locked, now: _at(59)), isNull);

      final unlocked = (await store.unlockApp(sealUnprotected: false)).single;
      expect(unlocked.key, _link);
      expect(otpForProfile(unlocked, now: _at(59)), '94287082');
    });
  });
}
