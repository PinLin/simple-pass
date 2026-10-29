/// Minimal string key/value persistence, abstracted so tests can swap in an
/// in-memory fake instead of touching the platform Keystore.
abstract class KeyValueBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
