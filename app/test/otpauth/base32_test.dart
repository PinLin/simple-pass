import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/otpauth/base32.dart';

void main() {
  // RFC 4648 section 10.
  const vectors = {
    '': '',
    'f': 'MY======',
    'fo': 'MZXQ====',
    'foo': 'MZXW6===',
    'foob': 'MZXW6YQ=',
    'fooba': 'MZXW6YTB',
    'foobar': 'MZXW6YTBOI======',
  };

  group('RFC 4648 vectors', () {
    for (final MapEntry(key: plain, value: encoded) in vectors.entries) {
      test('"$plain" <-> "$encoded"', () {
        expect(base32Encode(ascii.encode(plain), padding: true), encoded);
        expect(base32Encode(ascii.encode(plain)), encoded.replaceAll('=', ''));
        expect(base32Decode(encoded), ascii.encode(plain));
      });
    }
  });

  test('accepts missing padding, lowercase and whitespace anywhere', () {
    expect(base32Decode('mzxw6ytboi'), ascii.encode('foobar'));
    expect(base32Decode(' MZXW 6YTB\nOI== \t'), ascii.encode('foobar'));
    expect(base32Decode('jbsw y3dp ehpk 3pxp'), base32Decode('JBSWY3DPEHPK3PXP'));
  });

  test('rejects characters outside the alphabet', () {
    for (final bad in ['MZXW0YTB', 'MZXW1YTB', 'MZXW8YTB', 'MZXW-YTB', 'MZ=XW6YTB']) {
      expect(base32Decode(bad), isNull, reason: bad);
    }
  });

  test('rejects lengths no whole number of bytes can produce', () {
    for (final bad in ['M', 'MZX', 'MZXW6Y', 'MZXW6YTBO']) {
      expect(base32Decode(bad), isNull, reason: bad);
    }
  });

  test('ignores leftover bits after the last byte, zero or not', () {
    expect(base32Decode('MZXW6YQ'), ascii.encode('foob'));
    expect(base32Decode('MZXW6YR'), ascii.encode('foob'));
    expect(base32Decode('MZXW6YTBOJ'), ascii.encode('foobar'));
    expect(base32Decode('MZXW6YTBOI'), ascii.encode('foobar'));
    expect(base32Decode('AB'), [0x00]);
    expect(base32Decode('AA'), [0x00]);
    // 26 random characters, as some services generate, decode to 16 bytes.
    expect(base32Decode('ABCDEFGHIJKLMNOPQRSTUVWXYZ'), hasLength(16));
  });

  test('round-trips arbitrary bytes', () {
    final bytes = List<int>.generate(37, (i) => (i * 73 + 11) & 0xff);
    expect(base32Decode(base32Encode(bytes)), bytes);
  });
}
