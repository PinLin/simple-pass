import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/l10n/gen/app_localizations.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/otpauth/base32.dart';
import 'package:simple_pass/otpauth/otpauth_uri.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';
import 'package:simple_pass/screens/otp_helpers.dart';

const _knownCode = 'XLOH5-NFAMR-3Z5TW-6EL5Y';
const _knownSecret = '6AUQT6RLB5EWBTRGXFRZOAQDSOP5WVZ75V6XMXZUS7MQTTWEUUZA';
const _eightDigitCode = 'MQ57Q-JKGBQ-PF77Z-PBAAS';
const _timeCode = 'VTH7N-PZJYN-M3TMH-QBACP';
const _registeredKey = 'yqZjy2vEoVSmj/THIULg3ysjfM0L6Bo6QzLlgvA3oQU=';
const _totpLink = 'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP';
const _hotpLink = 'otpauth://hotp/Example:alice?secret=JBSWY3DPEHPK3PXP&counter=3';

Profile _manual({String code = _knownCode, String policy = ''}) =>
    Profile(id: 'm', name: 'M', activationCode: code, policy: policy, counter: 0);

Profile _registered({String policy = '9346'}) => Profile(
  id: 'r',
  name: 'R',
  activationCode: '',
  kind: ProfileKind.mobilePassKey,
  key: _registeredKey,
  serial: '123456789',
  policy: policy,
  counter: 0,
);

Profile _standard(ProfileKind kind, String key) =>
    Profile(id: 's', name: 'S', activationCode: '', kind: kind, key: key, counter: 0);

