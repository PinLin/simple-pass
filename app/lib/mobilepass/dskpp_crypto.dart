import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Length of the client nonce R_C.
const int clientNonceLength = 32;

/// PBKDF2 iteration count sent in ClientNonce.
const int authenticationIterations = 1000;

/// DSKPP-PRF-SHA256 (RFC 6063 Appendix D.3.2): HMAC-SHA256 blocks over `INT32(i) ‖ s`, truncated
/// to [length] bytes.
Uint8List dskppPrf(List<int> key, List<int> s, int length) {
  final hmac = Hmac(sha256, key);
  final out = BytesBuilder(copy: false);
  for (var i = 1; out.length < length; i++) {
    final block = Uint8List(4 + s.length)
      ..buffer.asByteData().setUint32(0, i)
      ..setRange(4, 4 + s.length, s);
    out.add(hmac.convert(block).bytes);
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}

/// K_PROV = PRF(R_C, "Key generation" ‖ K ‖ R_S, 64), split into its MAC key and token key halves.
/// [serverKey] is K: the server's public key bytes exactly as sent.
({Uint8List macKey, Uint8List tokenKey}) deriveProvisioningKeys(
  List<int> clientNonce,
  List<int> serverNonce,
  List<int> serverKey,
) {
  final kProv = dskppPrf(clientNonce, [...ascii.encode('Key generation'), ...serverKey, ...serverNonce], 64);
  return (macKey: Uint8List.sublistView(kProv, 0, 32), tokenKey: Uint8List.sublistView(kProv, 32));
}

/// Uppercase hex of [text]'s UTF-8 bytes, as ASCII; how user ID and passphrase enter the protocol.
String hexText(String text) => utf8.encode(text).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// PBKDF2-HMAC-SHA256 (RFC 8018).
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations, int length) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder(copy: false);
  for (var block = 1; out.length < length; block++) {
    final first = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..buffer.asByteData().setUint32(salt.length, block);
    var u = hmac.convert(first).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}

/// MAC proving knowledge of the passphrase: PRF(K_AC, HEX(user ID) ‖ URL ‖ R_C ‖ R_S, 16) with
/// K_AC = PBKDF2(HEX(passphrase), R_C ‖ K, iterations, 16).
Uint8List authenticationCodeMac({
  required String passphrase,
  required String userId,
  required String url,
  required List<int> clientNonce,
  required List<int> serverNonce,
  required List<int> serverKey,
  int iterations = authenticationIterations,
}) {
  final kAc = pbkdf2Sha256(ascii.encode(hexText(passphrase)), [...clientNonce, ...serverKey], iterations, 16);
  return dskppPrf(kAc, [...ascii.encode(hexText(userId)), ...utf8.encode(url), ...clientNonce, ...serverNonce], 16);
}

/// ServerFinished key confirmation: PRF(K_MAC, "MAC 1 computation" ‖ SHA256(ClientHello ‖ ServerHello ‖
/// ClientNonce), 32), each message being the exact HTTP body.
Uint8List serverFinishedMac(List<int> macKey, List<List<int>> messages) {
  final digest = sha256.convert([for (final m in messages) ...m]).bytes;
  return dskppPrf(macKey, [...ascii.encode('MAC 1 computation'), ...digest], 32);
}

/// Compares without an early exit, so timing doesn't reveal how much of a MAC matched.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// An RSA public key.
class RsaPublicKey {
  const RsaPublicKey(this.modulus, this.exponent);

  final BigInt modulus;
  final BigInt exponent;

  int get lengthInBytes => (modulus.bitLength + 7) ~/ 8;

  /// Parses a DER SubjectPublicKeyInfo or a bare PKCS#1 RSAPublicKey. Throws [FormatException].
  factory RsaPublicKey.fromDer(List<int> der) {
    final outer = _DerReader(der).sequence();
    final first = outer.peekTag();
    if (first == 0x02) return RsaPublicKey(outer.integer(), outer.integer());
    final algorithm = outer.sequence();
    if (!_listEquals(algorithm.objectIdentifier(), _rsaEncryptionOid)) {
      throw const FormatException('Not an RSA public key');
    }
    final bits = outer.bitString();
    final rsa = _DerReader(bits).sequence();
    return RsaPublicKey(rsa.integer(), rsa.integer());
  }

  /// RSAES-PKCS1-v1_5 encryption (RFC 8017 §7.2.1).
  Uint8List encryptPkcs1(List<int> message, {Random? random}) {
    final k = lengthInBytes;
    if (message.length > k - 11) throw ArgumentError('message too long for the key');
    final rng = random ?? Random.secure();
    final em = Uint8List(k)..[1] = 0x02;
    final psEnd = k - message.length - 1;
    for (var i = 2; i < psEnd; i++) {
      em[i] = 1 + rng.nextInt(255);
    }
    em.setRange(psEnd + 1, k, message);
    final c = _toBigInt(em).modPow(exponent, modulus);
    return _fromBigInt(c, k);
  }
}

const _rsaEncryptionOid = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

BigInt _toBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List _fromBigInt(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

/// Minimal DER reader for the structures in an RSA public key.
class _DerReader {
  _DerReader(List<int> bytes) : _bytes = bytes, _end = bytes.length;
  _DerReader._(this._bytes, this._pos, this._end);

  final List<int> _bytes;
  int _pos = 0;
  final int _end;

  int peekTag() {
    if (_pos >= _end) throw const FormatException('Truncated DER');
    return _bytes[_pos];
  }

  (int, int) _element(int tag) {
    if (peekTag() != tag) throw FormatException('Expected DER tag $tag');
    _pos++;
    if (_pos >= _end) throw const FormatException('Truncated DER');
    var length = _bytes[_pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4) throw const FormatException('Bad DER length');
      length = 0;
      for (var i = 0; i < count; i++) {
        if (_pos >= _end) throw const FormatException('Truncated DER');
        length = (length << 8) | _bytes[_pos++];
      }
    }
    final start = _pos;
    if (start + length > _end) throw const FormatException('Truncated DER');
    _pos += length;
    return (start, start + length);
  }

  _DerReader sequence() {
    final (start, end) = _element(0x30);
    return _DerReader._(_bytes, start, end);
  }

  BigInt integer() {
    final (start, end) = _element(0x02);
    if (start == end || _bytes[start] & 0x80 != 0) throw const FormatException('Bad RSA integer');
    return _toBigInt(_bytes.sublist(start, end));
  }

  List<int> objectIdentifier() {
    final (start, end) = _element(0x06);
    return _bytes.sublist(start, end);
  }

  List<int> bitString() {
    final (start, end) = _element(0x03);
    if (start == end || _bytes[start] != 0) throw const FormatException('Bad DER bit string');
    return _bytes.sublist(start + 1, end);
  }
}
