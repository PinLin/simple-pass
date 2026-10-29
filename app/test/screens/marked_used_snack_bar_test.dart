import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/storage/profile_store.dart';

import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

void main() {
  late ProfileStore store;
  var active = true;
  final updates = <Profile>[];
  var saveFailures = 0;

  setUp(() async {
    store = ProfileStore(MemoryKeyValueBackend());
    await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 6)]);
    active = true;
    updates.clear();
    saveFailures = 0;
  });

  Future<void> show(WidgetTester tester) async {
    await pumpLocalized(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMarkedUsedSnackBar(
              context,
              store: store,
              profileId: 'a1',
              counter: 5,
              active: () => active,
              onUpdated: updates.add,
              onSaveFailed: () => saveFailures++,
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
  }

  testWidgets('Undo restores the counter while still active', (tester) async {
    await show(tester);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await store.loadAll()).single.counter, 5);
    expect(updates.single.counter, 5);
  });

  testWidgets('once no longer active (the app relocked), Undo changes nothing and reports nothing', (tester) async {
    await show(tester);
    active = false;
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await store.loadAll()).single.counter, 6);
    expect(updates, isEmpty);
    expect(saveFailures, 0);
    expect(find.byType(SnackBar), findsNothing);
  });
}
