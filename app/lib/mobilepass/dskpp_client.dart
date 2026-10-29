import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'dskpp_crypto.dart';
import 'enrollment_string.dart';
import 'mobilepass_exception.dart';
import 'policy.dart';

/// Media type of every DSKPP message (RFC 6063 §5.1).
const dskppContentType = 'application/dskpp+xml';

/// Shortest server RSA key accepted.
const minRsaKeyBits = 1024;

const _nsDecl =
    "xmlns:pskc='urn:ietf:params:xml:ns:keyprov:pskc' xmlns:dskpp='urn:ietf:params:xml:ns:keyprov:dskpp' "
    "xmlns:xenc='http://www.w3.org/2001/04/xmlenc#' xmlns:ds='http://www.w3.org/2000/09/xmldsig#' "
    "xmlns:mpdskpp='urn:safenet-inc:mp:dskppext'";
const _keyTypeHotp = 'urn:ietf:params:xml:ns:keyprov:pskc:hotp';
const _encryptionRsa15 = 'http://www.w3.org/2001/04/xmlenc#rsa_1_5';
const _macPrfSha256 = 'urn:ietf:params:xml:ns:keyprov:dskpp:prf-sha256';
const _keyPackageContainer = 'urn:ietf:params:xml:ns:keyprov:dskpp:pskc-key-container';

/// One HTTP exchange's result, as the client needs it. Header names are lowercase.
class DskppHttpResponse {
  const DskppHttpResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;
}

/// Sends one DSKPP message. An interface so tests can stand in for the server.
abstract class DskppTransport {
  /// Throws [IOException] or [TimeoutException] when the exchange fails below HTTP.
  Future<DskppHttpResponse> post(Uri url, Uint8List body);
}

/// [DskppTransport] over `dart:io`; certificates are checked by the platform as usual.
class HttpDskppTransport implements DskppTransport {
  HttpDskppTransport({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  /// DSKPP replies are a few kilobytes; a server sending more is cut off.
  static const maxResponseBytes = 64 * 1024;

  @override
  Future<DskppHttpResponse> post(Uri url, Uint8List body) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    // Per-step timeouts alone let a server trickle bytes forever; aborting the client fails the exchange.
    final deadline = Timer(timeout * 2, () => client.close(force: true));
    try {
      final request = await client.postUrl(url).timeout(timeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.contentTypeHeader, dskppContentType)
        ..headers.set(HttpHeaders.acceptHeader, dskppContentType)
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store')
        ..headers.set(HttpHeaders.pragmaHeader, 'no-cache')
        ..contentLength = body.length
        ..add(body);
      final response = await request.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await response.timeout(timeout).forEach((chunk) {
        bytes.add(chunk);
        if (bytes.length > maxResponseBytes) throw const HttpException('Response too large');
      });
      final headers = <String, String>{};
      response.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(', '));
      return DskppHttpResponse(response.statusCode, headers, bytes.takeBytes());
    } finally {
      deadline.cancel();
      client.close(force: true);
    }
  }
}

/// The server's rules for the OTP PIN it wants set during registration.
class SoftPinPolicy {
  const SoftPinPolicy({required this.minLength, required this.maxLength, required this.alphanumeric});

  final int minLength;
  final int maxLength;

  /// Letters are allowed besides digits.
  final bool alphanumeric;

  bool accepts(String pin) =>
      pin.length >= minLength &&
      pin.length <= maxLength &&
      (alphanumeric ? RegExp(r'^[0-9A-Za-z]*$') : RegExp(r'^[0-9]*$')).hasMatch(pin);
}

/// Registration progress, in order.
enum EnrollmentStep { contactingServer, registering }

/// Why a registration failed.
enum EnrollmentErrorCode {
  /// No HTTP response: offline, DNS or timeout.
  network,

  /// TLS failed, typically a server certificate the system's CAs don't vouch for.
  certificate,

  /// The server answered with an HTTP error status.
  httpStatus,

  /// The response wasn't a DSKPP message this client understands.
  badResponse,

  /// The server answered with a DSKPP status other than success; see [EnrollmentException.detail].
  rejected,

  /// ServerFinished failed key confirmation: the server doesn't hold the same key.
  macMismatch,

  /// The server's policy isn't one this app can generate codes for. Key confirmation already passed,
  /// so the server may consider the registration done.
  unsupportedPolicy,

