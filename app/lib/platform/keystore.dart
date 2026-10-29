import 'package:flutter/services.dart';

/// How long a key stays usable after authentication; secrets are dropped on background, so
/// returning asks again.
const keyValiditySeconds = 10;

/// Outcome of the system authentication prompt.
enum AuthResult {
  success,
  canceled,

  /// The device has no screen lock (PIN/pattern/password) set up.
  noCredentials,
  lockedOut,
  failed,
}

/// Android refused the key because the user hasn't authenticated recently
/// enough for its validity window. Prompt, then retry.
class UserNotAuthenticatedException implements Exception {
  const UserNotAuthenticatedException();
}

/// The key is gone for good (screen lock removed or changed); what it sealed is unrecoverable.
/// One sealed value doesn't decrypt (its authentication tag doesn't match): that value is damaged,
/// while the key may still open the others.
class SecretDamagedException implements Exception {
  const SecretDamagedException();
}

class KeyInvalidatedException implements Exception {
  const KeyInvalidatedException();
}

/// AndroidKeyStore keys bound to user authentication, plus the system prompt
/// that satisfies them. An interface so tests can use a fake.
abstract class Keystore {
  /// Shows the system prompt (strong biometric or screen lock).
  Future<AuthResult> authenticate();

  /// Creates the key on first use; a dead or missing key is replaced unless [keyInUse], then this
  /// throws [KeyInvalidatedException].
  Future<String> encrypt(String alias, int timeoutSeconds, String plaintext, {required bool keyInUse});

  Future<String> decrypt(String alias, String ciphertext);

  Future<void> deleteKey(String alias);
}

/// Dart side of the `me.pinlin.simple_pass/keystore` platform channel.
class PlatformKeystore implements Keystore {
  static const _channel = MethodChannel('me.pinlin.simple_pass/keystore');

  @override
  Future<AuthResult> authenticate() async {
    final name = await _channel.invokeMethod<String>('authenticate');
    return AuthResult.values.where((r) => r.name == name).firstOrNull ?? AuthResult.failed;
  }

  @override
  Future<String> encrypt(String alias, int timeoutSeconds, String plaintext, {required bool keyInUse}) => _call(
    'encrypt',
    {'alias': alias, 'timeoutSeconds': timeoutSeconds, 'plaintext': plaintext, 'keyInUse': keyInUse},
  );

  @override
  Future<String> decrypt(String alias, String ciphertext) =>
      _call('decrypt', {'alias': alias, 'ciphertext': ciphertext});

  @override
  Future<void> deleteKey(String alias) => _call('deleteKey', {'alias': alias});

  Future<String> _call(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<String>(method, args) ?? '';
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'notAuthenticated' => const UserNotAuthenticatedException(),
        'keyInvalidated' => const KeyInvalidatedException(),
        'damaged' => const SecretDamagedException(),
        _ => e,
      };
    }
  }
}
