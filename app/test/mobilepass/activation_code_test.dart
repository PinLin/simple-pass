import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/activation_code.dart' show activationCodeToKey, checkCharacter;
import 'package:simple_pass/mobilepass/mobilepass.dart';

Uint8List _hex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

const _legacyVectors = {
  '00112233445566778899': 'AAISK-EM2EJ-KVTHT-PCEZN',
  'a1b2c3d4e5f60718293a': 'UGZMF-HVHFE-6YDR4-QKJ2N',
  'ffeeddccbbaa99887766': '77XNF-3TF3Z-VKMYX-Q53GQ',
};

const _versionedVectors = {
  '0123456789abcdef0123': 'AERUK-Z4JVP-G66AJ-DBACL',
  'deadbeefcafebabe1234': '32W35-36K72-5L4ER-UBACQ',
};

void main() {
  group('normalizeActivationCode', () {
    test('uppercases and re-groups a code typed without hyphens', () {
      expect(normalizeActivationCode('apscgykkaunezgcprdsm'), 'APSCG-YKKAU-NEZGC-PRDSM');
    });

    test('strips existing hyphens and whitespace before re-grouping', () {
      expect(normalizeActivationCode(' APSCG-YKKAU- NEZGC -PRDSM '), 'APSCG-YKKAU-NEZGC-PRDSM');
    });

    test('strips zero-width characters (U+200B, U+200C, U+200D, U+FEFF)', () {
      expect(
        normalizeActivationCode('\uFEFFAPSCG\u200B-YKKAU\u200C-NEZGC\u200D-PRDSM\u200B'),
        'APSCG-YKKAU-NEZGC-PRDSM',
      );
      expect(isValidActivationCode(normalizeActivationCode('apscg\u200bykkaunezgcprdsm')), isTrue);
    });

    test("keeps '0', '1', '8' and '9' as typed", () {
      expect(normalizeActivationCode('aa1sk em2ej kvtht pcezn'), 'AA1SK-EM2EJ-KVTHT-PCEZN');
      expect(normalizeActivationCode('0089K'), '0089K');
    });

    test('drops symbols and non-ASCII characters', () {
      expect(normalizeActivationCode('AAISK_EM2EJ.KVTHT/PCEZN!'), 'AAISK-EM2EJ-KVTHT-PCEZN');
      expect(normalizeActivationCode('AAISKé'), 'AAISK');
    });

    test('is a no-op on an already-normalized code', () {
      const code = 'APSCG-YKKAU-NEZGC-PRDSM';
      expect(normalizeActivationCode(code), code);
    });
  });

  group('checkCharacter', () {
    test('is alphabet[sum of code unit × (position + 1) mod 32]', () {
      // 'AAAA': 65 × (1 + 2 + 3 + 4) = 650, 650 mod 32 = 10 -> 'K'.
      expect(checkCharacter('AAAA'), 'K');
      expect(['AAIS', 'EM2E', 'KVTH', 'PCEZ'].map(checkCharacter), ['K', 'J', 'T', 'N']);
      expect(['UGZM', 'HVHF', '6YDR', 'QKJ2'].map(checkCharacter), ['F', 'E', '4', 'N']);
    });
  });

  group('legacy format', () {
    _legacyVectors.forEach((seedHex, code) {
      test('$seedHex <-> $code', () {
        expect(encodeLegacyActivationCode(_hex(seedHex)), code);
        final decoded = decodeActivationCode(code)!;
        expect(decoded.format, ActivationCodeFormat.legacy);
        expect(decoded.seed, _hex(seedHex));
        expect(decoded.version, isNull);
      });
    });

    test('round-trips random seeds', () {
      for (var i = 0; i < 200; i++) {
        final seed = generateActivationSeed();
        final code = encodeLegacyActivationCode(seed);
        expect(isValidActivationCode(code), isTrue, reason: code);
        expect(decodeActivationCode(code)!.seed, seed);
      }
    });

    test('rejects a wrong check character in any group', () {
      const code = 'AAISK-EM2EJ-KVTHT-PCEZN';
      for (final position in [4, 10, 16, 22]) {
        final wrong = code.replaceRange(position, position + 1, code[position] == 'A' ? 'B' : 'A');
        expect(decodeActivationCode(wrong), isNull, reason: wrong);
      }
    });
  });

  group('versioned format', () {
    _versionedVectors.forEach((seedHex, code) {
      test('$seedHex v2 <-> $code', () {
        expect(encodeVersionedActivationCode(_hex(seedHex), 2), code);
        final decoded = decodeActivationCode(code)!;
        expect(decoded.format, ActivationCodeFormat.versioned);
        expect(decoded.seed, _hex(seedHex));
        expect(decoded.version, 2);
      });
    });

    test('round-trips random seeds and versions', () {
      for (var i = 0; i < 200; i++) {
        final seed = generateActivationSeed();
        final version = 1 + i % 6;
        final decoded = decodeActivationCode(encodeVersionedActivationCode(seed, version))!;
        expect(decoded.seed, seed);
        expect(decoded.version, version);
      }
    });

    test('rejects any single changed character', () {
      const code = 'AERUKZ4JVPG66AJDBACL';
      for (var i = 0; i < code.length; i++) {
        final wrong = code.replaceRange(i, i + 1, code[i] == 'A' ? 'B' : 'A');
        expect(decodeActivationCode(wrong), isNull, reason: wrong);
      }
    });
  });

  group('activationCodeToKey (lenient)', () {
    test('decodes valid codes like decodeActivationCode', () {
      expect(activationCodeToKey('AERUK-Z4JVP-G66AJ-DBACL'), _hex('0123456789abcdef0123'));
      expect(activationCodeToKey('AAISK-EM2EJ-KVTHT-PCEZN'), _hex('00112233445566778899'));
    });

    test('ignores the check characters of codes that fail strict validation', () {
      const unchecked = 'WMPX4-TD2BV-QZM7C-QX4J4';
      expect(decodeActivationCode(unchecked), isNull);
      // Same data characters, correct check characters.
      final checked = ['WMPX', 'TD2B', 'QZM7', 'QX4J'].map((g) => '$g${checkCharacter(g)}').join('-');
      expect(activationCodeToKey(unchecked), decodeActivationCode(checked)!.seed);
    });

    test('rejects codes of the wrong length', () {
      expect(
        () => activationCodeToKey('AAISK-EM2EJ-KVTHT'),
        throwsA(isA<MobilePassException>().having((e) => e.code, 'code', MobilePassErrorCode.invalidActivationCode)),
      );
    });
  });

  group('isValidActivationCode', () {
    test('accepts well-formed codes in either format', () {
      expect(isValidActivationCode('APSCG-YKKAU-NEZGC-PRDSM'), isTrue);
      expect(isValidActivationCode('AERUK-Z4JVP-G66AJ-DBACL'), isTrue);
    });

    test('rejects a code with wrong check characters', () {
      expect(isValidActivationCode('WMPX4-TD2BV-QZM7C-QX4J4'), isFalse);
    });

    test('rejects wrong length', () {
      expect(isValidActivationCode(normalizeActivationCode('APSCG-YKKAU-NEZGC')), isFalse);
    });

    test('rejects codes containing 0, 1, 8 or 9 instead of reading them as letters', () {
      expect(isValidActivationCode('AAISK-EM2EJ-KVTHT-PCEZN'), isTrue);
      expect(isValidActivationCode('AA1SK-EM2EJ-KVTHT-PCEZN'), isFalse);
      expect(decodeActivationCode('aa1sk-em2ej-kvtht-pcezn'), isNull);
      expect(isValidActivationCode(normalizeActivationCode('01189-YKKAU-NEZGC-PRDSM')), isFalse);
      expect(() => activationCodeToKey('AA1SK-EM2EJ-KVTHT-PCEZN'), throwsA(isA<MobilePassException>()));
    });

    test('rejects empty string', () {
      expect(isValidActivationCode(''), isFalse);
    });
  });

  group('generateMobilePassOtp with invalid activation code', () {
    test('throws MobilePassException(invalidActivationCode)', () {
      expect(
        () => generateMobilePassOtp('not-a-code', 0),
        throwsA(isA<MobilePassException>().having((e) => e.code, 'code', MobilePassErrorCode.invalidActivationCode)),
      );
    });
  });
}
