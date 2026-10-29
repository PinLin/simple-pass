import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/android_licenses.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/device_info.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/screens/settings_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

void main() {
  late List<MethodCall> guardCalls;
  late MemoryKeyValueBackend backend;
  late FakeKeystore keystore;
  late ProfileStore profileStore;

  setUp(() {
    guardCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(ScreenGuard.channelName),
      (call) async {
        guardCalls.add(call);
        return null;
      },
    );
    backend = MemoryKeyValueBackend();
    keystore = FakeKeystore();
    profileStore = ProfileStore(backend, keystore: keystore);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(ScreenGuard.channelName),
      null,
    );
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await pumpLocalized(
      tester,
      SettingsScreen(settingsStore: SettingsStore(backend), screenGuard: ScreenGuard(), profileStore: profileStore),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('defaults: clipboard, authentication, tap-to-reveal and screenshot options; only screenshots on', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.byType(SwitchListTile), findsNWidgets(3));
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('requireAuthSwitch'))).value, isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('tapToRevealSwitch'))).value, isFalse);
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Block screenshots')).value, isFalse);
  });

  testWidgets('turning off allowScreenshots sets FLAG_SECURE and persists', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Block screenshots'));
    await tester.pumpAndSettle();
    expect(guardCalls.single.method, 'setSecure');
    expect((await SettingsStore(backend).load()).allowScreenshots, isFalse);
  });

  testWidgets('turning on Tap to reveal persists it', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Tap to reveal passcodes'));
    await tester.pumpAndSettle();
    expect((await SettingsStore(backend).load()).tapToReveal, isTrue);
    expect(guardCalls, isEmpty);
  });

  group('clipboard clearing', () {
    testWidgets('defaults to 1 minute and offers the five options', (tester) async {
      await pumpSettings(tester);
      expect(
        find.descendant(of: find.byKey(const ValueKey('clipboardClearTile')), matching: find.text('1 minute')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('clipboardClearTile')));
      await tester.pumpAndSettle();
      for (final o in ['Never', '30 seconds', '1 minute', '2 minutes', '5 minutes']) {
        expect(find.text(o), findsWidgets);
      }
    });

    testWidgets('picking an option persists it and updates the subtitle', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byKey(const ValueKey('clipboardClearTile')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Never'));
      await tester.pumpAndSettle();
      expect((await SettingsStore(backend).load()).clipboardClear, ClipboardClear.never);
      expect(
        find.descendant(of: find.byKey(const ValueKey('clipboardClearTile')), matching: find.text('Never')),
        findsOneWidget,
      );
    });
  });

  testWidgets('order: app lock, block screenshots, tap to reveal, clipboard clearing; all off by default', (
    tester,
  ) async {
    await pumpSettings(tester);
    final titles = [
      for (final key in ['requireAuthSwitch', 'blockScreenshotsSwitch', 'tapToRevealSwitch', 'clipboardClearTile'])
        tester.getTopLeft(find.byKey(ValueKey(key))).dy,
    ];
    expect([...titles]..sort(), titles);
    for (final key in ['requireAuthSwitch', 'blockScreenshotsSwitch', 'tapToRevealSwitch']) {
      expect(tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value, isFalse, reason: key);
    }
  });

  testWidgets('a stored "screenshots not allowed" from before shows as Block screenshots on', (tester) async {
    backend.seedRaw(SettingsStore.storageKey, '{"allowScreenshots":false,"clipboardClearSeconds":60}');
    await pumpSettings(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('blockScreenshotsSwitch'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('blockScreenshotsSwitch')));
    await tester.pumpAndSettle();
    expect((await SettingsStore(backend).load()).allowScreenshots, isTrue);
    expect(guardCalls.last.arguments, {'secure': false});
  });

  group('require authentication', () {
    const code = 'APSCG-YKKAU-NEZGC-PRDSM';
    const otherCode = 'WMPX4-TD2BV-QZM7C-QX4J4';
    final switchFinder = find.byKey(const ValueKey('requireAuthSwitch'));

    Future<void> seed() => profileStore.saveAll([
      Profile(id: 'a1', name: 'Work', activationCode: code, counter: 5, pin: '1234'),
      Profile(id: 'b2', name: 'Home', activationCode: otherCode, counter: 7),
    ]);

    // Both profiles sealed and the setting on, as after turning it on; the window has run out.
    Future<void> seedSealed() async {
      await seed();
      await profileStore.setAllProtected(true);
      await SettingsStore(backend).save(const Settings(requireAuth: true));
      profileStore.forget();
      keystore
        ..expire()
        ..authenticateCalls = 0;
    }

    String raw() => backend.rawValue(ProfileStore.storageKey)!;
    int sealedCount() => RegExp('"sealed"').allMatches(raw()).length;
    bool switchValue(WidgetTester tester) => tester.widget<SwitchListTile>(switchFinder).value;
    Future<bool?> storedSetting() async => (await SettingsStore(backend).load()).requireAuth;

    Future<void> tapSwitch(WidgetTester tester) async {
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
    }

    Future<void> tapInDialog(WidgetTester tester, String label) async {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(label)));
      await tester.pumpAndSettle();
    }

    testWidgets('has the title and subtitle, and reflects the stored value', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: true));
      await pumpSettings(tester);
      expect(find.text('Require authentication to open the app'), findsOneWidget);
      expect(find.text('Unlock with fingerprint, face, or screen lock'), findsOneWidget);
      expect(switchValue(tester), isTrue);
    });

    testWidgets('turning on warns first, then seals every profile after one authentication and saves true', (
      tester,
    ) async {
      await seed();
      await pumpSettings(tester);
      await tapSwitch(tester);
      expect(
        find.textContaining('protected profiles can no longer be unlocked; they can only be deleted'),
        findsOneWidget,
      );
      expect(keystore.authenticateCalls, 0, reason: 'nothing prompts before the warning is confirmed');

      await tapInDialog(tester, 'Turn on');

      expect(keystore.authenticateCalls, 1);
      expect(sealedCount(), 2);
      expect(raw(), allOf(isNot(contains(code)), isNot(contains(otherCode)), isNot(contains('1234'))));
      expect(await storedSetting(), isTrue);
      expect(switchValue(tester), isTrue);
      expect((await profileStore.loadAll()).map((p) => (p.protected, p.locked)), [(true, false), (true, false)]);
    });

    testWidgets('turning on also seals a profile that is already sealed, still with one authentication', (
      tester,
    ) async {
      await seed();
      await profileStore.updateProfile('a1', (p) => p.copyWith(protected: true));
      profileStore.forget();
      keystore
        ..expire()
        ..authenticateCalls = 0;
      await pumpSettings(tester);
      await tapSwitch(tester);
      await tapInDialog(tester, 'Turn on');
      expect(keystore.authenticateCalls, 1);
      expect(sealedCount(), 2);
      expect(await storedSetting(), isTrue);
    });

    testWidgets('Cancel in the warning changes nothing and never prompts', (tester) async {
      await seed();
      await pumpSettings(tester);
      final before = raw();
      final writes = backend.writeCount;
      await tapSwitch(tester);
      await tapInDialog(tester, 'Cancel');

      expect(keystore.authenticateCalls, 0);
      expect((raw(), backend.writeCount), (before, writes));
      expect(await storedSetting(), isNull);
      expect(switchValue(tester), isFalse);
    });

    testWidgets('a failed authentication says so and leaves profiles and setting alone', (tester) async {
      await seed();
      await pumpSettings(tester);
      final before = raw();
      final writes = backend.writeCount;
      keystore.authResults.add(AuthResult.canceled);
      await tapSwitch(tester);
      await tapInDialog(tester, 'Turn on');

      expect(find.text('Authentication canceled'), findsOneWidget);
      // The setting was saved first and put back, so only the profiles' blob is untouched.
      expect(raw(), before);
      expect(backend.writeCount, writes + 2);
      expect(await storedSetting(), isNull);
      expect(switchValue(tester), isFalse);
      expect(tester.widget<SwitchListTile>(switchFinder).onChanged, isNotNull, reason: 'usable again');
    });

    testWidgets('a failed settings save changes nothing: no prompt, nothing sealed', (tester) async {
      await seed();
      await pumpSettings(tester);
      final before = raw();
      backend.failWritesFor.add(SettingsStore.storageKey);
      await tapSwitch(tester);
      await tapInDialog(tester, 'Turn on');
      expect(find.text('Could not save changes'), findsOneWidget);
      expect(keystore.authenticateCalls, 0);
      expect(raw(), before);
      expect(await storedSetting(), isNull);
      expect(switchValue(tester), isFalse);
    });

    testWidgets('a failed seal puts the setting back, so profiles and setting still agree', (tester) async {
      await seed();
      await pumpSettings(tester);
      final before = raw();
      backend.failWritesFor.add(ProfileStore.storageKey);
      await tapSwitch(tester);
      await tapInDialog(tester, 'Turn on');
      expect(find.text('Could not save changes'), findsOneWidget);
      expect(raw(), before);
      expect(await storedSetting(), isNull);
      expect(switchValue(tester), isFalse);
    });

    testWidgets('a failed unseal puts the setting back on', (tester) async {
      await seedSealed();
      await pumpSettings(tester);
      final before = raw();
      backend.failWritesFor.add(ProfileStore.storageKey);
      await tapSwitch(tester);
      expect(find.text('Could not save changes'), findsOneWidget);
      expect(raw(), before);
      expect(sealedCount(), 2);
      expect(await storedSetting(), isTrue);
      expect(switchValue(tester), isTrue);
    });

    testWidgets('turning off needs no warning, authenticates once, unseals everything and saves false', (tester) async {
      await seedSealed();
      await pumpSettings(tester);
      expect(switchValue(tester), isTrue);
      await tapSwitch(tester);

      expect(find.text('Turn on'), findsNothing);
      expect(keystore.authenticateCalls, 1);
      expect(sealedCount(), 0);
      expect(raw(), allOf(contains(code), contains(otherCode), contains('1234')));
      expect(await storedSetting(), isFalse);
      expect(switchValue(tester), isFalse);
      expect((await profileStore.loadAll()).map((p) => p.protected), [false, false]);
    });

    testWidgets('a canceled prompt while turning off keeps everything sealed and the setting on', (tester) async {
      await seedSealed();
      await pumpSettings(tester);
      final before = raw();
      keystore.authResults.add(AuthResult.canceled);
      await tapSwitch(tester);

      expect(find.text('Authentication canceled'), findsOneWidget);
      expect(raw(), before);
      expect(sealedCount(), 2);
      expect(await storedSetting(), isTrue);
      expect(switchValue(tester), isTrue);
    });

    testWidgets('a dead key while turning off explains; Cancel keeps the profiles, deleting removes them', (
      tester,
    ) async {
      await seedSealed();
      keystore.invalidate();
      await pumpSettings(tester);
      await tapSwitch(tester);
      expect(find.textContaining('screen lock was removed'), findsOneWidget);
      await tapInDialog(tester, 'Cancel');
      expect(sealedCount(), 2);
      expect(await storedSetting(), isTrue);

      await tapSwitch(tester);
      await tapInDialog(tester, 'Delete these profiles');
      expect(await profileStore.loadAll(), isEmpty);
      expect(await storedSetting(), isTrue, reason: 'the setting itself is not changed by the deletion');
    });

    testWidgets('a dead key while turning on explains and offers deleting too', (tester) async {
      await seed();
      await profileStore.updateProfile('a1', (p) => p.copyWith(protected: true));
      profileStore.forget();
      keystore
        ..expire()
        ..invalidate();
      await pumpSettings(tester);
      await tapSwitch(tester);
      await tapInDialog(tester, 'Turn on');
      expect(find.textContaining('screen lock was removed'), findsOneWidget);
      expect(await storedSetting(), isNull);
      expect(switchValue(tester), isFalse);
    });

    testWidgets('an unreadable profile store reports the failed save and keeps the setting', (tester) async {
      await pumpSettings(tester);
      backend.seedRaw(ProfileStore.storageKey, '{not json');
      await tapSwitch(tester);
      await tapInDialog(tester, 'Turn on');
      expect(find.text('Could not save changes'), findsOneWidget);
      expect(await storedSetting(), isNull);
      expect(backend.rawValue(ProfileStore.storageKey), '{not json');
    });
  });

  group('FLAG_SECURE and the app lock', () {
    const lockNote =
        "With the app lock on, Android 12 and older always block screenshots, so the recent apps screen can't show your profiles.";
    // Tapping "Block screenshots" flips the stored allowScreenshots, as the old switch did.
    final allowScreenshots = find.widgetWithText(SwitchListTile, 'Block screenshots');
    final requireAuthSwitch = find.byKey(const ValueKey('requireAuthSwitch'));

    /// [sdkInt] null leaves the device channel unanswered, like a platform without the call.
    Future<void> pumpWithSdk(WidgetTester tester, int? sdkInt, {VoidCallback? onLockEnabled}) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(DeviceInfo.channelName),
        (call) async => call.method == 'sdkInt' ? sdkInt : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(DeviceInfo.channelName), null));
      await pumpLocalized(
        tester,
        SettingsScreen(
          settingsStore: SettingsStore(backend),
          screenGuard: ScreenGuard(),
          profileStore: profileStore,
          onLockEnabled: onLockEnabled,
        ),
      );
      await tester.pumpAndSettle();
    }

    List<Object?> secureArgs() =>
        guardCalls.where((c) => c.method == 'setSecure').map((c) => c.arguments['secure']).toList();

    Future<void> turnLockOn(WidgetTester tester) async {
      await tester.tap(requireAuthSwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Turn on')));
      await tester.pumpAndSettle();
    }

    for (final (sdk, expectSecure) in [(32, true), (33, false), (null, true)]) {
      testWidgets('turning the app lock on with sdk $sdk sets FLAG_SECURE to $expectSecure, off clears it', (
        tester,
      ) async {
        await pumpWithSdk(tester, sdk);
        await turnLockOn(tester);
        expect((await SettingsStore(backend).load()).requireAuth, isTrue);
        expect(secureArgs(), [expectSecure]);

        await tester.tap(requireAuthSwitch);
        await tester.pumpAndSettle();
        expect((await SettingsStore(backend).load()).requireAuth, isFalse);
        expect(secureArgs(), [expectSecure, false]);
      });
    }

    for (final (sdk, expectSecure) in [(32, true), (33, false)]) {
      testWidgets(
        'lock off but a profile still sealed, sdk $sdk: allowing screenshots keeps FLAG_SECURE at $expectSecure',
        (tester) async {
          await profileStore.saveAll([
            Profile(id: 'a1', name: 'Work', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 1),
          ]);
          await profileStore.setAllProtected(true);
          await SettingsStore(backend).save(const Settings(requireAuth: false, allowScreenshots: false));
          await pumpWithSdk(tester, sdk);
          await tester.tap(allowScreenshots);
          await tester.pumpAndSettle();
          expect(secureArgs(), [expectSecure]);
        },
      );
    }

    for (final (sdk, expectSecure) in [(32, true), (33, false)]) {
      testWidgets('with the lock on and sdk $sdk, allowing screenshots keeps FLAG_SECURE at $expectSecure', (
        tester,
      ) async {
        await SettingsStore(backend).save(const Settings(requireAuth: true, allowScreenshots: false));
        await pumpWithSdk(tester, sdk);
        await tester.tap(allowScreenshots);
        await tester.pumpAndSettle();
        expect((await SettingsStore(backend).load()).allowScreenshots, isTrue);
        expect(secureArgs(), [expectSecure]);

        await tester.tap(allowScreenshots);
        await tester.pumpAndSettle();
        expect(secureArgs(), [expectSecure, true]);
      });
    }

    testWidgets('with the lock off, the screenshot switch alone decides FLAG_SECURE, whatever the sdk', (tester) async {
      await pumpWithSdk(tester, 32);
      await tester.tap(allowScreenshots);
      await tester.pumpAndSettle();
      await tester.tap(allowScreenshots);
      await tester.pumpAndSettle();
      expect(secureArgs(), [true, false]);
    });

    testWidgets('the screenshot note shows with the lock on and sdk 32', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: true));
      await pumpWithSdk(tester, 32);
      expect(find.textContaining(lockNote), findsOneWidget);
    });

    testWidgets('the screenshot note shows while the sdk is unknown', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: true));
      await pumpWithSdk(tester, null);
      expect(find.textContaining(lockNote), findsOneWidget);
    });

    testWidgets('the screenshot note is absent with sdk 33 even with the lock on', (tester) async {
      await SettingsStore(backend).save(const Settings(requireAuth: true));
      await pumpWithSdk(tester, 33);
      expect(find.textContaining(lockNote), findsNothing);
    });

    testWidgets('the screenshot note is absent with the lock off', (tester) async {
      await pumpWithSdk(tester, 32);
      expect(find.textContaining(lockNote), findsNothing);
    });

    testWidgets('the screenshot note appears once the lock is turned on, sdk 32', (tester) async {
      await pumpWithSdk(tester, 32);
      expect(find.textContaining(lockNote), findsNothing);
      await turnLockOn(tester);
      expect(find.textContaining(lockNote), findsOneWidget);
    });

    testWidgets('onLockEnabled fires after turning the lock on, not for turning it off', (tester) async {
      var enabled = 0;
      await pumpWithSdk(tester, 33, onLockEnabled: () => enabled++);
      await turnLockOn(tester);
      expect(enabled, 1);
      await tester.tap(requireAuthSwitch);
      await tester.pumpAndSettle();
      expect(enabled, 1);
    });

    testWidgets('onLockEnabled does not fire when the authentication is canceled', (tester) async {
      var enabled = 0;
      keystore.authResults.add(AuthResult.canceled);
      await pumpWithSdk(tester, 33, onLockEnabled: () => enabled++);
      await turnLockOn(tester);
      expect(enabled, 0);
      expect((await SettingsStore(backend).load()).requireAuth, isNull);
      expect(secureArgs(), isEmpty);
    });
  });

  testWidgets('open-source licenses tile opens the license page', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(const ValueKey('licensesTile')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('SimplePASS'), findsWidgets);
  });

  test('registered Android licenses name the Gradle dependencies', () async {
    registerAndroidLicenses();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    expect(packages, containsAll(androidApache2Packages));
    expect(androidApache2Packages, containsAll(['androidx.appcompat', 'androidx.biometric', 'FreeDroidWarn']));
  });
}
