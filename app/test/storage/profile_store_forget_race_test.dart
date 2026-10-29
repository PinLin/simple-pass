import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/storage_exceptions.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';
const _otherCode = 'WMPX4-TD2BV-QZM7C-QX4J4';

/// Holds every decryption until [gate] completes, signalling [waiting] when one starts.
class _GatedKeystore extends FakeKeystore {
  Completer<void>? gate;
  final Completer<void> waiting = Completer<void>();

  @override
  Future<String> decrypt(String alias, String ciphertext) async {
    final gate = this.gate;
    if (gate != null) {
      if (!waiting.isCompleted) waiting.complete();
      await gate.future;
    }
    return super.decrypt(alias, ciphertext);
  }
}

void main() {
  late MemoryKeyValueBackend backend;
  late _GatedKeystore keystore;
  late ProfileStore store;

  String raw() => backend.rawValue(ProfileStore.storageKey)!;

  setUp(() async {
    backend = MemoryKeyValueBackend();
    keystore = _GatedKeystore();
    store = ProfileStore(backend, keystore: keystore);
    await store.saveAll([
      Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5, pin: '1234'),
      Profile(id: 'b2', name: 'Home', activationCode: _otherCode, counter: 7, pin: '5678'),
    ]);
  });

  /// Runs [operation] while a forget() lands in the middle of its decryption, and returns its error.
  Future<Object?> raceWithForget(Future<Object?> Function() operation) async {
    await store.forget();
    keystore
      ..expire()
      ..gate = Completer<void>();
    final running = operation().then<Object?>((_) => null, onError: (Object e) => e);
    await keystore.waiting.future;
    await store.forget();
    keystore.gate!.complete();
    return running;
  }

  for (final protect in [false, true]) {
    test('setAllProtected($protect) interrupted by forget() writes nothing at all', () async {
      // Turning off needs everything sealed; turning on, at least one sealed profile to open.
      if (protect) {
        await store.updateProfile('a1', (p) => p.copyWith(protected: true));
      } else {
        await store.setAllProtected(true);
      }
      final before = raw();
      final writes = backend.writeCount;

      final error = await raceWithForget(() => store.setAllProtected(protect));

      expect(error, isA<SecretsForgottenException>());
      expect(raw(), before, reason: 'byte for byte');
      expect(backend.writeCount, writes);
      // The sealed secrets are still there and open again with the next unlock.
      keystore.gate = null;
      final reopened = await store.unlockApp(sealUnprotected: false);
      expect(reopened.map((p) => (p.activationCode, p.pin)), [(_code, '1234'), (_otherCode, '5678')]);
    });
  }

  test('a write never stores a sealed profile whose secrets are not open', () async {
    await store.setAllProtected(true);
    await store.forget();
    final before = raw();
    // A locked profile handed back as if it were open, with its empty placeholders.
    await expectLater(
      store.update((all) => [for (final p in all) p.copyWith(locked: false)]),
      throwsA(isA<SecretsForgottenException>()),
    );
    await expectLater(
      store.update((all) => [for (final p in all) p.copyWith(locked: false, protected: false)]),
      throwsA(isA<SecretsForgottenException>()),
    );
    expect(raw(), before);
    expect(jsonEncode(jsonDecode(raw())), isNot(contains('"activationCode":""')));
  });

  test('locked profiles still pass through untouched (reorder, ✓ and delete keep working)', () async {
    await store.setAllProtected(true);
    await store.forget();
    await store.reorder(['b2', 'a1']);
    await store.update((all) => all.where((p) => p.id != 'b2').toList());
    keystore.expire();
    final opened = await store.unlockApp(sealUnprotected: false);
    expect(opened.single.activationCode, _code);
    expect(opened.single.pin, '1234');
  });
}
