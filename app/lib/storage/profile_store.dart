import 'dart:async';
import 'dart:convert';

import '../models/profile.dart';
import '../models/mobilepass_registration.dart';
import '../platform/keystore.dart';
import 'key_value_backend.dart';
import 'storage_exceptions.dart';

/// Persists the profile list as one JSON blob under [storageKey]; protected secrets are stored sealed
/// and load as [Profile.locked] until [unlock]ed. Operations are queued so overlapping calls can't lose an update.
class ProfileStore {
  ProfileStore(this._backend, {Keystore? keystore}) : _keystore = keystore;

  static const storageKey = 'profiles';

  final KeyValueBackend _backend;
  final Keystore? _keystore;

  // Decrypted secrets by profile id, with the sealed text they came from.
  final Map<String, ({String sealed, String code, String key, String pin, MobilePassRegistration? registration})>
  _opened = {};
  bool _prompting = false;
  Completer<bool>? _forgetAfterPrompt;

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

  /// Throws [StorageCorruptedException] if the stored blob can't be decoded.
  Future<List<Profile>> loadAll() => _serialized(() async => _profilesFrom(await _readRaw()));

  /// Replaces the whole list; refuses if the stored blob is unreadable, so it can't bury recoverable data.
  Future<void> saveAll(List<Profile> profiles) => _serialized(() async {
    final current = await _readRaw();
    await _write(current, profiles);
  });

  /// Applies [mutate] to the latest stored list and saves it, atomically with respect to other
  /// operations. Adding or changing protection requires authentication.
  Future<List<Profile>> update(List<Profile> Function(List<Profile> current) mutate) => _serialized(() async {
    final raw = await _readRaw();
    final next = mutate(_profilesFrom(raw));
    await _write(raw, next);
    return next;
  });

  /// Puts the stored profiles listed in [ids] in that order. Profiles not in [ids] (added
  /// meanwhile) keep their slots; listed ids that no longer exist are skipped. Locked profiles
  /// move without unlocking.
  Future<List<Profile>> reorder(List<String> ids) => update((current) {
    final rank = {for (final (i, id) in ids.indexed) id: i};
    final moved = current.where((p) => rank.containsKey(p.id)).toList()
      ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    final next = moved.iterator;
    return [for (final p in current) rank.containsKey(p.id) ? (next..moveNext()).current : p];
  });

  /// [update] for one profile; null if [id] no longer exists. An identical result skips the write.
  Future<Profile?> updateProfile(String id, Profile Function(Profile current) mutate) => _serialized(() async {
    final raw = await _readRaw();
    final profiles = _profilesFrom(raw);
    final index = profiles.indexWhere((p) => p.id == id);
    if (index == -1) return null;
    final updated = mutate(profiles[index]);
    if (identical(updated, profiles[index])) return updated;
    profiles[index] = updated;
    await _write(raw, profiles);
    return updated;
  });

  /// The app lock: always authenticates, then opens every sealed profile and, with [sealUnprotected],
  /// seals any still in the clear, under that one authentication. Profiles stay open until [forget].
  /// A sealed secret that can't be read leaves just that profile locked. Throws [AuthFailedException]
  /// or [KeyInvalidatedException].
  Future<List<Profile>> unlockApp({bool sealUnprotected = true}) => _serialized(() async {
    final raw = await _readRaw();
    await _authenticateOrThrow();
    final forgets = _forgets;
    await _openAll(raw);
    var result = _profilesFrom(raw);
    if (sealUnprotected && !result.every((p) => p.protected)) {
      result = [for (final p in result) p.copyWith(protected: true)];
      await _write(raw, result, authenticated: true);
    }
    // A forget() while this ran (the app went to the background) wins: nothing it opened stays.
    if (forgets != _forgets) {
      _opened.clear();
      return _profilesFrom(await _readRaw());
    }
    return result;
  });

  /// Whether a system authentication prompt is up right now (it may pause the app).
  bool get prompting => _prompting;

  /// Whether the most recent prompt ended in a successful authentication.
  bool get lastPromptSucceeded => _lastPromptSucceeded;
  bool _lastPromptSucceeded = false;

