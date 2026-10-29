import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:simple_pass/mobilepass/dskpp_client.dart';
import 'package:simple_pass/mobilepass/dskpp_crypto.dart';

const _nsDecl =
    "xmlns:pskc='urn:ietf:params:xml:ns:keyprov:pskc' xmlns:dskpp='urn:ietf:params:xml:ns:keyprov:dskpp' "
    "xmlns:xenc='http://www.w3.org/2001/04/xmlenc#' xmlns:ds='http://www.w3.org/2000/09/xmldsig#' "
    "xmlns:mpdskpp='urn:safenet-inc:mp:dskppext'";

Map<String, dynamic> _testKey(String name) =>
    (jsonDecode(File('test/fixtures/dskpp_vectors.json').readAsStringSync()) as Map)[name] as Map<String, dynamic>;

/// In-process DSKPP server for [DskppClient] tests: decrypts R_C, checks the authentication MAC and
/// answers like a real server would, with knobs for each failure the client must handle.
class FakeDskppServer implements DskppTransport {
  FakeDskppServer({required this.userId, required this.passphrase, this.policy = '9346'});

  final String userId;
  final String passphrase;
  String policy;
  String serial = '123456789';

  /// SoftPinPolicy (min, max, alphanumeric); null leaves the element out.
  (int, int, bool)? softPin = (4, 8, false);
  bool collectDeviceName = true;
  String helloStatus = 'Continue';
  String finishedStatus = 'Success';
  int httpStatus = 200;
  bool tamperMac = false;
  bool failNetwork = false;
  bool failTls = false;

  /// Answers the next message with this body instead.
  String? nextBody;

  final List<Uri> urls = [];
  final List<String> requests = [];
  Uint8List? tokenKey;
  bool? authMacValid;

  final _random = Random(7);

  /// Fixture key the server uses: `testRsaKey` (2048-bit) or `testRsaKey1024`.
  String keyName = 'testRsaKey';
  late final _key = _testKey(keyName);

  /// Sent as the server key instead of the test key.
  List<int>? spkiOverride;

  late final _testSpki = base64.decode(_key['spki'] as String);
  List<int> get _spki => spkiOverride ?? _testSpki;
  Uint8List? _serverNonce;
  Uint8List? _clientHello;
  Uint8List? _serverHello;

  @override
  Future<DskppHttpResponse> post(Uri url, Uint8List body) async {
    if (failNetwork) throw const SocketException('unreachable');
    if (failTls) throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
    urls.add(url);
    final text = utf8.decode(body);
    requests.add(text);
    String reply;
    if (nextBody != null) {
      reply = nextBody!;
      nextBody = null;
    } else if (text.startsWith('<dskpp:KeyProvClientHello')) {
      _clientHello = body;
      reply = _hello();
      _serverHello = utf8.encode(reply);
    } else {
      reply = _finished(url, text, body);
    }
    return DskppHttpResponse(httpStatus, {
      'content-type': dskppContentType,
      'cache-control': 'no-cache, no-must-revalidate, private',
    }, utf8.encode(reply));
  }

  String _hello() {
    final nonce = _serverNonce = Uint8List.fromList(List.generate(16, (_) => _random.nextInt(256)));
    final pin = softPin;
    return "<dskpp:KeyProvServerHello $_nsDecl Version='1.0' Status='$helloStatus' SessionID='4001'>"
        '<dskpp:KeyType>urn:ietf:params:xml:ns:keyprov:pskc:hotp</dskpp:KeyType>'
        '<dskpp:EncryptionKey><ds:KeyName>${base64.encode(_spki)}</ds:KeyName></dskpp:EncryptionKey>'
        '<dskpp:Payload><dskpp:Nonce>${base64.encode(nonce)}</dskpp:Nonce></dskpp:Payload>'
        "<dskpp:Extensions xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'>"
        "<dskpp:Extension xsi:type='mpdskpp:MPDSKPPExtensionType'>"
        "<mpdskpp:MPData Name='CollectDeviceName'>$collectDeviceName</mpdskpp:MPData>"
        '${pin == null ? '' : '<mpdskpp:SoftPinPolicy><mpdskpp:alphanum>${pin.$3}</mpdskpp:alphanum>'
                  '<mpdskpp:minlen>${pin.$1}</mpdskpp:minlen><mpdskpp:maxlen>${pin.$2}</mpdskpp:maxlen>'
                  '</mpdskpp:SoftPinPolicy>'}'
        '</dskpp:Extension></dskpp:Extensions>'
        '</dskpp:KeyProvServerHello>';
  }

  String _finished(Uri url, String text, Uint8List body) {
    final cipher = base64.decode(RegExp('<dskpp:EncryptedNonce>([^<]+)<').firstMatch(text)!.group(1)!);
    final clientNonce = _decrypt(cipher);
    final sentMac = base64.decode(
      RegExp('<dskpp:AuthenticationCodeMac>.*?<dskpp:Mac [^>]*>([^<]+)<').firstMatch(text)!.group(1)!,
    );
    authMacValid = constantTimeEquals(
      sentMac,
      authenticationCodeMac(
        passphrase: passphrase,
        userId: userId,
        url: url.toString(),
        clientNonce: clientNonce,
        serverNonce: _serverNonce!,
        serverKey: _spki,
      ),
    );
    final keys = deriveProvisioningKeys(clientNonce, _serverNonce!, _spki);
    tokenKey = keys.tokenKey;
    final mac = serverFinishedMac(keys.macKey, [_clientHello!, _serverHello!, body]);
    if (tamperMac) mac[0] ^= 1;
    return "<dskpp:KeyProvServerFinished $_nsDecl Version='1.0' Status='$finishedStatus' SessionID='4001'>"
        "<dskpp:KeyPackage><dskpp:KeyContainer Version='1.0' Id='KC0001'><pskc:KeyPackage>"
        '<pskc:DeviceInfo><pskc:Manufacturer>Test &amp; Co.</pskc:Manufacturer>'
        '<pskc:SerialNo>$serial</pskc:SerialNo></pskc:DeviceInfo>'
        "<pskc:Key Id='$serial' Algorithm='urn:ietf:params:xml:ns:keyprov:pskc:hotp'>"
        '<pskc:KeyProfileId>$policy</pskc:KeyProfileId>'
        '</pskc:Key></pskc:KeyPackage></dskpp:KeyContainer></dskpp:KeyPackage>'
        "<dskpp:Mac MacAlgorithm='urn:ietf:params:xml:ns:keyprov:dskpp:prf-sha256'>${base64.encode(mac)}</dskpp:Mac>"
        '</dskpp:KeyProvServerFinished>';
  }

  Uint8List _decrypt(List<int> cipher) {
    final n = BigInt.parse(_key['modulus'] as String, radix: 16);
    final d = BigInt.parse(_key['privateExponent'] as String, radix: 16);
    var c = BigInt.zero;
    for (final b in cipher) {
      c = (c << 8) | BigInt.from(b);
    }
    final em = c.modPow(d, n).toRadixString(16).padLeft((n.bitLength + 7) ~/ 8 * 2, '0');
    final bytes = [for (var i = 0; i < em.length; i += 2) int.parse(em.substring(i, i + 2), radix: 16)];
    if (bytes[0] != 0 || bytes[1] != 2) throw StateError('bad padding');
    return Uint8List.fromList(bytes.sublist(bytes.indexOf(0, 2) + 1));
  }
}
