import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/app_theme.dart';
import 'package:simple_pass/l10n/app_locale.dart';
import 'package:simple_pass/l10n/gen/app_localizations.dart';

import 'flutter_test_config.dart' show cjkFontFamily;

/// Delegates every test's [MaterialApp] needs; the Global*Localizations ones initialize intl date
/// data, without which non-English dates throw.
const testLocalizationsDelegates = [
  ...AppLocalizations.localizationsDelegates,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// [appDarkTheme] with the test CJK font as glyph fallback, so zh text
/// renders as real characters instead of tofu boxes.
final ThemeData testTheme = appDarkTheme.copyWith(
  textTheme: appDarkTheme.textTheme.apply(fontFamilyFallback: const [cjkFontFamily]),
);

/// Pumps [child] in a localized [MaterialApp]; [locale] defaults to the harness's English.
Future<void> pumpLocalized(WidgetTester tester, Widget child, {Locale? locale}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: appSupportedLocales,
      theme: testTheme,
      home: child,
    ),
  );
}

Future<void> openRegistrationInfo(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('profileMenuButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('registrationInfoMenuItem')));
  await tester.pumpAndSettle();
}

/// Taps the menu's "Copy otpauth link" item; the link lands on the (mocked) sensitive clipboard.
Future<void> copyExportLink(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('profileMenuButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('copyOtpauthLinkButton')));
  await tester.pump();
}

/// Lets the clipboard auto-clear timer and the snackbar from a copy run out.
Future<void> settleCopy(WidgetTester tester) => tester.pumpAndSettle(const Duration(seconds: 61));

Future<void> closeProfileInfo(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('closeProfileInfoButton')));
  await tester.pumpAndSettle();
}