  Future<void> _openAll(_Raw raw) async {
    for (final entry in raw) {
      try {
        await _open(entry);
      } on AuthFailedException {
        rethrow;
      } on KeyInvalidatedException {
        rethrow;
      } catch (_) {
        // A damaged value (SecretDamagedException, or one that isn't even well-formed) stays locked;
        // the others still open.
      }
    }
  }

  /// Seals ([protected]) or unseals every profile, after one authentication. Throws
  /// [AuthFailedException] or [KeyInvalidatedException], or whatever stops a sealed secret from being
  /// read (unsealing it would lose it); nothing changes then.
  Future<List<Profile>> setAllProtected(bool protected) => _serialized(() async {
    final raw = await _readRaw();
    await _authenticateOrThrow();
    final forgets = _forgets;
    for (final entry in raw) {
      await _open(entry);
    }
    // The app went to the background meanwhile: some secrets may not be open, so nothing is written.
    if (forgets != _forgets) throw const SecretsForgottenException();
    final next = [for (final p in _profilesFrom(raw)) p.copyWith(protected: protected, locked: false)];
    await _write(raw, next, authenticated: true);
    return next;
  });

  /// Drops decrypted secrets; completes with whether there were any. Waits for a system prompt in flight.
  Future<bool> forget() {
    if (_prompting) return (_forgetAfterPrompt ??= Completer<bool>()).future;
    return Future.value(_drop());
  }

  bool _drop() {
    final had = _opened.isNotEmpty;
    _opened.clear();
    _forgets++;
    return had;
  }

  // Bumped by every [forget] that drops secrets: a decryption or seal still in flight then must not
  // put its plaintext back.
  int _forgets = 0;

  /// After [KeyInvalidatedException]: deletes the protected profiles, whose sealed secrets can't be recovered.
  Future<void> deleteUnrecoverable() => _serialized(() async {
    final raw = await _readRaw();
    final entries = [
      for (final e in raw)
        if (!_isProtected(e)) e,
    ];
    await _backend.write(storageKey, jsonEncode({'profiles': entries}));
    _opened.clear();
    await _keystore?.deleteKey(_keyAlias);
  });

  Future<void> _open(Map<String, dynamic> entry) async {
    final id = entry['id'] as String;
    final sealed = entry['sealed'];
    if (sealed is! String || _opened[id]?.sealed == sealed) return;
    final (alias, ciphertext) = _split(sealed);
    final forgets = _forgets;
    final secret = jsonDecode(await _withAuth(() => _keystore!.decrypt(alias, ciphertext))) as Map;
    if (forgets != _forgets) return;
    _opened[id] = (
      sealed: sealed,
      code: secret['a'] as String,
      key: secret['k'] as String? ?? '',
      pin: secret['p'] as String,
      registration: secret['r'] == null
          ? null
          : MobilePassRegistration.fromJson(Map<String, dynamic>.from(secret['r'] as Map)),
    );
  }

  Future<_Raw> _readRaw() async {
    final raw = await _backend.read(storageKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final list = (jsonDecode(raw) as Map)['profiles'] as List<dynamic>;
      return [for (final e in list) e as Map<String, dynamic>];
    } catch (e) {
      throw StorageCorruptedException(storageKey, e);
    }
  }

  List<Profile> _profilesFrom(_Raw raw) => [for (final e in raw) _profileFrom(e)];

  // A "protected" flag without a sealed secret guards nothing, so it isn't trusted.
  static bool _isProtected(Map<String, dynamic> entry) => entry['sealed'] is String;

  Profile _profileFrom(Map<String, dynamic> entry) {
    final protected = _isProtected(entry);
    final opened = _opened[entry['id']];
    final open = opened != null && opened.sealed == entry['sealed'];
    final json = !protected
        ? {...entry, 'protected': false}
        : {
            ...entry,
            'protected': true,
            'activationCode': open ? opened.code : '',
            'key': open ? opened.key : '',
            'pin': open ? opened.pin : '',
            'registration': open ? opened.registration?.toJson() : null,
          };
    try {
      final profile = Profile.fromJson(json);
      return protected && !open ? profile.copyWith(locked: true) : profile;
    } catch (e) {
      throw StorageCorruptedException(storageKey, e);
    }
  }

