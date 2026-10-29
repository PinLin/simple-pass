import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/otpauth/base32.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _secret = 'JBSWY3DPEHPK3PXP';
const _timeCode = 'VTH7N-PZJYN-M3TMH-QBACP';
const _knownCode = 'XLOH5-NFAMR-3Z5TW-6EL5Y';
const _knownSecret = '6AUQT6RLB5EWBTRGXFRZOAQDSOP5WVZ75V6XMXZUS7MQTTWEUUZA';

DateTime _at(int unixSeconds) => DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

void main() {
  late ProfileStore store;

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder switchTile() => key('mobilePassFormatSwitch');
  String algorithmShown(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(of: key('otpAlgorithmField'), matching: find.byType(Text)))
      .map((t) => t.data)
      .firstWhere((d) => d != null && d.startsWith('SHA-'))!;
  bool algorithmLocked(WidgetTester tester) => tester
      .widgetList<IgnorePointer>(find.ancestor(of: key('otpAlgorithmField'), matching: find.byType(IgnorePointer)))
      .any((w) => w.ignoring);

  Future<void> openAdd(WidgetTester tester, {String secret = _secret}) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = ProfileStore(MemoryKeyValueBackend());
    await pumpLocalized(
      tester,
      ProfileEditScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        kind: ProfileKind.totp,
      ),
    );
    await tester.enterText(key('nameField'), 'Work');
    await tester.enterText(key('secretField'), secret);
    await tester.pumpAndSettle();
  }

  Future<void> openEdit(WidgetTester tester, Profile profile) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([profile]);
    await pumpLocalized(
      tester,
      ProfileEditScreen(profileStore: store, settingsStore: SettingsStore(MemoryKeyValueBackend()), profile: profile),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String field, String label) async {
    await tester.ensureVisible(key(field));
    await tester.tap(key(field));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.ensureVisible(switchTile());
    await tester.tap(switchTile());
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<Set<String>> menuItems(WidgetTester tester) async {
    await tester.tap(key('profileMenuButton'));
    await tester.pumpAndSettle();
    final keys = {
      for (final item in tester.widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>)))
        (item.key! as ValueKey<String>).value,
    };
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    return keys;
  }

  group('the switch on the manual add page', () {
    testWidgets('only shows for a typed secret making a time-based token', (tester) async {
      await openAdd(tester);
      expect(switchTile(), findsOneWidget);
      expect(find.text('Use MobilePASS format'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(switchTile()).value, isFalse);

      await choose(tester, 'otpTypeField', 'Counter-based');
      expect(switchTile(), findsNothing);
      await choose(tester, 'otpTypeField', 'Time-based');
      expect(switchTile(), findsOneWidget);

      await tester.enterText(key('secretField'), 'otpauth://totp/X?secret=$_secret');
      await tester.pumpAndSettle();
      expect(switchTile(), findsNothing);
    });

    testWidgets('fixes the algorithm at SHA-256 and gives the chosen one back when switched off', (tester) async {
      await openAdd(tester);
      await choose(tester, 'otpAlgorithmField', 'SHA-512');
      expect(algorithmLocked(tester), isFalse);

      await toggle(tester);
      expect(algorithmShown(tester), 'SHA-256');
      expect(algorithmLocked(tester), isTrue);
      // Digits and period stay editable.
      expect(
        tester.widget<TextField>(find.descendant(of: key('otpPeriodField'), matching: find.byType(TextField))).readOnly,
        isFalse,
      );
      await choose(tester, 'otpDigitsField', '8 digits');
      expect(find.text('8 digits'), findsOneWidget);

      await toggle(tester);
      expect(algorithmShown(tester), 'SHA-512');
      expect(algorithmLocked(tester), isFalse);
    });

    testWidgets('a counter-based token saved after the switch was on is a plain HOTP', (tester) async {
      await openAdd(tester);
      await toggle(tester);
      await choose(tester, 'otpTypeField', 'Counter-based');
      await save(tester);
      final saved = (await store.loadAll()).single;
      expect((saved.kind, saved.mobilePassTime), (ProfileKind.hotp, false));
      expect(saved.oathCredential!.algorithm, OtpAlgorithm.sha1);
    });

    testWidgets('switching it on counts as an unsaved change', (tester) async {
      await openAdd(tester, secret: '');
      await tester.enterText(key('nameField'), '');
      await tester.pumpAndSettle();
      await toggle(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(key('discardChangesButton'), findsOneWidget);
    });
  });

  testWidgets('a MobilePASS time-based key entered with the switch on gives the same codes', (tester) async {
    final original = Profile(id: 'm', name: 'Work', activationCode: _timeCode, policy: '75817049', counter: 0);
    final secret = base32Encode(mobilePassKeyOf(original)!);
    await openAdd(tester, secret: secret);
    await toggle(tester);
    await tester.ensureVisible(key('otpPeriodField'));
    await tester.enterText(key('otpPeriodField'), '60');
    await save(tester);

    final saved = (await store.loadAll()).single;
    expect((saved.kind, saved.mobilePassTime, saved.timeStep, saved.codeDigits), (ProfileKind.totp, true, 60, 6));
    expect(saved.oathCredential!.algorithm, OtpAlgorithm.sha256);
    expect(base32Encode(saved.oathCredential!.secret), secret);
    for (final t in [946684800, 1000000000, 1700000000, 1791875555, 2000000000]) {
      expect(
        otpForProfile(saved, now: _at(t)),
        otpForProfile(original, now: _at(t)),
        reason: 'at $t',
      );
    }
  });

  group('editing', () {
    Profile flagged() => Profile(
      id: 't',
      name: 'Cloud',
      activationCode: '',
      counter: 0,
      kind: ProfileKind.totp,
      key: 'otpauth://totp/Cloud?secret=$_secret&algorithm=SHA256&digits=6&period=60',
      mobilePassTime: true,
    );

    testWidgets('a MobilePASS-format TOTP says so, keeps its secret on the page and offers no link', (tester) async {
      await openEdit(tester, flagged());
      expect(find.text('TOTP profile'), findsOneWidget);
      expect(tester.widget<Text>(key('sourceLine')).data, 'MobilePASS format');
      expect(key('otpFormatField'), findsNothing);
      expect(tester.getTopLeft(key('sourceLine')).dy, lessThan(tester.getTopLeft(key('nameField')).dy));
      expect(await menuItems(tester), isNot(contains('registrationInfoMenuItem')));
      expect(await menuItems(tester), isNot(contains('copyOtpauthLinkButton')));
    });

    testWidgets('a plain TOTP has no format line', (tester) async {
      await openEdit(
        tester,
        Profile(id: 't', name: 'T', activationCode: '', counter: 0, kind: ProfileKind.totp, key: _secret),
      );
      expect(key('sourceLine'), findsNothing);
    });

    for (final (name, profile) in [
      ('manual event-based', Profile(id: 'm', name: 'M', activationCode: _knownCode, counter: 0)),
      ('manual time-based', Profile(id: 'm', name: 'M', activationCode: _timeCode, policy: '75817049', counter: 0)),
      ('challenge-response', Profile(id: 'm', name: 'M', activationCode: _timeCode, policy: '38039554', counter: 0)),
    ]) {
      testWidgets('MobilePASS $name: the secret key sits above the digits', (tester) async {
        await openEdit(tester, profile);
        expect(key('mobilePassSecretField'), findsOneWidget);
        expect(
          tester.getTopLeft(key('mobilePassSecretField')).dy,
          lessThan(tester.getTopLeft(key('otpDigitsField')).dy),
        );
        if (profile.policy.isEmpty) {
          final field = tester.widget<TextField>(
            find.descendant(of: key('mobilePassSecretField'), matching: find.byType(TextField)),
          );
          expect(field.controller!.text, _knownSecret);
          expect(field.obscureText, isTrue);
        }
      });
    }

    testWidgets('parameters that don\'t parse still leave the secret key on the page', (tester) async {
      await openEdit(
        tester,
        Profile(
          id: 'r',
          name: 'Auto',
          activationCode: '',
          kind: ProfileKind.mobilePassKey,
          key: 'yqZjy2vEoVSmj/THIULg3ysjfM0L6Bo6QzLlgvA3oQU=',
          policy: 'abc',
          counter: 0,
        ),
      );
      expect(key('mobilePassSecretField'), findsOneWidget);
      expect(key('otpDigitsField'), findsNothing);
    });

    testWidgets('a standard credential that doesn\'t parse still shows as the secret key', (tester) async {
      await openEdit(
        tester,
        Profile(id: 's', name: 'S', activationCode: '', counter: 0, kind: ProfileKind.totp, key: 'not base32!'),
      );
      expect(key('secretField'), findsOneWidget);
      expect(key('otpDigitsField'), findsNothing);
    });

    testWidgets('a MobilePASS profile with no usable key shows no secret key', (tester) async {
      await openEdit(
        tester,
        Profile(
          id: 'r',
          name: 'Auto',
          activationCode: '',
          kind: ProfileKind.mobilePassKey,
          key: '***',
          policy: '9346',
          counter: 0,
        ),
      );
      expect(key('mobilePassSecretField'), findsNothing);
      expect(key('otpDigitsField'), findsOneWidget);
    });
  });
}
