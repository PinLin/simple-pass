import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/enrollment_string.dart';

String _encode(String text) => base64.encode(utf8.encode(text));

void main() {
  Matcher failsWith(EnrollmentStringError error) =>
      throwsA(isA<EnrollmentStringException>().having((e) => e.error, 'error', error));

  test('decodes URL, user ID and passphrase', () {
    final s = parseEnrollmentString(
      _encode('EnrollmentURL=https://otp.example.com/dskpp/\r\nUserID=alice\r\nPassphrase=a=b c'),
    );
    expect(s.url, 'https://otp.example.com/dskpp/');
    expect(s.userId, 'alice');
    expect(s.passphrase, 'a=b c');
    expect(s.uri.host, 'otp.example.com');
  });

  test('ignores trailing NULs, LF-only lines and whitespace in the pasted text', () {
    final b64 = base64.encode([...utf8.encode('EnrollmentURL=https://h.example/\nUserID=bob\nPassphrase=pw'), 0, 0]);
    final pasted = '  ${b64.substring(0, 10)}\n${b64.substring(10)} ';
    final s = parseEnrollmentString(pasted);
    expect(s.userId, 'bob');
    expect(s.passphrase, 'pw');
  });

  test('missing UserID and Passphrase come back empty', () {
    final s = parseEnrollmentString(_encode('EnrollmentURL=https://h.example/'));
    expect(s.userId, '');
    expect(s.passphrase, '');
    final filled = s.copyWith(userId: 'u', passphrase: 'p');
    expect((filled.url, filled.userId, filled.passphrase), ('https://h.example/', 'u', 'p'));
  });

  test('accepts unpadded Base64', () {
    final b64 = _encode('EnrollmentURL=https://h.example/x').replaceAll('=', '');
    expect(parseEnrollmentString(b64).url, 'https://h.example/x');
  });

  test('rejects text that is not an Enrollment String', () {
    expect(() => parseEnrollmentString(''), failsWith(EnrollmentStringError.invalidFormat));
    expect(() => parseEnrollmentString('not base64 !!'), failsWith(EnrollmentStringError.invalidFormat));
    expect(() => parseEnrollmentString('ABCDE-FGHIJ'), failsWith(EnrollmentStringError.invalidFormat));
    expect(() => parseEnrollmentString(_encode('UserID=alice')), failsWith(EnrollmentStringError.invalidFormat));
  });

  test('rejects URLs that are not https', () {
    for (final url in ['http://h.example/', 'ftp://h.example/', 'https:///path', 'h.example']) {
      expect(() => parseEnrollmentString(_encode('EnrollmentURL=$url')), failsWith(EnrollmentStringError.notHttps));
    }
  });
}
