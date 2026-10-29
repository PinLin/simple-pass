import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _secret = 'JBSWY3DPEHPK3PXP';

void main() {
  late ProfileStore store;

  Finder key(String name) => find.byKey(ValueKey(name));
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
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
    await tester.enterText(key('secretField'), _secret);
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String field, String label) async {
    await tester.ensureVisible(key(field));
    await tester.tap(key(field));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('manual HOTP saves chosen digits and algorithm, starts at counter 0 and generates matching codes', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, 'otpTypeField', 'Counter-based');
    expect(key('otpPeriodField'), findsNothing);
    await choose(tester, 'otpDigitsField', '8 digits');
    await choose(tester, 'otpAlgorithmField', 'SHA-512');
    expect(key('counterField'), findsNothing);
    await save(tester);
    final saved = (await store.loadAll()).single;
    expect(saved.kind, ProfileKind.hotp);
    expect(saved.counter, 0);
    expect(saved.codeDigits, 8);
    expect(saved.oathCredential!.algorithm, OtpAlgorithm.sha512);
    expect(
      otpForProfile(saved),
      generateStandardHotp(saved.oathCredential!.secret, 0, digits: 8, algorithm: OtpAlgorithm.sha512),
    );
  });

  testWidgets('manual TOTP validates period and saves chosen parameters', (tester) async {
    await open(tester);
    await choose(tester, 'otpDigitsField', '8 digits');
    await choose(tester, 'otpAlgorithmField', 'SHA-256');
    await tester.ensureVisible(key('otpPeriodField'));
    await tester.enterText(key('otpPeriodField'), '0');
    await save(tester);
    expect(await store.loadAll(), isEmpty);
    await tester.ensureVisible(key('otpPeriodField'));
    await tester.enterText(key('otpPeriodField'), '60');
    await save(tester);
    final saved = (await store.loadAll()).single;
    expect(saved.kind, ProfileKind.totp);
    expect(saved.timeStep, 60);
    expect(saved.codeDigits, 8);
    expect(saved.oathCredential!.algorithm, OtpAlgorithm.sha256);
    final now = DateTime.utc(2026, 10, 15);
    expect(
      otpForProfile(saved, now: now),
      generateStandardTotp(
        saved.oathCredential!.secret,
        now.millisecondsSinceEpoch ~/ 1000,
        period: 60,
        digits: 8,
        algorithm: OtpAlgorithm.sha256,
      ),
    );
  });

  testWidgets('pasted URI overrides manual options, clearing it restores the manual configuration', (tester) async {
    await open(tester);
    await choose(tester, 'otpTypeField', 'Counter-based');
    await choose(tester, 'otpDigitsField', '8 digits');
    await tester.ensureVisible(key('secretField'));
    await tester.enterText(key('secretField'), 'otpauth://totp/Imported?secret=$_secret&algorithm=SHA256&period=45');
    await tester.pumpAndSettle();
    expect(find.text('Time-based · SHA-256 · 45 s · 6 digits'), findsNothing);
    expect(find.text('Time-based'), findsOneWidget);
    expect(find.text('SHA-256'), findsOneWidget);
    expect(find.text('6 digits'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(key('counterField'), findsNothing);
    await tester.enterText(key('secretField'), _secret);
    await tester.pumpAndSettle();
    expect(key('otpTypeField'), findsOneWidget);
    expect(key('counterField'), findsNothing);
    expect(find.text('8 digits'), findsOneWidget);
    await save(tester);
    expect((await store.loadAll()).single.kind, ProfileKind.hotp);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the scan action sits inside the credential field', (tester) async {
    await open(tester);
    expect(find.descendant(of: key('secretField'), matching: key('scanQrButton')), findsOneWidget);
    expect(find.descendant(of: key('secretField'), matching: find.byType(IconButton)), findsOneWidget);
    final field = tester.widget<TextField>(find.descendant(of: key('secretField'), matching: find.byType(TextField)));
    expect(field.obscureText, isFalse);
    expect(key('toggleSecretVisibility'), findsNothing);
    expect(key('otpImportMenuButton'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
