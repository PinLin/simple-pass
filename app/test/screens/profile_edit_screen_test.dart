import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/l10n/app_locale.dart';
import 'package:simple_pass/mobilepass/mobilepass.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/platform/sensitive_clipboard.dart';
import 'package:simple_pass/screens/profile_edit_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';
const _otherCode = 'WMPX4-TD2BV-QZM7C-QX4J4';

TextField _innerField(WidgetTester tester, String label) => tester.widget<TextField>(
  find.descendant(
    of: label == 'PIN' ? find.byKey(const ValueKey('pinField')) : find.widgetWithText(TextFormField, label),
    matching: find.byType(TextField),
  ),
);

Future<void> _fillRequired(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
  await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), _code);
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

/// The app bar's back button: leaving goes through the "Unsaved changes" check.
Future<void> _goBack(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// New profiles follow the app-wide setting, so it is set before the screen opens.
Future<void> _requireAuth(SettingsStore store, bool value) => store.save(Settings(requireAuth: value));

void main() {
  late MemoryKeyValueBackend backend;
  late FakeKeystore keystore;
  late ProfileStore store;
  late SettingsStore settingsStore;
  late List<MethodCall> clipboardCalls;
  // What the screen popped with; null until it pops.
  late List<Object?> popped;

  setUp(() {
    backend = MemoryKeyValueBackend();
    keystore = FakeKeystore();
    store = ProfileStore(backend, keystore: keystore);
    settingsStore = SettingsStore(MemoryKeyValueBackend());
    popped = [];
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

  /// Pushes the screen behind an "open" button so Save/Cancel have a route
  /// to pop back to.
  Future<void> open(
    WidgetTester tester, {
    Profile? profile,
    ProfileKind kind = ProfileKind.activationCode,
    Uint8List Function()? generateSeed,
  }) async {
    // Phone-like height, so a snackbar doesn't cover the buttons at the end of the form.
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: appSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => popped.add(
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileEditScreen(
                        profileStore: store,
                        settingsStore: settingsStore,
                        profile: profile,
                        kind: kind,
                        generateSeed: generateSeed ?? generateActivationSeed,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('default selection menu', () {
    Future<EditableTextState> selectAllInCodeField(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), _code);
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(
        find.descendant(of: find.widgetWithText(TextFormField, 'Activation Code'), matching: find.byType(EditableText)),
      );
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(selection: TextSelection(baseOffset: 0, extentOffset: _code.length)),
        SelectionChangedCause.tap,
      );
      state.showToolbar();
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('fields use Flutter\'s own menu: cut, copy, paste, select all', (tester) async {
      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        if (call.method == 'Clipboard.hasStrings') return {'value': true};
        if (call.method == 'Clipboard.getData') return {'text': 'x'};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await open(tester);
      final state = await selectAllInCodeField(tester);
      final types = state.contextMenuButtonItems.map((i) => i.type).toList();
      expect(types, containsAll([ContextMenuButtonType.cut, ContextMenuButtonType.copy, ContextMenuButtonType.paste]));
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(platformCalls.where((c) => c.method == 'Clipboard.setData').single.arguments, {'text': _code});
      expect(clipboardCalls, isEmpty);
    });
  });

  group('secret field selection', () {
    const link =
        'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=Example&period=30';

    testWidgets('a chosen range survives rebuilds from the field listener', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      final field = find.byKey(const ValueKey('secretField'));
      expect(field, findsOneWidget);
      await tester.enterText(field, link);
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)));
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(selection: const TextSelection(baseOffset: 10, extentOffset: 30)),
        SelectionChangedCause.drag,
      );
      await tester.pumpAndSettle();
      expect(state.textEditingValue.selection, const TextSelection(baseOffset: 10, extentOffset: 30));
    });

    testWidgets('a tap in the middle puts a collapsed cursor there and rebuilds keep it', (tester) async {
      await open(tester, kind: ProfileKind.totp);
      final field = find.byKey(const ValueKey('secretField'));
      await tester.enterText(field, link);
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)));
      final target = state.renderEditable.localToGlobal(
        state.renderEditable.getLocalRectForCaret(const TextPosition(offset: 95)).center,
      );
      await tester.tapAt(target);
      await tester.pumpAndSettle();
      final sel = state.textEditingValue.selection;
      expect(sel.isCollapsed, isTrue);
      expect((sel.baseOffset - 95).abs(), lessThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 1));
      expect(state.textEditingValue.selection, sel);
    });
  });

  group('add', () {
    testWidgets('activation code field keeps the IME from learning or suggesting the code', (tester) async {
      await open(tester);
      final field = _innerField(tester, 'Activation Code');
      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.keyboardType, TextInputType.visiblePassword);
      expect(field.obscureText, isFalse);
    });

    testWidgets('PIN field keeps the IME from learning or suggesting the PIN and uses a number keyboard', (
      tester,
    ) async {
      await open(tester);
      final field = _innerField(tester, 'PIN');
      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.keyboardType, TextInputType.number);
      expect(field.obscureText, isFalse);
    });

    testWidgets('rejects an empty name', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), _code);
      await _tapSave(tester);
      expect(find.text('Name is required'), findsOneWidget);
      expect(backend.writeCount, 0);
    });

    testWidgets('rejects an invalid activation code', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'not-a-code');
      await _tapSave(tester);
      expect(find.text('Invalid Activation Code'), findsOneWidget);
    });

    testWidgets('a new profile has no counter field and starts at 0', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('counterField')), findsNothing);
    });

    for (final input in ['12a4', '12345678901234567', '123']) {
      testWidgets('rejects PIN "$input"', (tester) async {
        await open(tester);
        await _fillRequired(tester);
        await tester.enterText(find.byKey(const ValueKey('pinField')), input);
        await _tapSave(tester);
        expect(find.text('PIN must be 4–16 digits'), findsOneWidget);
        expect(popped, isEmpty);
        expect(backend.writeCount, 0);
      });
    }

    testWidgets('saving stores a normalized profile without a PIN by default and pops true', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), ' Work VPN ');
      // Zero-width characters from a copied code are stripped.
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'apscg​ykkaunezgcprdsm');
      await _tapSave(tester);

      expect(popped, [true]);
      final saved = (await store.loadAll()).single;
      expect(saved.name, 'Work VPN');
      expect(saved.activationCode, _code);
      expect(saved.counter, 0);
      expect(saved.pin, isEmpty);
      expect(saved.appendPinOnCopy, isFalse);
      expect(saved.protected, isFalse);
      expect(keystore.authenticateCalls, 0);
    });

    testWidgets('saving with a PIN and the append switch on stores both', (tester) async {
      await open(tester);
      await _fillRequired(tester);
      await tester.enterText(find.byKey(const ValueKey('pinField')), '1234');
      await tester.ensureVisible(find.text('Append PIN when copying'));
      await tester.tap(find.text('Append PIN when copying'));
      await tester.pump();
      await _tapSave(tester);

      final saved = (await store.loadAll()).single;
      expect(saved.pin, '1234');
      expect(saved.appendPinOnCopy, isTrue);
    });

    testWidgets('there is no per-profile protection switch', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('protectedSwitch')), findsNothing);
      expect(find.text('Require authentication to use'), findsNothing);
    });

    testWidgets('with app-wide protection on, a new profile is sealed after one authentication', (tester) async {
      await _requireAuth(settingsStore, true);
      await open(tester);
      await _fillRequired(tester);
      await _tapSave(tester);

      expect(keystore.authenticateCalls, 1);
      expect(popped, [true]);
      expect(backend.rawValue(ProfileStore.storageKey), isNot(contains(_code)));
      expect((await store.loadAll()).single.protected, isTrue);
    });

    testWidgets('with app-wide protection off or not decided, a new profile is stored in the clear', (tester) async {
      for (final value in [false, null]) {
        backend = MemoryKeyValueBackend();
        store = ProfileStore(backend, keystore: keystore);
        settingsStore = SettingsStore(MemoryKeyValueBackend());
        if (value != null) await _requireAuth(settingsStore, value);
        await open(tester);
        await _fillRequired(tester);
        await _tapSave(tester);
        expect((await store.loadAll()).single.protected, isFalse, reason: 'requireAuth $value');
        expect(backend.rawValue(ProfileStore.storageKey), contains(_code));
      }
      expect(keystore.authenticateCalls, 0);
    });

    testWidgets('an unreadable settings store counts as protection on, so nothing is saved in the clear', (
      tester,
    ) async {
      settingsStore = SettingsStore(_BrokenBackend());
      await open(tester);
      await _fillRequired(tester);
      await _tapSave(tester);
      expect((await store.loadAll()).single.protected, isTrue);
      expect(backend.rawValue(ProfileStore.storageKey), isNot(contains(_code)));
      expect(keystore.authenticateCalls, 1);
      expect(popped, [true]);
    });

    testWidgets('a canceled prompt writes nothing and stays on the page; saving again retries', (tester) async {
      await _requireAuth(settingsStore, true);
      await open(tester);
      keystore.authResults.add(AuthResult.canceled);
      await _fillRequired(tester);
      await _tapSave(tester);

      expect(find.text('Authentication canceled'), findsOneWidget);
      expect(find.byType(ProfileEditScreen), findsOneWidget);
      expect(popped, isEmpty);
      expect(await store.loadAll(), isEmpty);
      await _tapSave(tester);
      expect(popped, [true]);
      expect(keystore.authenticateCalls, 2);
    });

    testWidgets('adding while a dead key still seals another profile explains and offers deleting it first', (
      tester,
    ) async {
      await store.saveAll([Profile(id: 'old', name: 'Old', activationCode: _otherCode, counter: 0)]);
      await store.updateProfile('old', (p) => p.copyWith(protected: true));
      store.forget();
      keystore.invalidate();
      await _requireAuth(settingsStore, true);
      await open(tester);
      await _fillRequired(tester);
      await _tapSave(tester);
      expect(find.textContaining('screen lock was removed'), findsOneWidget);
      expect(popped, isEmpty);

      await tester.tap(find.text('Delete these profiles'));
      await tester.pumpAndSettle();
      await _tapSave(tester);
      expect(popped, [true]);
      expect((await store.loadAll()).map((p) => (p.name, p.protected)), [('Work', true)]);
    });

    testWidgets('back with something typed asks; Discard writes nothing', (tester) async {
      await open(tester);
      await _fillRequired(tester);
      await _goBack(tester);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await _answer(tester, 'discardChangesButton');
      expect(popped, [null]);
      expect(backend.writeCount, 0);
    });

    testWidgets('an unreadable store: Save says so, writes nothing and stays open', (tester) async {
      await open(tester);
      backend.seedRaw(ProfileStore.storageKey, '{not json');
      await _fillRequired(tester);
      await _tapSave(tester);
      expect(find.text('Could not save changes'), findsOneWidget);
      expect(find.byType(ProfileEditScreen), findsOneWidget);
      expect(backend.rawValue(ProfileStore.storageKey), '{not json');
    });
  });

  group('add: policy and activation code input', () {
    Finder codeField() =>
        find.descendant(of: find.byKey(const ValueKey('activationCodeField')), matching: find.byType(TextField));
    TextEditingValue codeValue(WidgetTester tester) => tester.widget<TextField>(codeField()).controller!.value;

    // Sends what the platform would after an edit, so the field's formatter sees it.
    Future<void> send(WidgetTester tester, String text, int cursor) async {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: cursor),
        ),
      );
      await tester.pump();
    }

    Future<void> clearCode(WidgetTester tester) async {
      await tester.showKeyboard(codeField());
      await send(tester, '', 0);
    }

    Future<void> typeKeys(WidgetTester tester, String keys) async {
      for (final key in keys.split('')) {
        final v = codeValue(tester);
        final at = v.selection.start;
        await send(tester, v.text.replaceRange(at, v.selection.end, key), at + 1);
      }
    }

    Future<void> backspace(WidgetTester tester) async {
      final v = codeValue(tester);
      final at = v.selection.baseOffset;
      await send(tester, v.text.replaceRange(at - 1, at, ''), at - 1);
    }

    testWidgets('policy field is labelled optional and has no placeholder', (tester) async {
      await open(tester);
      final policy = tester.widget<TextField>(
        find.descendant(of: find.byKey(const ValueKey('policyField')), matching: find.byType(TextField)),
      );
      expect(policy.decoration!.labelText, 'Policy String (optional)');
      expect(policy.decoration!.hintText, isNull);
    });

    testWidgets('activation code placeholder uses X throughout', (tester) async {
      await open(tester);
      expect(tester.widget<TextField>(codeField()).decoration!.hintText, 'XXXXX-XXXXX-XXXXX-XXXXX');
    });

    testWidgets('a: typing adds the hyphen only with the sixth character', (tester) async {
      await open(tester);
      await clearCode(tester);
      await typeKeys(tester, 'abcde');
      expect(codeValue(tester).text, 'ABCDE');
      expect(codeValue(tester).selection, const TextSelection.collapsed(offset: 5));
      await typeKeys(tester, 'f');
      expect(codeValue(tester).text, 'ABCDE-F');
      expect(codeValue(tester).selection, const TextSelection.collapsed(offset: 7));
    });

    testWidgets('b: backspace right after a hyphen deletes the character before it', (tester) async {
      await open(tester);
      await clearCode(tester);
      await typeKeys(tester, 'abcdefghij');
      await send(tester, 'ABCDE-FGHIJ', 6);
      await backspace(tester);
      expect(codeValue(tester).text, 'ABCDF-GHIJ');
      expect(codeValue(tester).selection, const TextSelection.collapsed(offset: 4));
    });

    testWidgets('a/b: backspacing from the end never sticks on a hyphen', (tester) async {
      await open(tester);
      await clearCode(tester);
      await typeKeys(tester, 'apscgykkaunezgcprdsm');
      expect(codeValue(tester).text, _code);
      for (var left = 19; left >= 0; left--) {
        await backspace(tester);
        expect(codeValue(tester).text, normalizeActivationCode('APSCGYKKAUNEZGCPRDSM'.substring(0, left)));
      }
    });

    testWidgets('c: inserting in the middle regroups the rest and keeps the cursor after the new character', (
      tester,
    ) async {
      await open(tester);
      await clearCode(tester);
      await typeKeys(tester, 'abcdefghij');
      await send(tester, 'ABCDE-FGHIJ', 2);
      await typeKeys(tester, 'x');
      expect(codeValue(tester).text, 'ABXCD-EFGHI-J');
      expect(codeValue(tester).selection, const TextSelection.collapsed(offset: 3));
    });

    testWidgets('d: pasting a messy code groups it with the cursor at the end, and saves as before', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
      await tester.enterText(codeField(), 'ａｐｓｃｇ－ykkau nezgc-prdsm');
      expect(codeValue(tester).text, _code);
      expect(codeValue(tester).selection, const TextSelection.collapsed(offset: 23));
      await _tapSave(tester);
      expect((await store.loadAll()).single.activationCode, _code);
    });

    testWidgets('e: replacing a selection across a hyphen', (tester) async {
      await open(tester);
      await clearCode(tester);
      await typeKeys(tester, 'abcdefghij');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'ABCDE-FGHIJ', selection: TextSelection(baseOffset: 3, extentOffset: 8)),
      );
      await tester.pump();
      await typeKeys(tester, 'x');
      expect(codeValue(tester).text, 'ABCXH-IJ');
      expect(codeValue(tester).selection, const TextSelection.collapsed(offset: 4));
    });

    testWidgets('f: composing text is left alone until it is committed', (tester) async {
      await open(tester);
      await clearCode(tester);
      await typeKeys(tester, 'abcde');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ABCDEf',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 5, end: 6),
        ),
      );
      await tester.pump();
      expect(codeValue(tester).text, 'ABCDEf');
      await send(tester, 'ABCDEf', 6);
      expect(codeValue(tester).text, 'ABCDE-F');
    });

    testWidgets('formatting carries on with the code hidden', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('toggleActivationCodeVisibility')));
      await tester.pump();
      expect(tester.widget<TextField>(codeField()).obscureText, isTrue);
      await clearCode(tester);
      await typeKeys(tester, 'abcdef');
      expect(codeValue(tester).text, 'ABCDE-F');
    });
  });

  group('edit', () {
    final work = Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5, pin: '1234');

    setUp(() async => store.saveAll([work]));

    testWidgets('shows the current values in plain text with the add-form protections', (tester) async {
      await open(tester, profile: work);
      expect(find.text('HOTP profile'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.byKey(const ValueKey('activationCodeField')), findsNothing);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('1234'), findsOneWidget);
      expect(find.byKey(const ValueKey('protectedSwitch')), findsNothing);
    });

    testWidgets('Save applies every editable field and keeps the code', (tester) async {
      await open(tester, profile: work);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await tester.enterText(find.widgetWithText(TextFormField, 'Counter'), '9');
      await tester.enterText(find.byKey(const ValueKey('pinField')), '');
      await _tapSave(tester);

      expect(popped, [true]);
      final saved = (await store.loadAll()).single;
      expect(saved.name, 'Office');
      expect(saved.activationCode, _code);
      expect(saved.counter, 9);
      expect(saved.pin, isEmpty);
    });

    testWidgets('an HOTP profile shows its counter field', (tester) async {
      await open(tester, profile: work);
      expect(find.byKey(const ValueKey('counterField')), findsOneWidget);
    });

    for (final input in ['-1', '0x10', '+5', '1e3']) {
      testWidgets('rejects counter "$input"', (tester) async {
        await open(tester, profile: work);
        await tester.enterText(find.widgetWithText(TextFormField, 'Counter'), input);
        await _tapSave(tester);
        expect(find.text('Counter must be a non-negative integer'), findsOneWidget);
      });
    }

    testWidgets('rejects a counter above 2^53-1 with a limit message', (tester) async {
      await open(tester, profile: work);
      await tester.enterText(find.widgetWithText(TextFormField, 'Counter'), '9007199254740992');
      await _tapSave(tester);
      expect(find.text('Counter cannot exceed 9007199254740991'), findsOneWidget);
    });

    testWidgets('accepts the largest counter', (tester) async {
      await open(tester, profile: work);
      await tester.enterText(find.widgetWithText(TextFormField, 'Counter'), '9007199254740991');
      await _tapSave(tester);
      expect((await store.loadAll()).single.counter, maxCounter);
    });

    testWidgets('an untouched counter keeps a ✓ that landed after the page opened', (tester) async {
      await open(tester, profile: work);
      await store.updateProfile('a1', (p) => p.copyWith(counter: 6));
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _tapSave(tester);
      final saved = (await store.loadAll()).single;
      expect((saved.name, saved.counter), ('Office', 6));
    });

    testWidgets('back + Discard leaves the stored profile alone', (tester) async {
      await open(tester, profile: work);
      final writes = backend.writeCount;
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _goBack(tester);
      await _answer(tester, 'discardChangesButton');
      expect(popped, [null]);
      expect(backend.writeCount, writes);
      expect((await store.loadAll()).single.name, 'Work');
    });

    testWidgets('validation errors keep the page open and write nothing', (tester) async {
      await open(tester, profile: work);
      final writes = backend.writeCount;
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), ' ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Counter'), 'x');
      await _tapSave(tester);
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Counter must be a non-negative integer'), findsOneWidget);
      expect(popped, isEmpty);
      expect(backend.writeCount, writes);
    });

    testWidgets('plain edits of an unprotected profile never prompt', (tester) async {
      await open(tester, profile: work);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _tapSave(tester);
      expect(keystore.authenticateCalls, 0);
    });

    testWidgets('editing a sealed profile once the window ran out asks again; a canceled prompt changes nothing', (
      tester,
    ) async {
      await store.updateProfile('a1', (p) => p.copyWith(protected: true));
      final unlocked = (await store.loadAll()).single;
      keystore
        ..expire()
        ..authenticateCalls = 0;
      await open(tester, profile: unlocked);
      final before = backend.rawValue(ProfileStore.storageKey);
      keystore.authResults.add(AuthResult.canceled);
      await tester.enterText(find.byKey(const ValueKey('pinField')), '5678');
      await _tapSave(tester);

      expect(find.text('Authentication canceled'), findsOneWidget);
      expect(find.byType(ProfileEditScreen), findsOneWidget);
      expect(backend.rawValue(ProfileStore.storageKey), before);
      // The edits are still in the form; saving again prompts again and goes through.
      await _tapSave(tester);
      expect(popped, [true]);
      expect(keystore.authenticateCalls, 2);
      final saved = (await store.loadAll()).single;
      expect((saved.protected, saved.pin), (true, '5678'));
      expect(backend.rawValue(ProfileStore.storageKey), isNot(contains('5678')));
    });

    testWidgets('an unprotected profile stays unprotected even when app-wide protection is on', (tester) async {
      await _requireAuth(settingsStore, true);
      await open(tester, profile: work);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _tapSave(tester);
      expect(keystore.authenticateCalls, 0);
      expect((await store.loadAll()).single.protected, isFalse);
    });
  });

  group('edit with an invalidated key', () {
    testWidgets('deleting the unrecoverable profiles closes the editor of one of them', (tester) async {
      await store.saveAll([
        Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 0),
        Profile(id: 'b2', name: 'Home', activationCode: _otherCode, counter: 0),
      ]);
      await store.updateProfile('a1', (p) => p.copyWith(protected: true));
      await store.updateProfile('b2', (p) => p.copyWith(protected: true));
      final unlocked = (await store.loadAll()).first;
      keystore.invalidate();
      await open(tester, profile: unlocked);
      await tester.enterText(find.byKey(const ValueKey('pinField')), '5678');
      await _tapSave(tester);
      expect(find.textContaining('screen lock was removed'), findsOneWidget);

      await tester.tap(find.text('Delete these profiles'));
      await tester.pumpAndSettle();
      expect(popped, [true]);
      expect(await store.loadAll(), isEmpty);
    });
  });

  group('activation code prefill and policy', () {
    final seed = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01, 0x23]);
    const legacy = 'AERUV-KZ4JD-VPG6D-6AJDG';
    const versioned = 'AERUK-Z4JVP-G66AJ-DBACL';

    String codeText(WidgetTester tester) => _innerField(tester, 'Activation Code').controller!.text;

    Future<void> enterPolicy(WidgetTester tester, String policy) async {
      await tester.enterText(find.byKey(const ValueKey('policyField')), policy);
      await tester.pump();
    }

    testWidgets('a new profile starts with a valid generated code and saves as is', (tester) async {
      await open(tester);
      final prefilled = codeText(tester);
      expect(isValidActivationCode(prefilled), isTrue);
      expect(decodeActivationCode(prefilled)!.format, ActivationCodeFormat.legacy);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
      await _tapSave(tester);
      expect(popped, [true]);
      final saved = (await store.loadAll()).single;
      expect((saved.activationCode, saved.policy, saved.counter), (prefilled, '', 0));
    });

    testWidgets('the prefilled code comes from the injected seed', (tester) async {
      await open(tester, generateSeed: () => seed);
      expect(codeText(tester), encodeLegacyActivationCode(seed));
      expect(codeText(tester), legacy);
    });

    testWidgets('a wrong check character is rejected and nothing is saved', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'AAISK-EM2EJ-KVTHT-PCEZM');
      await _tapSave(tester);
      expect(find.text('Invalid Activation Code'), findsOneWidget);
      expect(popped, isEmpty);
      expect(backend.writeCount, 0);
    });

    testWidgets('a typed code is stored normalized and regrouped', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'aeruk z4jvp g66aj dbacl');
      await enterPolicy(tester, '75817049');
      await _tapSave(tester);
      expect((await store.loadAll()).single.activationCode, versioned);
    });

    testWidgets('a v2 policy switches an untouched prefill to the versioned layout and back', (tester) async {
      await open(tester, generateSeed: () => seed);
      await enterPolicy(tester, '75817049');
      expect(codeText(tester), versioned);
      await enterPolicy(tester, '');
      expect(codeText(tester), legacy);
    });

    testWidgets('a code the user typed is not replaced when the policy changes', (tester) async {
      await open(tester, generateSeed: () => seed);
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'APSCG-YKKAU-NEZGC-PRDSM');
      await enterPolicy(tester, '75817049');
      expect(codeText(tester), 'APSCG-YKKAU-NEZGC-PRDSM');
    });

    testWidgets('regenerate replaces the code and follows the policy again', (tester) async {
      var calls = 0;
      await open(tester, generateSeed: () => calls++ == 0 ? Uint8List(10) : seed);
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'APSCG-YKKAU-NEZGC-PRDSM');
      await enterPolicy(tester, '75817049');
      await tester.tap(find.byKey(const ValueKey('regenerateActivationCodeButton')));
      await tester.pump();
      expect(codeText(tester), versioned);
      await enterPolicy(tester, '');
      expect(codeText(tester), legacy);
    });

    testWidgets('editing has a copy button but no regenerate button', (tester) async {
      await open(
        tester,
        profile: Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 0),
      );
      expect(find.byKey(const ValueKey('regenerateActivationCodeButton')), findsNothing);
      await openRegistrationInfo(tester);
      expect(find.byKey(const ValueKey('copyActivationCodeButton')), findsOneWidget);
    });

    testWidgets('copy puts the normalized code on the clipboard as sensitive and clears it later', (tester) async {
      await settingsStore.save(const Settings(clipboardClear: ClipboardClear.thirtySeconds));
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), 'apscg ykkaunezgcprdsm');
      await tester.tap(find.byKey(const ValueKey('copyActivationCodeButton')));
      await tester.pump();
      expect(clipboardCalls.single.method, 'setText');
      expect(clipboardCalls.single.arguments, {'text': _code, 'sensitive': true});
      expect(find.text('Activation Code copied'), findsOneWidget);
      expect(SensitiveClipboard.instance.hasPendingClear, isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(clipboardCalls.last.method, 'clearIfMatches');
      await tester.pumpAndSettle();
    });

    testWidgets('editing copies the stored code', (tester) async {
      await open(
        tester,
        profile: Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 0),
      );
      await openRegistrationInfo(tester);
      await tester.tap(find.byKey(const ValueKey('copyActivationCodeButton')));
      await tester.pumpAndSettle();
      expect(clipboardCalls.first.arguments, {'text': _code, 'sensitive': true});
      expect(find.text('Activation Code copied'), findsOneWidget);
      // Lets the default one-minute clear run.
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
    });

    for (final (policy, message) in [
      ('75817048', 'Invalid Policy String'),
      ('abc', 'Invalid Policy String'),
      // Version 3, mode 0.
      ('19922962', "This Policy String version isn't supported"),
      // Version 2, mode 3.
      ('152567810', "This Policy String's passcode type isn't supported"),
    ]) {
      testWidgets('policy "$policy" shows "$message" and saves nothing', (tester) async {
        await open(tester);
        await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
        await enterPolicy(tester, policy);
        await _tapSave(tester);
        expect(find.text(message), findsOneWidget);
        expect(backend.writeCount, 0);
      });
    }

    testWidgets('a time-based policy is saved trimmed', (tester) async {
      await open(tester, generateSeed: () => seed);
      expect(find.byKey(const ValueKey('counterField')), findsNothing);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Cloud');
      await enterPolicy(tester, ' 75817049 ');
      expect(find.byKey(const ValueKey('counterField')), findsNothing);
      await _tapSave(tester);
      final saved = (await store.loadAll()).single;
      expect((saved.policy, saved.activationCode, saved.isTimeBased), ('75817049', versioned, true));
    });

    for (final policy in ['38039554', '9439']) {
      testWidgets('a challenge-response policy ($policy) hides the counter and saves', (tester) async {
        await open(tester, generateSeed: () => seed);
        await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Portal');
        await enterPolicy(tester, policy);
        expect(find.byKey(const ValueKey('counterField')), findsNothing);
        expect(find.byKey(const ValueKey('pinField')), findsOneWidget);
        await _tapSave(tester);
        final saved = (await store.loadAll()).single;
        expect((saved.policy, saved.activationCode, saved.isChallengeResponse), (policy, versioned, true));
      });
    }

    testWidgets('a format that does not match the policy version blocks saving', (tester) async {
      const mismatch = "This Activation Code's format doesn't match the Policy String version";
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), legacy);
      await enterPolicy(tester, '75817049');
      await _tapSave(tester);
      expect(find.text(mismatch), findsOneWidget);
      expect(popped, isEmpty);
      await enterPolicy(tester, '');
      await _tapSave(tester);
      expect(find.text(mismatch), findsNothing);
      expect(popped, [true]);
    });

    testWidgets('a versioned code with a blank policy blocks saving', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Work');
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), versioned);
      await _tapSave(tester);
      expect(find.text("This Activation Code's format doesn't match the Policy String version"), findsOneWidget);
      expect(popped, isEmpty);
    });

    testWidgets('an existing mismatched profile can still be renamed', (tester) async {
      final old = Profile(id: 'a1', name: 'Work', activationCode: legacy, counter: 2, policy: '75817049');
      await store.saveAll([old]);
      await open(tester, profile: old);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _tapSave(tester);
      expect(popped, [true]);
    });

    testWidgets('an existing code without valid check characters can be kept while editing', (tester) async {
      final old = Profile(id: 'a1', name: 'Work', activationCode: _otherCode, counter: 2);
      await store.saveAll([old]);
      await open(tester, profile: old);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _tapSave(tester);
      expect(popped, [true]);
      final saved = (await store.loadAll()).single;
      expect((saved.name, saved.activationCode), ('Office', _otherCode));
    });

    testWidgets('editing shows the code and policy read-only and saves them unchanged', (tester) async {
      final old = Profile(id: 'a1', name: 'Work', activationCode: versioned, counter: 2, policy: '75817049');
      await store.saveAll([old]);
      await open(tester, profile: old);
      await openRegistrationInfo(tester);
      expect(_innerField(tester, 'Activation Code').readOnly, isTrue);
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: find.byKey(const ValueKey('policyField')), matching: find.byType(TextField)),
            )
            .readOnly,
        isTrue,
      );
      await closeProfileInfo(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _tapSave(tester);
      final saved = (await store.loadAll()).single;
      expect((saved.name, saved.activationCode, saved.policy), ('Office', versioned, '75817049'));
    });
  });
  group('leaving with unsaved changes', () {
    final work = Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5, pin: '1234');

    testWidgets('there is no Cancel button, only Save', (tester) async {
      await open(tester);
      expect(find.text('Cancel'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    });

    testWidgets('an untouched new profile (only the prefilled code) leaves without asking', (tester) async {
      await open(tester);
      await _goBack(tester);
      expect(find.text('Unsaved changes'), findsNothing);
      expect(popped, [null]);
    });

    testWidgets('regenerating the prefilled code is still untouched', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('regenerateActivationCodeButton')));
      await tester.pumpAndSettle();
      await _goBack(tester);
      expect(popped, [null]);
    });

    testWidgets('an Activation Code typed in counts as a change', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Activation Code'), _code);
      await _goBack(tester);
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    testWidgets('an existing profile without changes leaves without asking, also by system back', (tester) async {
      await store.saveAll([work]);
      await open(tester, profile: work);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsNothing);
      expect(popped, [null]);
    });

    for (final (label, edit) in [
      ('name', (WidgetTester t) => t.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office')),
      ('PIN', (WidgetTester t) => t.enterText(find.byKey(const ValueKey('pinField')), '987654')),
      ('counter', (WidgetTester t) => t.enterText(find.byKey(const ValueKey('counterField')), '9')),
    ]) {
      testWidgets('a changed $label asks by system back; Keep editing stays with the edit', (tester) async {
        await store.saveAll([work]);
        await open(tester, profile: work);
        await edit(tester);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        expect(find.text('Discard'), findsOneWidget);
        expect(find.text('Keep editing'), findsOneWidget);
        await _answer(tester, 'keepEditingButton');
        expect(find.byType(ProfileEditScreen), findsOneWidget);
        expect(popped, isEmpty);
      });
    }

    testWidgets('Discard in the dialog leaves without saving', (tester) async {
      await store.saveAll([work]);
      await open(tester, profile: work);
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Office');
      await _goBack(tester);
      await _answer(tester, 'discardChangesButton');
      expect(find.byType(ProfileEditScreen), findsNothing);
      expect((await store.loadAll()).single.name, 'Work');
    });

    group('"Append PIN when copying" on an existing profile', () {
      Finder appendSwitch() => find.widgetWithText(SwitchListTile, 'Append PIN when copying');

      testWidgets('saves as soon as it is switched, nothing else', (tester) async {
        await store.saveAll([work]);
        await open(tester, profile: work);
        await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Not saved');
        await tester.ensureVisible(appendSwitch());
        await tester.tap(appendSwitch());
        await tester.pumpAndSettle();
        final saved = (await store.loadAll()).single;
        expect(saved.appendPinOnCopy, isTrue);
        expect(saved.name, 'Work');
      });

      testWidgets('switching it and going back does not ask', (tester) async {
        await store.saveAll([work]);
        await open(tester, profile: work);
        await tester.ensureVisible(appendSwitch());
        await tester.tap(appendSwitch());
        await tester.pumpAndSettle();
        await _goBack(tester);
        expect(find.text('Unsaved changes'), findsNothing);
        expect(popped, [null]);
        expect((await store.loadAll()).single.appendPinOnCopy, isTrue);
      });

      testWidgets('a failed save puts the switch back and says so', (tester) async {
        await store.saveAll([work]);
        await open(tester, profile: work);
        backend.seedRaw(ProfileStore.storageKey, '{not json');
        await tester.ensureVisible(appendSwitch());
        await tester.tap(appendSwitch());
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(appendSwitch()).value, isFalse);
        expect(find.text('Could not save changes'), findsOneWidget);
      });

      testWidgets('on a new profile it is saved with the rest, and counts as a change', (tester) async {
        await open(tester);
        await tester.ensureVisible(appendSwitch());
        await tester.tap(appendSwitch());
        await tester.pumpAndSettle();
        expect(backend.writeCount, 0);
        await _goBack(tester);
        expect(find.text('Unsaved changes'), findsOneWidget);
      });
    });
  });
}

class _BrokenBackend extends MemoryKeyValueBackend {
  @override
  Future<String?> read(String key) async => throw PlatformException(code: 'decrypt', message: 'bad key');
}
