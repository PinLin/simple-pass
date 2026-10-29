import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

// RFC 6238 appendix B SHA1 seed: 94287082 at 59 s, 8 digits.
const _link = 'otpauth://totp/Example?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8';
const _code = 'APSCG-YKKAU-NEZGC-PRDSM';

Profile _totp() =>
    Profile(id: 't1', name: 'Example', activationCode: '', kind: ProfileKind.totp, key: _link, counter: 0);

Profile _event() => Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 42);

void main() {
  late List<MethodCall> clipboardCalls;
  late DateTime now;

  setUp(() {
    clipboardCalls = [];
    now = DateTime.fromMillisecondsSinceEpoch(50 * 1000, isUtc: true);
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

  Future<ProfileStore> pump(WidgetTester tester, List<Profile> profiles, {bool tapToReveal = true}) async {
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll(profiles);
    final settings = SettingsStore(MemoryKeyValueBackend());
    await settings.save(Settings(tapToReveal: tapToReveal, clipboardClear: ClipboardClear.never));
    await pumpLocalized(
      tester,
      ProfileListScreen(profileStore: store, settingsStore: settings, screenGuard: ScreenGuard(), now: () => now),
    );
    await tester.pump();
    await tester.pump();
    return store;
  }

  Finder masked(String id) => find.byKey(ValueKey('maskedCode-$id'));

  Future<void> tapRow(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('profileRowCopy-$id')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('off by default: codes show as before', (tester) async {
    await pump(tester, [_totp(), _event()], tapToReveal: false);
    expect(masked('t1'), findsNothing);
    expect(masked('a1'), findsNothing);
    // 50 s falls in the same 30 s step as RFC 6238's 59 s vector.
    expect(find.text('9428 7082'), findsOneWidget);
  });

  testWidgets('on: every code is masked; ✓ and countdown stay', (tester) async {
    await pump(tester, [_totp(), _event()]);
    expect(masked('t1'), findsOneWidget);
    expect(masked('a1'), findsOneWidget);
    expect(find.text('9428 7082'), findsNothing);
    expect(find.byKey(const ValueKey('profileCountdown-t1')), findsOneWidget);
    expect(find.byTooltip('Mark as used'), findsOneWidget);
    expect(clipboardCalls, isEmpty);
  });

  testWidgets('a tap shows and copies; a TOTP code hides again when its period ends', (tester) async {
    await pump(tester, [_totp()]);
    await tapRow(tester, 't1');
    expect(find.text('9428 7082'), findsOneWidget);
    expect(clipboardCalls.single.arguments, {'text': '94287082', 'sensitive': true});
    // 50 s into a 30 s step: the code changes 10 s later.
    await tester.pump(const Duration(seconds: 9));
    expect(masked('t1'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(masked('t1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an event-based code hides again after 30 seconds', (tester) async {
    await pump(tester, [_event()]);
    await tapRow(tester, 'a1');
    expect(masked('a1'), findsNothing);
    expect(clipboardCalls.single.method, 'setText');
    await tester.pump(const Duration(seconds: 29));
    expect(masked('a1'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(masked('a1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a TOTP tap in the last seconds of a step stays shown through the next step', (tester) async {
    now = DateTime.fromMillisecondsSinceEpoch(58 * 1000, isUtc: true);
    await pump(tester, [_totp()]);
    await tapRow(tester, 't1');
    // The copy is the code valid at the tap.
    expect(clipboardCalls.single.arguments, {'text': '94287082', 'sensitive': true});
    await tester.pump(const Duration(seconds: 31));
    expect(masked('t1'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(masked('t1'), findsOneWidget);
  });

  testWidgets('✓ masks the next event-based code again', (tester) async {
    final store = await pump(tester, [_event()]);
    await tapRow(tester, 'a1');
    expect(masked('a1'), findsNothing);
    await tester.tap(find.byTooltip('Mark as used'));
    await tester.pump();
    await tester.pump();
    expect((await store.loadAll()).single.counter, 43);
    expect(masked('a1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 35));
  });

  testWidgets('a second tap while shown copies again without hiding', (tester) async {
    await pump(tester, [_event()]);
    await tapRow(tester, 'a1');
    await tapRow(tester, 'a1');
    expect(clipboardCalls.where((c) => c.method == 'setText'), hasLength(2));
    expect(masked('a1'), findsNothing);
    await tester.pump(const Duration(seconds: 35));
  });

  testWidgets('going to the background masks everything again', (tester) async {
    await pump(tester, [_totp(), _event()]);
    await tapRow(tester, 't1');
    await tapRow(tester, 'a1');
    expect(masked('t1'), findsNothing);
    expect(masked('a1'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    // Already on inactive, before the recents thumbnail is taken.
    expect(masked('t1'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(masked('t1'), findsOneWidget);
    expect(masked('a1'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 35));
  });

  testWidgets('a challenge response shows right after the Challenge Code is entered', (tester) async {
    await pump(tester, [
      Profile(id: 'c6', name: 'Portal', activationCode: 'HCF4B-47YNP-OVAPP-4BAE2', counter: 0, policy: '38039554'),
    ]);
    await tester.tap(find.text('Portal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('challengeConfirmButton')));
    await tester.pumpAndSettle();
    expect(masked('c6'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('challengeLabel-c6'))).data, '123456');
  });
}
