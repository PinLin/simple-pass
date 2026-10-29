import 'package:flutter/material.dart';

/// The app's snackbar: tapping the message dismisses it (swiping is set in
/// the theme). The action sits outside the tap area, so it still runs.
SnackBar appSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) => SnackBar(
  content: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: messenger.hideCurrentSnackBar,
    child: SizedBox(width: double.infinity, child: Text(message)),
  ),
  action: action,
  duration: duration,
  persist: false,
);
