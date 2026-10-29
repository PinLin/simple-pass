import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _key = 'yqZjy2vEoVSmj/THIULg3ysjfM0L6Bo6QzLlgvA3oQU=';

Profile _enrolled({String policy = '9346', String pin = '123'}) => Profile(
  id: 'k1',
  name: 'Enrolled',
  activationCode: '',
  kind: ProfileKind.mobilePassKey,
  key: _key,
  serial: '123456789',
  policy: policy,
  pin: pin,
  counter: 4,
);

void main() {
  late ProfileStore store;

  Future<void> open(WidgetTester tester, Profile profile) async {
    tester.view.physicalSize = const Size(800, 2000);
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

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows no Activation Code, a read-only policy and serial, and the counter for event-based', (
    tester,
  ) async {
    await open(tester, _enrolled());
    expect(find.byKey(const ValueKey('activationCodeField')), findsNothing);
    expect(find.text('Activation Code'), findsNothing);
    expect(find.byKey(const ValueKey('counterField')), findsOneWidget);
    await openRegistrationInfo(tester);
    for (final key in ['policyField', 'serialField']) {
      final field = tester.widget<TextField>(
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)),
      );
      expect(field.readOnly, isTrue, reason: key);
    }
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('9346'), findsOneWidget);
  });

  testWidgets('time-based key profiles have no counter field', (tester) async {
    await open(tester, _enrolled(policy: '9381'));
    expect(find.byKey(const ValueKey('counterField')), findsNothing);
  });

  testWidgets('keeps the key and policy while name, PIN and options change', (tester) async {
    await open(tester, _enrolled());
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Renamed');
    await tester.enterText(find.byKey(const ValueKey('counterField')), '9');
    await tester.ensureVisible(find.text('Append PIN when copying'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Append PIN when copying'));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = (await store.loadAll()).single;
    expect(saved.name, 'Renamed');
    expect(saved.counter, 9);
    expect(saved.key, _key);
    expect(saved.kind, ProfileKind.mobilePassKey);
    expect(saved.policy, '9346');
    expect(saved.serial, '123456789');
    expect(saved.pin, '123');
    expect(saved.appendPinOnCopy, isTrue);
  });

  testWidgets('the server-set PIN is kept even outside the app rules, but a new PIN must follow them', (tester) async {
    await open(tester, _enrolled());
    await tester.enterText(find.byKey(const ValueKey('pinField')), '12');
    await save(tester);
    expect(find.textContaining('PIN must be'), findsOneWidget);
    expect((await store.loadAll()).single.pin, '123');

    await tester.enterText(find.byKey(const ValueKey('pinField')), '5678');
    await save(tester);
    expect((await store.loadAll()).single.pin, '5678');
  });

  for (final serverPin in ['ab12', '12345678901234567']) {
    testWidgets('a server-set PIN like $serverPin doesn\'t block saving other changes', (tester) async {
      await open(tester, _enrolled(pin: serverPin));
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Renamed');
      await save(tester);
      expect(find.textContaining('PIN must be'), findsNothing);
      final saved = (await store.loadAll()).single;
      expect((saved.name, saved.pin), ('Renamed', serverPin));
    });
  }

  testWidgets('the PIN field offers letters only when the stored PIN has them', (tester) async {
    TextField pinField() => tester.widget<TextField>(
      find.descendant(of: find.byKey(const ValueKey('pinField')), matching: find.byType(TextField)),
    );
    await open(tester, _enrolled(pin: 'ab12'));
    expect(pinField().keyboardType, TextInputType.visiblePassword);
  });

  testWidgets('a digits-only PIN keeps the number keyboard', (tester) async {
    await open(tester, _enrolled(pin: '2468'));
    final field = tester.widget<TextField>(
      find.descendant(of: find.byKey(const ValueKey('pinField')), matching: find.byType(TextField)),
    );
    expect(field.keyboardType, TextInputType.number);
  });
}