  /// The user dismissed the OTP PIN prompt.
  canceled,
}

class EnrollmentException implements Exception {
  const EnrollmentException(this.code, [this.detail]);

  final EnrollmentErrorCode code;

  /// Server status or HTTP status, when there is one; safe to show.
  final String? detail;

  @override
  String toString() => 'EnrollmentException(${code.name}${detail == null ? '' : ': $detail'})';
}

/// What a successful registration provisions.
class EnrolledToken {
  const EnrolledToken({required this.key, required this.policy, required this.serial, required this.pin});

  /// K_TOKEN, used directly as the OTP key.
  final Uint8List key;

  /// Policy String from the key package's KeyProfileId.
  final String policy;
  final String serial;

  /// OTP PIN sent to the server; empty when the server didn't ask for one.
  final String pin;
}

/// Asks the user for an OTP PIN under [policy]; null cancels the registration.
typedef SoftPinPrompt = Future<String?> Function(SoftPinPolicy policy);

/// DSKPP four-pass registration (RFC 6063 §3.4.1) as MobilePASS servers expect it.
class DskppClient {
  DskppClient({DskppTransport? transport, Random? random, this.osVersion = ''})
    : _transport = transport ?? HttpDskppTransport(),
      _random = random ?? Random.secure();

  final DskppTransport _transport;
  final Random _random;

  /// Android version reported in ClientHello, e.g. "16".
  final String osVersion;

  /// Registers with [enrollment]'s server; [tokenName] is sent when the server asks for a device
  /// name. Throws [EnrollmentException]; nothing is stored here.
  Future<EnrolledToken> enroll(
    EnrollmentString enrollment, {
    required String tokenName,
    required SoftPinPrompt requestPin,
    void Function(EnrollmentStep step)? onStep,
  }) async {
    final url = enrollment.uri;
    onStep?.call(EnrollmentStep.contactingServer);
    final clientHello = utf8.encode(_clientHello(enrollment.userId, osVersion));
    final serverHelloBytes = await _exchange(url, clientHello);
    final serverHello = _parse(serverHelloBytes, 'KeyProvServerHello');
    _expectStatus(serverHello, 'Continue');

    final sessionId = _attribute(serverHello, 'SessionID');
    final serverNonce = _base64(_text(_child(_child(serverHello, 'Payload'), 'Nonce')));
    final keyName = _text(_child(_child(serverHello, 'EncryptionKey'), 'KeyName'));
    final serverKey = _base64(keyName.split('\n').where((l) => !l.trimLeft().startsWith('-----')).join());
    final RsaPublicKey publicKey;
    try {
      publicKey = RsaPublicKey.fromDer(serverKey);
    } on FormatException {
      throw const EnrollmentException(EnrollmentErrorCode.badResponse);
    }
    // Older servers may still use 1024-bit keys; anything shorter is not accepted.
    if (publicKey.modulus.bitLength < minRsaKeyBits || publicKey.exponent < BigInt.from(3)) {
      throw const EnrollmentException(EnrollmentErrorCode.badResponse);
    }

    var pin = '';
    final pinPolicy = _softPinPolicy(serverHello);
    if (pinPolicy != null) {
      final entered = await requestPin(pinPolicy);
      if (entered == null) throw const EnrollmentException(EnrollmentErrorCode.canceled);
      pin = entered;
    }

    onStep?.call(EnrollmentStep.registering);
    final clientNonceValue = Uint8List.fromList(List.generate(clientNonceLength, (_) => _random.nextInt(256)));
    final authMac = authenticationCodeMac(
      passphrase: enrollment.passphrase,
      userId: enrollment.userId,
      url: enrollment.url,
      clientNonce: clientNonceValue,
      serverNonce: serverNonce,
      serverKey: serverKey,
    );
    final clientNonce = utf8.encode(
      _clientNonce(
        sessionId: sessionId,
        userId: enrollment.userId,
        encryptedNonce: publicKey.encryptPkcs1(clientNonceValue, random: _random),
        authMac: authMac,
        pin: pin,
        deviceName: _collectsDeviceName(serverHello) ? tokenName : null,
      ),
    );
    final finishedBytes = await _exchange(url, clientNonce);
    final finished = _parse(finishedBytes, 'KeyProvServerFinished');
    _expectStatus(finished, 'Success');

    final keys = deriveProvisioningKeys(clientNonceValue, serverNonce, serverKey);
    final mac = _base64(_text(_directChild(finished, 'Mac')));
    if (!constantTimeEquals(mac, serverFinishedMac(keys.macKey, [clientHello, serverHelloBytes, clientNonce]))) {
      throw const EnrollmentException(EnrollmentErrorCode.macMismatch);
    }

    final policy = _text(_child(finished, 'KeyProfileId')).trim();
    try {
      parsePolicy(policy);
    } on MobilePassException {
      throw EnrollmentException(EnrollmentErrorCode.unsupportedPolicy, policy);
    }
    final serialElement = _find(finished, 'SerialNo');
    return EnrolledToken(
      key: Uint8List.fromList(keys.tokenKey),
      policy: policy,
      serial: serialElement == null ? '' : serialElement.innerText.trim(),
      pin: pin,
    );
  }