  Future<void> _write(_Raw raw, List<Profile> profiles, {bool authenticated = false}) async {
    for (final p in profiles) {
      if (!isValidCounter(p.counter)) {
        throw CounterOutOfRangeException(p.counter);
      }
    }
    final stored = {for (final e in raw) e['id'] as String: e};
    bool wasProtected(Profile p) => stored[p.id] != null && _isProtected(stored[p.id]!);
    // Switching an existing profile's protection always confirms who's asking, even inside the key's
    // window; a new one sealed as it's added only needs the key (the app lock already asked).
    if (!authenticated && profiles.any((p) => stored.containsKey(p.id) && p.protected != wasProtected(p))) {
      await _authenticateOrThrow();
    }
    // A sealed profile is written either passed through as it is (locked) or from secrets opened from
    // that very ciphertext; anything else would overwrite the real secret with empty placeholders.
    for (final p in profiles) {
      final old = stored[p.id];
      if (old != null && _isProtected(old) && !p.locked && _opened[p.id]?.sealed != old['sealed']) {
        throw const SecretsForgottenException();
      }
      // A locked profile only carries empty placeholders; secrets set on it (an edit that raced a
      // forget) would be dropped by the pass-through below, so the write is refused instead.
      if (p.locked && (p.activationCode.isNotEmpty || p.key.isNotEmpty || p.pin.isNotEmpty || p.registration != null)) {
        throw const SecretsForgottenException();
      }
    }
    final entries = <Map<String, dynamic>>[];
    for (final p in profiles) {
      final json = p.toJson();
      if (p.locked) {
        // Never opened, so the stored ciphertext is passed through as is.
        json
          ..remove('activationCode')
          ..remove('key')
          ..remove('pin')
          ..remove('registration')
          ..['sealed'] = stored[p.id]!['sealed'];
      } else if (p.protected) {
        json
          ..remove('activationCode')
          ..remove('key')
          ..remove('pin')
          ..remove('registration')
          ..['sealed'] = await _seal(p, raw);
      }
      entries.add(json);
    }
    _opened.removeWhere((id, _) => !profiles.any((p) => p.id == id && p.protected));
    await _backend.write(storageKey, jsonEncode({'profiles': entries}));
  }

  /// Reuses the stored ciphertext when nothing changed, so ordinary writes never need the key.
  Future<String> _seal(Profile p, _Raw raw) async {
    const alias = _keyAlias;
    final opened = _opened[p.id];
    if (opened != null &&
        _split(opened.sealed).$1 == alias &&
        opened.code == p.activationCode &&
        opened.key == p.key &&
        opened.pin == p.pin &&
        opened.registration == p.registration) {
      return opened.sealed;
    }
    final forgets = _forgets;
    final plaintext = jsonEncode({
      'a': p.activationCode,
      if (p.key.isNotEmpty) 'k': p.key,
      'p': p.pin,
      if (p.registration != null) 'r': p.registration!.toJson(),
    });
    // Replacing a dead key would orphan whatever else it sealed.
    final keyInUse = raw.any((e) => e['id'] != p.id && '${e['sealed']}'.startsWith('$alias:'));
    final sealed =
        '$alias:${await _withAuth(() => _keystore!.encrypt(alias, keyValiditySeconds, plaintext, keyInUse: keyInUse))}';
    if (forgets == _forgets) {
      _opened[p.id] = (sealed: sealed, code: p.activationCode, key: p.key, pin: p.pin, registration: p.registration);
    }
    return sealed;
  }

  Future<T> _withAuth<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on UserNotAuthenticatedException {
      await _authenticateOrThrow();
      return op();
    }
  }

  Future<void> _authenticateOrThrow() async {
    _prompting = true;
    AuthResult? result;
    try {
      result = await _keystore!.authenticate();
      _lastPromptSucceeded = result == AuthResult.success;
      if (result != AuthResult.success) throw AuthFailedException(result);
    } finally {
      _prompting = false;
      final pending = _forgetAfterPrompt;
      _forgetAfterPrompt = null;
      pending?.complete(result != AuthResult.success && _drop());
    }
  }

  static const _keyAlias = 'profile_secrets';

  static (String, String) _split(String sealed) {
    final i = sealed.indexOf(':');
    if (i < 0) throw const SecretDamagedException();
    return (sealed.substring(0, i), sealed.substring(i + 1));
  }
}

typedef _Raw = List<Map<String, dynamic>>;
