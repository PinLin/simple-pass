import 'package:flutter/material.dart';

import 'platform/system_cjk_font.dart';

const Color brandOrange = Color(0xFFE47404);

final ColorScheme _scheme = ColorScheme.fromSeed(
  seedColor: brandOrange,
  brightness: Brightness.dark,
).copyWith(primary: brandOrange, onPrimary: const Color(0xFF1B1B1B));

final ThemeData appDarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: _scheme,
  // Ignored until loadSystemCjkFont registers it.
  fontFamilyFallback: const [systemCjkFontFamily],
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: _scheme.primary,
    foregroundColor: _scheme.onPrimary,
  ),
  // Floating snackbars sit above the FAB instead of shoving it up.
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    dismissDirection: DismissDirection.horizontal,
  ),
);
