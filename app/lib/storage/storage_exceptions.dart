import '../models/profile.dart';
import '../platform/keystore.dart';

/// The blob stored under [key] exists but could not be decoded. Callers must
/// not overwrite it, since the user may still be able to recover it.
class StorageCorruptedException implements Exception {
  const StorageCorruptedException(this.key, this.cause);

  final String key;
  final Object cause;

  @override
  String toString() => 'StorageCorruptedException($key): $cause';
}

/// A write tried to persist a counter outside `0..maxCounter`.
class CounterOutOfRangeException implements Exception {
  const CounterOutOfRangeException(this.counter);

  final int counter;

  @override
  String toString() => 'CounterOutOfRangeException: $counter (max $maxCounter)';
}

/// The system prompt ended without a successful authentication.
class AuthFailedException implements Exception {
  const AuthFailedException(this.result);

  final AuthResult result;

  @override
  String toString() => 'AuthFailedException(${result.name})';
}

/// A sealed profile's secrets weren't open when it was about to be written (the app went to the
/// background mid-operation), so the write was refused rather than storing empty placeholders.
class SecretsForgottenException implements Exception {
  const SecretsForgottenException();

  @override
  String toString() => 'SecretsForgottenException';
}
