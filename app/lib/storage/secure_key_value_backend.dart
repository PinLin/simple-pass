import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_value_backend.dart';

/// Keystore-backed [KeyValueBackend] (AES-GCM data key, RSA-OAEP wrapped —
/// the default `AndroidOptions` cipher pair, API 23+).
class SecureKeyValueBackend implements KeyValueBackend {
  SecureKeyValueBackend({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The plugin's default wipes all data on a decryption error; surface it instead.
            aOptions: AndroidOptions(resetOnError: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}
