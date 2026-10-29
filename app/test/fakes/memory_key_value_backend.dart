import 'dart:async';

import 'package:simple_pass/storage/key_value_backend.dart';

/// In-memory [KeyValueBackend] fake, so storage-layer tests don't touch the
/// platform Keystore.
class MemoryKeyValueBackend implements KeyValueBackend {
  MemoryKeyValueBackend({this.writeDelay = Duration.zero});

  /// Makes each write take this long, so overlapping writers really overlap.
  final Duration writeDelay;

  final Map<String, String> _values = {};

  /// Number of completed [write] calls — lets a test assert nothing was
  /// written.
  int writeCount = 0;

  /// Keys whose writes throw, to test what a failed save leaves behind.
  final Set<String> failWritesFor = {};

  /// Holds every write back while set, like slow storage, until the test completes it.
  Completer<void>? writeGate;

  /// Stores [value] verbatim, bypassing any store-level encoding — used to
  /// plant corrupted blobs.
  void seedRaw(String key, String value) => _values[key] = value;

  String? rawValue(String key) => _values[key];

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    await writeGate?.future;
    if (failWritesFor.contains(key)) throw Exception('write failed: $key');
    _values[key] = value;
    writeCount++;
  }
}
