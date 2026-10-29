import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/device_info.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/screens/enrollment_screen.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_dskpp_server.dart';
import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

String _enrollmentString({
  String user = 'alice',
  String pass = 'pass-1',
  String url = 'https://otp.example.com/dskpp',
}) {
  final lines = ['EnrollmentURL=$url', if (user.isNotEmpty) 'UserID=$user', if (pass.isNotEmpty) 'Passphrase=$pass'];
  return base64.encode(utf8.encode(lines.join('\r\n')));
}

/// Pops the route with this result so tests can see what the screen returned.
class _Host extends StatelessWidget {
  const _Host({required this.child, required this.onResult});

  final Widget child;
  final void Function(bool?) onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () async =>
            onResult(await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => child))),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  late MemoryKeyValueBackend backend;
  late ProfileStore store;
  late FakeDskppServer server;
  bool? result;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DeviceInfo.channelName),
      (call) async => call.method == 'osRelease' ? '16' : null,
    );
    backend = MemoryKeyValueBackend();
    store = ProfileStore(backend);
    server = FakeDskppServer(userId: 'alice', passphrase: 'pass-1');
    result = null;
  });

  Future<void> open(WidgetTester tester, {SettingsStore? settingsStore}) async {
    await pumpLocalized(
      tester,
      _Host(
        child: EnrollmentScreen(profileStore: store, settingsStore: settingsStore, transport: server),
        onResult: (r) => result = r,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String? string, String name = 'Work'}) async {
    await tester.enterText(find.byKey(const ValueKey('enrollmentStringField')), string ?? _enrollmentString());
    await tester.enterText(find.byKey(const ValueKey('enrollNameField')), name);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('enrollSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('enrollSubmitButton')));
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byKey(const ValueKey('otpPinField')), pin);
    await tester.tap(find.byKey(const ValueKey('otpPinConfirmButton')));
    await tester.pumpAndSettle();
  }

  String? errorText(WidgetTester tester) {
    final finder = find.byKey(const ValueKey('enrollError'));
    return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
  }

  group('app-wide protection', () {
    late FakeKeystore keystore;

    setUp(() {
      keystore = FakeKeystore();
      store = ProfileStore(backend, keystore: keystore);
    });

    Future<void> enroll(WidgetTester tester, SettingsStore? settingsStore) async {
      await open(tester, settingsStore: settingsStore);
      await fill(tester);
      await submit(tester);
      await enterPin(tester, '2468');
    }

    testWidgets('on: the registered profile is sealed after one prompt', (tester) async {
      final settings = SettingsStore(MemoryKeyValueBackend());
      await settings.save(const Settings(requireAuth: true));
      await enroll(tester, settings);

      expect(result, isTrue);
      expect(keystore.authenticateCalls, 1);
      final saved = (await store.loadAll()).single;
      expect((saved.protected, saved.key, saved.pin), (true, base64.encode(server.tokenKey!), '2468'));
      expect(backend.rawValue(ProfileStore.storageKey), isNot(contains(base64.encode(server.tokenKey!))));
      expect(saved.registration!.enrollmentString, _enrollmentString());
      expect(backend.rawValue(ProfileStore.storageKey), isNot(contains(_enrollmentString())));
      expect(backend.rawValue(ProfileStore.storageKey), isNot(contains('pass-1')));
    });

    for (final (what, value) in [('off', false), ('not decided yet', null)]) {
      testWidgets('$what: the registered profile is stored in the clear without a prompt', (tester) async {
        final settings = SettingsStore(MemoryKeyValueBackend());
        if (value != null) await settings.save(Settings(requireAuth: value));
        await enroll(tester, settings);

        expect(result, isTrue);
        expect(keystore.authenticateCalls, 0);
        expect((await store.loadAll()).single.protected, isFalse);
      });
    }

    testWidgets('unreadable settings fail closed: the registered profile is sealed', (tester) async {
      await enroll(tester, SettingsStore(_BrokenBackend()));

      expect(result, isTrue);
      expect(keystore.authenticateCalls, 1);
      expect((await store.loadAll()).single.protected, isTrue);
      expect(backend.rawValue(ProfileStore.storageKey), isNot(contains(base64.encode(server.tokenKey!))));
    });

    testWidgets('no settings store given: unprotected', (tester) async {
      await enroll(tester, null);
      expect((await store.loadAll()).single.protected, isFalse);
    });

    testWidgets('a failed prompt shows why, saves nothing and does not close; Save can be tried again', (tester) async {
      final settings = SettingsStore(MemoryKeyValueBackend());
      await settings.save(const Settings(requireAuth: true));
      keystore.authResults.add(AuthResult.canceled);
      await enroll(tester, settings);

      expect(result, isNull);
      expect(errorText(tester), 'Authentication canceled');
      expect(await store.loadAll(), isEmpty);
    });
  });

  testWidgets('registers, asks for the OTP PIN and saves a key profile that generates codes', (tester) async {
    await open(tester);
    await fill(tester);
    expect(find.text('Registers with otp.example.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('userIdField')), findsNothing);
    expect(find.byKey(const ValueKey('passphraseField')), findsNothing);

    await submit(tester);
    expect(find.text('Set OTP PIN'), findsOneWidget);
    expect(find.textContaining('4–8 digits'), findsOneWidget);
    final pinField = tester.widget<TextField>(
      find.descendant(of: find.byKey(const ValueKey('otpPinField')), matching: find.byType(TextField)),
    );
    expect(pinField.obscureText, isTrue);
    expect(pinField.keyboardType, TextInputType.number);
    await enterPin(tester, '12');
    expect(find.text("PIN doesn't meet the requirements"), findsOneWidget);
    await enterPin(tester, '2468');

    expect(result, isTrue);
    final saved = (await store.loadAll()).single;
    expect(saved.kind, ProfileKind.mobilePassKey);
    expect(saved.name, 'Work');
    expect(saved.key, base64.encode(server.tokenKey!));
    expect(saved.policy, '9346');
    expect(saved.serial, '123456789');
    expect(saved.registration!.enrollmentString, _enrollmentString());
    expect(saved.registration!.url, 'https://otp.example.com/dskpp');
    expect(saved.registration!.userId, 'alice');
    expect(saved.registration!.passphrase, 'pass-1');
    expect(saved.registration!.toJson(), isNot(contains('pin')));
    expect(saved.pin, '2468');
    expect(saved.activationCode, '');
    expect(saved.counter, 0);
    expect(otpForProfile(saved), hasLength(6));
    expect(server.requests[1], contains("<mpdskpp:MPData Name='DeviceName'>Work</mpdskpp:MPData>"));
    expect(server.requests[0], contains('<mpdskpp:OSVersion>16</mpdskpp:OSVersion>'));
  });

  testWidgets('asks for the user ID and passphrase the string leaves out', (tester) async {
    server.softPin = null;
    await open(tester);
    await fill(
      tester,
      string: _enrollmentString(user: '', pass: ''),
    );
    expect(find.byKey(const ValueKey('userIdField')), findsOneWidget);
    expect(find.byKey(const ValueKey('passphraseField')), findsOneWidget);

    await submit(tester);
    expect(find.text('User ID is required'), findsOneWidget);
    expect(find.text('Passphrase is required'), findsOneWidget);
    expect(server.requests, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('userIdField')), 'alice');
    await tester.enterText(find.byKey(const ValueKey('passphraseField')), 'pass-1');
    await submit(tester);

    expect(server.authMacValid, isTrue);
    expect(result, isTrue);
    final saved = (await store.loadAll()).single;
    expect(saved.pin, '');
    expect(saved.registration!.enrollmentString, _enrollmentString(user: '', pass: ''));
    expect(saved.registration!.userId, 'alice');
    expect(saved.registration!.passphrase, 'pass-1');
  });

  testWidgets('format and https errors show on the field and nothing is sent', (tester) async {
    await open(tester);
    await fill(tester, string: 'hello');
    await submit(tester);
    expect(find.text('Invalid Enrollment String'), findsOneWidget);

    await fill(tester, string: _enrollmentString(url: 'http://otp.example.com/'));
    await submit(tester);
    expect(find.text('The enrollment server must use https'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('enrollmentStringField')), '');
    await submit(tester);
    expect(find.text('Enrollment String is required'), findsOneWidget);
    expect(server.requests, isEmpty);
    expect(backend.writeCount, 0);
  });

  final failures = <String, (void Function(FakeDskppServer), String)>{
    'network': ((s) => s.failNetwork = true, "Couldn't reach the enrollment server"),
    'HTTP status': ((s) => s.httpStatus = 503, 'HTTP 503'),
    'rejection': ((s) => s.finishedStatus = 'Abort', 'refused the registration (Abort)'),
    'MAC mismatch': ((s) => s.tamperMac = true, 'key confirmation failed'),
    'bad response': ((s) => s.nextBody = 'garbage', "isn't a valid enrollment response"),
    'certificate': ((s) => s.failTls = true, "Couldn't verify the enrollment server's certificate"),
    'unsupported policy': ((s) => s.policy = '12345', 'may already have completed the registration'),
  };
  failures.forEach((name, failure) {
    testWidgets('$name: shows why and saves nothing', (tester) async {
      failure.$1(server);
      await open(tester);
      await fill(tester);
      await submit(tester);
      if (find.byKey(const ValueKey('otpPinField')).evaluate().isNotEmpty) await enterPin(tester, '2468');

      expect(errorText(tester), contains(failure.$2));
      expect(result, isNull);
      expect(await store.loadAll(), isEmpty);
      expect(backend.writeCount, 0);
      expect(find.byKey(const ValueKey('enrollProgress')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('enrollSubmitButton'))).onPressed, isNotNull);
    });
  });

  testWidgets('a long status from the server is cut short before it reaches the page', (tester) async {
    server.finishedStatus = '${'x' * 200}${'y' * 300}';
    await open(tester);
    await fill(tester);
    await submit(tester);
    if (find.byKey(const ValueKey('otpPinField')).evaluate().isNotEmpty) await enterPin(tester, '2468');

    final error = errorText(tester)!;
    expect(error, contains('${'x' * 200}…'));
    expect(error, isNot(contains('y')));
  });

  testWidgets('canceling the OTP PIN saves nothing and shows no error', (tester) async {
    await open(tester);
    await fill(tester);
    await submit(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();

    expect(errorText(tester), isNull);
    expect(server.requests, hasLength(1));
    expect(await store.loadAll(), isEmpty);
    expect(backend.writeCount, 0);
  });

  testWidgets('a failed save keeps the registered key and Save retries without registering again', (tester) async {
    server.softPin = null;
    backend.seedRaw(ProfileStore.storageKey, '[broken');
    await open(tester);
    await fill(tester);
    await submit(tester);

    expect(errorText(tester), contains('Tap Save to try again'));
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(server.requests, hasLength(2));

    backend.seedRaw(ProfileStore.storageKey, '');
    await submit(tester);
    expect(server.requests, hasLength(2));
    expect(result, isTrue);
    final saved = (await store.loadAll()).single;
    expect(saved.key, base64.encode(server.tokenKey!));
    expect(saved.registration!.enrollmentString, _enrollmentString());
  });

  testWidgets('leaving with a registered but unsaved key asks first', (tester) async {
    server.softPin = null;
    backend.seedRaw(ProfileStore.storageKey, '[broken');
    await open(tester);
    await fill(tester);
    await submit(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('keepEditingButton')));
    await tester.pumpAndSettle();
    expect(find.byType(EnrollmentScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discardChangesButton')));
    await tester.pumpAndSettle();
    expect(find.byType(EnrollmentScreen), findsNothing);
    expect(result, isNull);
  });

  testWidgets('pastes the Enrollment String from the clipboard', (tester) async {
    var clip = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': clip};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('pasteEnrollmentStringButton')));
    await tester.pumpAndSettle();
    expect(find.text('The clipboard has no text'), findsOneWidget);

    clip = '  ${_enrollmentString()}\n';
    await tester.tap(find.byKey(const ValueKey('pasteEnrollmentStringButton')));
    await tester.pumpAndSettle();
    expect(find.text('Registers with otp.example.com'), findsOneWidget);
  });

  testWidgets('the list offers both kinds and opens the matching screen', (tester) async {
    await pumpLocalized(
      tester,
      ProfileListScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('addKindActivationCode')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('addKindEnrollmentString')));
    await tester.pumpAndSettle();
    expect(find.byType(EnrollmentScreen), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('addKindActivationCode')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsOneWidget);
  });

  testWidgets('dismissing the kind sheet opens nothing', (tester) async {
    await pumpLocalized(
      tester,
      ProfileListScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(EnrollmentScreen), findsNothing);
    expect(find.byType(ProfileEditScreen), findsNothing);
  });
}

class _BrokenBackend extends MemoryKeyValueBackend {
  @override
  Future<String?> read(String key) async => throw PlatformException(code: 'decrypt', message: 'bad key');
}
