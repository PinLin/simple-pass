import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'android_licenses.dart';
import 'app_theme.dart';
import 'l10n/app_locale.dart';
import 'l10n/gen/app_localizations.dart';
import 'platform/device_info.dart';
import 'platform/keystore.dart';
import 'platform/screen_guard.dart';
import 'platform/system_cjk_font.dart';
import 'screens/otp_helpers.dart';
import 'screens/profile_list_screen.dart';
import 'storage/profile_store.dart';
import 'storage/secure_key_value_backend.dart';
import 'storage/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAndroidLicenses();

  final backend = SecureKeyValueBackend();
  final profileStore = ProfileStore(backend, keystore: PlatformKeystore());
  final settingsStore = SettingsStore(backend);
  final screenGuard = ScreenGuard();

  await applyStartupSettings(settingsStore, profileStore, screenGuard);

  runApp(SimplePassApp(profileStore: profileStore, settingsStore: settingsStore, screenGuard: screenGuard));
  // Off the startup path: text relayouts by itself once the family is registered.
  if (Platform.isAndroid) unawaited(loadSystemCjkFont(PlatformDispatcher.instance.locales));
}

/// Applies window flags before the first frame; FLAG_SECURE stays on if settings can't be read.
Future<void> applyStartupSettings(
  SettingsStore settingsStore,
  ProfileStore profileStore,
  ScreenGuard screenGuard, {
  DeviceInfo deviceInfo = const DeviceInfo(),
}) async {
  var secure = true;
  try {
    final settings = await settingsStore.load();
    final anySealed = await profileStore.loadAll().then((all) => all.any((p) => p.protected), onError: (_) => true);
    secure = secureWindow(
      allowScreenshots: settings.allowScreenshots,
      appLock: appLockActive(requireAuth: settings.requireAuth, anySealed: anySealed),
      sdkInt: await deviceInfo.sdkInt(),
    );
  } catch (_) {
    // Stays secure.
  }
  await screenGuard.setSecure(secure);
  try {
    await screenGuard.setRecentsScreenshotEnabled(!(await profileStore.loadAll()).any((p) => p.protected));
  } catch (_) {
    await screenGuard.setRecentsScreenshotEnabled(false);
  }
}

class SimplePassApp extends StatelessWidget {
  const SimplePassApp({super.key, required this.profileStore, required this.settingsStore, required this.screenGuard});

  final ProfileStore profileStore;
  final SettingsStore settingsStore;
  final ScreenGuard screenGuard;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: appSupportedLocales,
      darkTheme: appDarkTheme,
      themeMode: ThemeMode.dark,
      home: ProfileListScreen(profileStore: profileStore, settingsStore: settingsStore, screenGuard: screenGuard),
    );
  }
}