void main() {
  group('mobilePassKeyFor', () {
    test('known answer: the key behind a known Activation Code', () {
      expect(base32Encode(mobilePassKeyFor(_knownCode)), _knownSecret);
    });

    test('known answer: that code makes the documented one-time passwords', () {
      expect([for (var c = 0; c < 3; c++) generateMobilePassOtp(_knownCode, c)], ['848789', '229833', '131821']);
    });

    test('generateKeyOtp with the worked-out key matches generateMobilePassOtp', () {
      final key = mobilePassKeyFor(_eightDigitCode, policy: '18921500');
      for (var c = 0; c < 4; c++) {
        expect(
          generateKeyOtp(key, c, policy: '18921500'),
          generateMobilePassOtp(_eightDigitCode, c, policy: '18921500'),
        );
      }
    });
  });

  group('mobilePassKeyOf', () {
    test('manual: the worked-out key', () {
      expect(base32Encode(mobilePassKeyOf(_manual())!), _knownSecret);
    });

    test('auto enrollment: the registered base64 key', () {
      expect(mobilePassKeyOf(_registered()), base64.decode(_registeredKey));
    });

    test('standard tokens and broken data give null', () {
      expect(mobilePassKeyOf(_standard(ProfileKind.totp, _totpLink)), isNull);
      expect(mobilePassKeyOf(_standard(ProfileKind.hotp, _hotpLink)), isNull);
      expect(mobilePassKeyOf(_manual(code: 'not a code')), isNull);
      expect(mobilePassKeyOf(_registered().copyWith(key: '***')), isNull);
      expect(mobilePassKeyOf(_registered().copyWith(key: '')), isNull);
    });
  });

  group('equivalentHotpLink round trip', () {
    // (label, profile, digits, MobilePASS's own code for a counter)
    final cases = <(String, Profile, int, String Function(int))>[
      ('manual, no policy, 6 digits', _manual(), 6, (c) => generateMobilePassOtp(_knownCode, c)),
      (
        'manual, 8-digit event policy',
        _manual(code: _eightDigitCode, policy: '18921500'),
        8,
        (c) => generateMobilePassOtp(_eightDigitCode, c, policy: '18921500'),
      ),
      (
        'auto enrollment (base64 key)',
        _registered(),
        6,
        (c) => generateKeyOtp(base64.decode(_registeredKey), c, policy: '9346'),
      ),
    ];

    for (final (label, profile, digits, own) in cases) {
      test(label, () {
        for (final start in [0, 7, 123456]) {
          final link = equivalentHotpLink(profile, name: 'Work', counter: start)!;
          expect(link, startsWith('otpauth://hotp/Work?secret='));
          expect(link, contains('algorithm=SHA256'));
          expect(link, contains('digits=$digits'));
          expect(link, endsWith('&counter=$start'));
          expect(link, isNot(contains('=&')));
          expect(link, isNot(contains('secret=${base32Encode(mobilePassKeyOf(profile)!)}=')));

          final parsed = parseOtpauthUri(link);
          expect(parsed.type, OtpauthType.hotp);
          expect(parsed.algorithm, OtpAlgorithm.sha256);
          expect(parsed.digits, digits);
          expect(parsed.counter, start);
          for (var i = 0; i < 5; i++) {
            expect(
              generateStandardHotp(parsed.secret, start + i, algorithm: parsed.algorithm, digits: parsed.digits),
              own(start + i),
              reason: '$label counter ${start + i}',
            );
          }
        }
      });
    }

    test('a name with spaces and a colon is encoded and parses back', () {
      final link = equivalentHotpLink(_manual(), name: 'My Bank: main', counter: 2)!;
      expect(link, startsWith('otpauth://hotp/${Uri.encodeComponent('My Bank: main')}?secret='));
      expect(link, isNot(contains(' ')));
      final parsed = parseOtpauthUri(link);
      expect(parsed.issuer, 'My Bank');
      expect(parsed.account, 'main');
      expect(parsed.counter, 2);
    });

    test('a counter outside the valid range gives no link', () {
      expect(equivalentHotpLink(_manual(), name: 'Work', counter: -1), isNull);
      expect(equivalentHotpLink(_manual(), name: 'Work', counter: maxCounter + 1), isNull);
      expect(equivalentHotpLink(_manual(), name: 'Work', counter: maxCounter), isNotNull);
    });

    test('time-based, challenge-response and standard profiles have no link', () {
      expect(
        equivalentHotpLink(
          _manual(code: _timeCode, policy: '75817049'),
          name: 'x',
          counter: 0,
        ),
        isNull,
      );
      expect(
        equivalentHotpLink(
          _manual(code: _timeCode, policy: '38039554'),
          name: 'x',
          counter: 0,
        ),
        isNull,
      );
      expect(equivalentHotpLink(_registered(policy: '9381'), name: 'x', counter: 0), isNull);
      expect(equivalentHotpLink(_standard(ProfileKind.totp, _totpLink), name: 'x', counter: 0), isNull);
      expect(equivalentHotpLink(_standard(ProfileKind.hotp, _hotpLink), name: 'x', counter: 0), isNull);
    });
  });

  group('standard export round trip', () {
    test('TOTP retains algorithm, digits, period, issuer and original credential', () {
      const original =
          'otpauth://totp/Bank:alice?secret=JBSWY3DPEHPK3PXP&algorithm=SHA512&digits=8&period=60&issuer=Bank';
      final profile = _standard(ProfileKind.totp, original);
      final link = equivalentOtpLink(profile, name: 'Renamed / 帳號', counter: 0)!;
      final parsed = parseOtpauthUri(link);
      final exported = _standard(ProfileKind.totp, link);
      expect(parsed.algorithm, OtpAlgorithm.sha512);
      expect(parsed.digits, 8);
      expect(parsed.period, 60);
      expect(parsed.issuer, 'Bank');
      expect(parsed.account, 'Renamed / 帳號');
      expect(otpForProfile(exported, now: DateTime.utc(2026)), otpForProfile(profile, now: DateTime.utc(2026)));
      expect(profile.key, original);
    });

    test('bare Base32 gets a TOTP link with default parameters', () {
      final profile = _standard(ProfileKind.totp, 'JBSWY3DPEHPK3PXP');
      final exported = _standard(ProfileKind.totp, equivalentOtpLink(profile, name: 'Bare', counter: 0)!);
      expect(otpForProfile(exported, now: DateTime.utc(2026)), otpForProfile(profile, now: DateTime.utc(2026)));
    });

    test('HOTP exports the current counter instead of the enrollment counter', () {
      final profile = _standard(ProfileKind.hotp, _hotpLink).copyWith(counter: 42);
      final link = equivalentOtpLink(profile, name: 'Current', counter: profile.counter)!;
      final parsed = parseOtpauthUri(link);
      expect(parsed.counter, 42);
      expect(
        otpForProfile(_standard(ProfileKind.hotp, link).copyWith(counter: parsed.counter)),
        otpForProfile(profile),
      );
      expect(profile.key, _hotpLink);
      expect(equivalentOtpLink(profile, name: 'Invalid', counter: -1), isNull);
    });
  });

  group('codes for any clock value', () {
    final times = [
      DateTime.utc(1969, 12, 31, 23, 59, 59),
      DateTime.utc(1970),
      DateTime.utc(1999, 12, 31, 23, 59, 59),
      DateTime.utc(2000),
      DateTime.utc(2100),
      DateTime.fromMillisecondsSinceEpoch(-8640000000000000, isUtc: true),
      DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
    ];
    final profiles = {
      'MobilePASS time': _manual(code: _timeCode, policy: '75817049'),
      'registered MobilePASS time': _registered(policy: '75817049'),
      'standard TOTP': Profile(
        id: 't',
        name: 'T',
        activationCode: '',
        kind: ProfileKind.totp,
        key: _totpLink,
        counter: 0,
      ),
      'standard TOTP on the MobilePASS clock': Profile(
        id: 't',
        name: 'T',
        activationCode: '',
        kind: ProfileKind.totp,
        key: '$_totpLink&algorithm=SHA256',
        counter: 0,
        mobilePassTime: true,
      ),
    };

    profiles.forEach((name, profile) {
      test('$name never throws, and has no code before its epoch', () {
        final epoch = DateTime.fromMillisecondsSinceEpoch(profile.timeEpochSeconds * 1000, isUtc: true);
        for (final now in times) {
          final code = otpForProfile(profile, now: now);
          expect(code == null, now.isBefore(epoch), reason: '$now');
          expect(() => secondsUntilProfileCode(profile, now), returnsNormally, reason: '$now');
        }
      });
    });
  });

  group('type labels', () {
    final profiles = <(String, Profile, List<String>)>[
      ('manual event', _manual(), ['HOTP', 'HOTP']),
      ('auto event', _registered(), ['HOTP', 'HOTP']),
      ('MobilePASS time', _manual(code: _timeCode, policy: '75817049'), ['TOTP', 'TOTP']),
      ('challenge-response', _manual(code: _timeCode, policy: '38039554'), ['Challenge-response', '挑戰回應']),
      ('standard TOTP', _standard(ProfileKind.totp, _totpLink), ['TOTP', 'TOTP']),
      ('standard HOTP', _standard(ProfileKind.hotp, _hotpLink), ['HOTP', 'HOTP']),
    ];

    for (final (label, profile, expected) in profiles) {
      test(label, () async {
        final en = await AppLocalizations.delegate.load(const Locale('en'));
        final zh = await AppLocalizations.delegate.load(const Locale('zh', 'Hant_TW'));
        expect(profileTypeLabel(en, profile), expected[0]);
        expect(profileTypeLabel(zh, profile), expected[1]);
      });
    }
  });

  group('profile details title spacing', () {
    test('zh drops the space before a Chinese type and keeps it before Latin ones', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh', 'Hant_TW'));
      expect(zh.profileDetailsTitle('挑戰回應', 'cjk'), '挑戰回應設定檔');
      expect(zh.profileDetailsTitle('TOTP', 'other'), 'TOTP 設定檔');
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(en.profileDetailsTitle('Challenge-response', 'cjk'), 'Challenge-response profile');
    });
  });
}
