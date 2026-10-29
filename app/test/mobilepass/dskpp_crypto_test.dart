import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/dskpp_crypto.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';

Uint8List _hex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

String _toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _keyName(String serverHello) =>
    base64.decode(RegExp('<ds:KeyName>([^<]+)<').firstMatch(serverHello)!.group(1)!);

Uint8List _macIn(String message, String closingTag) =>
    base64.decode(RegExp("<dskpp:Mac [^>]*>([^<]+)</dskpp:Mac>$closingTag").firstMatch(message)!.group(1)!);

void main() {
  final vectors = jsonDecode(File('test/fixtures/dskpp_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final interop = vectors['interop'] as Map<String, dynamic>;
  final local = vectors['local'] as Map<String, dynamic>;

  group('DSKPP-PRF and PBKDF2', () {
    test('PRF block 1 is HMAC-SHA256 over INT32(1) ‖ s, and longer outputs chain blocks', () {
      final key = utf8.encode('k');
      final s = utf8.encode('seed');
      final block1 = Hmac(sha256, key).convert([0, 0, 0, 1, ...s]).bytes;
      final block2 = Hmac(sha256, key).convert([0, 0, 0, 2, ...s]).bytes;
      expect(dskppPrf(key, s, 16), block1.sublist(0, 16));
      expect(dskppPrf(key, s, 40), [...block1, ...block2.sublist(0, 8)]);
    });

    test('PBKDF2-HMAC-SHA256 matches the RFC 7914 §11 vector', () {
      expect(
        _toHex(pbkdf2Sha256(utf8.encode('passwd'), utf8.encode('salt'), 1, 64)),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('hexText is uppercase hex of the UTF-8 bytes', () {
      expect(hexText('testuser'), '7465737475736572');
      expect(hexText('é'), 'C3A9');
    });
  });

  group('recorded registration', () {
    final clientNonce = _hex(interop['clientNonceValue'] as String);
    final serverNonce = _hex(interop['serverNonceValue'] as String);
    final serverHello = interop['serverHello'] as String;
    final serverKey = _keyName(serverHello);

    test('K_PROV splits into the K_MAC and K_TOKEN the server recorded', () {
      final keys = deriveProvisioningKeys(clientNonce, serverNonce, serverKey);
      expect(_toHex(keys.macKey), interop['macKey']);
      expect(_toHex(keys.tokenKey), interop['tokenKey']);
    });

    test('ServerFinished MAC covers ClientHello ‖ ServerHello ‖ ClientNonce', () {
      final keys = deriveProvisioningKeys(clientNonce, serverNonce, serverKey);
      final messages = [
        for (final m in ['clientHello', 'serverHello', 'clientNonce']) utf8.encode(interop[m] as String),
      ];
      final sent = _macIn(interop['serverFinished'] as String, '</dskpp:KeyProvServerFinished>');
      expect(serverFinishedMac(keys.macKey, messages), sent);
      expect(serverFinishedMac(keys.macKey, messages.sublist(0, 2)), isNot(sent));
    });

    test('K_TOKEN used directly gives the codes the server expects for its policy', () {
      final key = _hex(interop['tokenKey'] as String);
      expect(generateKeyTimeOtp(key, interop['policy'] as String, 1700000010), '891699');
      expect([for (var c = 0; c < 3; c++) generateKeyOtp(key, c)], ['819703', '944681', '658163']);
    });

    test('authentication MAC matches the one the client sent', () {
      final mac = authenticationCodeMac(
        passphrase: local['passphrase'] as String,
        userId: local['userId'] as String,
        url: local['url'] as String,
        clientNonce: _hex(local['clientNonceValue'] as String),
        serverNonce: _hex(local['serverNonceValue'] as String),
        serverKey: _keyName(local['serverHello'] as String),
      );
      expect(mac, _macIn(local['clientNonce'] as String, '</dskpp:AuthenticationCodeMac>'));
      expect(_toHex(mac), '78411d36f8ceba711c35255586e1aeb2');
    });
  });

  group('RSA', () {
    final rsa = vectors['testRsaKey'] as Map<String, dynamic>;
    final n = BigInt.parse(rsa['modulus'] as String, radix: 16);
    final d = BigInt.parse(rsa['privateExponent'] as String, radix: 16);

    test('reads SubjectPublicKeyInfo and PKCS#1 DER', () {
      for (final der in [rsa['spki'], rsa['pkcs1']]) {
        final key = RsaPublicKey.fromDer(base64.decode(der as String));
        expect(key.modulus, n);
        expect(key.exponent, BigInt.from(65537));
      }
    });

    test('rejects truncated or non-RSA DER', () {
      final spki = base64.decode(rsa['spki'] as String);
      expect(() => RsaPublicKey.fromDer(spki.sublist(0, 40)), throwsFormatException);
      expect(() => RsaPublicKey.fromDer([0x04, 0x01, 0x00]), throwsFormatException);
    });

    test('PKCS#1 v1.5 encryption decrypts to 00 02 PS 00 M with a nonzero PS', () {
      final key = RsaPublicKey.fromDer(base64.decode(rsa['spki'] as String));
      final message = Uint8List.fromList(List.generate(32, (i) => i));
      final cipher = key.encryptPkcs1(message, random: Random(1));
      expect(cipher.length, 256);
      var m = BigInt.zero;
      for (final b in cipher) {
        m = (m << 8) | BigInt.from(b);
      }
      final plain = m.modPow(d, n).toRadixString(16).padLeft(512, '0');
      final em = _hex(plain);
      expect(em.sublist(0, 2), [0x00, 0x02]);
      final ps = em.sublist(2, 256 - 33);
      expect(ps.length, greaterThanOrEqualTo(8));
      expect(ps.contains(0), isFalse);
      expect(em[256 - 33], 0);
      expect(em.sublist(256 - 32), message);
    });
  });

  test('constantTimeEquals', () {
    expect(constantTimeEquals([1, 2], [1, 2]), isTrue);
    expect(constantTimeEquals([1, 2], [1, 3]), isFalse);
    expect(constantTimeEquals([1, 2], [1]), isFalse);
  });
}
