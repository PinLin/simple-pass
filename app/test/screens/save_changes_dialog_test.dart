import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/screens/otp_helpers.dart';

import '../test_helpers.dart';

void main() {
  Finder button(String key) => find.byKey(ValueKey(key));
  UnsavedChoice? result;

  Future<void> open(WidgetTester tester, {double scale = 1, Locale? locale}) async {
    result = null;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpLocalized(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await askAboutUnsavedChanges(context),
            child: const Text('open'),
          ),
        ),
      ),
      locale: locale ?? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('zh title', (tester) async {
    await open(tester);
    expect(find.text('有未儲存的內容'), findsOneWidget);
  });

  testWidgets('en title', (tester) async {
    await open(tester, locale: const Locale('en'));
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('two buttons: discard on the left, keep editing filled on the right', (tester) async {
    await open(tester);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
      findsNWidgets(2),
    );
    expect(tester.widget(button('keepEditingButton')), isA<FilledButton>());
    expect(tester.widget(button('discardChangesButton')), isA<TextButton>());
    expect(find.descendant(of: button('keepEditingButton'), matching: find.text('繼續編輯')), findsOneWidget);
    final discard = tester.getRect(button('discardChangesButton'));
    final keep = tester.getRect(button('keepEditingButton'));
    expect(discard.right, lessThan(keep.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('discard returns discard', (tester) async {
    await open(tester);
    await tester.tap(button('discardChangesButton'));
    await tester.pumpAndSettle();
    expect(result, UnsavedChoice.discard);
  });

  testWidgets('keep editing returns keepEditing', (tester) async {
    await open(tester);
    await tester.tap(button('keepEditingButton'));
    await tester.pumpAndSettle();
    expect(result, UnsavedChoice.keepEditing);
  });

  testWidgets('tapping outside keeps editing', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, UnsavedChoice.keepEditing);
  });

  testWidgets('large text does not overflow', (tester) async {
    await open(tester, scale: 2);
    expect(tester.takeException(), isNull);
    expect(button('discardChangesButton'), findsOneWidget);
    expect(button('keepEditingButton'), findsOneWidget);
  });
}
