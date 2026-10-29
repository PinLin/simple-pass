// Golden tests for the main screens; regenerate with `flutter test --update-goldens test/visual_test.dart`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/l10n/app_locale.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/mobilepass_registration.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/device_info.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/screens/enrollment_screen.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/screens/settings_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import 'fakes/fake_dskpp_server.dart';
import 'fakes/fake_keystore.dart';
import 'fakes/fake_qr.dart';
import 'fakes/memory_key_value_backend.dart';
import 'test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';
final _seed = Uint8List.fromList([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99]);

Future<void> _pumpAt(WidgetTester tester, Widget widget, {Locale? locale, bool settle = true}) async {
  // Pin to a Pixel 6 logical size (411x914) so goldens are stable across
  // hosts and a typical mid-range phone fits the layout naturally.
  await tester.binding.setSurfaceSize(const Size(411, 914));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: appSupportedLocales,
      theme: testTheme,
      home: widget,
    ),
  );
  // Time-based rows tick every second, so they never settle.
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

void main() {
  const zhHantTw = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');

  Future<void> golden(String name) => expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  ProfileListScreen list(ProfileStore store, [MemoryKeyValueBackend? backend]) => ProfileListScreen(
    profileStore: store,
    settingsStore: SettingsStore(backend ?? MemoryKeyValueBackend()),
    screenGuard: ScreenGuard(),
  );

  /// Three profiles; with [sealed], all of them sealed and locked, as under the app lock.
  Future<ProfileStore> threeProfiles({FakeKeystore? keystore, bool sealed = false}) async {
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: keystore ?? FakeKeystore());
    await store.saveAll([
      Profile(id: 'a1', name: 'Work VPN', activationCode: _code, counter: 42),
      Profile(id: 'b2', name: 'Personal', activationCode: _code, counter: 7),
      Profile(id: 'c3', name: 'Bank', activationCode: _code, counter: 1, pin: '1234'),
    ]);
    if (sealed) await store.setAllProtected(true);
    await store.forget();
    return store;
  }

  /// Lets the lock screen's own prompt run: it starts after a platform-channel call, which completes
  /// outside the fake clock.
  Future<void> settleLockScreen(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  /// Settings with the app lock on.
  Future<MemoryKeyValueBackend> lockedSettings() async {
    final backend = MemoryKeyValueBackend();
    await SettingsStore(backend).save(const Settings(requireAuth: true));
    return backend;
  }

  for (final (name, locale) in [('01_profile_list_empty', null), ('07_profile_list_empty_zh_hant_tw', zhHantTw)]) {
    testWidgets(name, (tester) async {
      await _pumpAt(tester, list(ProfileStore(MemoryKeyValueBackend())), locale: locale);
      await golden(name);
    });
  }

  for (final (name, locale) in [
    ('02_profile_list_with_profiles', null),
    ('08_profile_list_with_profiles_zh_hant_tw', zhHantTw),
  ]) {
    testWidgets('$name (three codes)', (tester) async {
      await _pumpAt(tester, list(await threeProfiles()), locale: locale);
      await golden(name);
    });
  }

  for (final (name, locale) in [('31_selection', null), ('32_selection_zh_hant_tw', zhHantTw)]) {
    testWidgets('$name (two selected)', (tester) async {
      await _pumpAt(tester, list(await threeProfiles()), locale: locale);
      await tester.longPress(find.text('Personal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank'));
      await tester.pumpAndSettle();
      await golden(name);
    });
  }

  for (final (name, locale) in [('04_edit', null), ('10_edit_zh_hant_tw', zhHantTw)]) {
    testWidgets(name, (tester) async {
      final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
      final profile = Profile(
        id: 'c3',
        name: 'Bank',
        activationCode: _code,
        counter: 5,
        pin: '1234',
        appendPinOnCopy: true,
        protected: true,
      );
      await store.saveAll([profile]);
      await _pumpAt(
        tester,
        ProfileEditScreen(profileStore: store, settingsStore: SettingsStore(MemoryKeyValueBackend()), profile: profile),
        locale: locale,
      );
      await golden(name);
    });
  }

  for (final (name, locale) in [('11_add', null), ('12_add_zh_hant_tw', zhHantTw)]) {
    testWidgets(name, (tester) async {
      await _pumpAt(
        tester,
        ProfileEditScreen(
          profileStore: ProfileStore(MemoryKeyValueBackend()),
          settingsStore: SettingsStore(MemoryKeyValueBackend()),
          generateSeed: () => _seed,
        ),
        locale: locale,
      );
      await golden(name);
    });
  }

  Future<void> pumpSettings(WidgetTester tester, {Locale? locale}) async {
    await _pumpAt(
      tester,
      SettingsScreen(
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
        profileStore: ProfileStore(MemoryKeyValueBackend()),
      ),
      locale: locale,
    );
  }

  testWidgets('05 settings screen', (tester) async {
    await pumpSettings(tester);
    await golden('05_settings');
  });

  testWidgets('06 settings (zh_Hant_TW)', (tester) async {
    await pumpSettings(tester, locale: zhHantTw);
    await golden('06_settings_zh_hant_tw');
  });

  for (final (name, locale) in [('17_time_based_en', null), ('18_time_based_zh_hant_tw', zhHantTw)]) {
    testWidgets('$name (8-digit event, time-based, locked 8-digit, challenge waiting and answered)', (tester) async {
      final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
      await store.saveAll([
        Profile(id: 'e8', name: 'Intranet', activationCode: 'AAISK-EM2EJ-KVTHT-PCEZN', counter: 3, policy: '18921500'),
        Profile(id: 't6', name: 'Cloud', activationCode: 'AERUK-Z4JVP-G66AJ-DBACL', counter: 0, policy: '75817049'),
        Profile(id: 't8', name: 'Bank', activationCode: 'AERUK-Z4JVP-G66AJ-DBACL', counter: 0, policy: '75890738'),
        Profile(id: 'c6', name: 'Portal', activationCode: 'HCF4B-47YNP-OVAPP-4BAE2', counter: 0, policy: '38039554'),
        Profile(id: 'c7', name: 'SSO', activationCode: 'HCF4B-47YNP-OVAPP-4BAE2', counter: 0, policy: '38039554'),
      ]);
      final screen = ProfileListScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        screenGuard: ScreenGuard(),
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000010 * 1000),
      );
      await _pumpAt(tester, screen, locale: locale, settle: false);
      await tester.pump();
      await tester.tap(find.text('SSO'));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('challengeConfirmButton')));
      await tester.pump(const Duration(seconds: 1));
      await golden(name);
    });
  }

  testWidgets('20 challenge code dialog (zh_Hant_TW)', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend());
    await store.saveAll([
      Profile(id: 'c6', name: 'Portal', activationCode: 'HCF4B-47YNP-OVAPP-4BAE2', counter: 0, policy: '38039554'),
    ]);
    await _pumpAt(tester, list(store), locale: zhHantTw);
    await tester.tap(find.text('Portal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();
    await golden('20_challenge_dialog_zh_hant_tw');
  });

  testWidgets('15 keys invalidated (zh_Hant_TW)', (tester) async {
    final keystore = FakeKeystore();
    final store = await threeProfiles(keystore: keystore, sealed: true);
    keystore
      ..expire()
      ..invalidate();
    // The lock screen prompts by itself; opening the sealed secrets then finds the key gone.
    await _pumpAt(tester, list(store, await lockedSettings()), locale: zhHantTw);
    await settleLockScreen(tester);
    await golden('15_keys_invalidated_zh_hant_tw');
  });

  for (final (name, locale) in [('33_app_locked', null), ('34_app_locked_zh_hant_tw', zhHantTw)]) {
    testWidgets('$name (prompt canceled)', (tester) async {
      final keystore = FakeKeystore();
      final store = await threeProfiles(keystore: keystore, sealed: true);
      keystore
        ..expire()
        ..authenticateCalls = 0
        ..authResults.add(AuthResult.canceled);
      await _pumpAt(tester, list(store, await lockedSettings()), locale: locale);
      await settleLockScreen(tester);
      expect(keystore.authenticateCalls, 1);
      // Let the "canceled" snackbar go.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await golden(name);
    });
  }

  for (final (name, locale) in [('21_add_kind_sheet', null), ('22_add_kind_sheet_zh_hant_tw', zhHantTw)]) {
    testWidgets(name, (tester) async {
      await _pumpAt(tester, list(ProfileStore(MemoryKeyValueBackend())), locale: locale);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await golden(name);
    });
  }

  // An Enrollment String without a passphrase, so the extra field shows.
  final enrollmentString = base64.encode(utf8.encode('EnrollmentURL=https://otp.example.com/dskpp\r\nUserID=alice'));

  for (final (name, locale, nameText) in [
    ('23_enrollment', null, 'Work VPN'),
    ('24_enrollment_zh_hant_tw', zhHantTw, 'Work VPN'),
  ]) {
    testWidgets(name, (tester) async {
      await _pumpAt(tester, EnrollmentScreen(profileStore: ProfileStore(MemoryKeyValueBackend())), locale: locale);
      await tester.enterText(find.byKey(const ValueKey('enrollmentStringField')), enrollmentString);
      await tester.enterText(find.byKey(const ValueKey('enrollNameField')), nameText);
      await tester.pumpAndSettle();
      await golden(name);
    });
  }

  testWidgets('25 OTP PIN prompt during registration (zh_Hant_TW)', (tester) async {
    final server = FakeDskppServer(userId: 'alice', passphrase: 'pass-1');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DeviceInfo.channelName),
      (call) async => '16',
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DeviceInfo.channelName),
        null,
      ),
    );
    await _pumpAt(
      tester,
      EnrollmentScreen(profileStore: ProfileStore(MemoryKeyValueBackend()), transport: server),
      locale: zhHantTw,
    );
    await tester.enterText(
      find.byKey(const ValueKey('enrollmentStringField')),
      base64.encode(utf8.encode('EnrollmentURL=https://otp.example.com/dskpp\r\nUserID=alice\r\nPassphrase=pass-1')),
    );
    await tester.enterText(find.byKey(const ValueKey('enrollNameField')), 'Work VPN');
    await tester.tap(find.byKey(const ValueKey('enrollSubmitButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('otpPinField')), '2468');
    await tester.pumpAndSettle();
    await golden('25_otp_pin_dialog_zh_hant_tw');
  });

  testWidgets('26 edit a registered profile (zh_Hant_TW)', (tester) async {
    final profile = Profile(
      id: 'k1',
      name: 'Work VPN',
      activationCode: '',
      kind: ProfileKind.mobilePassKey,
      key: 'yqZjy2vEoVSmj/THIULg3ysjfM0L6Bo6QzLlgvA3oQU=',
      serial: '123456789',
      policy: '9346',
      pin: '2468',
      counter: 3,
      appendPinOnCopy: true,
    );
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([profile]);
    await _pumpAt(
      tester,
      ProfileEditScreen(profileStore: store, settingsStore: SettingsStore(MemoryKeyValueBackend()), profile: profile),
      locale: zhHantTw,
    );
    await golden('26_edit_registered_zh_hant_tw');
  });

  for (final (name, locale) in [('27_add_totp', null), ('28_add_totp_zh_hant_tw', zhHantTw)]) {
    testWidgets(name, (tester) async {
      await _pumpAt(
        tester,
        ProfileEditScreen(
          profileStore: ProfileStore(MemoryKeyValueBackend()),
          settingsStore: SettingsStore(MemoryKeyValueBackend()),
          kind: ProfileKind.totp,
          cameraPermission: FakeCameraPermission(),
          qrReader: FakeQrReader(),
        ),
        locale: locale,
      );
      await golden(name);
    });
  }

  testWidgets('29 list with TOTP and HOTP profiles (zh_Hant_TW)', (tester) async {
    // RFC 6238 appendix B SHA1 seed.
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([
      Profile(id: 'a1', name: 'Work VPN', activationCode: _code, counter: 42),
      Profile(
        id: 't1',
        name: 'GitHub: alice@example.com',
        activationCode: '',
        kind: ProfileKind.totp,
        key: 'otpauth://totp/GitHub:alice@example.com?secret=$secret&issuer=GitHub',
        counter: 0,
      ),
      Profile(
        id: 't2',
        name: 'Cloud',
        activationCode: '',
        kind: ProfileKind.totp,
        key: 'otpauth://totp/Example%20Cloud:ops?secret=$secret&algorithm=SHA256&digits=8&period=60',
        counter: 0,
      ),
      Profile(
        id: 'h1',
        name: 'Legacy',
        activationCode: '',
        kind: ProfileKind.hotp,
        key: 'otpauth://hotp/bob?secret=$secret&counter=0',
        counter: 7,
      ),
    ]);
    final screen = ProfileListScreen(
      profileStore: store,
      settingsStore: SettingsStore(MemoryKeyValueBackend()),
      screenGuard: ScreenGuard(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000010 * 1000),
    );
    await _pumpAt(tester, screen, locale: zhHantTw, settle: false);
    await tester.pump();
    await golden('29_profile_list_totp_zh_hant_tw');
  });

  testWidgets('30 Tap to reveal: every code masked (zh_Hant_TW)', (tester) async {
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([
      Profile(id: 'a1', name: 'Work VPN', activationCode: _code, counter: 42),
      Profile(
        id: 't1',
        name: 'GitHub: alice@example.com',
        activationCode: '',
        kind: ProfileKind.totp,
        key: 'otpauth://totp/GitHub:alice@example.com?secret=$secret&issuer=GitHub',
        counter: 0,
      ),
      Profile(id: 'c6', name: 'Portal', activationCode: 'HCF4B-47YNP-OVAPP-4BAE2', counter: 0, policy: '38039554'),
    ]);
    final settings = SettingsStore(MemoryKeyValueBackend());
    await settings.save(const Settings(tapToReveal: true));
    final screen = ProfileListScreen(
      profileStore: store,
      settingsStore: settings,
      screenGuard: ScreenGuard(),
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000010 * 1000),
    );
    await _pumpAt(tester, screen, locale: zhHantTw, settle: false);
    await tester.pump();
    await golden('30_tap_to_reveal_zh_hant_tw');
  });
  for (final (name, mode) in [
    ('35_standard_hotp_manual_zh_hant_tw', 'manual'),
    ('36_standard_imported_zh_hant_tw', 'imported'),
    ('37_manual_registration_info_zh_hant_tw', 'registration'),
    ('38_auto_registration_info_zh_hant_tw', 'auto'),
    ('39_profile_menu_zh_hant_tw', 'menu'),
    ('40_mobilepass_totp_details_zh_hant_tw', 'time'),
    ('45_add_totp_mobilepass_format_zh_hant_tw', 'mobilePassFormat'),
  ]) {
    testWidgets(name, (tester) async {
      final store = ProfileStore(MemoryKeyValueBackend());
      final Profile? profile = switch (mode) {
        'manual' || 'imported' || 'mobilePassFormat' => null,
        'auto' => Profile(
          id: 'auto',
          name: 'Work VPN',
          activationCode: '',
          kind: ProfileKind.mobilePassKey,
          key: 'dGVzdA==',
          policy: '9346',
          serial: '123456789',
          counter: 0,
          registration: const MobilePassRegistration(
            enrollmentString: 'RW5yb2xsbWVudFVSTD1odHRwczovL2V4YW1wbGUudGVzdA==',
            url: 'https://otp.example.com/enroll',
            userId: 'alice',
            passphrase: 'passphrase',
          ),
        ),
        'time' => Profile(
          id: 'time',
          name: 'Work VPN',
          activationCode: 'VTH7N-PZJYN-M3TMH-QBACP',
          policy: '75817049',
          counter: 0,
        ),
        _ => Profile(id: 'manual', name: 'Work VPN', activationCode: _code, counter: 42, pin: '1234'),
      };
      if (profile != null) await store.saveAll([profile]);
      await _pumpAt(
        tester,
        ProfileEditScreen(
          profileStore: store,
          settingsStore: SettingsStore(MemoryKeyValueBackend()),
          profile: profile,
          kind: ProfileKind.totp,
        ),
        locale: zhHantTw,
      );
      if (mode == 'manual') {
        await tester.enterText(find.byKey(const ValueKey('nameField')), 'Work VPN');
        await tester.enterText(find.byKey(const ValueKey('secretField')), 'JBSWY3DPEHPK3PXP');
        await tester.tap(find.byKey(const ValueKey('otpTypeField')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('依計數器產生').last);
      } else if (mode == 'mobilePassFormat') {
        await tester.enterText(find.byKey(const ValueKey('nameField')), 'Work VPN');
        await tester.enterText(find.byKey(const ValueKey('secretField')), 'JBSWY3DPEHPK3PXP');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mobilePassFormatSwitch')));
      } else if (mode == 'imported') {
        await tester.enterText(
          find.byKey(const ValueKey('secretField')),
          'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&period=60&digits=8',
        );
      } else if (mode == 'registration' || mode == 'auto') {
        await openRegistrationInfo(tester);
      } else if (mode == 'menu') {
        await tester.tap(find.byKey(const ValueKey('profileMenuButton')));
      }
      await tester.pumpAndSettle();
      await golden(name);
    });
  }
  testWidgets('43_standard_totp_edit_zh_hant_tw', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend());
    final profile = Profile(
      id: 'totp',
      name: 'Example',
      activationCode: '',
      kind: ProfileKind.totp,
      key: 'JBSWY3DPEHPK3PXP',
      pin: '1234',
      counter: 0,
    );
    await store.saveAll([profile]);
    await _pumpAt(
      tester,
      ProfileEditScreen(profileStore: store, settingsStore: SettingsStore(MemoryKeyValueBackend()), profile: profile),
      locale: zhHantTw,
    );
    await golden('43_standard_totp_edit_zh_hant_tw');
  });
  testWidgets('41 save changes dialog on a compact phone', (tester) async {
    await _pumpAt(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => askAboutUnsavedChanges(context), child: const Text('open')),
        ),
      ),
      locale: zhHantTw,
    );
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await golden('41_save_changes_dialog_zh_hant_tw');
  });
  testWidgets('42 OTP QR source chooser', (tester) async {
    await _pumpAt(
      tester,
      ProfileEditScreen(
        profileStore: ProfileStore(MemoryKeyValueBackend()),
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        kind: ProfileKind.totp,
      ),
      locale: zhHantTw,
    );
    await tester.tap(find.byKey(const ValueKey('scanQrButton')));
    await tester.pumpAndSettle();
    await golden('42_otp_qr_source_zh_hant_tw');
  });
}
