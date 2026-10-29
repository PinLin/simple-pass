import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/otpauth/otpauth_uri.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';

void main() {
  // The example from the Key Uri Format documentation.
  const example = 'otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
  final exampleSecret = [...ascii.encode('Hello!'), 0xde, 0xad, 0xbe, 0xef];

  test('parses the documented example with defaults filled in', () {
    final link = parseOtpauthUri(example);
    expect(link.type, OtpauthType.totp);
    expect(link.secret, exampleSecret);
    expect(link.issuer, 'Example');
    expect(link.account, 'alice@google.com');
    expect(link.algorithm, OtpAlgorithm.sha1);
    expect(link.digits, 6);
    expect(link.period, 30);
  });

  test('reads algorithm, digits and period', () {
    final link = parseOtpauthUri(
      'otpauth://totp/ACME%20Co:john.doe@example.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ'
      '&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60',
    );
    expect(link.issuer, 'ACME Co');
    expect(link.account, 'john.doe@example.com');
    expect(link.algorithm, OtpAlgorithm.sha256);
    expect(link.digits, 8);
    expect(link.period, 60);
  });

  test('takes the issuer from the label when the parameter is absent, with an encoded colon and spaces', () {
    final link = parseOtpauthUri('otpauth://totp/Big%20Corp%3A%20alice?secret=jbsw%20y3dp%20ehpk%203pxp');
    expect(link.issuer, 'Big Corp');
    expect(link.account, 'alice');
    expect(link.secret, exampleSecret);
  });

  test('the issuer parameter wins over the label prefix', () {
    expect(parseOtpauthUri('otpauth://totp/Old:bob?secret=JBSWY3DPEHPK3PXP&issuer=New').issuer, 'New');
  });

  test('a label without issuer is the account; an empty label is fine', () {
    final plain = parseOtpauthUri('otpauth://totp/bob?secret=JBSWY3DPEHPK3PXP');
    expect(plain.issuer, '');
    expect(plain.account, 'bob');
    final empty = parseOtpauthUri('otpauth://totp/?secret=JBSWY3DPEHPK3PXP');
    expect(empty.account, '');
  });

  test('scheme, type and algorithm are case-insensitive; surrounding whitespace is ignored', () {
    final link = parseOtpauthUri('  OTPAUTH://TOTP/x?secret=JBSWY3DPEHPK3PXP&algorithm=sha512\n');
    expect(link.type, OtpauthType.totp);
    expect(link.algorithm, OtpAlgorithm.sha512);
  });

  test('hotp reads the counter', () {
    final link = parseOtpauthUri('otpauth://hotp/Svc:carol?secret=JBSWY3DPEHPK3PXP&counter=42');
    expect(link.type, OtpauthType.hotp);
    expect(link.counter, 42);
    expect(parseOtpauthUri('otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=0').counter, 0);
  });

  group('errors', () {
    void expectError(String input, OtpauthErrorCode code) {
      expect(
        () => parseOtpauthUri(input),
        throwsA(isA<OtpauthException>().having((e) => e.code, 'code', code)),
        reason: input,
      );
    }

    test('not an otpauth link', () {
      for (final input in ['', 'JBSWY3DPEHPK3PXP', 'https://example.com/?secret=JBSWY3DPEHPK3PXP', 'otpauth']) {
        expectError(input, OtpauthErrorCode.notOtpauth);
      }
    });

    test('Google Authenticator migration exports', () {
      expectError('otpauth-migration://offline?data=CjEKCkhlbGxvId6tvu8', OtpauthErrorCode.migrationUnsupported);
      expectError('OTPAUTH-MIGRATION://offline?data=x', OtpauthErrorCode.migrationUnsupported);
    });

    test('unknown types', () {
      expectError('otpauth://steam/x?secret=JBSWY3DPEHPK3PXP', OtpauthErrorCode.unsupportedType);
      expectError('otpauth:///x?secret=JBSWY3DPEHPK3PXP', OtpauthErrorCode.unsupportedType);
    });

    test('missing, empty or non-Base32 secrets', () {
      for (final query in ['', '?issuer=x', '?secret=', '?secret=%20', '?secret=JBSW1Y3D', '?secret=M']) {
        expectError('otpauth://totp/x$query', OtpauthErrorCode.invalidSecret);
      }
    });

    test('unsupported algorithm, digits, period or counter', () {
      for (final query in [
        'algorithm=MD5',
        'digits=7',
        'digits=10',
        'digits=six',
        'period=0',
        'period=-30',
        'period=3601',
        'period=1e3',
      ]) {
        expectError('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&$query', OtpauthErrorCode.unsupportedParameters);
      }
      for (final query in [
        '',
        'counter=',
        'counter=-1',
        'counter=abc',
        'counter=9007199254740992',
        'counter=99999999999999999999',
      ]) {
        expectError('otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&$query', OtpauthErrorCode.unsupportedParameters);
      }
    });

    test('malformed percent-encoding', () {
      expectError('otpauth://totp/%E0%A4%A?secret=JBSWY3DPEHPK3PXP', OtpauthErrorCode.notOtpauth);
      expectError('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&issuer=%E0%A4%A', OtpauthErrorCode.notOtpauth);
    });
  });

  test('default names follow Google Authenticator', () {
    expect(defaultTokenName('Example', 'alice@example.com'), 'Example: alice@example.com');
    expect(defaultTokenName('', 'alice'), 'alice');
    expect(defaultTokenName('Example', ''), 'Example');
    expect(defaultTokenName(' ', ' '), '');
  });
}
