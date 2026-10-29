import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/activation_code.dart' show checkCharacter;
import 'package:simple_pass/mobilepass/mobilepass.dart';

/// Builds a policy string from its bits after the leading 1 (version, mode, fields), appending the
/// check value, so tests can reach versions and modes no real policy uses.
String _policyFromBits(String bits) {
  final body = int.parse('1$bits', radix: 2);
  final char = checkCharacter(body.toString());
  final code = char.codeUnitAt(0);
  final int check;
  if (code >= 0x32 && code <= 0x37) {
    check = code - 0x30;
  } else {
    check = 0x5A - code > 7 ? 0x60 - code : 0x5A - code;
  }
  return int.parse('1$bits${check.toRadixString(2).padLeft(5, '0')}', radix: 2).toString();
}

Matcher _throwsCode(MobilePassErrorCode code) =>
    throwsA(isA<MobilePassException>().having((e) => e.code, 'code', code));

void main() {
  group('known policies', () {
    test('75817049: v2 time-based, 6 digits, PIN 4, 10 attacks, 60 s', () {
      final p = parsePolicy('75817049');
      expect((p.version, p.type, p.digits, p.timeStep), (2, OtpType.time, 6, 60));
      expect((p.pinLength, p.maxAttacks, p.pinUseChanges, p.attackDelay), (4, 10, 0, 0));
      expect((p.secureMode, p.transactionSigning), (false, false));
    });

    test('75948051: v2 time-based, 8 digits, PIN 4, 10 attacks, 20 s', () {
      final p = parsePolicy('75948051');
      expect((p.version, p.type, p.digits, p.timeStep), (2, OtpType.time, 8, 20));
      expect((p.pinLength, p.maxAttacks), (4, 10));
    });

    test('18921500: v2 event-based, 8 digits, PIN 4, 10 attacks', () {
      final p = parsePolicy('18921500');
      expect((p.version, p.type, p.digits, p.timeStep), (2, OtpType.event, 8, null));
      expect((p.pinLength, p.maxAttacks), (4, 10));
    });

    test('9346: v2 mode 4, event-based, 6 digits', () {
      final p = parsePolicy('9346');
      expect((p.version, p.type, p.digits, p.timeStep), (2, OtpType.event, 6, null));
      expect((p.pinLength, p.maxAttacks), (0, 0));
    });

    test('9381: v2 mode 5, time-based, 6 digits, 30 s', () {
      final p = parsePolicy('9381');
      expect((p.version, p.type, p.digits, p.timeStep), (2, OtpType.time, 6, 30));
      expect((p.pinLength, p.maxAttacks), (0, 0));
    });

    test('75890738: v2 time-based, 8 digits, 30 s, no PIN, no attack limit', () {
      final p = parsePolicy('75890738');
      expect((p.version, p.type, p.digits, p.timeStep), (2, OtpType.time, 8, 30));
      expect((p.pinLength, p.maxAttacks), (0, 0));
    });

    test('38039554: v2 challenge-response, 6-digit response, 6-digit challenge', () {
      final p = parsePolicy('38039554');
      expect((p.version, p.type, p.digits, p.challengeLength, p.timeStep), (2, OtpType.challenge, 6, 6, null));
    });

    test('38105125: v2 challenge-response, 8-digit response, 8-digit challenge', () {
      final p = parsePolicy('38105125');
      expect((p.version, p.type, p.digits, p.challengeLength, p.timeStep), (2, OtpType.challenge, 8, 8, null));
    });

    test('9439: v2 mode 6, challenge-response, 8-digit response, 8-digit challenge', () {
      final p = parsePolicy('9439');
      expect((p.version, p.type, p.digits, p.challengeLength, p.timeStep), (2, OtpType.challenge, 8, 8, null));
      expect((p.pinLength, p.maxAttacks), (0, 0));
    });

    test('event- and time-based policies have no challenge length', () {
      for (final policy in ['', '9346', '9381', '18921500', '75817049']) {
        expect(parsePolicy(policy).challengeLength, isNull, reason: policy);
      }
    });

    test('surrounding whitespace is ignored', () {
      expect(parsePolicy(' 75817049\n').timeStep, 60);
    });
  });

  test('empty policy is v1, event-based, 6 digits', () {
    for (final input in ['', '  ']) {
      final p = parsePolicy(input);
      expect((p.version, p.type, p.digits, p.timeStep), (1, OtpType.event, 6, null));
    }
  });

  test('the test builder reproduces known policies', () {
    for (final policy in ['75817049', '75948051', '18921500']) {
      final bits = int.parse(policy).toRadixString(2);
      expect(_policyFromBits(bits.substring(1, bits.length - 5)), policy);
    }
  });

  group('rejects', () {
    test('a changed last digit (check value mismatch)', () {
      for (final input in ['75817048', '75817050', '18921501', '75890739']) {
        expect(() => parsePolicy(input), _throwsCode(MobilePassErrorCode.invalidPolicy), reason: input);
      }
    });

    test('non-numeric, negative, zero and out-of-range input', () {
      for (final input in ['abc', '-75817049', '0', '7581 7049', '99999999999999999999', '0x10']) {
        expect(() => parsePolicy(input), _throwsCode(MobilePassErrorCode.invalidPolicy), reason: input);
      }
    });

    test('version 3 as unsupported', () {
      // Version 3, mode 0, 15 field bits.
      final policy = _policyFromBits(
        '0011'
        '0000'
        '00000000000',
      );
      expect(() => parsePolicy(policy), _throwsCode(MobilePassErrorCode.unsupportedPolicyVersion));
    });

    test('mode 3 as an unsupported OTP type', () {
      final mode3 = _policyFromBits(
        '0010'
        '0011'
        '00000000000000',
      );
      expect(() => parsePolicy(mode3), _throwsCode(MobilePassErrorCode.unsupportedOtpType));
    });

    test('mode 2 with a field length other than 12 bits', () {
      final policy = _policyFromBits(
        '0010'
        '0010'
        '00000000000',
      );
      expect(() => parsePolicy(policy), _throwsCode(MobilePassErrorCode.invalidPolicy));
    });

    test('modes 7–15 as invalid', () {
      expect(
        () => parsePolicy(
          _policyFromBits(
            '0010'
            '0111',
          ),
        ),
        _throwsCode(MobilePassErrorCode.invalidPolicy),
      );
    });

    test('a field length that does not match the mode', () {
      // Mode 1 needs 13 bits after the mode; 11 is mode 0's length.
      final policy = _policyFromBits(
        '0010'
        '0001'
        '00000000000',
      );
      expect(() => parsePolicy(policy), _throwsCode(MobilePassErrorCode.invalidPolicy));
    });

    test('time step index 3', () {
      final policy = _policyFromBits(
        '0010'
        '0001'
        '00000000000'
        '11',
      );
      expect(() => parsePolicy(policy), _throwsCode(MobilePassErrorCode.invalidPolicy));
    });
  });

  test('mode 2 reads the challenge length from its last field bit', () {
    for (final (fields, digits, challengeLength) in [
      ('000000000000', 6, 6),
      ('000000000001', 6, 8),
      ('100000000000', 8, 6),
      ('100000000001', 8, 8),
    ]) {
      final p = parsePolicy(_policyFromBits('00100010$fields'));
      expect((p.type, p.digits, p.challengeLength), (OtpType.challenge, digits, challengeLength), reason: fields);
    }
    expect(
      _policyFromBits(
        '0010'
        '0110',
      ),
      '9439',
    );
  });

  test('modes 4 and 5 are fixed presets', () {
    final event = parsePolicy(
      _policyFromBits(
        '0010'
        '0100',
      ),
    );
    final time = parsePolicy(
      _policyFromBits(
        '0010'
        '0101'
        '1111',
      ),
    );
    expect(
      _policyFromBits(
        '0010'
        '0100',
      ),
      '9346',
    );
    expect(
      _policyFromBits(
        '0010'
        '0101',
      ),
      '9381',
    );
    expect((event.type, event.digits, event.timeStep), (OtpType.event, 6, null));
    expect((time.type, time.digits, time.timeStep), (OtpType.time, 6, 30));
  });

  test('v1 policies parse with the same fields', () {
    final p = parsePolicy(
      _policyFromBits(
        '0001'
        '0000'
        '10111000000',
      ),
    );
    expect((p.version, p.type, p.digits, p.pinLength, p.maxAttacks), (1, OtpType.event, 8, 4, 10));
  });
}
