import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/l10n/app_locale.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';
import 'package:simple_pass/platform/camera_permission.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/fake_qr.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

// "Hello!" followed by 0xDEADBEEF, the Key Uri Format example secret.
const _secret = 'JBSWY3DPEHPK3PXP';
final _secretBase64 = base64.encode([...ascii.encode('Hello!'), 0xde, 0xad, 0xbe, 0xef]);
const _link = 'otpauth://totp/Example:alice@google.com?secret=$_secret&issuer=Example';

void main() {
  late ProfileStore store;
  late FakeKeystore keystore;
  late SettingsStore settingsStore;
  late FakeCameraPermission permission;
  late FakeQrReader reader;
  late List<MethodCall> clipboardCalls;
  late List<Object?> popped;

  setUp(() {
    keystore = FakeKeystore();
    store = ProfileStore(MemoryKeyValueBackend(), keystore: keystore);
    settingsStore = SettingsStore(MemoryKeyValueBackend());
    permission = FakeCameraPermission();
    reader = FakeQrReader();
    popped = [];
    clipboardCalls = [];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    SensitiveClipboard.debugInstanceOverride = SensitiveClipboard();
    messenger.setMockMethodCallHandler(const MethodChannel(SensitiveClipboard.channelName), (call) async {
      clipboardCalls.add(call);
      return call.method == 'clearIfMatches' ? 'cleared' : null;
    });
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    SensitiveClipboard.debugInstanceOverride = null;
    messenger.setMockMethodCallHandler(const MethodChannel(SensitiveClipboard.channelName), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> open(WidgetTester tester, {Profile? profile}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: appSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => popped.add(
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileEditScreen(
                        profileStore: store,
                        settingsStore: settingsStore,
                        profile: profile,
                        kind: ProfileKind.totp,
                        cameraPermission: permission,
                        qrReader: reader,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(ValueKey(key));
  String text(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.descendant(of: field(key), matching: find.byType(TextField))).controller!.text;
  bool readOnly(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.descendant(of: field(key), matching: find.byType(TextField))).readOnly;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> scan(WidgetTester tester) async {
    final before = permission.requests;
    await tap(tester, field('scanQrButton'));
    expect(permission.requests, before);
    await tap(tester, field('scanQrCameraButton'));
  }

  Future<void> save(WidgetTester tester) => tap(tester, find.widgetWithText(FilledButton, 'Save'));

  group('adding', () {
    testWidgets('manual entry tolerates spaces and lowercase and saves the RFC 6238 defaults', (tester) async {
      await open(tester);
      expect(field('policyField'), findsNothing);
      expect(field('activationCodeField'), findsNothing);
      expect(field('counterField'), findsNothing);
      await tester.enterText(field('nameField'), 'GitHub');
      await tester.enterText(field('secretField'), 'jbsw y3dp ehpk 3pxp');
      await save(tester);

      final saved = (await store.loadAll()).single;
      expect(popped, [true]);
      expect(saved.kind, ProfileKind.totp);
      expect(saved.name, 'GitHub');
      // Stored as typed; used as SHA1, 6 digits, 30 seconds.
      expect(saved.key, 'jbsw y3dp ehpk 3pxp');
      expect(saved.oathCredential!.secret, base64.decode(_secretBase64));
      expect(saved.oathCredential!.algorithm, OtpAlgorithm.sha1);
      expect(saved.codeDigits, 6);
      expect(saved.timeStep, 30);
      expect(saved.activationCode, '');
      expect(saved.policy, '');
    });

    testWidgets(
      'app-wide protection on: a new TOTP and a new HOTP are sealed, prompting only once the window ran out',
      (tester) async {
        await settingsStore.save(const Settings(requireAuth: true));
        await open(tester);
        await tester.enterText(field('nameField'), 'GitHub');
        await tester.enterText(field('secretField'), _secret);
        await save(tester);
        expect(popped, [true]);
        expect(keystore.authenticateCalls, 1);
        expect((await store.loadAll()).single.protected, isTrue);

        await open(tester);
        await tester.enterText(field('nameField'), 'Counter');
        await tester.enterText(field('secretField'), 'otpauth://hotp/Svc?secret=$_secret&counter=5');
        await tester.pumpAndSettle();
        await save(tester);
        final all = await store.loadAll();
        expect(all.map((p) => (p.kind, p.protected)), [(ProfileKind.totp, true), (ProfileKind.hotp, true)]);
        expect(
          keystore.authenticateCalls,
          1,
          reason: 'a new profile sealed inside the key window needs no further prompt',
        );
      },
    );

    testWidgets('app-wide protection off: a new standard token is stored in the clear without a prompt', (
      tester,
    ) async {
      await settingsStore.save(const Settings(requireAuth: false));
      await open(tester);
      await tester.enterText(field('nameField'), 'GitHub');
      await tester.enterText(field('secretField'), _secret);
      await save(tester);
      expect((await store.loadAll()).single.protected, isFalse);
      expect(keystore.authenticateCalls, 0);
    });

    testWidgets('unreadable settings fail closed: a new standard token is sealed', (tester) async {
      settingsStore = SettingsStore(_BrokenBackend());
      await open(tester);
      await tester.enterText(field('nameField'), 'GitHub');
      await tester.enterText(field('secretField'), _secret);
      await save(tester);
      expect(popped, [true]);
      expect(keystore.authenticateCalls, 1);
      expect((await store.loadAll()).single.protected, isTrue);
    });

    testWidgets('a canceled prompt keeps the form and saves nothing', (tester) async {
      await settingsStore.save(const Settings(requireAuth: true));
      await open(tester);
      keystore.authResults.add(AuthResult.canceled);
      await tester.enterText(field('nameField'), 'GitHub');
      await tester.enterText(field('secretField'), _secret);
      await save(tester);
      expect(find.text('Authentication canceled'), findsOneWidget);
      expect(popped, isEmpty);
      expect(await store.loadAll(), isEmpty);
    });

    testWidgets('a missing or non-Base32 secret is refused', (tester) async {
      await open(tester);
      await tester.enterText(field('nameField'), 'X');
      await save(tester);
      expect(find.text('Secret key is required'), findsOneWidget);
      await tester.enterText(field('secretField'), 'JBSW1Y3D');
      await save(tester);
      expect(find.text('Not a valid Base32 secret key'), findsOneWidget);
      expect(await store.loadAll(), isEmpty);
    });

    testWidgets('manual entry exposes OTP parameters without separate issuer or account fields', (tester) async {
      await open(tester);
      expect(field('otpTypeField'), findsOneWidget);
      expect(field('otpAlgorithmField'), findsOneWidget);
      expect(field('otpDigitsField'), findsOneWidget);
      expect(field('otpPeriodField'), findsOneWidget);
      for (final gone in ['Issuer', 'Account', 'Advanced']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('scanning a link puts the whole link in Secret and names the profile "issuer: account"', (
      tester,
    ) async {
      await open(tester);
      reader.scanned = '$_link&algorithm=SHA256&digits=8&period=45';
      await scan(tester);
      expect(find.text('Filled in from the link'), findsOneWidget);
      expect(text(tester, 'nameField'), 'Example: alice@google.com');
      expect(text(tester, 'secretField'), '$_link&algorithm=SHA256&digits=8&period=45');
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.kind, ProfileKind.totp);
      expect(saved.key, '$_link&algorithm=SHA256&digits=8&period=45');
      expect(saved.oathCredential!.algorithm, OtpAlgorithm.sha256);
      expect(saved.codeDigits, 8);
      expect(saved.timeStep, 45);
    });

    testWidgets('a link typed into the Secret field stays as is and names the profile', (tester) async {
      await open(tester);
      await tester.enterText(field('secretField'), '$_link&digits=8&period=60');
      await tester.pumpAndSettle();
      expect(text(tester, 'secretField'), '$_link&digits=8&period=60');
      expect(text(tester, 'nameField'), 'Example: alice@google.com');
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.key, '$_link&digits=8&period=60');
      expect(saved.codeDigits, 8);
      expect(saved.timeStep, 60);
    });

    testWidgets('a bad link in the Secret field is refused with the link message', (tester) async {
      await open(tester);
      await tester.enterText(field('nameField'), 'X');
      await tester.enterText(field('secretField'), 'otpauth://totp/x?secret=$_secret&digits=7');
      await save(tester);
      expect(find.textContaining('this app doesn\'t support'), findsOneWidget);
      expect(await store.loadAll(), isEmpty);
    });

    testWidgets('replacing an imported link with a bare secret makes a default TOTP', (tester) async {
      await open(tester);
      reader.scanned = 'otpauth://hotp/Svc:carol?secret=$_secret&counter=42&algorithm=SHA512&digits=8';
      await scan(tester);
      expect(field('counterField'), findsNothing);
      await tester.enterText(field('secretField'), 'MZXW6YTBOI');
      await tester.pumpAndSettle();
      expect(field('counterField'), findsNothing);
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.kind, ProfileKind.totp);
      expect(saved.key, 'MZXW6YTBOI');
      expect(saved.oathCredential!.algorithm, OtpAlgorithm.sha1);
      expect(saved.codeDigits, 6);
      expect(saved.timeStep, 30);
      expect(saved.name, 'Svc: carol');
    });

    testWidgets('the kind follows the Secret text: an hotp link changed to totp saves as TOTP', (tester) async {
      await open(tester);
      reader.scanned = 'otpauth://hotp/Svc:carol?secret=$_secret&counter=0';
      await scan(tester);
      expect(field('counterField'), findsNothing);
      await tester.enterText(field('secretField'), 'otpauth://totp/Svc:carol?secret=$_secret&counter=0');
      await tester.pumpAndSettle();
      expect(field('counterField'), findsNothing);
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.kind, ProfileKind.totp);
      expect(saved.key, 'otpauth://totp/Svc:carol?secret=$_secret&counter=0');
      expect(saved.isTimeBased, isTrue);
    });

    testWidgets('a totp link changed to hotp saves as HOTP with the link counter', (tester) async {
      await open(tester);
      await tester.enterText(field('secretField'), 'otpauth://totp/Svc?secret=$_secret');
      await tester.pumpAndSettle();
      await tester.enterText(field('secretField'), 'otpauth://hotp/Svc?secret=$_secret&counter=5');
      await tester.pumpAndSettle();
      expect(field('counterField'), findsNothing);
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.kind, ProfileKind.hotp);
      expect(saved.counter, 5);
    });

    testWidgets('an Enrollment String points to auto enrollment instead', (tester) async {
      await open(tester);
      reader.scanned = base64.encode(
        utf8.encode('EnrollmentURL=https://example.com/enroll\r\nUserID=alice\r\nPassphrase=secret'),
      );
      await scan(tester);
      expect(
        find.text('This is an Enrollment String. Add it with "MobilePASS – Auto enrollment" instead.'),
        findsOneWidget,
      );
      expect(clipboardCalls, isEmpty);
    });

    testWidgets('a name the user already typed is kept', (tester) async {
      await open(tester);
      await tester.enterText(field('nameField'), 'Mine');
      reader.scanned = _link;
      await scan(tester);
      expect(text(tester, 'nameField'), 'Mine');
    });

    testWidgets('an hotp link makes an event-based profile with its counter', (tester) async {
      await open(tester);
      reader.scanned = 'otpauth://hotp/Svc:carol?secret=$_secret&counter=42&digits=8';
      await scan(tester);
      expect(field('counterField'), findsNothing);
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.kind, ProfileKind.hotp);
      expect(saved.key, 'otpauth://hotp/Svc:carol?secret=$_secret&counter=42&digits=8');
      expect(saved.counter, 42);
      expect(saved.codeDigits, 8);
      expect(saved.name, 'Svc: carol');
    });

    for (final (input, message) in [
      ('otpauth-migration://offline?data=CjEKCkhlbGxv', 'otpauth-migration://'),
      ('https://example.com', 'Not an otpauth:// link'),
      ('otpauth://totp/x?secret=0000', 'The link\'s secret is missing or invalid'),
      ('otpauth://totp/x?secret=$_secret&digits=7', 'this app doesn\'t support'),
      ('otpauth://steam/x?secret=$_secret', 'Only TOTP and HOTP links are supported'),
      ('otpauth://hotp/x?secret=$_secret', 'this app doesn\'t support'),
    ]) {
      testWidgets('a bad link ($input) explains itself and changes nothing', (tester) async {
        await open(tester);
        reader.scanned = input;
        await scan(tester);
        expect(find.textContaining(message), findsOneWidget);
        expect(text(tester, 'secretField'), '');
        expect(text(tester, 'nameField'), '');
      });
    }
  });

  group('scanning', () {
    testWidgets('source chooser only offers camera and photo; cancel preserves input without permission requests', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(field('secretField'), _secret);
      await tap(tester, field('scanQrButton'));
      expect(field('qrSourceSheet'), findsOneWidget);
      expect(field('scanQrCameraButton'), findsOneWidget);
      expect(field('importQrPhotoButton'), findsOneWidget);
      expect(field('pasteOtpauthLinkButton'), findsNothing);
      expect(permission.requests, 0);
      expect(reader.scans, 0);
      expect(reader.photos, 0);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(field('qrSourceSheet'), findsNothing);
      expect(text(tester, 'secretField'), _secret);
      expect(tester.widget<IconButton>(field('scanQrButton')).onPressed, isNotNull);
      expect(permission.requests, 0);
    });

    testWidgets('asks for the camera only on tap, then fills the form from the code', (tester) async {
      reader.scanned = _link;
      await open(tester);
      expect(permission.requests, 0);
      await scan(tester);
      expect(permission.requests, 1);
      expect(reader.scans, 1);
      expect(text(tester, 'secretField'), _link);
      expect(text(tester, 'nameField'), 'Example: alice@google.com');
    });

    testWidgets('backing out of the scanner changes nothing', (tester) async {
      await open(tester);
      await scan(tester);
      expect(reader.scans, 1);
      expect(text(tester, 'secretField'), '');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a denied permission explains, never opens the camera, and manual entry still works', (tester) async {
      permission.status = CameraPermissionStatus.denied;
      await open(tester);
      await scan(tester);
      expect(reader.scans, 0);
      expect(find.text('Scanning needs camera access. You can still enter the secret key by hand.'), findsOneWidget);
      await tester.enterText(field('nameField'), 'Manual');
      await tester.enterText(field('secretField'), _secret);
      await save(tester);
      expect((await store.loadAll()).single.key, _secret);
    });

    testWidgets('a permanently denied permission offers the system settings', (tester) async {
      permission.status = CameraPermissionStatus.permanentlyDenied;
      await open(tester);
      await scan(tester);
      expect(reader.scans, 0);
      expect(find.textContaining('Turn it on in system settings'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(permission.settingsOpened, 1);
    });

    testWidgets('a second tap while an import runs does nothing; a busy dialog says nothing', (tester) async {
      final gate = Completer<String?>();
      reader.scanGate = gate;
      await open(tester);
      await tap(tester, field('scanQrButton'));
      await tester.tap(field('scanQrCameraButton'));
      await tester.pump();
      await tester.tap(field('scanQrButton'), warnIfMissed: false);
      await tester.pump();
      expect(permission.requests, 1);
      expect(tester.widget<IconButton>(field('scanQrButton')).onPressed, isNull);
      gate.complete(_link);
      await tester.pumpAndSettle();
      expect(text(tester, 'secretField'), _link);
      expect(tester.widget<IconButton>(field('scanQrButton')).onPressed, isNotNull);

      permission.status = CameraPermissionStatus.busy;
      ScaffoldMessenger.of(tester.element(field('scanQrButton'))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await scan(tester);
      expect(reader.scans, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a photo with a code fills the form; none found or a failure says so; cancel is silent', (
      tester,
    ) async {
      await open(tester);
      reader.photo = null;
      await tap(tester, field('scanQrButton'));
      await tap(tester, field('importQrPhotoButton'));
      expect(find.byType(SnackBar), findsNothing);

      reader.photo = '';
      await tap(tester, field('scanQrButton'));
      await tap(tester, field('importQrPhotoButton'));
      expect(find.text('No QR code found in that photo'), findsOneWidget);

      reader.photoError = PlatformException(code: 'photo_access_denied');
      await tap(tester, field('scanQrButton'));
      await tap(tester, field('importQrPhotoButton'));
      expect(find.text('No QR code found in that photo'), findsOneWidget);

      reader
        ..photoError = null
        ..photo = _link;
      await tap(tester, field('scanQrButton'));
      await tap(tester, field('importQrPhotoButton'));
      expect(text(tester, 'secretField'), _link);
      expect(permission.requests, 0);
    });
  });

  group('editing', () {
    const storedLink = '$_link&algorithm=SHA256&digits=8&period=60';
    Profile stored() => Profile(
      id: 't1',
      name: 'Example',
      activationCode: '',
      kind: ProfileKind.totp,
      key: storedLink,
      pin: '1234',
      counter: 0,
    );

    testWidgets('the secret key alone is shown read-only; titled by type; no import buttons', (tester) async {
      await store.saveAll([stored()]);
      await open(tester, profile: stored());
      expect(readOnly(tester, 'secretField'), isTrue);
      expect(text(tester, 'secretField'), _secret);
      expect(field('equivalentLinkField'), findsNothing);
      expect(find.widgetWithText(AppBar, 'TOTP profile'), findsOneWidget);
      expect(field('issuerField'), findsNothing);
      expect(field('accountField'), findsNothing);
      expect(field('scanQrButton'), findsNothing);
      expect(field('pasteOtpauthLinkButton'), findsNothing);
      expect(find.text('Advanced'), findsNothing);
      expect(readOnly(tester, 'otpPeriodField'), isTrue);
      expect(text(tester, 'otpPeriodField'), '60');
      expect(readOnly(tester, 'otpDigitsField'), isTrue);
      expect(readOnly(tester, 'otpAlgorithmField'), isTrue);
      expect(text(tester, 'otpAlgorithmField'), 'SHA-256');
    });

    testWidgets('Copy Secret copies the secret key as sensitive', (tester) async {
      await store.saveAll([stored()]);
      await open(tester, profile: stored());
      await tap(tester, field('copySecretButton'));
      expect(clipboardCalls.first.method, 'setText');
      expect(clipboardCalls.first.arguments, {'text': _secret, 'sensitive': true});
      expect(find.text('Secret key copied'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('name, PIN and copy options change; secret and parameters stay', (tester) async {
      await store.saveAll([stored()]);
      await open(tester, profile: stored());
      await tester.enterText(field('nameField'), 'Renamed');
      await tester.enterText(field('pinField'), '987654');
      await tap(tester, find.text('Append PIN when copying'));
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.name, 'Renamed');
      expect(saved.pin, '987654');
      expect(saved.appendPinOnCopy, isTrue);
      expect(saved.key, storedLink);
      expect(saved.codeDigits, 8);
    });

    testWidgets('an HOTP profile is titled as such and keeps its own counter', (tester) async {
      final hotp = Profile(
        id: 'h1',
        name: 'Svc',
        activationCode: '',
        kind: ProfileKind.hotp,
        key: 'otpauth://hotp/Svc?secret=$_secret&counter=0',
        counter: 7,
      );
      await store.saveAll([hotp]);
      await open(tester, profile: hotp);
      expect(find.widgetWithText(AppBar, 'HOTP profile'), findsOneWidget);
      expect(text(tester, 'counterField'), '7');
      await tester.enterText(field('counterField'), '9');
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect(saved.counter, 9);
      expect(saved.key, 'otpauth://hotp/Svc?secret=$_secret&counter=0');
    });
  });

  testWidgets('the add sheet offers TOTP and opens its form', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpLocalized(
      tester,
      ProfileListScreen(profileStore: store, settingsStore: settingsStore, screenGuard: ScreenGuard()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add profile'));
    await tester.pumpAndSettle();
    for (final kind in ['MobilePASS – Manual enrollment', 'MobilePASS – Auto enrollment', 'Add manually']) {
      expect(find.text(kind), findsOneWidget, reason: kind);
    }
    await tester.tap(find.byKey(const ValueKey('addKindTotp')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Add manually'), findsOneWidget);
    expect(field('secretField'), findsOneWidget);
    expect(field('scanQrButton'), findsOneWidget);
    expect(field('activationCodeField'), findsNothing);
  });

  group('PlatformCameraPermission', () {
    const channel = MethodChannel(PlatformCameraPermission.channelName);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('maps the platform answer', () async {
      for (final (answer, expected) in [
        ('granted', CameraPermissionStatus.granted),
        ('denied', CameraPermissionStatus.denied),
        ('permanentlyDenied', CameraPermissionStatus.permanentlyDenied),
        ('busy', CameraPermissionStatus.busy),
        ('weird', CameraPermissionStatus.denied),
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'request' ? answer : null);
        expect(await PlatformCameraPermission().request(), expected, reason: answer);
      }
    });

    test('platform errors and a missing binding count as denied', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'NO_ACTIVITY'));
      expect(await PlatformCameraPermission().request(), CameraPermissionStatus.denied);
      messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'IN_PROGRESS'));
      expect(await PlatformCameraPermission().request(), CameraPermissionStatus.busy);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await PlatformCameraPermission().request(), CameraPermissionStatus.denied);
      await PlatformCameraPermission().openSettings();
    });
  });
}

class _BrokenBackend extends MemoryKeyValueBackend {
  @override
  Future<String?> read(String key) async => throw PlatformException(code: 'decrypt', message: 'bad key');
}
