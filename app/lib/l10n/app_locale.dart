import 'package:flutter/widgets.dart';

/// zh_Hant_TW is listed on top of zh so Taiwan and Hant devices match it exactly; with plain zh alone
/// they resolve to zh and Material/Cupertino strings (paste, dismiss menu) come out Simplified.
const appSupportedLocales = [
  Locale('en'),
  Locale('zh'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
];
