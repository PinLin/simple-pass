import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/dskpp_client.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/device_info.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
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

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';

Profile _work() => Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5, pin: '1234');
Profile _home() => Profile(id: 'b2', name: 'Home', activationCode: _code, counter: 7);
Profile _token() => Profile(
  id: 'k1',
  name: 'Token',
  activationCode: '',
  kind: ProfileKind.mobilePassKey,
  key: base64.encode(List.filled(20, 7)),
  serial: '123456789',
  policy: '9346',
  pin: '2468',
  counter: 0,
);

String _enrollmentString() => base64.encode(
  utf8.encode(['EnrollmentURL=https://otp.example.com/dskpp', 'UserID=alice', 'Passphrase=pass-1'].join('\r\n')),
);

typedef _Handler = Future<DskppHttpResponse> Function(Uri url, Uint8List body);

/// Routes every `HttpClient` post the app makes to [handler], so the list's own Enrollment page
/// (which builds its own transport) talks to the fake server.
class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides(this.handler);
  final _Handler handler;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient(handler);
}

class _FakeClient implements HttpClient {
  _FakeClient(this.handler);
  final _Handler handler;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _FakeRequest(url, handler);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) => values[name] = '$value';

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      values.forEach((name, value) => action(name, [value]));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.url, this.handler);
  final Uri url;
  final _Handler handler;
  final _body = BytesBuilder();
  final _headers = _FakeHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  void add(List<int> data) => _body.add(data);

  @override
  Future<HttpClientResponse> close() async {
    final reply = await handler(url, _body.toBytes());
    return _FakeResponse(reply);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.reply);
  final DskppHttpResponse reply;

  @override
  int get statusCode => reply.statusCode;

  @override
  HttpHeaders get headers {
    final headers = _FakeHeaders();
    reply.headers.forEach(headers.set);
    return headers;
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(
    reply.body,
  ).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late MemoryKeyValueBackend backend;
  late FakeKeystore keystore;
  late ProfileStore store;
  late FakeDskppServer server;
  late HttpOverrides? originalOverrides;

  // Held back while non-null, like a server that takes a long time to answer.
  Completer<void>? gate;

  setUp(() async {
    backend = MemoryKeyValueBackend();
    keystore = FakeKeystore();
    store = ProfileStore(backend, keystore: keystore);
    server = FakeDskppServer(userId: 'alice', passphrase: 'pass-1');
    gate = null;
    await store.saveAll([_work(), _home()]);
    originalOverrides = HttpOverrides.current;
    HttpOverrides.global = _FakeHttpOverrides((url, body) async {
      await gate?.future;
      return server.post(url, body);
    });
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), (call) async => null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(SensitiveClipboard.channelName),
      (call) async => call.method == 'clearIfMatches' ? 'cleared' : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(DeviceInfo.channelName),
      (call) async => call.method == 'osRelease' ? '16' : null,
    );
  });

  tearDown(() {
    HttpOverrides.global = originalOverrides;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), null);
    messenger.setMockMethodCallHandler(const MethodChannel(SensitiveClipboard.channelName), null);
    messenger.setMockMethodCallHandler(const MethodChannel(DeviceInfo.channelName), null);
  });

  String raw() => backend.rawValue(ProfileStore.storageKey)!;

  /// Profiles sealed and the key's window ran out, the way a cold start finds them.
  Future<void> coldStart({required bool auth}) async {
    await SettingsStore(backend).save(Settings(requireAuth: auth));
    if (auth) await store.setAllProtected(true);
    store.forget();
    keystore.expire();
    keystore.authenticateCalls = 0;
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLocalized(
      tester,
      ProfileListScreen(profileStore: store, settingsStore: SettingsStore(backend), screenGuard: ScreenGuard()),
    );
    await tester.pumpAndSettle();
  }

  // A busy Enrollment page animates a progress bar forever, so pumpAndSettle never returns there; the
  // real-time wait lets the HTTP client stand-in finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> background(WidgetTester tester) async {
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await settle(tester);
  }

  Future<void> resume(WidgetTester tester) async {
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await settle(tester);
  }

  final unlockButton = find.byKey(const ValueKey('unlockAppButton'));
  final lockedText = find.text('SimplePASS is locked');
  final stringField = find.byKey(const ValueKey('enrollmentStringField'));
  final submitButton = find.byKey(const ValueKey('enrollSubmitButton'));
  final enrollment = find.byType(EnrollmentScreen, skipOffstage: false);

  Future<void> openAddSheet(WidgetTester tester, String kindKey) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(kindKey)));
    await tester.pumpAndSettle();
  }

  Future<void> openEnrollment(WidgetTester tester) => openAddSheet(tester, 'addKindEnrollmentString');

  Future<void> fillEnrollment(WidgetTester tester) async {
    await tester.enterText(stringField, _enrollmentString());
    await tester.enterText(find.byKey(const ValueKey('enrollNameField')), 'Office');
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await settle(tester);
  }

  Future<void> enterPin(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('otpPinField')), '2468');
    await tester.tap(find.byKey(const ValueKey('otpPinConfirmButton')));
    await settle(tester);
  }

  void expectCovered() {
    expect(enrollment, findsOneWidget, reason: 'the Enrollment page was not closed');
    expect(stringField, findsNothing, reason: 'and none of its content is visible');
    expect(find.byKey(const ValueKey('enrollNameField')), findsNothing);
    expect(submitButton, findsNothing);
    expect(lockedText, findsOneWidget);
    expect(unlockButton, findsOneWidget);
    expect(find.text('Work'), findsNothing);
  }

  Future<void> expectSavedAndListed(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(enrollment, findsNothing);
    expect(find.text('Office'), findsOneWidget);
    final saved = (await store.loadAll()).firstWhere((p) => p.name == 'Office');
    expect((saved.kind, saved.protected, saved.locked, saved.pin), (ProfileKind.mobilePassKey, true, false, '2468'));
  }

  group('Enrollment page under the app lock', () {
    testWidgets('registration in progress: backgrounding covers it, unlocking returns to it and it finishes', (
      tester,
    ) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);

      gate = Completer<void>();
      await submit(tester);
      expect(find.byKey(const ValueKey('enrollProgress')), findsOneWidget, reason: 'registering');

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      expectCovered();

      await resume(tester);
      expectCovered();
      expect(keystore.authenticateCalls, 2, reason: 'the unlock at start and the canceled one on resuming');

      await tester.tap(unlockButton);
      await settle(tester);
      expect(lockedText, findsNothing);
      expect(stringField, findsOneWidget, reason: 'back on the Enrollment page');
      expect(find.byKey(const ValueKey('enrollProgress')), findsOneWidget, reason: 'still registering');

      gate!.complete();
      await settle(tester);
      await enterPin(tester);
      await expectSavedAndListed(tester);
    });

    testWidgets('the server answers while covered: the PIN prompt waits until the page is unlocked', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);
      gate = Completer<void>();
      await submit(tester);

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      await resume(tester);
      expectCovered();

      gate!.complete();
      await settle(tester);
      expectCovered();
      expect(find.byKey(const ValueKey('otpPinField')), findsNothing, reason: 'nothing shows above the cover');

      await tester.tap(unlockButton);
      await settle(tester);
      expect(lockedText, findsNothing);
      expect(find.byKey(const ValueKey('otpPinField')), findsOneWidget);
      await enterPin(tester);
      await expectSavedAndListed(tester);
    });

    testWidgets('a save that lands while covered closes only the Enrollment page, and the cover stays', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);
      await submit(tester);
      backend.writeGate = Completer<void>();
      await enterPin(tester);

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      await resume(tester);
      expectCovered();

      backend.writeGate!.complete();
      backend.writeGate = null;
      await settle(tester);
      expect(enrollment, findsNothing, reason: 'saved, so the page is done');
      expect(stringField, findsNothing);
      expect(lockedText, findsOneWidget);
      expect(unlockButton, findsOneWidget);
      expect(find.text('Work'), findsNothing);
      expect(find.text('Office'), findsNothing);

      await tester.tap(unlockButton);
      await settle(tester);
      await expectSavedAndListed(tester);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('a successful unlock on resuming goes straight back to the registration', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);
      gate = Completer<void>();
      await submit(tester);

      await background(tester);
      expectCovered();
      await resume(tester);
      expect(lockedText, findsNothing);
      expect(stringField, findsOneWidget);

      gate!.complete();
      await settle(tester);
      await enterPin(tester);
      await expectSavedAndListed(tester);
    });

    testWidgets('registered but not saved: backgrounding covers it, and after unlocking Save succeeds', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);
      backend.failWritesFor.add(ProfileStore.storageKey);
      await submit(tester);
      await enterPin(tester);
      expect(find.textContaining("Registered, but the profile couldn't be saved"), findsOneWidget);

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      await resume(tester);
      expectCovered();
      expect(find.textContaining("Registered, but"), findsNothing);

      backend.failWritesFor.clear();
      await tester.tap(unlockButton);
      await settle(tester);
      expect(lockedText, findsNothing);
      expect(find.textContaining("Registered, but the profile couldn't be saved"), findsOneWidget);

      await tester.tap(submitButton);
      await settle(tester);
      await expectSavedAndListed(tester);
      expect(raw(), isNot(contains('2468')), reason: 'sealed, not in the clear');
    });

    testWidgets('a canceled unlock keeps the cover up, hides the content and ignores the back button', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);
      backend.failWritesFor.add(ProfileStore.storageKey);
      await submit(tester);
      await enterPin(tester);

      keystore.authResults.addAll([AuthResult.canceled, AuthResult.canceled]);
      await background(tester);
      await resume(tester);
      expectCovered();

      await tester.binding.handlePopRoute();
      await settle(tester);
      expectCovered();

      await tester.tap(unlockButton);
      await settle(tester);
      expectCovered();
      expect(keystore.authenticateCalls, 3);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expectCovered();
      expect(find.byType(AlertDialog), findsNothing);

      backend.failWritesFor.clear();
      await tester.tap(unlockButton);
      await settle(tester);
      expect(stringField, findsOneWidget);
      await tester.tap(submitButton);
      await settle(tester);
      await expectSavedAndListed(tester);
    });

    testWidgets('an Enrollment page with nothing in flight is closed like any other sub-page', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      await resume(tester);
      expect(enrollment, findsNothing);
      expect(lockedText, findsOneWidget);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('an ordinary edit page is still closed when the app relocks', (tester) async {
      await coldStart(auth: true);
      await pumpList(tester);
      await openAddSheet(tester, 'addKindActivationCode');
      expect(find.byType(ProfileEditScreen), findsOneWidget);

      keystore.authResults.add(AuthResult.canceled);
      await background(tester);
      await resume(tester);
      expect(find.byType(ProfileEditScreen, skipOffstage: false), findsNothing);
      expect(lockedText, findsOneWidget);
      expect(unlockButton, findsOneWidget);
      expect(find.text('Work'), findsNothing);

      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileEditScreen, skipOffstage: false), findsNothing);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('requireAuth off and nothing sealed: backgrounding leaves a running registration alone', (
      tester,
    ) async {
      await coldStart(auth: false);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);
      gate = Completer<void>();
      await submit(tester);

      await background(tester);
      await resume(tester);
      expect(lockedText, findsNothing);
      expect(unlockButton, findsNothing);
      expect(stringField, findsOneWidget);
      expect(keystore.authenticateCalls, 0);

      gate!.complete();
      await settle(tester);
      await enterPin(tester);
      await tester.pumpAndSettle();
      expect(enrollment, findsNothing);
      expect(find.text('Office'), findsOneWidget);
      expect(keystore.authenticateCalls, 0);
    });

    testWidgets('requireAuth off: a registered-but-unsaved page is left alone too', (tester) async {
      await coldStart(auth: false);
      await pumpList(tester);
      await openEnrollment(tester);
      await fillEnrollment(tester);
      backend.failWritesFor.add(ProfileStore.storageKey);
      await submit(tester);
      await enterPin(tester);

      await background(tester);
      await resume(tester);
      expect(lockedText, findsNothing);
      expect(stringField, findsOneWidget);
      expect(find.textContaining("Registered, but the profile couldn't be saved"), findsOneWidget);
      expect(keystore.authenticateCalls, 0);

      backend.failWritesFor.clear();
      await tester.tap(submitButton);
      await settle(tester);
      await tester.pumpAndSettle();
      expect(enrollment, findsNothing);
      expect(find.text('Office'), findsOneWidget);
    });
  });

  group('a damaged sealed value in the list', () {
    void damage(String id) {
      final all = ((jsonDecode(raw()) as Map)['profiles'] as List).cast<Map<String, dynamic>>();
      final entry = all.firstWhere((e) => e['id'] == id);
      final parts = (entry['sealed'] as String).split(':');
      parts[parts.length - 1] = base64.encode(utf8.encode('not what was sealed'));
      entry['sealed'] = parts.join(':');
      backend.seedRaw(ProfileStore.storageKey, jsonEncode({'profiles': all}));
    }

    String otp(int counter) => formatOtpForDisplay(generateMobilePassOtp(_code, counter));

    testWidgets('unlocking opens the good row; the damaged one shows an invalid code and no deletion is offered', (
      tester,
    ) async {
      await coldStart(auth: true);
      damage('b2');
      final before = raw();
      await pumpList(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Delete these profiles'), findsNothing);
      expect(lockedText, findsNothing);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text(otp(5)), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Invalid Activation Code'), findsOneWidget);
      expect(find.text(otp(7)), findsNothing);
      expect(keystore.authenticateCalls, 1);
      expect(raw(), before, reason: 'nothing was deleted or rewritten');
    });

    testWidgets('a damaged MobilePASS key row says the stored key is invalid', (tester) async {
      await store.saveAll([_work(), _token()]);
      await coldStart(auth: true);
      damage('k1');
      await pumpList(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(otp(5)), findsOneWidget);
      expect(find.text('Token'), findsOneWidget);
      expect(find.text('Invalid stored key'), findsOneWidget);
    });
  });

  group('saving an edit after the secrets were dropped', () {
    testWidgets('shows the save-failed message and writes nothing, instead of pretending to succeed', (tester) async {
      await store.setAllProtected(true);
      final open = (await store.loadAll()).firstWhere((p) => p.id == 'a1');
      expect(open.locked, isFalse);
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLocalized(
        tester,
        ProfileEditScreen(profileStore: store, settingsStore: SettingsStore(backend), profile: open),
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Renamed');
      await tester.pump();

      // The app was backgrounded behind the page (as with a prompt that paused it): the secrets are gone.
      await store.forget();
      keystore.expire();
      final before = raw();
      final writes = backend.writeCount;

      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text('Could not save changes'), findsOneWidget);
      expect(find.byType(ProfileEditScreen), findsOneWidget, reason: 'the page stays so nothing is lost');
      expect((raw(), backend.writeCount), (before, writes));
    });
  });
}
