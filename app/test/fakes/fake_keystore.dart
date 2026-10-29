import 'dart:convert';

import 'package:simple_pass/platform/keystore.dart';

/// In-memory [Keystore] like an auth-bound key: usable only while [authenticated], dead once
/// [invalidate]d; ciphertext records its key.
class FakeKeystore implements Keystore {
  bool authenticated = false;
  final Set<String> _invalidated = {};

  /// Results handed out by [authenticate], in order; success once empty.
  final List<AuthResult> authResults = [];
  int authenticateCalls = 0;

  /// Runs while the prompt is "up", e.g. to send the app to the background.
  Future<void> Function()? duringPrompt;

  /// Alias → validity seconds of every existing key.
  final Map<String, int> keys = {};
  final Map<String, int> _ids = {};
  int _nextId = 0;

  /// The validity window ran out.
  void expire() => authenticated = false;

  /// The screen lock was removed: every existing key is dead.
  void invalidate() => _invalidated.addAll(keys.keys);

  @override
  Future<AuthResult> authenticate() async {
    authenticateCalls++;
    await duringPrompt?.call();
    final result = authResults.isEmpty ? AuthResult.success : authResults.removeAt(0);
    if (result == AuthResult.success) authenticated = true;
    return result;
  }

  // Like KeystorePlugin: a dead or missing key is replaced unless keyInUse.
  @override
  Future<String> encrypt(String alias, int timeoutSeconds, String plaintext, {required bool keyInUse}) async {
    if (_invalidated.contains(alias) || !keys.containsKey(alias)) {
      if (keyInUse) throw const KeyInvalidatedException();
      _invalidated.remove(alias);
      keys[alias] = timeoutSeconds;
      _ids[alias] = _nextId++;
    }
    if (!authenticated) throw const UserNotAuthenticatedException();
    return 'ct:${_ids[alias]}:${base64.encode(utf8.encode(plaintext).reversed.toList())}';
  }

  // Like KeystorePlugin, where another key's ciphertext fails with
  // AEADBadTagException and is reported as invalidated.
  @override
  Future<String> decrypt(String alias, String ciphertext) async {
    if (_invalidated.contains(alias) || !keys.containsKey(alias)) throw const KeyInvalidatedException();
    if (!authenticated) throw const UserNotAuthenticatedException();
    final [_, id, body] = ciphertext.split(':');
    if (id != '${_ids[alias]}') throw const KeyInvalidatedException();
    // Like a failing GCM tag: anything that isn't exactly what was sealed is damaged.
    final String plaintext;
    try {
      plaintext = utf8.decode(base64.decode(body).reversed.toList());
      jsonDecode(plaintext);
    } on FormatException {
      throw const SecretDamagedException();
    }
    return plaintext;
  }

  @override
  Future<void> deleteKey(String alias) async {
    keys.remove(alias);
    _ids.remove(alias);
    _invalidated.remove(alias);
  }
}
