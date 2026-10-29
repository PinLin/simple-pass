import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/storage_exceptions.dart';

import '../fakes/memory_key_value_backend.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';

void main() {
  group('stored JSON', () {
    test('a stored profile without pin or policy is corrupted', () async {
      for (final missing in ['pin', 'policy']) {
        final json = Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 4).toJson()..remove(missing);
        final backend = MemoryKeyValueBackend()
          ..seedRaw(
            ProfileStore.storageKey,
            jsonEncode({
              'profiles': [json],
            }),
          );
        await expectLater(ProfileStore(backend).loadAll(), throwsA(isA<StorageCorruptedException>()), reason: missing);
      }
    });

    test('pin and appendPinOnCopy round-trip through toJson/fromJson', () {
      final original = Profile(
        id: 'a1',
        name: 'Work',
        activationCode: _code,
        counter: 1,
        pin: '0042',
        appendPinOnCopy: true,
      );

      final restored = Profile.fromJson(jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      expect(restored.pin, '0042');
      expect(restored.appendPinOnCopy, isTrue);
    });

    test('a wrong-typed appendPinOnCopy reads as off, but a wrong-typed pin is refused', () {
      Map<String, dynamic> json({Object pin = ''}) => {
        'id': 'a1',
        'name': 'Work',
        'activationCode': _code,
        'counter': 1,
        'pin': pin,
        'policy': '',
        'appendPinOnCopy': 'yes',
        'createdAt': '2026-01-01T00:00:00.000Z',
      };

      expect(Profile.fromJson(json()).appendPinOnCopy, isFalse);
      expect(() => Profile.fromJson(json(pin: 1234)), throwsA(isA<TypeError>()));
    });
  });

  group('isValidPin', () {
    test('accepts no PIN and 4 to 16 ASCII digits', () {
      for (final pin in ['', '1234', '0000', '1234567890123456']) {
        expect(isValidPin(pin), isTrue, reason: pin);
      }
    });

    test('rejects non-digits, non-ASCII digits, too short and too long', () {
      for (final pin in ['12a4', ' 1234', '12-34', '١٢٣٤', '１２３４', '123', '12345678901234567']) {
        expect(isValidPin(pin), isFalse, reason: pin);
      }
    });
  });

  group('clipboardTextFor', () {
    Profile profile({String pin = '', bool append = false}) =>
        Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 1, pin: pin, appendPinOnCopy: append);

    test('appendPinOnCopy on with a PIN: PIN directly followed by the OTP', () {
      expect(clipboardTextFor(profile(pin: '1234', append: true), '885200'), '1234885200');
    });

    test('appendPinOnCopy off: only the OTP', () {
      expect(clipboardTextFor(profile(pin: '1234'), '885200'), '885200');
    });

    test('appendPinOnCopy on but no PIN: only the OTP', () {
      expect(clipboardTextFor(profile(append: true), '885200'), '885200');
    });
  });
}
