import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:simple_pass/mobilepass/dskpp_client.dart';
import 'package:simple_pass/mobilepass/enrollment_string.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';

import '../fakes/fake_dskpp_server.dart';

void main() {
  const enrollment = EnrollmentString(url: 'https://otp.example.com/dskpp', userId: 'alice', passphrase: 'pass-1');
  late FakeDskppServer server;
  late List<SoftPinPolicy> pinRequests;
  late List<EnrollmentStep> steps;

  setUp(() {
    server = FakeDskppServer(userId: 'alice', passphrase: 'pass-1');
    pinRequests = [];
    steps = [];
  });

  Future<EnrolledToken> enroll({String? pin = '2468', EnrollmentString? using}) =>
      DskppClient(transport: server, random: Random(3), osVersion: '16').enroll(
        using ?? enrollment,
        tokenName: 'Work',
        requestPin: (policy) async {
          pinRequests.add(policy);
          return pin;
        },
        onStep: steps.add,
      );

  Matcher failsWith(EnrollmentErrorCode code, [String? detail]) => throwsA(
    isA<EnrollmentException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.detail, 'detail', detail ?? anything),
  );

  test('four passes provision the key the server holds, with its policy, serial and the OTP PIN', () async {
    final token = await enroll();
    expect(token.key, server.tokenKey);
    expect(token.key, hasLength(32));
    expect(token.policy, '9346');
    expect(token.serial, '123456789');
    expect(token.pin, '2468');
    expect(server.authMacValid, isTrue);
    expect(steps, [EnrollmentStep.contactingServer, EnrollmentStep.registering]);
    expect(server.urls, everyElement(Uri.parse(enrollment.url)));
    expect(server.requests, hasLength(2));
    expect(pinRequests.single.minLength, 4);
    expect(pinRequests.single.maxLength, 8);
    expect(server.requests[0], contains('<mpdskpp:userID>616C696365</mpdskpp:userID>'));
    expect(server.requests[1], contains("<mpdskpp:MPData Name='softPIN'>2468</mpdskpp:MPData>"));
    expect(server.requests[1], contains("<mpdskpp:MPData Name='DeviceName'>Work</mpdskpp:MPData>"));
    expect(server.requests[1], contains("SessionID='4001'"));
    expect(generateKeyOtp(token.key, 0, policy: token.policy), hasLength(6));
  });

  test('no OTP PIN prompt when the server asks for none; an empty softPIN is sent', () async {
    server
      ..softPin = null
      ..collectDeviceName = false;
    final token = await enroll();
    expect(pinRequests, isEmpty);
    expect(token.pin, '');
    expect(server.requests[1], contains("<mpdskpp:MPData Name='softPIN'></mpdskpp:MPData>"));
    expect(server.requests[1], isNot(contains('DeviceName')));
  });

  test('a 0..0 SoftPinPolicy means no PIN', () async {
    server.softPin = (0, 0, false);
    await enroll();
    expect(pinRequests, isEmpty);
  });

  test('the time-based policy from KeyProfileId is kept', () async {
    server.policy = '75890738';
    final token = await enroll();
    expect(parsePolicy(token.policy).type, OtpType.time);
    expect(parsePolicy(token.policy).digits, 8);
  });

  test('canceling the PIN prompt stops before the key is requested', () async {
    await expectLater(enroll(pin: null), failsWith(EnrollmentErrorCode.canceled));
    expect(server.requests, hasLength(1));
  });

  test('network failure', () async {
    server.failNetwork = true;
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.network));
  });

  test('HTTP error status', () async {
    server.httpStatus = 500;
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.httpStatus, '500'));
  });

  test('an HTTP error carrying a DSKPP status reports the status', () async {
    server
      ..httpStatus = 400
      ..nextBody = "<dskpp:KeyProvServerFinished xmlns:dskpp='urn:ietf:params:xml:ns:keyprov:dskpp' Status='Abort'/>";
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.rejected, 'Abort'));
  });

  test('ServerHello status other than Continue', () async {
    server.helloStatus = 'AuthenticationDataInvalid';
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.rejected, 'AuthenticationDataInvalid'));
  });

  test('ServerFinished status other than Success', () async {
    server.finishedStatus = 'ProvisioningPeriodExpired';
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.rejected, 'ProvisioningPeriodExpired'));
  });

  test('ServerFinished MAC that does not verify', () async {
    server.tamperMac = true;
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.macMismatch));
  });

  test('a wrong passphrase gives a MAC the server rejects', () async {
    server.finishedStatus = 'AuthenticationDataInvalid';
    await expectLater(enroll(using: enrollment.copyWith(passphrase: 'wrong')), failsWith(EnrollmentErrorCode.rejected));
    expect(server.authMacValid, isFalse);
  });

  test('TLS failures are reported apart from other network errors', () async {
    server.failTls = true;
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.certificate));
  });

  test('1024-bit server keys still work; shorter ones are refused', () async {
    server.keyName = 'testRsaKey1024';
    final token = await enroll();
    expect(token.key, server.tokenKey);

    final short = FakeDskppServer(userId: 'alice', passphrase: 'pass-1')
      ..spkiOverride = _spkiFor(BigInt.one << 1022 | BigInt.one);
    await expectLater(
      DskppClient(transport: short).enroll(enrollment, tokenName: 'W', requestPin: (_) async => '1234'),
      failsWith(EnrollmentErrorCode.badResponse),
    );
  });

  test('non-XML or unexpected messages', () async {
    server.nextBody = '<html>Not here</html>';
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.badResponse));
    server.nextBody = 'garbage';
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.badResponse));
  });

  test('a policy this app cannot use', () async {
    server.policy = '12345';
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.unsupportedPolicy, '12345'));
  });

  test('SoftPinPolicy.accepts follows length and character rules', () {
    const digits = SoftPinPolicy(minLength: 4, maxLength: 6, alphanumeric: false);
    expect(digits.accepts('1234'), isTrue);
    expect(digits.accepts('123'), isFalse);
    expect(digits.accepts('1234567'), isFalse);
    expect(digits.accepts('12a4'), isFalse);
    const alnum = SoftPinPolicy(minLength: 4, maxLength: 6, alphanumeric: true);
    expect(alnum.accepts('12aB'), isTrue);
    expect(alnum.accepts('12 B'), isFalse);
  });

  test('the client request bodies are plain ASCII', () async {
    await enroll();
    for (final r in server.requests) {
      expect(ascii.encode(r), isNotEmpty);
    }
  });

  test('a server key too small for the nonce is a bad response, not a crash', () async {
    server.spkiOverride = base64.decode('MBwwDQYJKoZIhvcNAQEBBQADCwAwCAIDAQABAgEB');
    await expectLater(enroll(), failsWith(EnrollmentErrorCode.badResponse));
  });

  test('a minimum length of 0 makes the OTP PIN optional', () async {
    server.softPin = (0, 6, false);
    final token = await enroll(pin: '');
    expect(pinRequests.single.minLength, 0);
    expect(pinRequests.single.accepts(''), isTrue);
    expect(token.pin, '');
  });

  group('HttpDskppTransport', () {
    late HttpServer http;
    late List<int> reply;
    late Map<String, String> seenHeaders;

    setUp(() async {
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((request) async {
        seenHeaders = {'content-type': request.headers.value('content-type') ?? ''};
        await request.drain<void>();
        request.response
          ..headers.set('cache-control', 'no-cache, no-must-revalidate, private')
          ..add(reply);
        await request.response.close();
      });
    });
    tearDown(() => http.close(force: true));

    Uri url() => Uri.parse('http://127.0.0.1:${http.port}/dskpp');

    test('posts DSKPP XML and returns status, headers and body', () async {
      reply = utf8.encode('<ok/>');
      final response = await HttpDskppTransport().post(url(), Uint8List.fromList(utf8.encode('<hello/>')));
      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], 'no-cache, no-must-revalidate, private');
      expect(utf8.decode(response.body), '<ok/>');
      expect(seenHeaders['content-type'], dskppContentType);
    });

    test('refuses an oversized reply', () async {
      reply = List.filled(HttpDskppTransport.maxResponseBytes + 1, 0x41);
      await expectLater(HttpDskppTransport().post(url(), Uint8List(0)), throwsA(isA<IOException>()));
    });
  });

  group('messages match a MobilePASS client', () {
    final recorded = (jsonDecode(File('test/fixtures/dskpp_vectors.json').readAsStringSync()) as Map)['interop'] as Map;

    // Element paths with their attribute names, in document order; values and text are left out.
    List<String> shape(String xml) => [
      for (final e in XmlDocument.parse(xml).descendantElements)
        '${[...e.ancestorElements.toList().reversed.map((a) => a.name.qualified), e.name.qualified].join('/')}'
            '[${(e.attributes.map((a) => a.name.qualified).toList()..sort()).join(',')}]',
    ];

    test('ClientHello has the same elements, order, namespaces and attributes', () async {
      await enroll();
      expect(shape(server.requests[0]), shape(recorded['clientHello'] as String));
      expect(server.requests[0], contains('<mpdskpp:Capability>6</mpdskpp:Capability>'));
      expect(server.requests[0], contains('<mpdskpp:OSType>Android</mpdskpp:OSType>'));
      expect(server.requests[0], contains('<mpdskpp:OSVersion>16</mpdskpp:OSVersion>'));
      expect(server.requests[0], contains('<mpdskpp:Rooted>False</mpdskpp:Rooted>'));
    });

    test('ClientNonce has the same elements, order, namespaces and attributes', () async {
      await enroll();
      expect(shape(server.requests[1]), shape(recorded['clientNonce'] as String));
      final names = [
        for (final e in XmlDocument.parse(server.requests[1]).findAllElements('mpdskpp:MPData')) e.getAttribute('Name'),
      ];
      expect(names, ['DeviceName', 'softPIN']);
    });

    test('the shape check notices a missing device field', () {
      final hello = recorded['clientHello'] as String;
      expect(shape(hello.replaceFirst(RegExp('<mpdskpp:Rooted>[^<]*</mpdskpp:Rooted>'), '')), isNot(shape(hello)));
    });
  });
}

// DER SubjectPublicKeyInfo for an RSA key with [modulus] and exponent 65537.
List<int> _spkiFor(BigInt modulus) {
  List<int> der(int tag, List<int> body) {
    final n = body.length;
    final length = n < 0x80 ? [n] : (n < 0x100 ? [0x81, n] : [0x82, n >> 8, n & 0xff]);
    return [tag, ...length, ...body];
  }

  var hex = modulus.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  final rsa = der(0x30, [
    ...der(0x02, [if (bytes[0] & 0x80 != 0) 0, ...bytes]),
    ...der(0x02, [1, 0, 1]),
  ]);
  final algorithm = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00];
  return der(0x30, [
    ...algorithm,
    ...der(0x03, [0, ...rsa]),
  ]);
}
