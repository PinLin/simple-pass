import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

// RFC 6238 appendix B SHA1 seed; at 59 s its 8-digit code is 94287082.
const _secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
final _now = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);

Profile _token({
  String id = 't1',
  String name = 'Example',
  ProfileKind kind = ProfileKind.totp,
  int counter = 0,
  String pin = '',
  bool appendPinOnCopy = false,
}) => Profile(
  id: id,
  name: name,
  activationCode: '',
  kind: kind,
  key: kind == ProfileKind.hotp
      ? 'otpauth://hotp/Example:alice@example.com?secret=$_secret&digits=8&counter=0'
      : 'otpauth://totp/Example:alice@example.com?secret=$_secret&issuer=Example&digits=8',
  counter: counter,
  pin: pin,
  appendPinOnCopy: appendPinOnCopy,
);

void main() {
  late List<MethodCall> clipboardCalls;

  setUp(() {
    clipboardCalls = [];
    SensitiveClipboard.debugInstanceOverride = SensitiveClipboard();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(SensitiveClipboard.channelName),
      (call) async {
        clipboardCalls.add(call);
        return call.method == 'clearIfMatches' ? 'cleared' : null;
      },
    );
  });

  tearDown(() {
    SensitiveClipboard.debugInstanceOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(SensitiveClipboard.channelName),
      null,
    );
  });

  Future<ProfileStore> pump(WidgetTester tester, List<Profile> profiles) async {
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll(profiles);
    await pumpLocalized(
      tester,
      ProfileListScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
        now: () => _now,
      ),
    );
    await tester.pump();
    await tester.pump();
    return store;
  }

  testWidgets('a TOTP row shows its code, only the name and a countdown', (tester) async {
    await pump(tester, [_token(name: 'Example: alice@example.com')]);
    expect(find.text('9428 7082'), findsOneWidget);
    expect(find.text('Example: alice@example.com'), findsOneWidget);
    expect(find.text('alice@example.com'), findsNothing);
    expect(find.byKey(const ValueKey('profileCountdown-t1')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('Mark as used'), findsNothing);
  });

  testWidgets('tapping copies PIN + code when asked to', (tester) async {
    await pump(tester, [_token(pin: '1234', appendPinOnCopy: true)]);
    await tester.tap(find.byKey(const ValueKey('profileRowCopy-t1')));
    await tester.pump();
    expect(clipboardCalls.first.arguments, {'text': '123494287082', 'sensitive': true});
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('an HOTP row follows its counter and ✓ advances it', (tester) async {
    final store = await pump(tester, [_token(kind: ProfileKind.hotp, counter: 1)]);
    // Counter 1 is the same step RFC 6238 uses at 59 s.
    expect(find.text('9428 7082'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark as used'));
    await tester.pump();
    await tester.pump();
    expect((await store.loadAll()).single.counter, 2);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an unsupported stored credential reads as an invalid key instead of a code', (tester) async {
    final json = {..._token().toJson(), 'key': 'otpauth://totp/x?secret=$_secret&algorithm=MD5'};
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([Profile.fromJson(json)]);
    await pumpLocalized(
      tester,
      ProfileListScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
        now: () => _now,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Invalid stored key'), findsOneWidget);
  });

  testWidgets('a broken stored secret reads as an invalid key', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([
      Profile.fromJson({..._token().toJson(), 'key': 'GEZD!!!'}),
    ]);
    await pumpLocalized(
      tester,
      ProfileListScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
        now: () => _now,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Invalid stored key'), findsOneWidget);
  });

  testWidgets('a link with period 0 shows an invalid key instead of crashing the countdown', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([
      Profile.fromJson({..._token().toJson(), 'key': 'otpauth://totp/x?secret=$_secret&period=0'}),
    ]);
    await pumpLocalized(
      tester,
      ProfileListScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
        now: () => _now,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Invalid stored key'), findsOneWidget);
    expect(find.byKey(const ValueKey('profileCountdown-t1')), findsNothing);
  });
}
