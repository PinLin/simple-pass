import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/platform/keystore.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/storage_exceptions.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

const _code = 'APSCG-YKKAU-NEZGC-PRDSM';

Profile _work() => Profile(id: 'a1', name: 'Work', activationCode: _code, counter: 5, pin: '1234');
Profile _home() => Profile(id: 'b2', name: 'Home', activationCode: _code, counter: 7);

void main() {
  late MemoryKeyValueBackend backend;
  late FakeKeystore keystore;
  late ProfileStore store;

  setUp(() async {
    backend = MemoryKeyValueBackend();
    keystore = FakeKeystore();
    store = ProfileStore(backend, keystore: keystore);
    await store.saveAll([_work(), _home()]);
  });

  String raw() => backend.rawValue(ProfileStore.storageKey)!;
  List<Map<String, dynamic>> entries() => ((jsonDecode(raw()) as Map)['profiles'] as List).cast();
  Map<String, dynamic> entry(String id) => entries().firstWhere((e) => e['id'] == id);
  Future<Profile> load(String id) async => (await store.loadAll()).firstWhere((p) => p.id == id);

  /// Rewrites one stored entry in place, bypassing the store.
  void tamper(String id, void Function(Map<String, dynamic> entry) change) {
    final all = entries();
    change(all.firstWhere((e) => e['id'] == id));
    backend.seedRaw(ProfileStore.storageKey, jsonEncode({'profiles': all}));
  }

  /// Both profiles sealed, then the app went to the background.
  Future<void> sealBothAndLeave() async {
    await store.setAllProtected(true);
    store.forget();
    keystore.expire();
  }

  // Valid base64 that decodes to text which is not what was sealed: what a failing GCM tag looks like.
  void damageBody(String id) => tamper(id, (e) {
    final parts = (e['sealed'] as String).split(':');
    parts[parts.length - 1] = base64.encode(utf8.encode('not what was sealed'));
    e['sealed'] = parts.join(':');
  });

  group('one damaged sealed value', () {
    test('unlockApp opens the good profile, leaves the damaged one locked, and writes nothing', () async {
      await sealBothAndLeave();
      damageBody('b2');
      final before = raw();
      final writes = backend.writeCount;
      keystore.authenticateCalls = 0;

      final all = await store.unlockApp();

      expect(keystore.authenticateCalls, 1);
      final work = all.firstWhere((p) => p.id == 'a1');
      final home = all.firstWhere((p) => p.id == 'b2');
      expect((work.locked, work.activationCode, work.pin), (false, _code, '1234'));
      expect((home.locked, home.protected, home.activationCode), (true, true, ''));
      expect((await load('a1')).locked, isFalse);
      expect((await load('b2')).locked, isTrue);
      expect((raw(), backend.writeCount), (before, writes));
    });

    test('the damaged value does not stop the rest, whichever comes first', () async {
      await sealBothAndLeave();
      damageBody('a1');
      final all = await store.unlockApp(sealUnprotected: false);
      expect(all.map((p) => (p.id, p.locked)), [('a1', true), ('b2', false)]);
      expect(all.last.activationCode, _code);
    });

    test('a damaged profile still takes metadata edits and keeps its ciphertext', () async {
      await sealBothAndLeave();
      damageBody('b2');
      final sealed = entry('b2')['sealed'];
      await store.unlockApp();
      await store.updateProfile('b2', (p) => p.copyWith(name: 'Renamed'));
      expect(entry('b2')['name'], 'Renamed');
      expect(entry('b2')['sealed'], sealed);
    });

    test('setAllProtected(false) fails on it and leaves the storage as it was', () async {
      await sealBothAndLeave();
      damageBody('b2');
      final before = raw();
      final writes = backend.writeCount;
      await expectLater(store.setAllProtected(false), throwsA(isA<SecretDamagedException>()));
      expect((raw(), backend.writeCount), (before, writes));
      expect((await load('b2')).locked, isTrue);
    });

    test('setAllProtected(true) over a damaged sealed value fails and writes nothing either', () async {
      await sealBothAndLeave();
      damageBody('b2');
      final before = raw();
      await expectLater(store.setAllProtected(true), throwsA(isA<SecretDamagedException>()));
      expect(raw(), before);
    });

    test('a key that is dead still aborts the unlock instead of skipping profiles', () async {
      await sealBothAndLeave();
      keystore.invalidate();
      await expectLater(store.unlockApp(), throwsA(isA<KeyInvalidatedException>()));
    });

    test('a canceled prompt still aborts the unlock', () async {
      await sealBothAndLeave();
      keystore.authResults.add(AuthResult.canceled);
      await expectLater(store.unlockApp(), throwsA(isA<AuthFailedException>()));
    });
  });

  group('what counts as protected', () {
    test('"sealed": null is not protected, whatever "protected" says, and the clear secrets stay', () async {
      tamper('a1', (e) {
        e['sealed'] = null;
        e['protected'] = true;
      });
      final work = await load('a1');
      expect((work.protected, work.locked, work.activationCode, work.pin), (false, false, _code, '1234'));
      keystore.authenticateCalls = 0;
      final all = await store.unlockApp(sealUnprotected: false);
      expect(all.every((p) => !p.locked && !p.protected), isTrue);
    });

    test('a store with only "sealed": null entries is left alone by deleteUnrecoverable', () async {
      tamper('a1', (e) => e['sealed'] = null);
      await store.deleteUnrecoverable();
      expect((await store.loadAll()).map((p) => p.id), ['a1', 'b2']);
    });

    test('a sealed string without ":" leaves just that profile locked; unlockApp does not throw', () async {
      await sealBothAndLeave();
      tamper('a1', (e) => e['sealed'] = 'garbagewithoutcolon');
      final all = await store.unlockApp();
      expect(all.map((p) => (p.id, p.locked)), [('a1', true), ('b2', false)]);
      expect(entry('a1')['sealed'], 'garbagewithoutcolon');
    });

    test('an empty sealed string is protected and stays locked', () async {
      await sealBothAndLeave();
      tamper('a1', (e) => e['sealed'] = '');
      final all = await store.unlockApp();
      expect(all.firstWhere((p) => p.id == 'a1').locked, isTrue);
      expect(all.firstWhere((p) => p.id == 'b2').locked, isFalse);
    });

    test(
      'setAllProtected over a sealed string without ":" fails with SecretDamagedException, nothing written',
      () async {
        await sealBothAndLeave();
        tamper('a1', (e) => e['sealed'] = 'garbagewithoutcolon');
        final before = raw();
        await expectLater(store.setAllProtected(false), throwsA(isA<SecretDamagedException>()));
        expect(raw(), before);
      },
    );
  });

  group('a locked profile never takes secrets', () {
    Future<void> lockWork() async {
      await store.updateProfile('a1', (p) => p.copyWith(protected: true));
      store.forget();
      keystore.expire();
    }

    final edits = <String, Profile Function(Profile)>{
      'pin': (p) => p.copyWith(pin: '9999'),
      'activation code': (p) => p.copyWith(activationCode: _code),
      'key': (p) => p.copyWith(key: 'a2V5'),
    };

    for (final MapEntry(key: what, value: edit) in edits.entries) {
      test('setting the $what on a profile that was forgotten is refused and the storage is untouched', () async {
        await lockWork();
        final before = raw();
        final writes = backend.writeCount;
        await expectLater(store.updateProfile('a1', edit), throwsA(isA<SecretsForgottenException>()));
        expect((raw(), backend.writeCount), (before, writes));
      });
    }

    test('update() and saveAll() refuse it the same way', () async {
      await lockWork();
      final before = raw();
      await expectLater(
        store.update((all) => [for (final p in all) p.id == 'a1' ? p.copyWith(pin: '9999') : p]),
        throwsA(isA<SecretsForgottenException>()),
      );
      final locked = await load('a1');
      await expectLater(
        store.saveAll([locked.copyWith(pin: '9999'), _home()]),
        throwsA(isA<SecretsForgottenException>()),
      );
      expect(raw(), before);
    });

    test('metadata edits on a locked profile still go through', () async {
      await lockWork();
      final sealed = entry('a1')['sealed'];
      await store.updateProfile('a1', (p) => p.copyWith(name: 'Renamed', counter: 9));
      expect((entry('a1')['name'], entry('a1')['counter'], entry('a1')['sealed']), ('Renamed', 9, sealed));
    });
  });
}
