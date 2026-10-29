import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/mobilepass/ocra.dart';

Matcher _throwsCode(MobilePassErrorCode code) =>
    throwsA(isA<MobilePassException>().having((e) => e.code, 'code', code));

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const code6 = 'HCF4B-47YNP-OVAPP-4BAE2';
  const code8 = 'E3Q5C-HCPLO-AWLVJ-QBAA3';
  const codePreset = 'UIRZV-CPKBZ-5MWYV-ZBAAF';

  group('known-answer vectors', () {
    for (final (activationCode, policy, challenge, response) in [
      (code6, '38039554', '123456', '506945'),
      (code6, '38039554', '001234', '570122'),
      (code6, '38039554', '999999', '712832'),
      (code8, '38105125', '87654321', '37034620'),
      (codePreset, '9439', '10203040', '07022569'),
    ]) {
      test('$policy, $challenge -> $response', () {
        expect(generateMobilePassChallengeResponse(activationCode, policy, challenge), response);
      });
    }
  });

  test('suite names the response and challenge lengths', () {
    expect(ocraSuite(6, 6), 'OCRA-1:HOTP-SHA256-6:QN06');
    expect(ocraSuite(8, 8), 'OCRA-1:HOTP-SHA256-8:QN08');
  });

  group('challenge encoding', () {
    test('is the hex value left-aligned in 128 bytes', () {
      final q = encodeNumericChallenge('123456');
      expect(q, hasLength(128));
      // 123456 = 0x1E240; the odd final nibble is followed by a 0 nibble.
      expect(_hex(q.sublist(0, 3)), '1e2400');
      expect(q.skip(3).every((b) => b == 0), isTrue);
    });

    test('an 8-digit challenge is 7 hex digits plus a 0 nibble', () {
      expect(_hex(encodeNumericChallenge('87654321').sublist(0, 5)), '5397fb1000');
    });

    test('leading zeros do not change the value', () {
      expect(_hex(encodeNumericChallenge('001234').sublist(0, 2)), '4d20');
      expect(encodeNumericChallenge('001234'), encodeNumericChallenge('1234'));
    });

    test('an even-length hex value fills whole bytes', () {
      expect(_hex(encodeNumericChallenge('65535').sublist(0, 3)), 'ffff00');
      expect(_hex(encodeNumericChallenge('255').sublist(0, 2)), 'ff00');
    });

    test('zero encodes as all zero bytes', () {
      expect(encodeNumericChallenge('000000').every((b) => b == 0), isTrue);
    });
  });

  group('challenge length', () {
    test('must be exactly the policy length in ASCII digits', () {
      expect(isValidChallenge('123456', 6), isTrue);
      expect(isValidChallenge('000000', 6), isTrue);
      for (final input in ['12345', '1234567', '', '12345a', ' 12345', '１２３４５６']) {
        expect(isValidChallenge(input, 6), isFalse, reason: input);
      }
      expect(isValidChallenge('123456', 8), isFalse);
    });

    test('a short or long challenge is rejected', () {
      for (final challenge in ['12345', '1234567', '12 456', '']) {
        expect(
          () => generateMobilePassChallengeResponse(code6, '38039554', challenge),
          _throwsCode(MobilePassErrorCode.invalidChallenge),
          reason: challenge,
        );
      }
      expect(
        () => generateMobilePassChallengeResponse(code8, '38105125', '123456'),
        _throwsCode(MobilePassErrorCode.invalidChallenge),
      );
    });
  });

  test('challenge-response and counter-driven policies refuse each other', () {
    expect(
      () => generateMobilePassChallengeResponse('AERUK-Z4JVP-G66AJ-DBACL', '18921500', '123456'),
      _throwsCode(MobilePassErrorCode.unsupportedOtpType),
    );
    expect(
      () => generateMobilePassOtp(code6, 0, policy: '38039554'),
      _throwsCode(MobilePassErrorCode.unsupportedOtpType),
    );
    expect(
      () => generateMobilePassTimeOtp(code6, '38039554', 1700000000),
      _throwsCode(MobilePassErrorCode.unsupportedOtpType),
    );
  });
}
