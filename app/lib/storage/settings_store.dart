import 'dart:async';
import 'dart:convert';

import '../models/settings.dart';
import 'key_value_backend.dart';

/// Persists [Settings] as one JSON blob under [storageKey]; operations run on one queue so
/// overlapping calls can't lose an update.
class SettingsStore {
  SettingsStore(this._backend);

  static const storageKey = 'settings';

  final KeyValueBackend _backend;

  // Non-null only while an operation runs.
  Future<void>? _running;

  Future<T> _serialized<T>(Future<T> Function() op) async {
    while (_running != null) {
      await _running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      return await op();
    } finally {
      _running = null;
      done.complete();
    }
  }

  /// An undecodable blob reads as the defaults until a setting changes.
  Future<Settings> load() => _serialized(_read);

  Future<void> save(Settings settings) => _serialized(() => _write(settings));

  /// Applies [mutate] to the latest stored settings and saves, so overlapping updates both take effect.
  Future<Settings> update(Settings Function(Settings current) mutate) => _serialized(() async {
    final next = mutate(await _read());
    await _write(next);
    return next;
  });

  Future<Settings> _read() async {
    final raw = await _backend.read(storageKey);
    if (raw == null || raw.isEmpty) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> _write(Settings settings) => _backend.write(storageKey, jsonEncode(settings.toJson()));
}
