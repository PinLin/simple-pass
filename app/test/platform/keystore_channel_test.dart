import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/platform/keystore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('me.pinlin.simple_pass/keystore');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final keystore = PlatformKeystore();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void failWith(String code) =>
      messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: code, message: 'x'));

  final calls = <String, Future<Object?> Function()>{
    'encrypt': () => keystore.encrypt('alias', 10, 'plain', keyInUse: false),
    'decrypt': () => keystore.decrypt('alias', 'cipher'),
    'deleteKey': () => keystore.deleteKey('alias'),
  };

  for (final MapEntry(key: method, value: call) in calls.entries) {
    group(method, () {
      test('damaged becomes SecretDamagedException', () async {
        failWith('damaged');
        await expectLater(call(), throwsA(isA<SecretDamagedException>()));
      });

      test('keyInvalidated becomes KeyInvalidatedException', () async {
        failWith('keyInvalidated');
        await expectLater(call(), throwsA(isA<KeyInvalidatedException>()));
      });

      test('notAuthenticated becomes UserNotAuthenticatedException', () async {
        failWith('notAuthenticated');
        await expectLater(call(), throwsA(isA<UserNotAuthenticatedException>()));
      });

      test('any other code stays the PlatformException', () async {
        failWith('boom');
        await expectLater(call(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'boom')));
      });
    });
  }

  test('the damaged and keyInvalidated exceptions are distinct types', () async {
    failWith('damaged');
    await expectLater(keystore.decrypt('alias', 'c'), throwsA(isNot(isA<KeyInvalidatedException>())));
    failWith('keyInvalidated');
    await expectLater(keystore.decrypt('alias', 'c'), throwsA(isNot(isA<SecretDamagedException>())));
  });

  test('a successful call passes the arguments and returns the result', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return 'sealed-text';
    });
    expect(await keystore.decrypt('alias', 'cipher'), 'sealed-text');
    expect(seen!.method, 'decrypt');
    expect(seen!.arguments as Map, {'alias': 'alias', 'ciphertext': 'cipher'});
  });
}