  Future<Uint8List> _exchange(Uri url, Uint8List body) async {
    final DskppHttpResponse response;
    try {
      response = await _transport.post(url, body);
    } on TlsException {
      throw const EnrollmentException(EnrollmentErrorCode.certificate);
    } on IOException {
      throw const EnrollmentException(EnrollmentErrorCode.network);
    } on TimeoutException {
      throw const EnrollmentException(EnrollmentErrorCode.network);
    }
    if (response.statusCode != HttpStatus.ok) {
      // A DSKPP error status in the body says more than the HTTP code.
      _rejectionIn(response.body);
      throw EnrollmentException(EnrollmentErrorCode.httpStatus, '${response.statusCode}');
    }
    return response.body;
  }

  // Throws [EnrollmentErrorCode.rejected] when [body] is a DSKPP message with an error status.
  void _rejectionIn(Uint8List body) {
    XmlElement root;
    try {
      root = XmlDocument.parse(latin1.decode(body)).rootElement;
    } on XmlException {
      return;
    }
    final status = _attributeOrNull(root, 'Status');
    if (status != null && status.isNotEmpty && status != 'Continue' && status != 'Success') {
      throw EnrollmentException(EnrollmentErrorCode.rejected, status);
    }
  }
}

// Device fields and their order follow what MobilePASS clients send; root detection isn't done, so
// the device is reported as not rooted.
String _clientHello(String userId, String osVersion) =>
    "<dskpp:KeyProvClientHello $_nsDecl Version='1.0'>"
    '<dskpp:DeviceIdentifierData><mpdskpp:MPInfo>'
    '<mpdskpp:userID>${hexText(userId)}</mpdskpp:userID>'
    '<mpdskpp:Capability>6</mpdskpp:Capability>'
    '<mpdskpp:OSType>Android</mpdskpp:OSType>'
    '<mpdskpp:OSVersion>${_escape(osVersion)}</mpdskpp:OSVersion>'
    '<mpdskpp:Rooted>False</mpdskpp:Rooted>'
    '</mpdskpp:MPInfo></dskpp:DeviceIdentifierData>'
    '<dskpp:SupportedKeyTypes><dskpp:Algorithm>$_keyTypeHotp</dskpp:Algorithm></dskpp:SupportedKeyTypes>'
    '<dskpp:SupportedEncryptionAlgorithms><dskpp:Algorithm>$_encryptionRsa15</dskpp:Algorithm>'
    '</dskpp:SupportedEncryptionAlgorithms>'
    '<dskpp:SupportedMacAlgorithms><dskpp:Algorithm>$_macPrfSha256</dskpp:Algorithm></dskpp:SupportedMacAlgorithms>'
    '<dskpp:SupportedProtocolVariants><dskpp:FourPass/></dskpp:SupportedProtocolVariants>'
    '<dskpp:SupportedKeyPackages><dskpp:KeyPackageFormat>$_keyPackageContainer</dskpp:KeyPackageFormat>'
    '</dskpp:SupportedKeyPackages>'
    '</dskpp:KeyProvClientHello>';

