import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Result of asking the platform to clear the clipboard only if it still
/// holds what this app put there.
enum ClearResult {
  cleared,

  /// The user copied something else since; left alone.
  changed,

  /// The clipboard couldn't be read (Android 10+ denies reads to apps
  /// without window focus), so it's unknown whether it's still ours.
  unavailable,
}

/// Dart side of the `me.pinlin.simple_pass/clipboard` channel: copies as sensitive and clears later.
class SensitiveClipboard {
  SensitiveClipboard({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'me.pinlin.simple_pass/clipboard';

  static final SensitiveClipboard _default = SensitiveClipboard();

  @visibleForTesting
  static SensitiveClipboard? debugInstanceOverride;

  static SensitiveClipboard get instance => debugInstanceOverride ?? _default;

  /// Delay after regaining focus before retrying a clear that couldn't run while backgrounded.
  static const Duration resumeRetryDelay = Duration(seconds: 1);

  final MethodChannel _channel;
  Timer? _clearTimer;
  String? _pendingClear;
  AppLifecycleListener? _lifecycleListener;

  /// Copies [text] as sensitive. With [clearAfter], the clipboard is cleared
  /// once that much time has passed — but only if it still holds [text].
  Future<void> copy(String text, {Duration? clearAfter}) async {
    _cancelPendingClear();
    await _setText(text);
    if (clearAfter != null) {
      _pendingClear = text;
      _clearTimer = Timer(clearAfter, _tryClear);
    }
  }

  /// Clears the clipboard if it still holds [text], e.g. a secret the app just read from it.
  Future<void> clearIfMatches(String text) async {
    if (_pendingClear == text) _cancelPendingClear();
    await _clearIfMatches(text);
  }

  @visibleForTesting
  bool get hasPendingClear => _pendingClear != null;

  Future<void> _tryClear({bool afterResume = false}) async {
    _clearTimer = null;
    final text = _pendingClear;
    if (text == null) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      _retryOnResume();
      return;
    }
    final result = await _clearIfMatches(text);
    if (_pendingClear != text) return;
    // Still unreadable while focused means the clipboard is simply empty.
    if (result == ClearResult.unavailable && !afterResume) {
      _retryOnResume();
    } else {
      _cancelPendingClear();
    }
  }

  void _retryOnResume() {
    _lifecycleListener ??= AppLifecycleListener(
      onResume: () {
        _clearTimer?.cancel();
        _clearTimer = Timer(resumeRetryDelay, () => _tryClear(afterResume: true));
      },
    );
  }

  void _cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _pendingClear = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  Future<void> _setText(String text) => _channel.invokeMethod<void>('setText', {'text': text, 'sensitive': true});

  Future<ClearResult> _clearIfMatches(String text) async {
    final result = await _channel.invokeMethod<String>('clearIfMatches', {'text': text});
    return ClearResult.values.firstWhere((r) => r.name == result, orElse: () => ClearResult.unavailable);
  }
}
