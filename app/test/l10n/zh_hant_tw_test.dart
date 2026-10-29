import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/l10n/app_locale.dart';
import 'package:simple_pass/l10n/gen/app_localizations.dart';

import '../test_helpers.dart';

void main() {
  const hantTw = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');

  // Pumps the app's locale setup with [deviceLocale] as the system preference (Flutter's default
  // resolution) and returns a context below the resolved Localizations.
  Future<BuildContext> pumpWithDeviceLocale(WidgetTester tester, Locale deviceLocale) async {
    tester.platformDispatcher.localesTestValue = [deviceLocale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: appSupportedLocales,
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return capturedContext;
  }

  // (name, device locale, resolved locale, Material paste label, Material dismiss-menu label)
  for (final (name, device, resolved, paste, dismiss) in const [
    ('zh_TW', Locale('zh', 'TW'), hantTw, '貼上', '關閉選單'),
    ('zh_Hant_TW', hantTw, hantTw, '貼上', '關閉選單'),
    ('zh_Hant', Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), hantTw, '貼上', '關閉選單'),
    ('zh_Hant_HK', Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK'), hantTw, '貼上', '關閉選單'),
    ('zh_HK', Locale('zh', 'HK'), Locale('zh'), '粘贴', '关闭菜单'),
    ('zh_MO', Locale('zh', 'MO'), Locale('zh'), '粘贴', '关闭菜单'),
    ('zh_CN', Locale('zh', 'CN'), Locale('zh'), '粘贴', '关闭菜单'),
    (
      'zh_Hans_CN',
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
      Locale('zh'),
      '粘贴',
      '关闭菜单',
    ),
    ('zh', Locale('zh'), Locale('zh'), '粘贴', '关闭菜单'),
  ]) {
    testWidgets('$name device resolves to $resolved with the single Chinese app translation', (tester) async {
      final context = await pumpWithDeviceLocale(tester, device);

      expect(Localizations.localeOf(context), resolved);
      expect(AppLocalizations.of(context).settingsTitle, '設定');
      expect(AppLocalizations.of(context).notSetValue, '未設定');
      expect(MaterialLocalizations.of(context).pasteButtonLabel, paste);
      expect(MaterialLocalizations.of(context).menuDismissLabel, dismiss);
    });
  }

  testWidgets('a language the app does not ship falls back to English', (tester) async {
    final context = await pumpWithDeviceLocale(tester, const Locale('fr', 'FR'));

    expect(Localizations.localeOf(context), const Locale('en'));
    expect(AppLocalizations.of(context).settingsTitle, 'Settings');
    expect(MaterialLocalizations.of(context).pasteButtonLabel, 'Paste');
  });
}
