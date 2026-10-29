import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/mobilepass_registration.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

void main() {
  const registration = MobilePassRegistration(
    enrollmentString: 'original-string',
    url: 'https://example.test/enroll',
    userId: 'alice',
    passphrase: 'phrase',
  );
  late ProfileStore store;
  late MemoryKeyValueBackend backend;
  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> open(WidgetTester tester, {bool auto = false}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend = MemoryKeyValueBackend();
    store = ProfileStore(backend);
    final profile = Profile(
      id: 'work',
      name: 'Work',
      activationCode: auto ? '' : 'APSCG-YKKAU-NEZGC-PRDSM',
      counter: 3,
      kind: auto ? ProfileKind.mobilePassKey : ProfileKind.activationCode,
      key: auto ? 'dGVzdA==' : '',
      registration: auto ? registration : null,
      pin: '5678',
    );
    await store.saveAll([profile]);
    await pumpLocalized(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfileEditScreen(
                  profileStore: store,
                  settingsStore: SettingsStore(MemoryKeyValueBackend()),
                  profile: profile,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> delete(WidgetTester tester) async {
    await tester.tap(key('profileMenuButton'));
    await tester.pumpAndSettle();
    await tester.tap(key('deleteProfileButton'));
    await tester.pumpAndSettle();
  }

  testWidgets('registration details open from the menu without duplicating PIN', (tester) async {
    await open(tester, auto: true);
    expect(key('enrollmentStringField'), findsNothing);
    await openRegistrationInfo(tester);
    TextField field(String id) =>
        tester.widget<TextField>(find.descendant(of: key(id), matching: find.byType(TextField)));
    expect(field('enrollmentStringField').controller!.text, 'original-string');
    expect(field('enrollmentStringField').obscureText, isTrue);
    expect(key('enrollmentUrlField'), findsNothing);
    expect(key('enrollmentUserIdField'), findsNothing);
    expect(key('enrollmentPassphraseField'), findsNothing);
    expect(key('enrollmentPinField'), findsNothing);
    await closeProfileInfo(tester);
    expect(field('pinField').controller!.text, '5678');
  });

  testWidgets('canceling delete retains edits; confirming removes only this profile and closes details', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(key('nameField'), 'Unsaved name');
    await delete(tester);
    expect(find.textContaining('does not remove the authenticator from the service'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved name'), findsOneWidget);
    expect(await store.loadAll(), hasLength(1));
    await store.update(
      (all) => [...all, Profile(id: 'other', name: 'Other', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 0)],
    );
    await delete(tester);
    await tester.tap(key('confirmDeleteProfileButton'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsNothing);
    expect((await store.loadAll()).single.id, 'other');
  });

  testWidgets('failed delete stays on the details page and preserves stored data', (tester) async {
    await open(tester);
    final before = backend.rawValue(ProfileStore.storageKey);
    await delete(tester);
    backend.failWritesFor.add(ProfileStore.storageKey);
    await tester.tap(key('confirmDeleteProfileButton'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsOneWidget);
    expect(find.text('Could not save changes'), findsOneWidget);
    expect(backend.rawValue(ProfileStore.storageKey), before);
  });
}
