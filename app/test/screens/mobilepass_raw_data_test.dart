import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/otpauth/base32.dart';
import 'package:simple_pass/otpauth/otpauth_uri.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _knownCode = 'XLOH5-NFAMR-3Z5TW-6EL5Y';
const _knownSecret = '6AUQT6RLB5EWBTRGXFRZOAQDSOP5WVZ75V6XMXZUS7MQTTWEUUZA';
const _timeCode = 'VTH7N-PZJYN-M3TMH-QBACP';
const _registeredKey = 'yqZjy2vEoVSmj/THIULg3ysjfM0L6Bo6QzLlgvA3oQU=';
const _totpLink = 'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP';
const _hotpLink = 'otpauth://hotp/Example:bob?secret=JBSWY3DPEHPK3PXP&counter=3';

Profile _manual({String code = _knownCode, String policy = '', int counter = 5}) =>
    Profile(id: 'm', name: 'Work', activationCode: code, policy: policy, counter: counter, pin: '1234');

Profile _registered() => Profile(
  id: 'r',
  name: 'Auto',
  activationCode: '',
  kind: ProfileKind.mobilePassKey,
  key: _registeredKey,
  serial: '123456789',
  policy: '9346',
  counter: 4,
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

  Future<void> open(WidgetTester tester, Profile profile) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([profile]);
    await pumpLocalized(
      tester,
      ProfileEditScreen(profileStore: store, settingsStore: SettingsStore(MemoryKeyValueBackend()), profile: profile),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder inner(String name) => find.descendant(of: key(name), matching: find.byType(TextField));
  TextField fieldOf(WidgetTester tester, String name) => tester.widget<TextField>(inner(name));
  String textOf(WidgetTester tester, String name) => fieldOf(tester, name).controller!.text;
  Finder appBarTitle(String title) => find.descendant(of: find.byType(AppBar), matching: find.text(title));

  // Neither a link field nor any note about one, whatever the kind.
  void expectNoLinkOnPage() {
    expect(key('equivalentLinkField'), findsNothing);
    expect(key('noEquivalentLinkNote'), findsNothing);
    for (final word in ['otpauth', 'HOTP app', 'export']) {
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(word)), findsNothing);
    }
  }

  // Keys of the ⋮ menu's entries; the menu is closed again afterwards.
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

  Map<Object?, Object?> lastCopy() => clipboardCalls.last.arguments as Map<Object?, Object?>;

  String copiedLink() => lastCopy()['text']! as String;

  group('manual event-based', () {
    testWidgets('titled HOTP with the format line, no top button, and the info sheet in the menu', (tester) async {
      await open(tester, _manual());
      expect(appBarTitle('HOTP profile'), findsOneWidget);
      expect(tester.widget<Text>(key('sourceLine')).data, 'MobilePASS format');
      expect(key('registrationInfoButton'), findsNothing);
      expect(key('otpFormatField'), findsNothing);
      expect(await menuItems(tester), containsAll(['registrationInfoMenuItem', 'deleteProfileButton']));
      await openRegistrationInfo(tester);
      expect(
        find.descendant(of: key('registrationInfoSheet'), matching: find.text('MobilePASS – Manual enrollment')),
        findsOneWidget,
      );
      expect(find.text('MobilePASS registration info'), findsNothing);
    });

    testWidgets('a profile without saved enrollment inputs shows only its fields in the sheet', (tester) async {
      await open(tester, _manual());
      await openRegistrationInfo(tester);
      expect(key('policyField'), findsOneWidget);
      expect(find.textContaining('before enrollment inputs'), findsNothing);
    });

    testWidgets('the Secret key is read-only, hidden at first, Base32, and the eye shows and hides it', (tester) async {
      await open(tester, _manual());
      expect(key('mobilePassSecretField'), findsOneWidget);
      expect(fieldOf(tester, 'mobilePassSecretField').readOnly, isTrue);
      expect(fieldOf(tester, 'mobilePassSecretField').obscureText, isTrue);
      expect(textOf(tester, 'mobilePassSecretField'), _knownSecret);

      await tester.tap(key('toggleMobilePassSecretVisibility'));
      await tester.pump();
      expect(fieldOf(tester, 'mobilePassSecretField').obscureText, isFalse);
      await tester.tap(key('toggleMobilePassSecretVisibility'));
      await tester.pump();
      expect(fieldOf(tester, 'mobilePassSecretField').obscureText, isTrue);
    });

    testWidgets('copying the Secret key uses the sensitive clipboard', (tester) async {
      await open(tester, _manual());
      await tester.tap(key('copyMobilePassSecretButton'));
      await tester.pump();
      expect(clipboardCalls.single.method, 'setText');
      expect(clipboardCalls.single.arguments, {'text': _knownSecret, 'sensitive': true});
      expect(find.text('Secret key copied'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 61));
    });

    testWidgets('the menu copies the link as sensitive and confirms with a snackbar', (tester) async {
      await open(tester, _manual());
      await copyExportLink(tester);
      final expected = 'otpauth://hotp/Work?secret=$_knownSecret&algorithm=SHA256&digits=6&counter=5';
      expect(clipboardCalls.single.method, 'setText');
      expect(clipboardCalls.single.arguments, {'text': expected, 'sensitive': true});
      expect(find.text('Link copied'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await settleCopy(tester);
    });

    testWidgets('the link follows the Counter and Name fields as they are typed', (tester) async {
      await open(tester, _manual());
      await tester.enterText(key('counterField'), '42');
      await tester.pump();
      await copyExportLink(tester);
      expect(parseOtpauthUri(copiedLink()).counter, 42);

      await tester.enterText(key('nameField'), 'Bank: main');
      await tester.pump();
      await copyExportLink(tester);
      final link = copiedLink();
      expect(link, startsWith('otpauth://hotp/${Uri.encodeComponent('Bank: main')}?'));
      final parsed = parseOtpauthUri(link);
      expect(parsed.issuer, 'Bank');
      expect(parsed.account, 'main');
      expect(parsed.counter, 42);
      expect(base32Encode(parsed.secret), _knownSecret);
      await settleCopy(tester);
    });

    testWidgets('an empty or invalid counter keeps the last stored one in the link', (tester) async {
      await open(tester, _manual());
      await tester.enterText(key('counterField'), '');
      await tester.pump();
      await copyExportLink(tester);
      expect(parseOtpauthUri(copiedLink()).counter, 5);
      await settleCopy(tester);
    });

    testWidgets('an empty Policy String shows "Not set" and no copy button', (tester) async {
      await open(tester, _manual());
      await openRegistrationInfo(tester);
      expect(fieldOf(tester, 'policyField').readOnly, isTrue);
      expect(textOf(tester, 'policyField'), isEmpty);
      expect(key('copy-policyField'), findsNothing);
      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('a set Policy String shows no "Not set" and has a copy button', (tester) async {
      await open(tester, _manual(code: 'MQ57Q-JKGBQ-PF77Z-PBAAS', policy: '18921500'));
      await openRegistrationInfo(tester);
      expect(fieldOf(tester, 'policyField').decoration!.hintText, isNull);
      expect(find.text('Not set'), findsNothing);
      expect(key('copy-policyField'), findsOneWidget);
    });
  });

  group('auto enrollment', () {
    testWidgets('shows the serial, the registered key as Base32 and the link', (tester) async {
      await open(tester, _registered());
      expect(appBarTitle('HOTP profile'), findsOneWidget);
      expect(tester.widget<Text>(key('sourceLine')).data, 'MobilePASS format');
      expect(key('registrationInfoButton'), findsNothing);
      await openRegistrationInfo(tester);
      expect(
        find.descendant(of: key('registrationInfoSheet'), matching: find.text('MobilePASS – Auto enrollment')),
        findsOneWidget,
      );
      expect(key('serialField'), findsOneWidget);
      expect(find.text('123456789'), findsOneWidget);
      await closeProfileInfo(tester);
      final secret = base32Encode(base64.decode(_registeredKey));
      expect(textOf(tester, 'mobilePassSecretField'), secret);
      expect(fieldOf(tester, 'mobilePassSecretField').obscureText, isTrue);
      await copyExportLink(tester);
      final link = parseOtpauthUri(copiedLink());
      expect(link.counter, 4);
      expect(link.digits, 6);
      expect(base32Encode(link.secret), secret);
      await settleCopy(tester);
    });
  });

  group('other kinds', () {
    testWidgets('time-based: TOTP, no link and nothing about one', (tester) async {
      await open(tester, _manual(code: _timeCode, policy: '75817049'));
      expect(appBarTitle('TOTP profile'), findsOneWidget);
      expect(key('mobilePassSecretField'), findsOneWidget);
      expectNoLinkOnPage();
      expect(await menuItems(tester), isNot(contains('copyOtpauthLinkButton')));
      expect(await menuItems(tester), contains('registrationInfoMenuItem'));
    });

    testWidgets('challenge-response: titled Challenge-response, no link and nothing about one', (tester) async {
      await open(tester, _manual(code: _timeCode, policy: '38039554'));
      expect(appBarTitle('Challenge-response profile'), findsOneWidget);
      expect(key('mobilePassSecretField'), findsOneWidget);
      expectNoLinkOnPage();
      expect(await menuItems(tester), isNot(contains('copyOtpauthLinkButton')));
    });

    testWidgets('standard TOTP: TOTP, no source line, export link', (tester) async {
      await open(
        tester,
        Profile(id: 't', name: 'T', activationCode: '', kind: ProfileKind.totp, key: _totpLink, counter: 0),
      );
      expect(appBarTitle('TOTP profile'), findsOneWidget);
      expect(key('sourceLine'), findsNothing);
      expect(key('mobilePassSecretField'), findsNothing);
      expectNoLinkOnPage();
      expect(await menuItems(tester), isNot(contains('registrationInfoMenuItem')));
      await copyExportLink(tester);
      expect(parseOtpauthUri(copiedLink()).period, 30);
      await settleCopy(tester);
    });
  });

  group('the menu offers export only where a link exists', () {
    for (final (name, profile, exports) in [
      (
        'standard TOTP',
        Profile(id: 't', name: 'T', activationCode: '', kind: ProfileKind.totp, key: _totpLink, counter: 0),
        true,
      ),
      (
        'standard HOTP',
        Profile(id: 'h', name: 'H', activationCode: '', kind: ProfileKind.hotp, key: _hotpLink, counter: 3),
        true,
      ),
      ('MobilePASS event-based', _manual(), true),
      ('MobilePASS auto enrollment', _registered(), true),
      ('MobilePASS time-based', _manual(code: _timeCode, policy: '75817049'), false),
      ('MobilePASS challenge-response', _manual(code: _timeCode, policy: '38039554'), false),
    ]) {
      testWidgets(name, (tester) async {
        await open(tester, profile);
        expectNoLinkOnPage();
        final items = await menuItems(tester);
        expect(items.contains('copyOtpauthLinkButton'), exports);
        // Every kind shows its secret key on the page itself.
        expect(items.contains('viewSecretButton'), isFalse);
      });
    }
  });

  testWidgets('the menu lists registration info, then the link, then delete', (tester) async {
    await open(tester, _manual());
    expect(await menuItems(tester), ['registrationInfoMenuItem', 'copyOtpauthLinkButton', 'deleteProfileButton']);
  });

  group('a saved standard token shows just its secret key, above the digits', () {
    for (final (kind, stored) in [(ProfileKind.totp, _totpLink), (ProfileKind.hotp, _hotpLink)]) {
      testWidgets(kind.name, (tester) async {
        await open(tester, Profile(id: 's', name: 'S', activationCode: '', kind: kind, key: stored, counter: 3));
        expect(find.text('Secret key'), findsOneWidget);
        expect(textOf(tester, 'secretField'), 'JBSWY3DPEHPK3PXP');
        expect(fieldOf(tester, 'secretField').readOnly, isTrue);
        expect(tester.getTopLeft(key('secretField')).dy, lessThan(tester.getTopLeft(key('otpDigitsField')).dy));
        expect(tester.getTopLeft(key('nameField')).dy, lessThan(tester.getTopLeft(key('secretField')).dy));

        expect(fieldOf(tester, 'secretField').obscureText, isTrue);
        await tester.tap(key('toggleSecretVisibility'));
        await tester.pump();
        expect(fieldOf(tester, 'secretField').obscureText, isFalse);

        await tester.tap(key('copySecretButton'));
        await tester.pump();
        expect(clipboardCalls.first.arguments, {'text': 'JBSWY3DPEHPK3PXP', 'sensitive': true});
        expect(find.text('Secret key copied'), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 61));
      });
    }
  });

  testWidgets('standard export copies as sensitive and preserves the enrollment credential', (tester) async {
    const original = 'otpauth://hotp/Example:alice?secret=JBSWY3DPEHPK3PXP&counter=3';
    final profile = Profile(
      id: 'h',
      name: 'Example',
      activationCode: '',
      kind: ProfileKind.hotp,
      key: original,
      counter: 42,
    );
    await open(tester, profile);
    expect(profile.key, original);
    await tester.enterText(key('counterField'), '43');
    await tester.pump();
    await copyExportLink(tester);
    final link = copiedLink();
    expect(parseOtpauthUri(link).counter, 43);
    expect(lastCopy()['sensitive'], isTrue);
    expect(find.text('Link copied'), findsOneWidget);
    expect(profile.key, original);
    await settleCopy(tester);
  });

  testWidgets('adding keeps its title and shows none of the derived data', (tester) async {
    await pumpLocalized(
      tester,
      ProfileEditScreen(
        profileStore: ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore()),
        settingsStore: SettingsStore(MemoryKeyValueBackend()),
      ),
    );
    await tester.pumpAndSettle();
    expect(appBarTitle('MobilePASS – Manual enrollment'), findsOneWidget);
    expect(key('sourceLine'), findsNothing);
    expect(key('mobilePassSecretField'), findsNothing);
    expectNoLinkOnPage();
  });

  testWidgets('labels follow the locale', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final profile = _manual();
    final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
    await store.saveAll([profile]);
    await pumpLocalized(
      tester,
      ProfileEditScreen(profileStore: store, settingsStore: SettingsStore(MemoryKeyValueBackend()), profile: profile),
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
    );
    await tester.pumpAndSettle();
    expect(appBarTitle('HOTP 設定檔'), findsOneWidget);
    expect(tester.widget<Text>(key('sourceLine')).data, 'MobilePASS 規格');
  });
}
