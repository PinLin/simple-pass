import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';

void main() {
  // RFC 6238 appendix B: the seed for each hash is the ASCII digits repeated to its output length.
  final seeds = {
    OtpAlgorithm.sha1: Uint8List.fromList(ascii.encode('12345678901234567890')),
    OtpAlgorithm.sha256: Uint8List.fromList(ascii.encode('12345678901234567890123456789012')),
    OtpAlgorithm.sha512: Uint8List.fromList(
      ascii.encode('1234567890123456789012345678901234567890123456789012345678901234'),
    ),
  };
  const vectors = <int, Map<OtpAlgorithm, String>>{
    59: {OtpAlgorithm.sha1: '94287082', OtpAlgorithm.sha256: '46119246', OtpAlgorithm.sha512: '90693936'},
    1111111109: {OtpAlgorithm.sha1: '07081804', OtpAlgorithm.sha256: '68084774', OtpAlgorithm.sha512: '25091201'},
    1111111111: {OtpAlgorithm.sha1: '14050471', OtpAlgorithm.sha256: '67062674', OtpAlgorithm.sha512: '99943326'},
    1234567890: {OtpAlgorithm.sha1: '89005924', OtpAlgorithm.sha256: '91819424', OtpAlgorithm.sha512: '93441116'},
    2000000000: {OtpAlgorithm.sha1: '69279037', OtpAlgorithm.sha256: '90698825', OtpAlgorithm.sha512: '38618901'},
    20000000000: {OtpAlgorithm.sha1: '65353130', OtpAlgorithm.sha256: '77737706', OtpAlgorithm.sha512: '47863826'},
  };

  group('RFC 6238 appendix B', () {
    for (final MapEntry(key: time, value: byAlgorithm) in vectors.entries) {
      for (final MapEntry(key: algorithm, value: expected) in byAlgorithm.entries) {
        test('${algorithm.label} at $time', () {
          final key = seeds[algorithm]!;
          expect(generateStandardTotp(key, time, algorithm: algorithm, digits: 8), expected);
          // Six digits are the same value taken mod 10^6.
          expect(generateStandardTotp(key, time, algorithm: algorithm), expected.substring(2));
        });
      }
    }
  });

  test('RFC 4226 appendix D HOTP values', () {
    final key = seeds[OtpAlgorithm.sha1]!;
    const expected = [
      '755224',
      '287082',
      '359152',
      '969429',
      '338314',
      '254676',
      '287922',
      '162583',
      '399871',
      '520489',
    ];
    for (var counter = 0; counter < expected.length; counter++) {
      expect(generateStandardHotp(key, counter), expected[counter], reason: 'counter $counter');
    }
  });

  test('the period sets the step: a 60-second code holds across a 30-second boundary', () {
    final key = seeds[OtpAlgorithm.sha1]!;
    expect(generateStandardTotp(key, 60, period: 60), generateStandardTotp(key, 119, period: 60));
    expect(generateStandardTotp(key, 59, period: 60), isNot(generateStandardTotp(key, 60, period: 60)));
    expect(generateStandardTotp(key, 120, period: 60), generateStandardHotp(key, 2));
  });

  test('a negative counter is rejected', () {
    expect(() => generateStandardHotp(seeds[OtpAlgorithm.sha1]!, -1), throwsArgumentError);
  });

  test('algorithm labels are matched case-insensitively', () {
    expect(OtpAlgorithm.fromLabel('sha256'), OtpAlgorithm.sha256);
    expect(OtpAlgorithm.fromLabel('SHA512'), OtpAlgorithm.sha512);
    expect(OtpAlgorithm.fromLabel('MD5'), isNull);
    expect(OtpAlgorithm.fromLabel('SHA-1'), isNull);
  });
}
