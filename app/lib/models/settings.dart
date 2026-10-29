/// How long a copied code (with the PIN, if added) may stay on the
/// clipboard before the app tries to clear it.
enum ClipboardClear {
  never(0),
  thirtySeconds(30),
  oneMinute(60),
  twoMinutes(120),
  fiveMinutes(300);

  const ClipboardClear(this.seconds);

  final int seconds;

  Duration? get delay => seconds == 0 ? null : Duration(seconds: seconds);

  static ClipboardClear fromSeconds(int? seconds) => values.where((v) => v.seconds == seconds).firstOrNull ?? oneMinute;
}

/// App-wide settings, persisted as a single JSON blob. Protection is stored
/// with the profiles (see ProfileStore).
class Settings {
  const Settings({
    this.allowScreenshots = true,
    this.clipboardClear = ClipboardClear.oneMinute,
    this.tapToReveal = false,
    this.requireAuth,
  });

  final bool allowScreenshots;
  final ClipboardClear clipboardClear;

  /// Codes in the list stay masked until their row is tapped.
  final bool tapToReveal;

  /// Every profile is sealed behind authentication. Null until the user first chooses; reads as off.
  final bool? requireAuth;

  Settings copyWith({bool? allowScreenshots, ClipboardClear? clipboardClear, bool? tapToReveal, bool? requireAuth}) =>
      Settings(
        allowScreenshots: allowScreenshots ?? this.allowScreenshots,
        clipboardClear: clipboardClear ?? this.clipboardClear,
        tapToReveal: tapToReveal ?? this.tapToReveal,
        requireAuth: requireAuth ?? this.requireAuth,
      );

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    allowScreenshots: json['allowScreenshots'] as bool? ?? true,
    clipboardClear: ClipboardClear.fromSeconds(json['clipboardClearSeconds'] as int?),
    tapToReveal: json['tapToReveal'] == true,
    requireAuth: json['requireAuth'] is bool ? json['requireAuth'] as bool : null,
  );

  Map<String, dynamic> toJson() => {
    'allowScreenshots': allowScreenshots,
    'clipboardClearSeconds': clipboardClear.seconds,
    'tapToReveal': tapToReveal,
    if (requireAuth != null) 'requireAuth': requireAuth,
  };
}
