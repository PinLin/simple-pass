import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';
const _otherCode = 'WMPX4-TD2BV-QZM7C-QX4J4';

void main() {
  late MemoryKeyValueBackend backend;
  late FakeKeystore keystore;
  late ProfileStore store;
  late SettingsStore settings;

  setUp(() {
    backend = MemoryKeyValueBackend();
    keystore = FakeKeystore();
    store = ProfileStore(backend, keystore: keystore);
    settings = SettingsStore(backend);
  });

  final banner = find.byKey(const ValueKey('protectionBanner'));
  final bannerButton = find.byKey(const ValueKey('protectionBannerButton'));
  String raw() => backend.rawValue(ProfileStore.storageKey)!;
  int sealedCount() => RegExp('"sealed"').allMatches(raw()).length;

  Future<void> seed({required bool? requireAuth, int sealed = 0}) async {
    await store.saveAll([
      Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5, pin: '1234'),
      Profile(id: 'b2', name: 'Home', activationCode: _otherCode, counter: 7),
    ]);
    if (sealed > 0) {
      await store.update((all) => [for (final (i, p) in all.indexed) i < sealed ? p.copyWith(protected: true) : p]);
    }
    if (requireAuth != null) await settings.save(Settings(requireAuth: requireAuth));
    await store.forget();
    keystore
      ..expire()
      ..authenticateCalls = 0;
  }

  Future<void> pump(WidgetTester tester) async {
    // The app lock prompts only once the list's load, including its screen guard call, has finished.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), null));
    await pumpLocalized(
      tester,
      ProfileListScreen(profileStore: store, settingsStore: settings, screenGuard: ScreenGuard()),
    );
    await tester.pumpAndSettle();
  }

  group('protection banner', () {
    testWidgets('on with profiles in the clear: the unlock seals them in that one prompt, with no banner', (
      tester,
    ) async {
      await seed(requireAuth: true, sealed: 1);
      await pump(tester);
      expect(keystore.authenticateCalls, 1);
      expect(sealedCount(), 2);
      expect(raw(), allOf(isNot(contains(_code)), isNot(contains(_otherCode)), isNot(contains('1234'))));
      expect(find.text('Work'), findsOneWidget);
      expect(banner, findsNothing);
      expect(await settings.load().then((s) => s.requireAuth), isTrue);
    });

    testWidgets('a canceled unlock seals nothing and keeps the lock screen up', (tester) async {
      await seed(requireAuth: true, sealed: 1);
      final before = raw();
      keystore.authResults.add(AuthResult.canceled);
      await pump(tester);
      expect(raw(), before);
      expect(find.text('Work'), findsNothing);
      expect(find.byKey(const ValueKey('unlockAppButton')), findsOneWidget);
      expect(find.text('Authentication canceled'), findsOneWidget);
    });

    testWidgets('off with sealed profiles: locked first, then "Remove protection" unseals them all', (tester) async {
      await seed(requireAuth: false, sealed: 1);
      keystore.authResults.add(AuthResult.canceled);
      await pump(tester);
      expect(find.text('Work'), findsNothing);
      expect(banner, findsNothing, reason: 'the lock screen shows nothing about the profiles');

      await tester.tap(find.byKey(const ValueKey('unlockAppButton')));
      await tester.pumpAndSettle();
      expect(keystore.authenticateCalls, 2);
      expect(sealedCount(), 1, reason: 'opening alone changes nothing');
      expect(find.text('Authentication is off, but some profiles are still protected.'), findsOneWidget);
      expect(find.text('Authentication is on, but some profiles aren\'t protected yet.'), findsNothing);

      await tester.tap(bannerButton);
      await tester.pumpAndSettle();
      expect(keystore.authenticateCalls, 3);
      expect(sealedCount(), 0);
      expect(raw(), allOf(contains(_code), contains(_otherCode)));
      expect(banner, findsNothing);
    });

    testWidgets('a canceled "Remove protection" leaves the profiles and the banner', (tester) async {
      await seed(requireAuth: false, sealed: 1);
      await pump(tester);
      expect(banner, findsOneWidget);
      final before = raw();
      keystore.authResults.add(AuthResult.canceled);
      await tester.tap(bannerButton);
      await tester.pumpAndSettle();
      expect(raw(), before);
      expect(banner, findsOneWidget);
      expect(find.text('Authentication canceled'), findsOneWidget);
    });

    for (final (name, requireAuth, sealed) in [
      ('on and all sealed', true, 2),
      ('off and nothing sealed', false, 0),
      ('undecided and nothing sealed', null, 0),
      ('undecided with sealed profiles (migration still to run)', null, 1),
    ]) {
      testWidgets('no banner when $name', (tester) async {
        await seed(requireAuth: requireAuth, sealed: sealed);
        await pump(tester);
        expect(banner, findsNothing);
      });
    }

    testWidgets('hidden while selecting', (tester) async {
      await seed(requireAuth: false, sealed: 1);
      await pump(tester);
      expect(banner, findsOneWidget);
      await tester.longPress(find.text('Home'));
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
    });
  });

  testWidgets('a damaged sealed secret leaves only that profile without a code, showing the invalid-key text', (
    tester,
  ) async {
    await seed(requireAuth: true, sealed: 2);
    final blob = jsonDecode(raw()) as Map<String, dynamic>;
    final entries = (blob['profiles'] as List).cast<Map<String, dynamic>>();
    final sealed = entries.first['sealed'] as String;
    entries.first['sealed'] = '${sealed.substring(0, sealed.lastIndexOf(':'))}:!!!not base64';
    backend.seedRaw(ProfileStore.storageKey, jsonEncode(blob));
    await pump(tester);

    expect(keystore.authenticateCalls, 1);
    expect(find.text('Could not save changes'), findsNothing);
    expect(find.byKey(const ValueKey('profileLocked-a1')), findsNothing, reason: 'rows have no lock of their own');
    expect(find.text(formatOtpForDisplay(generateMobilePassOtp(_otherCode, 7))), findsOneWidget, reason: 'sound one');
    expect(find.text(formatOtpForDisplay(generateMobilePassOtp(_code, 5))), findsNothing);
    expect(find.byKey(const ValueKey('lockedCodePlaceholder')), findsNothing);
    expect(find.text('Invalid Activation Code'), findsOneWidget);

    // Nothing happens on tapping it and its › does not open the editor.
    await tester.tap(find.byKey(const ValueKey('profileRowCopy-a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profileEdit-a1')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(keystore.authenticateCalls, 1);
  });
}
