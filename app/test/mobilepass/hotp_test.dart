import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/hotp.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';

void main() {
  const legacyNoPolicy = 'APSCG-YKKAU-NEZGC-PRDSM';
  const expected = {0: '289693', 1: '270133', 2: '158188'};

  group('known-answer vectors', () {
    expected.forEach((counter, otp) {
      test('no policy, counter $counter -> $otp', () {
        expect(generateMobilePassOtp(legacyNoPolicy, counter), otp);
      });
    });

    test('v2 event-based, 8 digits', () {
      expect(generateMobilePassOtp('MQ57Q-JKGBQ-PF77Z-PBAAS', 0, policy: '18921500'), '58763920');
    });

    test('v2 mode 4 event-based preset', () {
      expect(generateMobilePassOtp('UDAU3-5SFBJ-RK7A7-SBABC', 0, policy: '9346'), '433613');
    });

    test('v2 time-based, 60 s, 6 digits', () {
      expect(generateMobilePassTimeOtp('VTH7N-PZJYN-M3TMH-QBACP', '75817049', 1791875555), '672964');
    });

    test('v2 time-based, 20 s, 8 digits', () {
      const code = 'SWZQS-TCONV-RYRBA-YBABO';
      expect(generateMobilePassTimeOtp(code, '75948051', 1791875659), '38600017');
      expect(generateMobilePassTimeOtp(code, '75948051', 1791875884), '55650458');
    });

    test('v2 mode 5 time-based preset, 30 s', () {
      expect(generateMobilePassTimeOtp('UCXP4-GHVQB-O2PSB-KBADI', '9381', 1791875758), '330686');
    });
  });

  group('fixture vectors', () {
    final fixtureFile = File('test/fixtures/mobilepass_vectors.json');
    final fixture = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final vectors = fixture['vectors'] as List<dynamic>;

    test('fixture file has at least 1000 vectors', () {
      expect(vectors.length, greaterThanOrEqualTo(1000));
    });

    test('every vector matches the Dart implementation', () {
      for (final entry in vectors) {
        final map = entry as Map<String, dynamic>;
        final activationCode = map['activationCode'] as String;
        final counter = map['counter'] as int;
        final expectedOtp = map['otp'] as String;
        expect(
          generateMobilePassOtp(activationCode, counter),
          expectedOtp,
          reason: 'activationCode=$activationCode counter=$counter',
        );
      }
    });
  });

  group('policy', () {
    const legacyCode = 'AAISK-EM2EJ-KVTHT-PCEZN';
    const versionedCode = 'AERUK-Z4JVP-G66AJ-DBACL';

    test('legacy code without policy', () {
      expect([0, 1, 2].map((c) => generateMobilePassOtp(legacyCode, c)), ['669021', '925556', '871342']);
    });

    test('an empty or v1 policy leaves the key unchanged', () {
      final seed = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01, 0x23]);
      expect(deriveHotpKey(seed, ''), deriveHotpKey(seed));
      for (final counter in [0, 1, 2]) {
        expect(generateMobilePassOtp(legacyNoPolicy, counter, policy: ''), expected[counter]);
      }
    });

    test('a v2 policy is part of the key', () {
      final seed = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01, 0x23]);
      final key = deriveHotpKey(seed, '18921500');
      expect(
        key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '302eb9ba59d0a48d6448bd3dc0f9a668ef4581d56c2e0f0351b93a57cc9589bc',
      );
    });

    test('time-based codes count time steps from 2000-01-01', () {
      expect(timeBasedCounter(1700000000, 30), 25110506);
      expect(timeBasedCounter(1700000030, 30), 25110507);
      expect(timeBasedCounter(2000000000, 30), 35110506);
      const code = 'SWZQS-TCONV-RYRBA-YBABO';
      expect(timeBasedCounter(1791875640, 20), 42259542);
      expect(timeBasedCounter(1791875660, 20), 42259543);
      expect(generateMobilePassTimeOtp(code, '75948051', 1791875640), '38600017');
      expect(generateMobilePassTimeOtp(code, '75948051', 1791875659), '38600017');
      expect(generateMobilePassTimeOtp(code, '75948051', 1791875660), isNot('38600017'));
    });

    test('time-based OTP rejects an event-based policy', () {
      expect(
        () => generateMobilePassTimeOtp(versionedCode, '18921500', 1700000000),
        throwsA(isA<MobilePassException>().having((e) => e.code, 'code', MobilePassErrorCode.unsupportedOtpType)),
      );
    });

    test('8-digit codes keep the 6-digit code as their last six digits', () {
      final key = deriveHotpKey(Uint8List.fromList([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99]));
      expect([0, 1, 2].map((c) => generateHotp(key, c, digits: 8)), ['24669021', '56925556', '81871342']);
    });

    test('an 8-digit event-based policy yields 8 digits', () {
      final otp = generateMobilePassOtp(versionedCode, 0, policy: '18921500');
      expect(otp, hasLength(8));
      expect(otp, matches(RegExp(r'^\d{8}$')));
      expect([1, 2].map((c) => generateMobilePassOtp(versionedCode, c, policy: '18921500')), ['55850479', '35592670']);
      expect(otp, '28768760');
    });

    test('an invalid policy throws', () {
      expect(
        () => generateMobilePassOtp(legacyCode, 0, policy: '75817048'),
        throwsA(isA<MobilePassException>().having((e) => e.code, 'code', MobilePassErrorCode.invalidPolicy)),
      );
    });
  });

  group('invalid counter', () {
    test('negative counter throws MobilePassException', () {
      expect(
        () => generateMobilePassOtp(legacyNoPolicy, -1),
        throwsA(isA<MobilePassException>().having((e) => e.code, 'code', MobilePassErrorCode.invalidCounter)),
      );
    });
  });
}
