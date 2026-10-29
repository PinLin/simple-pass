import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/storage_exceptions.dart';

import '../fakes/memory_key_value_backend.dart';

const _legacyCode = 'APSCG-YKKAU-NEZGC-PRDSM';

void main() {
  group('ProfileStore', () {
    test('loadAll returns an empty list when nothing was ever saved', () async {
      final store = ProfileStore(MemoryKeyValueBackend());
      expect(await store.loadAll(), isEmpty);
    });

    test('round-trips a list of profiles through JSON', () async {
      final backend = MemoryKeyValueBackend();
      final store = ProfileStore(backend);

      final profiles = [
        Profile(
          id: 'a1',
          name: 'Work VPN',
          activationCode: 'APSCG-YKKAU-NEZGC-PRDSM',
          counter: 5,
          createdAt: DateTime.utc(2025, 12, 1),
        ),
        Profile(id: 'b2', name: 'Personal', activationCode: 'ABCDE-FGHIJ-KLMNO-PQRST', counter: 0),
      ];

      await store.saveAll(profiles);
      final loaded = await store.loadAll();

      expect(loaded, hasLength(2));
      expect(loaded[0].id, 'a1');
      expect(loaded[0].name, 'Work VPN');
      expect(loaded[0].activationCode, 'APSCG-YKKAU-NEZGC-PRDSM');
      expect(loaded[0].counter, 5);
      expect(loaded[0].createdAt, DateTime.utc(2025, 12, 1));
      expect(loaded[1].id, 'b2');
      expect(loaded[1].counter, 0);
    });

    test('saveAll overwrites the previous snapshot rather than merging', () async {
      final backend = MemoryKeyValueBackend();
      final store = ProfileStore(backend);

      await store.saveAll([Profile(id: 'a1', name: 'One', activationCode: 'AAAAA-AAAAA-AAAAA-AAAAA', counter: 0)]);
      await store.saveAll([Profile(id: 'b2', name: 'Two', activationCode: 'BBBBB-BBBBB-BBBBB-BBBBB', counter: 0)]);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'b2');
    });
  });

  group('Profile', () {
    test('constructor rejects a negative counter', () {
      expect(
        () => Profile(id: 'x', name: 'x', activationCode: 'AAAAA-AAAAA-AAAAA-AAAAA', counter: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith rejects a negative counter', () {
      final profile = Profile(id: 'x', name: 'x', activationCode: 'AAAAA-AAAAA-AAAAA-AAAAA', counter: 0);
      expect(() => profile.copyWith(counter: -1), throwsA(isA<AssertionError>()));
    });
  });

  group('generateProfileId', () {
    test('produces distinct 32-character hex ids', () {
      final a = generateProfileId();
      final b = generateProfileId();
      expect(a, isNot(equals(b)));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
    });
  });

  group('ProfileStore — corrupted data', () {
    const corrupted = '[{"id": "a1", "name": "Work"'; // truncated JSON

    test('loadAll throws StorageCorruptedException instead of returning an empty list', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, corrupted);
      await expectLater(ProfileStore(backend).loadAll(), throwsA(isA<StorageCorruptedException>()));
    });

    test('update refuses to write over an unreadable blob', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, corrupted);
      final store = ProfileStore(backend);

      await expectLater(
        store.update((current) => [...current, Profile(id: 'n', name: 'n', activationCode: 'x', counter: 0)]),
        throwsA(isA<StorageCorruptedException>()),
      );
      expect(backend.writeCount, 0);
      expect(backend.rawValue(ProfileStore.storageKey), corrupted);
    });

    test('saveAll refuses to write over an unreadable blob', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, '{"not": "a list"}');
      final store = ProfileStore(backend);

      await expectLater(store.saveAll([]), throwsA(isA<StorageCorruptedException>()));
      expect(backend.writeCount, 0);
    });

    test('a failed operation does not wedge the queue', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, corrupted);
      final store = ProfileStore(backend);
      await expectLater(store.loadAll(), throwsA(isA<StorageCorruptedException>()));

      backend.seedRaw(ProfileStore.storageKey, '{"profiles":[]}');
      expect(await store.loadAll(), isEmpty);
    });

    test('a bare list without the "profiles" wrapper is corrupted', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, '[]');
      await expectLater(ProfileStore(backend).loadAll(), throwsA(isA<StorageCorruptedException>()));
    });
  });

  group('ProfileStore — serialized writes', () {
    test('two overlapping updates both apply instead of one overwriting the other', () async {
      final backend = MemoryKeyValueBackend(writeDelay: const Duration(milliseconds: 20));
      final store = ProfileStore(backend);
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: 'x', counter: 5)]);

      // Fired without awaiting in between, like a double tap.
      final first = store.updateProfile('a1', (p) => p.copyWith(counter: p.counter + 1));
      final second = store.updateProfile('a1', (p) => p.copyWith(counter: p.counter + 1));
      await Future.wait([first, second]);

      expect((await store.loadAll()).single.counter, 7);
    });

    test('overlapping list updates (add + add) keep both new profiles', () async {
      final backend = MemoryKeyValueBackend(writeDelay: const Duration(milliseconds: 20));
      final store = ProfileStore(backend);

      await Future.wait([
        store.update((c) => [...c, Profile(id: 'a', name: 'A', activationCode: 'x', counter: 0)]),
        store.update((c) => [...c, Profile(id: 'b', name: 'B', activationCode: 'x', counter: 0)]),
      ]);

      expect((await store.loadAll()).map((p) => p.id), ['a', 'b']);
    });

    test('updateProfile skips the write when mutate returns the profile unchanged', () async {
      final backend = MemoryKeyValueBackend();
      final store = ProfileStore(backend);
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: 'x', counter: 5)]);
      final writesBefore = backend.writeCount;

      await store.updateProfile('a1', (p) => p);

      expect(backend.writeCount, writesBefore);
    });
  });

  group('ProfileStore — counter limit', () {
    test('rejects writing a counter above maxCounter and leaves storage untouched', () async {
      final backend = MemoryKeyValueBackend();
      final store = ProfileStore(backend);
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: 'x', counter: maxCounter)]);
      final before = backend.rawValue(ProfileStore.storageKey);

      await expectLater(
        store.updateProfile('a1', (p) => p.copyWith(counter: p.counter + 1)),
        throwsA(isA<CounterOutOfRangeException>()),
      );
      expect(backend.rawValue(ProfileStore.storageKey), before);
      expect((await store.loadAll()).single.counter, maxCounter);
    });

    test('accepts exactly maxCounter', () async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: 'x', counter: maxCounter)]);
      final loaded = (await store.loadAll()).single;
      expect(loaded.counter, 9007199254740991);
      expect(loaded.isAtMaxCounter, isTrue);
    });
  });

  group('stored counter that is missing or out of range', () {
    String blob(String counterField) => jsonEncode({
      'profiles': [
        jsonDecode(
          '{"id":"bad","name":"Bad","activationCode":"APSCG-YKKAU-NEZGC-PRDSM",$counterField'
          '"pin":"","policy":"","createdAt":"2026-01-01T00:00:00.000Z"}',
        ),
        {
          'id': 'ok',
          'name': 'Ok',
          'activationCode': 'APSCG-YKKAU-NEZGC-PRDSM',
          'counter': 3,
          'pin': '',
          'policy': '',
          'createdAt': '2026-01-01T00:00:00.000Z',
        },
      ],
    });

    for (final bad in ['9223372036854775807', '9007199254740992', '-1', 'null', '"7"']) {
      test('counter $bad makes the stored data corrupted, and nothing is written over it', () async {
        final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, blob('"counter":$bad,'));
        final store = ProfileStore(backend);
        final before = backend.rawValue(ProfileStore.storageKey);

        await expectLater(store.loadAll(), throwsA(isA<StorageCorruptedException>()));
        await expectLater(
          store.updateProfile('ok', (p) => p.copyWith(counter: 4)),
          throwsA(isA<StorageCorruptedException>()),
        );
        expect(backend.rawValue(ProfileStore.storageKey), before);
      });
    }

    test('a missing counter makes the stored data corrupted', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(ProfileStore.storageKey, blob(''));
      await expectLater(ProfileStore(backend).loadAll(), throwsA(isA<StorageCorruptedException>()));
    });
  });

  group('ProfileStore.reorder', () {
    Profile p(String id) => Profile(id: id, name: id, activationCode: _legacyCode, counter: 0);

    test('puts the profiles in the given order', () async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([p('a'), p('b'), p('c')]);
      await store.reorder(['c', 'a', 'b']);
      expect((await store.loadAll()).map((p) => p.id), ['c', 'a', 'b']);
    });

    test('works from the latest stored list: added profiles keep their slot, deleted ones are skipped', () async {
      final store = ProfileStore(MemoryKeyValueBackend());
      await store.saveAll([p('a'), p('b'), p('new'), p('c')]);
      await store.reorder(['c', 'gone', 'b', 'a']);
      expect((await store.loadAll()).map((p) => p.id), ['c', 'b', 'new', 'a']);
    });
  });

  group('parseCounterInput', () {
    test('accepts plain digits, trimming surrounding whitespace', () {
      expect(parseCounterInput('0'), 0);
      expect(parseCounterInput(' 42 '), 42);
      expect(parseCounterInput('007'), 7);
      expect(parseCounterInput('9007199254740991'), maxCounter);
    });

    test('rejects forms int.tryParse would accept', () {
      expect(int.tryParse('0x10'), 16);
      expect(parseCounterInput('0x10'), isNull);
      expect(int.tryParse('+5'), 5);
      expect(parseCounterInput('+5'), isNull);
    });

    test('rejects negatives, empty, decimals and non-ASCII digits', () {
      for (final input in ['-1', '', '   ', '1.5', '1e3', '１２', '1 2']) {
        expect(parseCounterInput(input), isNull, reason: input);
      }
    });

    test('rejects values above maxCounter, including ones that overflow int64', () {
      expect(parseCounterInput('9007199254740992'), isNull);
      expect(parseCounterInput('9223372036854775808'), isNull);
      expect(parseCounterInput('99999999999999999999999'), isNull);
    });
  });
}
