import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/otpauth/otpauth_uri.dart';
import 'package:simple_pass/otpauth/standard_otp.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';
const _versioned = 'AERUK-Z4JVP-G66AJ-DBACL';
const _key = 'yqZjy2vEoVSmj/THIULg3ysjfM0L6Bo6QzLlgvA3oQU=';
const _secret = 'JBSWY3DPEHPK3PXP';
const _totpLink = 'otpauth://totp/Example:alice?secret=$_secret&algorithm=SHA256&digits=8&period=60';
const _hotpLink = 'otpauth://hotp/Example:alice?secret=$_secret&counter=3';

void main() {
  final parameters = find.byKey(const ValueKey('parametersLine'));

  Future<void> open(WidgetTester tester, {Profile? profile, ProfileKind kind = ProfileKind.activationCode}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    if (profile != null) await store.saveAll([profile]);
    await pumpLocalized(
      tester,
      ProfileEditScreen(
        profileStore: store,
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
        profile: profile,
        kind: kind,
      ),
    );
    await tester.pumpAndSettle();
  }

  String? shown(WidgetTester tester) => parameters.evaluate().isEmpty ? null : tester.widget<Text>(parameters).data;

  void expectSavedParameters(WidgetTester tester, Map<String, String> values) {
    expect(parameters, findsNothing);
    expect(find.byKey(const ValueKey('otpTypeField')), findsNothing);
    for (final entry in values.entries) {
      final field = tester.widget<TextField>(
        find.descendant(of: find.byKey(ValueKey(entry.key)), matching: find.byType(TextField)),
      );
      expect(field.controller!.text, entry.value);
      expect(field.readOnly, isTrue);
      expect(field.canRequestFocus, isFalse);
      expect(field.showCursor, isFalse);
    }
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  InputDecoration decorationOf(WidgetTester tester, String key) => tester
      .widget<TextField>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)))
      .decoration!;

  group('parameters line, adding a Standard OTP', () {
    testWidgets('is never shown, whatever is typed in the Secret key field', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      for (final text in ['', _secret, _totpLink, _hotpLink, 'not base32!']) {
        await enter(tester, 'secretField', text);
        expect(shown(tester), isNull, reason: text);
      }
    });
  });

  group('otpauth link in the Secret key field, adding a Standard OTP', () {
    const link = 'otpauth://hotp/X?secret=$_secret&algorithm=SHA256&digits=8&counter=5';

    T valueOf<T>(WidgetTester tester, String key) =>
        tester.widget<DropdownButtonFormField<T>>(find.byKey(ValueKey(key))).initialValue as T;

    bool locked(WidgetTester tester, String key) => find
        .ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(IgnorePointer))
        .evaluate()
        .any((e) => (e.widget as IgnorePointer).ignoring);

    TextField textField(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)));

    testWidgets('shows the link parameters in the usual fields, all read-only', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      await enter(tester, 'secretField', link);

      expect(find.text('Parameters from the otpauth link'), findsNothing);
      expect(parameters, findsNothing);
      expect(valueOf<OtpauthType>(tester, 'otpTypeField'), OtpauthType.hotp);
      expect(valueOf<OtpAlgorithm>(tester, 'otpAlgorithmField'), OtpAlgorithm.sha256);
      expect(valueOf<int>(tester, 'otpDigitsField'), 8);
      expect(find.byKey(const ValueKey('otpPeriodField')), findsNothing);
      expect(find.byKey(const ValueKey('counterField')), findsNothing);
      for (final key in ['otpTypeField', 'otpAlgorithmField', 'otpDigitsField']) {
        expect(locked(tester, key), isTrue, reason: key);
      }
    });

    testWidgets('a time-based link shows its period, read-only; missing parameters use the defaults', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      await enter(tester, 'secretField', 'otpauth://totp/X?secret=$_secret&period=45');

      expect(valueOf<OtpauthType>(tester, 'otpTypeField'), OtpauthType.totp);
      expect(valueOf<OtpAlgorithm>(tester, 'otpAlgorithmField'), OtpAlgorithm.sha1);
      expect(valueOf<int>(tester, 'otpDigitsField'), 6);
      expect(textField(tester, 'otpPeriodField').controller!.text, '45');
      expect(textField(tester, 'otpPeriodField').readOnly, isTrue);
    });

    testWidgets('back to a Base32 key the fields are editable again, with the manual values', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      await enter(tester, 'secretField', link);
      await enter(tester, 'secretField', _secret);

      expect(valueOf<OtpauthType>(tester, 'otpTypeField'), OtpauthType.totp);
      expect(valueOf<OtpAlgorithm>(tester, 'otpAlgorithmField'), OtpAlgorithm.sha1);
      expect(valueOf<int>(tester, 'otpDigitsField'), 6);
      expect(textField(tester, 'otpPeriodField').controller!.text, '30');
      expect(textField(tester, 'otpPeriodField').readOnly, isFalse);
      for (final key in ['otpTypeField', 'otpAlgorithmField', 'otpDigitsField']) {
        expect(locked(tester, key), isFalse, reason: key);
      }
    });
  });

  group('adding a MobilePASS profile', () {
    for (final policy in ['', '18921500', '75817049', '38039554', '9439']) {
      testWidgets('Policy String "$policy" shows no parameters line and no counter field', (tester) async {
        await open(tester);
        await enter(tester, 'policyField', policy);
        expect(parameters, findsNothing);
        expect(find.byKey(const ValueKey('counterField')), findsNothing);
      });
    }
  });

  group('title, editing', () {
    final profiles = <(String, Profile, String)>[
      ('an Activation Code profile', Profile(id: 'a1', name: 'W', activationCode: _code, counter: 1), 'HOTP'),
      (
        'a registered MobilePASS profile',
        Profile(
          id: 'k1',
          name: 'W',
          activationCode: '',
          kind: ProfileKind.mobilePassKey,
          key: _key,
          serial: '123456789',
          policy: '9346',
          counter: 1,
        ),
        'HOTP',
      ),
      (
        'a TOTP profile',
        Profile(id: 't1', name: 'W', activationCode: '', kind: ProfileKind.totp, key: _secret, counter: 0),
        'TOTP',
      ),
      (
        'an HOTP profile',
        Profile(id: 'h1', name: 'W', activationCode: '', kind: ProfileKind.hotp, key: _hotpLink, counter: 3),
        'HOTP',
      ),
    ];

    for (final (what, profile, title) in profiles) {
      testWidgets('$what is titled "$title"', (tester) async {
        await open(tester, profile: profile);
        expect(find.descendant(of: find.byType(AppBar), matching: find.text('$title profile')), findsOneWidget);
        for (final old in ['MobilePASS profile', 'TOTP', 'HOTP']) {
          expect(find.text(old), findsNothing);
        }
      });
    }

    testWidgets('adding is titled by the way of adding', (tester) async {
      await open(tester);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('MobilePASS – Manual enrollment')),
        findsOneWidget,
      );
    });

    testWidgets('adding a standard token is titled "Add manually"', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Add manually')), findsOneWidget);
    });
  });

  group('saved parameter fields', () {
    testWidgets('an Activation Code profile shows its own Policy String parameters', (tester) async {
      await open(
        tester,
        profile: Profile(id: 'a1', name: 'W', activationCode: _versioned, counter: 1, policy: '75817049'),
      );
      expectSavedParameters(tester, {
        'otpDigitsField': '6 digits',
        'otpAlgorithmField': 'SHA-256',
        'otpPeriodField': '60',
      });
    });

    testWidgets('a registered MobilePASS profile shows the server policy parameters', (tester) async {
      await open(
        tester,
        profile: Profile(
          id: 'k1',
          name: 'W',
          activationCode: '',
          kind: ProfileKind.mobilePassKey,
          key: _key,
          serial: '1',
          policy: '9439',
          counter: 0,
        ),
      );
      expectSavedParameters(tester, {
        'otpDigitsField': '8 digits',
        'otpAlgorithmField': 'SHA-256',
        'otpChallengeLengthField': '8',
      });
      expect(find.byKey(const ValueKey('otpPeriodField')), findsNothing);
    });

    testWidgets('standard tokens show the parameters of the stored credential', (tester) async {
      await open(
        tester,
        profile: Profile(id: 't1', name: 'W', activationCode: '', kind: ProfileKind.totp, key: _totpLink, counter: 0),
      );
      expectSavedParameters(tester, {
        'otpDigitsField': '8 digits',
        'otpAlgorithmField': 'SHA-256',
        'otpPeriodField': '60',
      });
    });

    testWidgets('HOTP parameters are fixed while the counter remains editable', (tester) async {
      await open(
        tester,
        profile: Profile(
          id: 'h1',
          name: 'Work',
          activationCode: '',
          kind: ProfileKind.hotp,
          key: _hotpLink,
          counter: 3,
        ),
      );
      expectSavedParameters(tester, {'otpDigitsField': '6 digits', 'otpAlgorithmField': 'SHA-1'});
      expect(find.byKey(const ValueKey('otpPeriodField')), findsNothing);
      final counter = tester.widget<TextField>(
        find.descendant(of: find.byKey(const ValueKey('counterField')), matching: find.byType(TextField)),
      );
      expect(counter.readOnly, isFalse);
    });

    testWidgets('a stored credential that no longer parses shows no line', (tester) async {
      await open(
        tester,
        profile: Profile(id: 't1', name: 'W', activationCode: '', kind: ProfileKind.totp, key: 'garbage!', counter: 0),
      );
      expect(shown(tester), isNull);
    });
  });

  group('read-only fields: same look, secondary text, no cursor or focus', () {
    TextField field(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)));

    void expectFixed(WidgetTester tester, String key) {
      final decoration = decorationOf(tester, key);
      final scheme = Theme.of(tester.element(find.byType(ProfileEditScreen))).colorScheme;
      expect(decoration.filled, isNot(true), reason: key);
      expect(decoration.border, isNull, reason: '$key keeps the normal underline');
      final text = field(tester, key);
      expect(text.readOnly, isTrue, reason: key);
      expect(text.showCursor, isFalse, reason: key);
      expect(text.canRequestFocus, isFalse, reason: key);
      expect(text.style?.color, readOnlyValueColor(scheme), reason: key);
    }

    void expectEditable(WidgetTester tester, String key) {
      final decoration = decorationOf(tester, key);
      expect(decoration.filled, isNot(true), reason: key);
      final text = field(tester, key);
      expect(text.readOnly, isFalse, reason: key);
      expect(text.style?.color, isNull, reason: key);
    }

    testWidgets('Activation Code and Policy String of a saved profile', (tester) async {
      await open(
        tester,
        profile: Profile(id: 'a1', name: 'W', activationCode: _versioned, counter: 1, policy: '75817049'),
      );
      await openRegistrationInfo(tester);
      expectFixed(tester, 'activationCodeField');
      expectFixed(tester, 'policyField');
      for (final key in ['nameField', 'pinField']) {
        expectEditable(tester, key);
      }
    });

    testWidgets('Policy String and serial number of a registered profile, and the counter stays editable', (
      tester,
    ) async {
      await open(
        tester,
        profile: Profile(
          id: 'k1',
          name: 'W',
          activationCode: '',
          kind: ProfileKind.mobilePassKey,
          key: _key,
          serial: '123456789',
          policy: '9346',
          counter: 2,
        ),
      );
      await openRegistrationInfo(tester);
      expectFixed(tester, 'policyField');
      expectFixed(tester, 'serialField');
      for (final key in ['nameField', 'counterField', 'pinField']) {
        expectEditable(tester, key);
      }
    });

    testWidgets('the Secret key of a saved standard token', (tester) async {
      await open(
        tester,
        profile: Profile(id: 't1', name: 'W', activationCode: '', kind: ProfileKind.totp, key: _secret, counter: 0),
      );
      expectFixed(tester, 'secretField');
      expectEditable(tester, 'nameField');
    });

    testWidgets('nothing is filled while adding', (tester) async {
      await open(tester);
      for (final key in ['nameField', 'policyField', 'activationCodeField', 'pinField']) {
        expectEditable(tester, key);
      }
      await open(tester, kind: ProfileKind.totp);
      expectEditable(tester, 'secretField');
    });
  });

  testWidgets('read-only text stays readable: secondary color at 4.5:1 or more against the page', (tester) async {
    await open(
      tester,
      profile: Profile(id: 'a1', name: 'W', activationCode: _versioned, counter: 1, policy: '75817049'),
    );
    final scheme = Theme.of(tester.element(find.byType(ProfileEditScreen))).colorScheme;
    final light = Color.alphaBlend(readOnlyValueColor(scheme), scheme.surface).computeLuminance();
    final dark = scheme.surface.computeLuminance();
    final (hi, lo) = light > dark ? (light, dark) : (dark, light);
    expect((hi + 0.05) / (lo + 0.05), greaterThanOrEqualTo(4.5));
  });

  group('show/hide for secrets', () {
    bool obscured(WidgetTester tester, String key) => tester
        .widget<TextField>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)))
        .obscureText;

    testWidgets('a saved profile starts hidden; the eye shows and hides each field on its own', (tester) async {
      await open(
        tester,
        profile: Profile(id: 'a1', name: 'W', activationCode: _versioned, counter: 1, pin: '1234', policy: '75817049'),
      );
      await openRegistrationInfo(tester);
      expect(obscured(tester, 'activationCodeField'), isTrue);
      expect(obscured(tester, 'pinField'), isTrue);
      expect(obscured(tester, 'policyField'), isFalse);
      expect(obscured(tester, 'nameField'), isFalse);
      expect(find.byKey(const ValueKey('toggleActivationCodeVisibility')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggleActivationCodeVisibility')));
      await tester.pump();
      expect(obscured(tester, 'activationCodeField'), isFalse);
      expect(obscured(tester, 'pinField'), isTrue);
      expect(find.byTooltip('Hide'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggleActivationCodeVisibility')));
      await tester.pump();
      expect(obscured(tester, 'activationCodeField'), isTrue);

      // The eye comes before the copy button.
      expect(
        tester.getCenter(find.byKey(const ValueKey('toggleActivationCodeVisibility'))).dx,
        lessThan(tester.getCenter(find.byKey(const ValueKey('copyActivationCodeButton'))).dx),
      );
    });

    testWidgets('a saved standard token hides its credential and the eye sits before copy', (tester) async {
      await open(
        tester,
        profile: Profile(id: 't1', name: 'W', activationCode: '', kind: ProfileKind.totp, key: _totpLink, counter: 0),
      );
      expect(obscured(tester, 'secretField'), isTrue);
      expect(
        tester.getCenter(find.byKey(const ValueKey('toggleSecretVisibility'))).dx,
        lessThan(tester.getCenter(find.byKey(const ValueKey('copySecretButton'))).dx),
      );
      await tester.tap(find.byKey(const ValueKey('toggleSecretVisibility')));
      await tester.pump();
      expect(obscured(tester, 'secretField'), isFalse);
    });

    testWidgets('while adding, secrets are shown to check them, and can be hidden', (tester) async {
      await open(tester);
      expect(obscured(tester, 'activationCodeField'), isFalse);
      expect(obscured(tester, 'pinField'), isFalse);
      await tester.tap(find.byKey(const ValueKey('togglePinVisibility')));
      await tester.pump();
      expect(obscured(tester, 'pinField'), isTrue);
    });

    testWidgets('adding a standard token shows the Secret key field', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      expect(obscured(tester, 'secretField'), isFalse);
      expect(find.byKey(const ValueKey('toggleSecretVisibility')), findsNothing);
      expect(find.byKey(const ValueKey('copySecretButton')), findsNothing);
      expect(find.byKey(const ValueKey('scanQrButton')), findsOneWidget);
    });
  });

  testWidgets('an Activation Code profile being edited shows its parameters in the saved fields', (tester) async {
    await open(
      tester,
      profile: Profile(id: 'a1', name: 'W', activationCode: _versioned, counter: 1, policy: '75817049'),
    );
    expect(find.byKey(const ValueKey('policyField')), findsNothing);
    expectSavedParameters(tester, {
      'otpDigitsField': '6 digits',
      'otpAlgorithmField': 'SHA-256',
      'otpPeriodField': '60',
    });
  });
}
