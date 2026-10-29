import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/key_value_backend.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';

String _grouped(int counter) => formatOtpForDisplay(generateMobilePassOtp(_code, counter));

ProfileListScreen _screen(ProfileStore profileStore, {SettingsStore? settingsStore}) => ProfileListScreen(
  profileStore: profileStore,
  settingsStore: settingsStore ?? SettingsStore(MemoryKeyValueBackend()),
  screenGuard: ScreenGuard(),
);

/// Scrolls [finder] into view first; the edit form is taller than the default test surface and
/// its lazy list has not built the lower fields yet.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets('shows the empty state when there are no profiles', (tester) async {
    await pumpLocalized(tester, _screen(ProfileStore(MemoryKeyValueBackend())));
    await tester.pumpAndSettle();

    expect(find.text('No profiles yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('lists profiles with name, grouped OTP, and compact counter', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend());
    await store.saveAll([
      Profile(id: 'a1', name: 'Work VPN', activationCode: _code, counter: 3),
      Profile(id: 'b2', name: 'Personal', activationCode: _code, counter: 0),
    ]);

    await pumpLocalized(tester, _screen(store));
    await tester.pumpAndSettle();

    expect(find.text('Work VPN'), findsOneWidget);
    expect(find.text(_grouped(3)), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text(_grouped(0)), findsOneWidget);
    expect(find.text('#0'), findsOneWidget);
  });

  testWidgets('shows the OTP grouped in 3+3 with a space, not as one run of digits', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend());
    await store.saveAll([Profile(id: 'a1', name: 'Work VPN', activationCode: _code, counter: 7)]);

    await pumpLocalized(tester, _screen(store));
    await tester.pumpAndSettle();

    final raw = generateMobilePassOtp(_code, 7);
    expect(find.text(_grouped(7)), findsOneWidget);
    expect(_grouped(7), '${raw.substring(0, 3)} ${raw.substring(3)}');
    expect(find.text(raw), findsNothing);
  });

  testWidgets('names use the whole width left of the buttons, cut short only when they really do not fit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(411, 914));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const fits = 'GitHub: alice@example.com';
    final tooLong = 'Very long issuer name: ${'x' * 80}@example.com';
    final store = ProfileStore(MemoryKeyValueBackend());
    await store.saveAll([
      Profile(id: 'a1', name: fits, activationCode: _code, counter: 3),
      Profile(id: 'b2', name: tooLong, activationCode: _code, counter: 4),
    ]);
    await pumpLocalized(tester, _screen(store));
    await tester.pumpAndSettle();
    expect(tester.renderObject<RenderParagraph>(find.text(fits)).didExceedMaxLines, isFalse);
    expect(tester.renderObject<RenderParagraph>(find.text(tooLong)).didExceedMaxLines, isTrue);
    // The counter sits right after a short name, and still shows beside a cut-off one.
    final name = tester.getRect(find.text(fits));
    final counter = tester.getRect(find.text('#3'));
    expect(counter.left - name.right, lessThan(12));
    expect(find.text('#4'), findsOneWidget);
    expect(
      tester.getRect(find.text('#4')).right,
      lessThan(tester.getRect(find.byKey(const ValueKey('profileEdit-b2'))).left),
    );
  });

  testWidgets('the last row scrolls fully clear of the add button', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend());
    await store.saveAll([
      for (var i = 0; i < 8; i++) Profile(id: 'p$i', name: 'Profile $i', activationCode: _code, counter: i),
    ]);
    await pumpLocalized(tester, _screen(store));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
    await tester.pumpAndSettle();

    final lastRow = tester.getRect(find.byKey(const ValueKey('profileRowCopy-p7')));
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(lastRow.bottom, lessThanOrEqualTo(fab.top));
  });

  testWidgets('adding a profile persists it and shows it in the list', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend());
    await pumpLocalized(tester, _screen(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('addKindActivationCode')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'New profile');
    await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'APSCG-YKKAU-NEZGC-PRDSM');
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('New profile'), findsOneWidget);
    final saved = await store.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'New profile');
  });

  group('edit button', () {
    final used = Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5);
    final edit = find.byKey(const ValueKey('profileEdit-a1'));

    Future<ProfileStore> pumpWith(WidgetTester tester, Profile profile) async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([profile]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('sits at the far right, after the ✓', (tester) async {
      await pumpWith(tester, used);
      expect(tester.widget<IconButton>(edit).tooltip, 'Edit');
      expect(find.descendant(of: edit, matching: find.byIcon(Icons.chevron_right)), findsOneWidget);
      expect(tester.getCenter(edit).dx, greaterThan(tester.getCenter(find.byTooltip('Mark as used')).dx));
      expect(tester.getRect(edit).right, lessThanOrEqualTo(tester.getSize(find.byType(Scaffold)).width));
    });

    testWidgets('opens the editor; saving there refreshes the row', (tester) async {
      final store = await pumpWith(tester, used);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('HOTP profile'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Counter'), '6');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect((await store.loadAll()).single.counter, 6);
      expect(find.text(_grouped(6)), findsOneWidget);
      expect(find.text('#6'), findsOneWidget);
    });

    testWidgets('tapping it does not copy the code', (tester) async {
      await pumpWith(tester, used);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('Passcode copied'), findsNothing);
    });
  });

  group('selection mode: deleting', () {
    Profile p(String id, String name) => Profile(id: id, name: name, activationCode: _code, counter: 3);

    Future<ProfileStore> pumpWith(WidgetTester tester, List<Profile> profiles) async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll(profiles);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();
      return store;
    }

    Future<void> select(WidgetTester tester, String id) async {
      await tester.longPress(find.byKey(ValueKey('profileRowCopy-$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('one profile: Cancel keeps it, Delete removes it', (tester) async {
      final store = await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')]);
      await select(tester, 'a1');
      await tester.tap(find.byKey(const ValueKey('deleteSelectedButton')));
      await tester.pumpAndSettle();
      expect(find.text('Delete profile?'), findsOneWidget);
      expect(find.text('This permanently deletes 1 profile.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await store.loadAll(), hasLength(2));
      expect(find.text('1 selected'), findsOneWidget, reason: 'still selecting after Cancel');

      await tester.tap(find.byKey(const ValueKey('deleteSelectedButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await store.loadAll()).map((p) => p.id), ['b2']);
      expect(find.text('Work'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('several profiles go in one confirmation, with the count in the text; selection ends', (tester) async {
      final store = await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home'), p('c3', 'Bank')]);
      await select(tester, 'a1');
      await tester.tap(find.byKey(const ValueKey('profileRowSelect-c3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deleteSelectedButton')));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 profiles?'), findsOneWidget);
      expect(find.text('This permanently deletes 2 profiles.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect((await store.loadAll()).map((p) => p.id), ['b2']);
      expect(find.byKey(const ValueKey('endSelectionButton')), findsNothing);
      expect(find.text('SimplePASS'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('a failed save says so and deletes nothing', (tester) async {
      final backend = _FailingWritesBackend();
      final store = ProfileStore(backend);
      await store.saveAll([p('a1', 'Work'), p('b2', 'Home')]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();
      await select(tester, 'a1');
      backend.failWrites = true;
      await tester.tap(find.byKey(const ValueKey('deleteSelectedButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save changes'), findsOneWidget);
      backend.failWrites = false;
      expect(await store.loadAll(), hasLength(2));
    });
  });

  group('unreadable store', () {
    testWidgets('shows an error with Retry, disables adding and writes nothing', (tester) async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, '[{"id": 1}]');
      await pumpLocalized(tester, _screen(ProfileStore(backend)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not read the saved data'), findsOneWidget);
      expect(find.text('No profiles yet. Tap + to add one.'), findsNothing);
      expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Add profile'), findsNothing);
      expect(backend.writeCount, 0);
      expect(backend.rawValue(ProfileStore.storageKey), '[{"id": 1}]');
    });

    testWidgets('Retry shows the profiles once the store is readable again', (tester) async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, 'not json');
      await pumpLocalized(tester, _screen(ProfileStore(backend)));
      await tester.pumpAndSettle();

      backend.seedRaw(
        ProfileStore.storageKey,
        '{"profiles":[{"id":"a1","name":"Recovered","activationCode":"APSCG-YKKAU-NEZGC-PRDSM","counter":2,'
        '"pin":"","policy":"","createdAt":"2026-01-01T00:00:00.000Z"}]}',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Recovered'), findsOneWidget);
      expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNotNull);
    });

    testWidgets('store becoming unreadable while the add form is open: nothing is written', (tester) async {
      final backend = MemoryKeyValueBackend();
      final store = ProfileStore(backend);
      await store.saveAll([Profile(id: 'a1', name: 'Existing', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 0)]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('addKindActivationCode')));
      await tester.pumpAndSettle();
      backend.seedRaw(ProfileStore.storageKey, '[truncated');
      final writesBefore = backend.writeCount;

      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'New');
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'APSCG-YKKAU-NEZGC-PRDSM');
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(backend.writeCount, writesBefore);
      expect(backend.rawValue(ProfileStore.storageKey), '[truncated');
      expect(find.text('Could not save changes'), findsOneWidget);
    });
  });

  testWidgets('adding a profile keeps profiles saved elsewhere since the list loaded', (tester) async {
    final store = ProfileStore(MemoryKeyValueBackend());
    await pumpLocalized(tester, _screen(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('addKindActivationCode')));
    await tester.pumpAndSettle();
    await store.saveAll([
      Profile(id: 'x', name: 'Saved meanwhile', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 0),
    ]);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'New');
    await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'APSCG-YKKAU-NEZGC-PRDSM');
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect((await store.loadAll()).map((p) => p.name), ['Saved meanwhile', 'New']);
  });

  testWidgets('a stored out-of-range counter shows the load error rather than a broken row', (tester) async {
    final backend = MemoryKeyValueBackend()
      ..seedRaw(
        ProfileStore.storageKey,
        '{"profiles":[{"id":"a1","name":"Broken","activationCode":"APSCG-YKKAU-NEZGC-PRDSM","counter":-1,'
        '"pin":"","policy":"","createdAt":"2026-01-01T00:00:00.000Z"},'
        '{"id":"b2","name":"Fine","activationCode":"APSCG-YKKAU-NEZGC-PRDSM","counter":4,'
        '"pin":"","policy":"","createdAt":"2026-01-01T00:00:00.000Z"}]}',
      );
    await pumpLocalized(tester, _screen(ProfileStore(backend)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read the saved data'), findsOneWidget);
    expect(find.text('Broken'), findsNothing);
    expect(find.text('Fine'), findsNothing);
  });

  group('mark as used from the list', () {
    void mockClipboard() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SensitiveClipboard.channelName),
        (call) async => call.method == 'clearIfMatches' ? 'cleared' : null,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(SensitiveClipboard.channelName),
          null,
        ),
      );
    }

    testWidgets('tapping the checkmark advances the shown counter', (tester) async {
      mockClipboard();
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5)]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      final updated = (await store.loadAll()).single;
      expect(updated.counter, 6);
      // The list re-rendered around the newly stored profile, not the stale one.
      expect(find.text(_grouped(6)), findsOneWidget);
      expect(find.text('#6'), findsOneWidget);
    });

    testWidgets('at maxCounter the checkmark is disabled', (tester) async {
      mockClipboard();
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: _code, counter: maxCounter)]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check)).onPressed, isNull);
    });

    testWidgets('the snackbar names the marked counter and Undo restores the counter', (tester) async {
      mockClipboard();
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5)]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(find.text('Marked #5 as used'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      final restored = (await store.loadAll()).single;
      expect(restored.counter, 5);
      expect(find.text('#5'), findsOneWidget);
    });

    testWidgets('Undo leaves the counter alone and says so when it changed meanwhile', (tester) async {
      mockClipboard();
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5)]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      await store.updateProfile('a1', (p) => p.copyWith(counter: 9));

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      final after = (await store.loadAll()).single;
      expect(after.counter, 9);
      expect(find.text("Can't undo: the counter has changed since."), findsOneWidget);
    });
  });

  group('code color', () {
    Color? otpColorOf(WidgetTester tester, int counter) =>
        tester.widget<Text>(find.text(_grouped(counter))).style?.color;

    testWidgets('the code is onSurface, before and after marking it used', (tester) async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 3)]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();

      final scheme = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;
      expect(otpColorOf(tester, 3), scheme.onSurface);
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(otpColorOf(tester, 4), scheme.onSurface);
    });
  });

  testWidgets('tapping the OTP copies it as sensitive and shows a snackbar', (tester) async {
    final clipboardCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(SensitiveClipboard.channelName),
      (call) async {
        clipboardCalls.add(call);
        return call.method == 'clearIfMatches' ? 'cleared' : null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SensitiveClipboard.channelName),
        null,
      ),
    );

    final store = ProfileStore(MemoryKeyValueBackend());
    await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5)]);
    await pumpLocalized(tester, _screen(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_grouped(5)));
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.method, 'setText');
    expect(clipboardCalls.single.arguments, {'text': generateMobilePassOtp(_code, 5), 'sensitive': true});
    expect(SensitiveClipboard.instance.hasPendingClear, isTrue);
    expect(find.text('Passcode copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  group('undo snackbar across pages', () {
    Future<ProfileStore> pumpList(WidgetTester tester) async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5)]);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();
      return store;
    }

    // Whatever page is on screen must agree with the store: a code for the
    // stored counter, and none for any other.
    Future<void> expectShowsOnly(WidgetTester tester, ProfileStore store, int counter) async {
      expect((await store.loadAll()).single.counter, counter);
      expect(find.text(_grouped(counter)), findsOneWidget);
      expect(find.text(_grouped(counter == 5 ? 6 : 5)), findsNothing);
    }

    testWidgets('marked on the list, then opening the editor and back: no stale Undo is offered', (tester) async {
      final store = await pumpList(tester);
      await tester.tap(find.byTooltip('Mark as used'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profileEdit-a1')));
      await tester.pump();
      expect(find.text('Undo'), findsNothing, reason: 'gone at once, not fading out');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Undo'), findsNothing);
      await expectShowsOnly(tester, store, 6);
    });

    testWidgets('Undo on the list itself still works and refreshes the row', (tester) async {
      final store = await pumpList(tester);
      await tester.tap(find.byTooltip('Mark as used'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      await expectShowsOnly(tester, store, 5);
    });
  });

  testWidgets('an unreadable store shows LoadErrorView with no rows and no checkmarks to tap', (tester) async {
    final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, 'not json');
    await pumpLocalized(tester, _screen(ProfileStore(backend)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read the saved data'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(backend.writeCount, 0);
  });

  group('row taps', () {
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

    Future<ProfileStore> pumpWith(
      WidgetTester tester,
      Profile profile, {
      ClipboardClear clear = ClipboardClear.never,
    }) async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([profile]);
      final settings = SettingsStore(MemoryKeyValueBackend());
      await settings.save(Settings(clipboardClear: clear));
      await pumpLocalized(tester, _screen(store, settingsStore: settings));
      await tester.pumpAndSettle();
      return store;
    }

    Profile work({int counter = 5, String pin = '', bool append = false}) =>
        Profile(id: 'a1', name: 'Work', activationCode: _code, counter: counter, pin: pin, appendPinOnCopy: append);

    List<String> copiedTexts() =>
        clipboardCalls.where((c) => c.method == 'setText').map((c) => (c.arguments as Map)['text'] as String).toList();

    for (final target in ['name', 'counter', 'row padding']) {
      testWidgets('tapping the $target copies the code', (tester) async {
        await pumpWith(tester, work());

        final finder = switch (target) {
          'name' => find.text('Work'),
          'counter' => find.text('#5'),
          _ => find.byKey(const ValueKey('profileRowCopy-a1')),
        };
        // For the row itself, tap its far-left padding, away from any text.
        if (target == 'row padding') {
          await tester.tapAt(tester.getTopLeft(finder) + const Offset(4, 4));
        } else {
          await tester.tap(finder);
        }
        await tester.pumpAndSettle();

        expect(copiedTexts(), [generateMobilePassOtp(_code, 5)]);
        expect(find.text('Passcode copied'), findsOneWidget);
        // Copying doesn't navigate.
        expect(find.text('Mark as used'), findsNothing);
      });
    }

    testWidgets('tapping ✓ marks used without copying', (tester) async {
      final store = await pumpWith(tester, work());

      await tester.tap(find.byTooltip('Mark as used'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, isEmpty);
      expect((await store.loadAll()).single.counter, 6);
    });

    testWidgets('tapping a disabled ✓ (at maxCounter) does not fall through to copying', (tester) async {
      await pumpWith(tester, work(counter: maxCounter));

      await tester.tap(find.byTooltip('Mark as used'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(clipboardCalls, isEmpty);
    });

    testWidgets('control: the same spot on an enabled ✓ does mark used', (tester) async {
      final store = await pumpWith(tester, work());

      await tester.tapAt(tester.getCenter(find.byTooltip('Mark as used')));
      await tester.pumpAndSettle();

      expect(clipboardCalls, isEmpty);
      expect((await store.loadAll()).single.counter, 6);
    });

    testWidgets('the disabled ✓ (at maxCounter) sits where the enabled one does, and the tap there is inert', (
      tester,
    ) async {
      final enabledSpot = await (() async {
        await pumpWith(tester, work());
        return tester.getCenter(find.byTooltip('Mark as used'));
      })();
      await pumpWith(tester, work(counter: maxCounter));
      expect(tester.getCenter(find.byTooltip('Mark as used')), enabledSpot);

      await tester.tapAt(enabledSpot);
      await tester.pumpAndSettle();

      expect(clipboardCalls, isEmpty);
      expect(find.text('Passcode copied'), findsNothing);
    });

    testWidgets('long-pressing starts selecting the row without copying', (tester) async {
      await pumpWith(tester, work());

      await tester.longPress(find.text(_grouped(5)));
      await tester.pumpAndSettle();

      expect(clipboardCalls, isEmpty);
      expect(find.text('Passcode copied'), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('appendPinOnCopy on: tapping the row copies PIN + OTP and clears it after the default minute', (
      tester,
    ) async {
      await pumpWith(tester, work(pin: '1234', append: true), clear: ClipboardClear.oneMinute);

      await tester.tap(find.text(_grouped(5)));
      await tester.pump();

      final expected = '1234${generateMobilePassOtp(_code, 5)}';
      expect(clipboardCalls.single.arguments, {'text': expected, 'sensitive': true});
      expect(SensitiveClipboard.instance.hasPendingClear, isTrue);
      expect(find.text('PIN + passcode copied'), findsOneWidget);
      expect(find.text('Passcode copied'), findsNothing);
      // Only the OTP is ever shown.
      expect(find.textContaining('1234'), findsNothing);

      await tester.pump(const Duration(seconds: 60));
      expect(clipboardCalls.last.method, 'clearIfMatches');
      expect(clipboardCalls.last.arguments, {'text': expected});
    });

    testWidgets('an OTP-only copy is cleared after the configured delay too', (tester) async {
      await pumpWith(tester, work(pin: '1234'), clear: ClipboardClear.thirtySeconds);

      await tester.tap(find.text(_grouped(5)));
      await tester.pump();
      expect(copiedTexts(), [generateMobilePassOtp(_code, 5)]);
      expect(SensitiveClipboard.instance.hasPendingClear, isTrue);

      await tester.pump(const Duration(seconds: 29));
      expect(clipboardCalls.last.method, 'setText');
      await tester.pump(const Duration(seconds: 1));
      expect(clipboardCalls.last.method, 'clearIfMatches');
      expect(clipboardCalls.last.arguments, {'text': generateMobilePassOtp(_code, 5)});
    });

    testWidgets('Never: nothing is scheduled for either kind of copy', (tester) async {
      await pumpWith(tester, work(pin: '1234', append: true), clear: ClipboardClear.never);
      await tester.tap(find.text(_grouped(5)));
      await tester.pump();
      expect(SensitiveClipboard.instance.hasPendingClear, isFalse);
      expect(find.text('PIN + passcode copied'), findsOneWidget);
    });

    testWidgets('the copy toast goes away by itself after about 2 seconds', (tester) async {
      await pumpWith(tester, work());
      await tester.tap(find.text(_grouped(5)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Passcode copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Passcode copied'), findsNothing);
    });

    testWidgets('a toast can be dismissed by tapping it or swiping it away', (tester) async {
      await pumpWith(tester, work());
      await tester.tap(find.text(_grouped(5)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Passcode copied'), findsOneWidget);
      await tester.tap(find.text('Passcode copied'));
      await tester.pumpAndSettle();
      expect(find.text('Passcode copied'), findsNothing);

      await tester.tap(find.text(_grouped(5)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Passcode copied'), findsOneWidget);
      await tester.drag(find.text('Passcode copied'), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Passcode copied'), findsNothing);
    });

    testWidgets('the mark-used snackbar: tap and swipe dismiss it, 復原 still undoes', (tester) async {
      final store = await pumpWith(tester, work());
      await tester.tap(find.byTooltip('Mark as used'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Marked #5 as used'));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);

      await tester.tap(find.byTooltip('Mark as used'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.drag(find.text('Marked #6 as used'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);

      await tester.tap(find.byTooltip('Mark as used'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await store.loadAll()).single.counter, 7);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('appendPinOnCopy on but no PIN: copies only the OTP', (tester) async {
      await pumpWith(tester, work(append: true));

      await tester.tap(find.text(_grouped(5)));
      await tester.pump();

      expect(copiedTexts(), [generateMobilePassOtp(_code, 5)]);
      expect(find.text('Passcode copied'), findsOneWidget);
      expect(find.text('PIN + passcode copied'), findsNothing);
    });

    testWidgets('the copy ink spans the whole row, ✓ included, while ✓ stays its own target', (tester) async {
      final store = await pumpWith(tester, work());
      final row = tester.getRect(find.byKey(const ValueKey('profileRowCopy-a1')));
      final check = find.byTooltip('Mark as used');

      expect(row.left, 0);
      expect(row.right, tester.getSize(find.byType(Scaffold)).width);
      expect(row.contains(tester.getCenter(check)), isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('profileRowCopy-a1')), matching: check), findsOneWidget);

      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(clipboardCalls, isEmpty);
      expect((await store.loadAll()).single.counter, 6);
    });

    testWidgets('the copy target and the ✓ button meet the 48dp tap target guideline', (tester) async {
      await pumpWith(tester, work());

      expect(tester.getSize(find.byKey(const ValueKey('profileRowCopy-a1'))).height, greaterThanOrEqualTo(48));
      final size = tester.getSize(find.widgetWithIcon(IconButton, Icons.check));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testWidgets('the row exposes tap and long-press actions with localized hints', (tester) async {
      final handle = tester.ensureSemantics();
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([work()]);
      await pumpLocalized(
        tester,
        _screen(store),
        locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('標記已使用'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('profileRowCopy-a1'))),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
          onTapHint: '複製驗證碼',
          onLongPressHint: '選取',
        ),
      );
      handle.dispose();
    });
  });

  group('time-based profiles', () {
    const code = 'VTH7N-PZJYN-M3TMH-QBACP';
    late List<MethodCall> clipboardCalls;
    late DateTime now;

    setUp(() {
      clipboardCalls = [];
      // 35 seconds into the 60-second step that shows 672964.
      now = DateTime.fromMillisecondsSinceEpoch(1791875555 * 1000);
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

    Profile cloud({String pin = '', bool append = false}) => Profile(
      id: 't1',
      name: 'Cloud',
      activationCode: code,
      counter: 0,
      policy: '75817049',
      pin: pin,
      appendPinOnCopy: append,
    );

    Future<ProfileStore> pumpTimeBased(WidgetTester tester, List<Profile> profiles) async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll(profiles);
      final settings = SettingsStore(MemoryKeyValueBackend());
      await settings.save(const Settings(clipboardClear: ClipboardClear.never));
      await pumpLocalized(
        tester,
        ProfileListScreen(profileStore: store, settingsStore: settings, screenGuard: ScreenGuard(), now: () => now),
      );
      // The row ticks every second, so it never settles.
      await tester.pump();
      await tester.pump();
      return store;
    }

    testWidgets('shows the code and a countdown instead of ✓ and the counter', (tester) async {
      await pumpTimeBased(tester, [cloud(), Profile(id: 'e1', name: 'Work', activationCode: _code, counter: 5)]);

      expect(find.text('672 964'), findsOneWidget);
      expect(find.byKey(const ValueKey('profileCountdown-t1')), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('#0'), findsNothing);
      // Only the event-based row has a ✓.
      expect(find.byTooltip('Mark as used'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('ticker-t1')), matching: find.byIcon(Icons.check)),
        findsNothing,
      );
    });

    testWidgets('the code and countdown follow the clock', (tester) async {
      await pumpTimeBased(tester, [cloud()]);
      expect(find.text('25'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('24'), findsOneWidget);
      expect(find.text('672 964'), findsOneWidget);

      now = now.add(const Duration(seconds: 24));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('176 058'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('tapping copies the current code with the PIN rule', (tester) async {
      await pumpTimeBased(tester, [cloud(pin: '1234', append: true)]);
      await tester.tap(find.text('672 964'));
      await tester.pump();
      expect(clipboardCalls.where((c) => c.method == 'setText').map((c) => (c.arguments as Map)['text']), [
        '1234672964',
      ]);
      expect(find.text('PIN + passcode copied'), findsOneWidget);
    });

    testWidgets('8-digit time-based codes are split 4 + 4', (tester) async {
      await pumpTimeBased(tester, [cloud().copyWith(policy: '75890738')]);
      final otp = generateMobilePassTimeOtp(code, '75890738', 1791875555);
      expect(otp, hasLength(8));
      expect(find.text('${otp.substring(0, 4)} ${otp.substring(4)}'), findsOneWidget);
    });

    testWidgets('no timer runs without a time-based row', (tester) async {
      await pumpTimeBased(tester, [Profile(id: 'e1', name: 'Work', activationCode: _code, counter: 5)]);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the ticking stops once the time-based row is gone', (tester) async {
      await pumpTimeBased(tester, [cloud()]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('challenge-response profiles', () {
    const code = 'HCF4B-47YNP-OVAPP-4BAE2';
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

    Profile portal({String pin = '', bool append = false, String policy = '38039554'}) => Profile(
      id: 'c1',
      name: 'Portal',
      activationCode: code,
      counter: 4,
      policy: policy,
      pin: pin,
      appendPinOnCopy: append,
    );

    Future<ProfileStore> pumpWith(WidgetTester tester, List<Profile> profiles, {ProfileStore? store}) async {
      store ??= ProfileStore(MemoryKeyValueBackend());
      await store.saveAll(profiles);
      final settings = SettingsStore(MemoryKeyValueBackend());
      await settings.save(const Settings(clipboardClear: ClipboardClear.oneMinute));
      await pumpLocalized(tester, _screen(store, settingsStore: settings));
      await tester.pumpAndSettle();
      return store;
    }

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.text('Portal'));
      await tester.pumpAndSettle();
    }

    final field = find.byKey(const ValueKey('challengeField'));
    final okButton = find.byKey(const ValueKey('challengeConfirmButton'));
    final row = find.byKey(const ValueKey('profileRowCopy-c1'));
    final placeholder = find.descendant(of: row, matching: find.byKey(const ValueKey('lockedCodePlaceholder')));
    bool okEnabled(WidgetTester tester) => tester.widget<FilledButton>(okButton).onPressed != null;
    List<String> copiedTexts() =>
        clipboardCalls.where((c) => c.method == 'setText').map((c) => (c.arguments as Map)['text'] as String).toList();

    Future<void> answer(WidgetTester tester, [String challenge = '123456']) async {
      await openDialog(tester);
      await tester.enterText(field, challenge);
      await tester.pump();
      await tester.tap(okButton);
      await tester.pumpAndSettle();
    }

    void expectAwaiting() {
      expect(placeholder, findsOneWidget);
      expect(find.descendant(of: row, matching: find.byIcon(Icons.dialpad)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.byIcon(Icons.check)), findsNothing);
      expect(find.byKey(const ValueKey('challengeLabel-c1')), findsNothing);
      expect(find.text('506 945'), findsNothing);
    }

    void expectAnswered() {
      expect(find.descendant(of: row, matching: find.text('506 945')), findsOneWidget);
      // Only the digits, grey, by the name; read out as "Challenge Code 123456".
      expect(find.descendant(of: row, matching: find.text('123456')), findsOneWidget);
      expect(find.byKey(const ValueKey('challengeLabel-c1')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('Challenge Code')), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Challenge Code 123456'),
        findsOneWidget,
      );
      expect(find.descendant(of: row, matching: find.byTooltip('Mark as used')), findsOneWidget);
      expect(placeholder, findsNothing);
      expect(find.descendant(of: row, matching: find.byIcon(Icons.dialpad)), findsNothing);
    }

    Future<FakeKeystore> pumpProtected(WidgetTester tester, {List<AuthResult> auth = const []}) async {
      final keystore = FakeKeystore();
      final store = ProfileStore(MemoryKeyValueBackend(), keystore: keystore);
      await store.saveAll([portal()]);
      await store.updateProfile('c1', (p) => p.copyWith(protected: true));
      store.forget();
      keystore
        ..expire()
        ..authenticateCalls = 0
        ..authResults.addAll(auth);
      // The app lock prompts only after the list's load finished, which includes this call.
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(ScreenGuard.channelName), null));
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();
      return keystore;
    }

    Future<void> backgroundAndBack(WidgetTester tester) async {
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('the row shows dots and the challenge icon, no code, ✓, counter or countdown', (tester) async {
      await pumpWith(tester, [portal(), Profile(id: 'e1', name: 'Work', activationCode: _code, counter: 5)]);

      expectAwaiting();
      expect(find.descendant(of: placeholder, matching: find.byType(Container)), findsNWidgets(6));
      expect(find.byKey(const ValueKey('profileChallenge-c1')), findsOneWidget);
      expect(find.text('#4'), findsNothing);
      expect(find.byKey(const ValueKey('profileCountdown-c1')), findsNothing);
      // The event-based row is unaffected.
      expect(find.text('#5'), findsOneWidget);
      expect(find.byTooltip('Mark as used'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('an 8-digit policy shows 8 dots', (tester) async {
      await pumpWith(tester, [portal(policy: '9439')]);
      expect(find.descendant(of: placeholder, matching: find.byType(Container)), findsNWidgets(8));
    });

    testWidgets('the dialog only takes the challenge; OK stays disabled until all digits are in', (tester) async {
      await pumpWith(tester, [portal()]);
      await openDialog(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Portal')), findsOneWidget);
      expect(find.text('Challenge Code'), findsOneWidget);
      expect(find.text('Enter 6 digits'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'OK'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      final textField = tester.widget<TextField>(field);
      expect((textField.autofocus, textField.maxLength), (true, 6));
      expect(okEnabled(tester), isFalse);

      await tester.enterText(field, '12345');
      await tester.pump();
      expect(okEnabled(tester), isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expectAwaiting();

      await tester.enterText(field, '123456');
      await tester.pump();
      expect(okEnabled(tester), isTrue);
      expect(find.text('506 945'), findsNothing);
    });

    testWidgets('the field takes digits only, up to the challenge length', (tester) async {
      await pumpWith(tester, [portal()]);
      await openDialog(tester);

      await tester.enterText(field, '12a3b4');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '1234');
      expect(okEnabled(tester), isFalse);

      await tester.enterText(field, '1234567');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '123456');
      expect(okEnabled(tester), isTrue);
    });

    testWidgets('OK closes the dialog and puts the response and challenge on the row', (tester) async {
      final backend = MemoryKeyValueBackend();
      final store = await pumpWith(tester, [portal()], store: ProfileStore(backend));
      final before = await backend.read(ProfileStore.storageKey);
      await answer(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expectAnswered();
      expect(find.byType(SnackBar), findsNothing);
      expect(copiedTexts(), isEmpty);
      expect(await backend.read(ProfileStore.storageKey), before);
      expect((await store.loadAll()).single.counter, 4);
    });

    testWidgets('Enter with all digits in confirms like OK', (tester) async {
      await pumpWith(tester, [portal()]);
      await openDialog(tester);
      await tester.enterText(field, '001234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.descendant(of: row, matching: find.text('570 122')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('challengeLabel-c1'))).data, '001234');
    });

    testWidgets('Cancel leaves the row waiting for a challenge', (tester) async {
      await pumpWith(tester, [portal()]);
      await openDialog(tester);
      await tester.enterText(field, '123456');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expectAwaiting();
      expect(copiedTexts(), isEmpty);
    });

    testWidgets('tapping an answered row copies the response, shows the toast and clears later', (tester) async {
      await pumpWith(tester, [portal(pin: '1234')]);
      await answer(tester);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(copiedTexts(), ['506945']);
      expect(SensitiveClipboard.instance.hasPendingClear, isTrue);
      expect(find.text('Passcode copied'), findsOneWidget);
      expectAnswered();
      await tester.pump(const Duration(minutes: 1));
      expect(clipboardCalls.last.method, 'clearIfMatches');
    });

    testWidgets('copying an answered row follows the PIN rule', (tester) async {
      await pumpWith(tester, [portal(pin: '1234', append: true)]);
      await answer(tester);
      expect(find.textContaining('1234506945'), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(copiedTexts(), ['1234506945']);
      expect(find.text('PIN + passcode copied'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('✓ puts the row back to waiting, without a toast or a save', (tester) async {
      final backend = MemoryKeyValueBackend();
      await pumpWith(tester, [portal()], store: ProfileStore(backend));
      final before = await backend.read(ProfileStore.storageKey);
      await answer(tester);
      await tester.tap(find.byTooltip('Mark as used'));
      await tester.pumpAndSettle();

      expectAwaiting();
      expect(find.byType(SnackBar), findsNothing);
      expect(copiedTexts(), isEmpty);
      expect(await backend.read(ProfileStore.storageKey), before);

      await openDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('long press selects the row without a dialog or copy, waiting or answered', (tester) async {
      await pumpWith(tester, [portal()]);
      await tester.longPress(find.text('Portal'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('endSelectionButton')));
      await tester.pumpAndSettle();

      await answer(tester);
      await tester.longPress(find.text('Portal'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(copiedTexts(), isEmpty);
    });

    testWidgets('saving the profile in the editor clears the answer', (tester) async {
      await pumpWith(tester, [portal()]);
      await answer(tester);
      await tester.tap(find.byKey(const ValueKey('profileEdit-c1')));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expectAwaiting();
    });

    testWidgets('leaving the editor without saving keeps the answer', (tester) async {
      await pumpWith(tester, [portal()]);
      await answer(tester);
      await tester.tap(find.byKey(const ValueKey('profileEdit-c1')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expectAnswered();
    });

    testWidgets('a deleted profile that comes back starts out waiting', (tester) async {
      final store = await pumpWith(tester, [portal()]);
      await answer(tester);
      await tester.longPress(find.text('Portal'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deleteSelectedButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Portal'), findsNothing);

      // The same id again; nothing of the old answer may survive.
      await store.saveAll([portal()]);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expectAwaiting();
    });

    testWidgets('an unprotected answer survives going to the background', (tester) async {
      await pumpWith(tester, [portal()]);
      await answer(tester);
      await backgroundAndBack(tester);
      expectAnswered();
    });

    testWidgets('a protected profile asks for the challenge once the app lock has opened', (tester) async {
      final keystore = await pumpProtected(tester);
      expect(keystore.authenticateCalls, 1, reason: 'the app lock prompted by itself');
      expect(find.byKey(const ValueKey('profileLocked-c1')), findsNothing);
      expectAwaiting();

      await answer(tester);
      expect(keystore.authenticateCalls, 1);
      expectAnswered();
    });

    testWidgets('while the app lock stays up there is no row and no dialog', (tester) async {
      await pumpProtected(tester, auth: [AuthResult.canceled]);

      expect(find.text('Portal'), findsNothing);
      expect(find.byKey(const ValueKey('profileChallenge-c1')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('unlockAppButton')), findsOneWidget);
    });

    testWidgets('relocking the app clears an answer', (tester) async {
      final keystore = await pumpProtected(tester);
      await answer(tester);
      expectAnswered();

      keystore.expire();
      await backgroundAndBack(tester);
      expect(keystore.authenticateCalls, 2, reason: 'coming back asked again');
      expect(find.text('506 945'), findsNothing);
      expect(find.byKey(const ValueKey('challengeLabel-c1')), findsNothing);
      expectAwaiting();
    });

    testWidgets('selection mode shows dots; the answer is back after leaving it', (tester) async {
      await pumpWith(tester, [portal(), Profile(id: 'e1', name: 'Work', activationCode: _code, counter: 5)]);
      await answer(tester);
      await tester.longPress(find.text('Work'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lockedCodePlaceholder')), findsNWidgets(2));
      expect(find.byIcon(Icons.dialpad), findsNothing);
      expect(find.text('506 945'), findsNothing);
      expect(find.byKey(const ValueKey('challengeLabel-c1')), findsNothing);
      expect(find.text('#4'), findsNothing);
      expect(find.text('#5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('endSelectionButton')));
      await tester.pumpAndSettle();
      expectAnswered();
    });

    testWidgets('the row hints at entering a challenge, then at copying', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWith(tester, [portal()]);
      Matcher hint(String tap) => isSemantics(
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
        onTapHint: tap,
        onLongPressHint: 'Select',
      );
      expect(tester.getSemantics(row), hint('Enter Challenge Code'));
      await answer(tester);
      expect(tester.getSemantics(row), hint('Copy passcode'));
      handle.dispose();
    });
  });

  group('selection mode', () {
    late List<MethodCall> clipboardCalls;

    setUp(() {
      clipboardCalls = [];
      SensitiveClipboard.debugInstanceOverride = SensitiveClipboard();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SensitiveClipboard.channelName),
        (call) async {
          clipboardCalls.add(call);
          return null;
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

    Profile p(String id, String name, {String policy = ''}) =>
        Profile(id: id, name: name, activationCode: _code, counter: 3, policy: policy);

    Future<ProfileStore> pumpWith(WidgetTester tester, List<Profile> profiles, {KeyValueBackend? backend}) async {
      final store = ProfileStore(backend ?? MemoryKeyValueBackend());
      await store.saveAll(profiles);
      await pumpLocalized(tester, _screen(store));
      await tester.pumpAndSettle();
      return store;
    }

    Finder copyRow(String id) => find.byKey(ValueKey('profileRowCopy-$id'));
    Finder selectRow(String id) => find.byKey(ValueKey('profileRowSelect-$id'));
    final endButton = find.byKey(const ValueKey('endSelectionButton'));
    final deleteButton = find.byKey(const ValueKey('deleteSelectedButton'));

    Future<void> select(WidgetTester tester, String id) async {
      await tester.longPress(copyRow(id));
      await tester.pumpAndSettle();
    }

    /// Long-presses [id], then drags it down by [rows] rows in small steps the way a finger moves.
    Future<void> dragDown(WidgetTester tester, String id, {int rows = 1}) async {
      final rowHeight = tester.getSize(find.byKey(ValueKey('selectRow-$id'))).height;
      final gesture = await tester.startGesture(tester.getCenter(selectRow(id)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      for (var i = 0; i < 10 * rows.abs(); i++) {
        await gesture.moveBy(Offset(0, rows.sign * rowHeight / 10));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    List<String> shownNames(WidgetTester tester) => tester
        .widgetList<Text>(find.descendant(of: find.byType(ReorderableListView), matching: find.byType(Text)))
        .map((t) => t.data!)
        .where((t) => t.length > 1 && !t.startsWith('#') && !t.endsWith('selected'))
        .toList();

    testWidgets('long-pressing a row selects it without copying; the bar shows the count and Delete', (tester) async {
      await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')]);
      await select(tester, 'a1');

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('SimplePASS'), findsNothing);
      expect(tester.widget<IconButton>(deleteButton).tooltip, 'Delete');
      expect(endButton, findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(clipboardCalls, isEmpty);
      expect(find.text('Passcode copied'), findsNothing);
    });

    testWidgets('rows mask the code and hide every button and the FAB; they keep the counter and height', (
      tester,
    ) async {
      await pumpWith(tester, [p('a1', 'Work'), p('t1', 'Cloud', policy: '75817049')]);
      final normal = tester.getSize(copyRow('a1')).height;
      await select(tester, 'a1');

      expect(find.text(_grouped(3)), findsNothing);
      expect(find.byKey(const ValueKey('lockedCodePlaceholder')), findsNWidgets(2));
      expect(find.text('#3'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('profileEdit-a1')), findsNothing);
      expect(tester.getSize(selectRow('a1')).height, normal);
    });

    testWidgets('only selected rows are highlighted and marked selected for accessibility', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')]);
      await select(tester, 'a1');

      Color? background(String id) =>
          tester.widget<Material>(find.ancestor(of: selectRow(id), matching: find.byType(Material)).first).color;
      expect(background('a1'), testTheme.colorScheme.secondaryContainer);
      expect(background('b2'), isNot(testTheme.colorScheme.secondaryContainer));
      expect(tester.getSemantics(selectRow('a1')), isSemantics(isSelected: true, isButton: true));
      expect(tester.getSemantics(selectRow('b2')), isSemantics(isSelected: false, isButton: true));
      handle.dispose();
    });

    testWidgets('tapping rows toggles the selection without copying or unlocking', (tester) async {
      await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home'), p('c3', 'Bank')]);
      await select(tester, 'a1');

      await tester.tap(selectRow('b2'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(selectRow('c3'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(selectRow('b2'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      expect(clipboardCalls, isEmpty);
      expect(find.text('Passcode copied'), findsNothing);
    });

    testWidgets('✕ ends selection and the normal list is back', (tester) async {
      await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')]);
      await select(tester, 'a1');
      await tester.tap(selectRow('b2'));
      await tester.pumpAndSettle();
      await tester.tap(endButton);
      await tester.pumpAndSettle();

      expect(find.text('SimplePASS'), findsOneWidget);
      expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
      expect(find.text(_grouped(3)), findsNWidgets(2));
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await select(tester, 'b2');
      expect(find.text('1 selected'), findsOneWidget, reason: 'the old selection did not linger');
    });

    testWidgets('system back ends selection instead of leaving the app', (tester) async {
      await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')]);
      await select(tester, 'a1');

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileListScreen), findsOneWidget);
      expect(find.text('SimplePASS'), findsOneWidget);
      expect(endButton, findsNothing);
      expect(find.text(_grouped(3)), findsNWidgets(2));
    });

    testWidgets('deselecting the last selected row ends selection', (tester) async {
      await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')]);
      await select(tester, 'a1');
      await tester.tap(selectRow('b2'));
      await tester.pumpAndSettle();
      await tester.tap(selectRow('a1'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(selectRow('b2'));
      await tester.pumpAndSettle();
      expect(find.text('SimplePASS'), findsOneWidget);
      expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('a time-based profile does not tick while selecting', (tester) async {
      await pumpWith(tester, [p('t1', 'Cloud', policy: '75817049'), p('a1', 'Work')]);
      await select(tester, 'a1');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('long-press then drag saves the new order right away', (tester) async {
      final store = await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home'), p('c3', 'Bank')]);
      await select(tester, 'a1');

      await dragDown(tester, 'a1');

      expect(shownNames(tester), ['Home', 'Work', 'Bank']);
      expect((await store.loadAll()).map((p) => p.id), ['b2', 'a1', 'c3']);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('an unselected row can be dragged too, and stays unselected', (tester) async {
      final store = await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home'), p('c3', 'Bank')]);
      await select(tester, 'a1');

      await dragDown(tester, 'c3', rows: -1);

      expect((await store.loadAll()).map((p) => p.id), ['a1', 'c3', 'b2']);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('entering and leaving selection keeps the scroll position', (tester) async {
      await pumpWith(tester, [for (var i = 0; i < 12; i++) p('id$i', 'Profile $i')]);
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
      double offset() => tester.state<ScrollableState>(list).position.pixels;
      final scrolled = offset();
      expect(scrolled, greaterThan(400));
      final visible = copyRow('id5');
      await tester.ensureVisible(visible);
      await tester.pumpAndSettle();
      final before = offset();

      await select(tester, 'id5');
      expect(offset(), before);
      await tester.tap(endButton);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);
      expect(offset(), before);
    });

    testWidgets('selection rows announce whether a tap selects or deselects', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')]);
      await select(tester, 'a1');
      // ReorderableListView adds its own move actions, so the tap hint is checked on its own.
      List<String?> hints(String id) => [
        for (final action in tester.getSemantics(selectRow(id)).getSemanticsData().customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(action)?.hint,
      ];
      expect(hints('a1'), contains('Deselect'));
      expect(hints('b2'), contains('Select'));
      handle.dispose();
    });

    testWidgets('dragging a row moves only that row, even with several selected', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      final store = await pumpWith(tester, [for (final id in ids) p(id, 'Profile $id')]);
      await select(tester, 'a');
      for (final id in ['c', 'e']) {
        await tester.tap(selectRow(id));
        await tester.pumpAndSettle();
      }
      await dragDown(tester, 'c', rows: 2);
      expect([for (final p in await store.loadAll()) p.id], ['a', 'b', 'd', 'e', 'c', 'f']);
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('a plain drag scrolls the list and does not reorder', (tester) async {
      final profiles = [for (var i = 0; i < 12; i++) p('id$i', 'Profile $i')];
      final store = await pumpWith(tester, profiles);
      await select(tester, 'id0');
      final before = tester.getTopLeft(selectRow('id2')).dy;

      await tester.drag(selectRow('id2'), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(selectRow('id2')).dy, lessThan(before - 100));
      await tester.fling(find.byType(ReorderableListView), const Offset(0, -400), 1000);
      await tester.pumpAndSettle();

      expect((await store.loadAll()).map((p) => p.id), [for (final p in profiles) p.id]);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('a failed save says so and puts the rows back', (tester) async {
      final backend = _FailingWritesBackend();
      final store = await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home')], backend: backend);
      await select(tester, 'a1');
      backend.failWrites = true;

      await dragDown(tester, 'a1');

      expect(find.text('Could not save changes'), findsOneWidget);
      expect(shownNames(tester), ['Work', 'Home']);
      expect((await store.loadAll()).map((p) => p.id), ['a1', 'b2']);
    });

    testWidgets('a second drag made while the first is saving survives the first one failing', (tester) async {
      final backend = _FailingWritesBackend();
      final store = await pumpWith(tester, [p('a1', 'Work'), p('b2', 'Home'), p('c3', 'Lab')], backend: backend);
      await select(tester, 'a1');
      final firstWrite = Completer<void>();
      backend.failNextAfter = firstWrite;

      await dragDown(tester, 'a1');
      expect(shownNames(tester), ['Home', 'Work', 'Lab']);
      await dragDown(tester, 'c3', rows: -1);
      expect(shownNames(tester), ['Home', 'Lab', 'Work']);

      firstWrite.complete();
      await tester.pumpAndSettle();

      expect(find.text('Could not save changes'), findsOneWidget);
      final stored = (await store.loadAll()).map((p) => p.name).toList();
      expect(stored, ['Home', 'Lab', 'Work'], reason: 'the second save went through');
      expect(shownNames(tester), stored, reason: 'the rows match what was saved, not the order before both drags');
    });
  });
}

class _FailingWritesBackend extends MemoryKeyValueBackend {
  bool failWrites = false;

  /// Makes just the next write wait for this, then fail.
  Completer<void>? failNextAfter;

  @override
  Future<void> write(String key, String value) async {
    if (failNextAfter case final wait?) {
      failNextAfter = null;
      await wait.future;
      throw StateError('write failed');
    }
    if (failWrites) throw StateError('write failed');
    await super.write(key, value);
  }
}