String _clientNonce({
  required String sessionId,
  required String userId,
  required List<int> encryptedNonce,
  required List<int> authMac,
  required String pin,
  required String? deviceName,
}) =>
    "<dskpp:KeyProvClientNonce $_nsDecl Version='1.0' SessionID='${_escape(sessionId)}'>"
    '<dskpp:EncryptedNonce>${base64.encode(encryptedNonce)}</dskpp:EncryptedNonce>'
    '<dskpp:AuthenticationData>'
    '<dskpp:ClientID>${hexText(userId)}</dskpp:ClientID>'
    '<dskpp:AuthenticationCodeMac>'
    '<dskpp:IterationCount>$authenticationIterations</dskpp:IterationCount>'
    "<dskpp:Mac MacAlgorithm='$_macPrfSha256'>${base64.encode(authMac)}</dskpp:Mac>"
    '</dskpp:AuthenticationCodeMac>'
    '</dskpp:AuthenticationData>'
    "<dskpp:Extensions xmlns:mpdskpp='urn:safenet-inc:mp:dskppext' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'>"
    "<dskpp:Extension xsi:type='mpdskpp:MPDSKPPExtensionType'>"
    "${deviceName == null ? '' : "<mpdskpp:MPData Name='DeviceName'>${_escape(deviceName)}</mpdskpp:MPData>"}"
    "<mpdskpp:MPData Name='softPIN'>${_escape(pin)}</mpdskpp:MPData>"
    '</dskpp:Extension></dskpp:Extensions>'
    '</dskpp:KeyProvClientNonce>';

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll("'", '&apos;')
    .replaceAll('"', '&quot;');

XmlElement _parse(Uint8List body, String expectedRoot) {
  final XmlElement root;
  try {
    root = XmlDocument.parse(latin1.decode(body)).rootElement;
  } on XmlException {
    throw const EnrollmentException(EnrollmentErrorCode.badResponse);
  }
  if (root.name.local != expectedRoot) {
    // An error reply may come back as a different message type carrying only a status.
    final status = _attributeOrNull(root, 'Status');
    throw status != null && status.isNotEmpty
        ? EnrollmentException(EnrollmentErrorCode.rejected, status)
        : const EnrollmentException(EnrollmentErrorCode.badResponse);
  }
  return root;
}

void _expectStatus(XmlElement message, String expected) {
  final status = _attributeOrNull(message, 'Status');
  if (status != expected) throw EnrollmentException(EnrollmentErrorCode.rejected, status ?? '');
}

String? _attributeOrNull(XmlElement element, String local) =>
    element.attributes.where((a) => a.name.local == local).firstOrNull?.value;

String _attribute(XmlElement element, String local) =>
    _attributeOrNull(element, local) ?? (throw const EnrollmentException(EnrollmentErrorCode.badResponse));

XmlElement? _find(XmlElement root, String local) =>
    root.descendantElements.where((e) => e.name.local == local).firstOrNull;

XmlElement _child(XmlElement parent, String local) =>
    _find(parent, local) ?? (throw const EnrollmentException(EnrollmentErrorCode.badResponse));

// ServerFinished's own MAC, not one nested in the key package.
XmlElement _directChild(XmlElement parent, String local) =>
    parent.childElements.where((e) => e.name.local == local).firstOrNull ??
    (throw const EnrollmentException(EnrollmentErrorCode.badResponse));

String _text(XmlElement element) => element.innerText;

Uint8List _base64(String text) {
  try {
    return base64.decode(text.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    throw const EnrollmentException(EnrollmentErrorCode.badResponse);
  }
}

bool _collectsDeviceName(XmlElement serverHello) => serverHello.descendantElements.any(
  (e) =>
      e.name.local == 'MPData' &&
      _attributeOrNull(e, 'Name') == 'CollectDeviceName' &&
      e.innerText.trim().toLowerCase() == 'true',
);

// Absent or a zero maximum means the server doesn't want an OTP PIN; an empty one is sent then.
SoftPinPolicy? _softPinPolicy(XmlElement serverHello) {
  final element = _find(serverHello, 'SoftPinPolicy');
  if (element == null) return null;
  int? number(String local) {
    final e = element.childElements.where((c) => c.name.local == local).firstOrNull;
    return e == null ? null : int.tryParse(e.innerText.trim());
  }

  final min = number('minlen');
  final max = number('maxlen');
  if (min == null || max == null) throw const EnrollmentException(EnrollmentErrorCode.badResponse);
  if (max == 0) return null;
  if (min < 0 || min > max) throw const EnrollmentException(EnrollmentErrorCode.badResponse);
  final alphanumeric = element.childElements.where((c) => c.name.local == 'alphanum').firstOrNull;
  return SoftPinPolicy(
    minLength: min,
    maxLength: max,
    alphanumeric: alphanumeric?.innerText.trim().toLowerCase() == 'true',
  );
}
