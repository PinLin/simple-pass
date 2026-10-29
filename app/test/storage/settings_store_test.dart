import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/settings.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/memory_key_value_backend.dart';

void main() {
  group('SettingsStore', () {
    test('defaults: allowScreenshots on', () async {
      expect((await SettingsStore(MemoryKeyValueBackend()).load()).allowScreenshots, isTrue);
    });

    test('round-trips saved settings', () async {
      final store = SettingsStore(MemoryKeyValueBackend());
      await store.save(const Settings(allowScreenshots: false));
      expect((await store.load()).allowScreenshots, isFalse);
    });

    test('clipboard clearing defaults to 1 minute and round-trips every option', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(SettingsStore.storageKey, '{"allowScreenshots":false}');
      final store = SettingsStore(backend);
      expect((await store.load()).clipboardClear, ClipboardClear.oneMinute);
      for (final option in ClipboardClear.values) {
        await store.save(Settings(clipboardClear: option));
        expect((await store.load()).clipboardClear, option);
      }
      expect(ClipboardClear.never.delay, isNull);
      expect(ClipboardClear.fiveMinutes.delay, const Duration(minutes: 5));
    });

    test('Tap to reveal is off for older blobs and round-trips', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(SettingsStore.storageKey, '{"allowScreenshots":true}');
      final store = SettingsStore(backend);
      expect((await store.load()).tapToReveal, isFalse);
      await store.update((c) => c.copyWith(tapToReveal: true));
      final loaded = await store.load();
      expect(loaded.tapToReveal, isTrue);
      expect(loaded.allowScreenshots, isTrue);
    });

    test('requireAuth is undecided (null) for older blobs, round-trips, and is only written once decided', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(SettingsStore.storageKey, '{"allowScreenshots":true}');
      final store = SettingsStore(backend);
      expect((await store.load()).requireAuth, isNull);
      expect(backend.rawValue(SettingsStore.storageKey), isNot(contains('requireAuth')));
      for (final value in [true, false]) {
        await store.update((c) => c.copyWith(requireAuth: value));
        expect((await store.load()).requireAuth, value);
        expect(backend.rawValue(SettingsStore.storageKey), contains('"requireAuth":$value'));
      }
      await store.update((c) => c.copyWith(tapToReveal: true));
      expect((await store.load()).requireAuth, isFalse, reason: 'other changes keep the decision');
    });

    test('a non-boolean requireAuth reads as undecided', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(SettingsStore.storageKey, '{"requireAuth":"yes"}');
      expect((await SettingsStore(backend).load()).requireAuth, isNull);
    });

    test('an undecodable blob reads as defaults and is kept until a setting changes', () async {
      final backend = MemoryKeyValueBackend()..seedRaw(SettingsStore.storageKey, '{oops');
      final store = SettingsStore(backend);
      expect((await store.load()).allowScreenshots, isTrue);
      expect(backend.writeCount, 0);
      await store.update((c) => c.copyWith(allowScreenshots: false));
      expect((await store.load()).allowScreenshots, isFalse);
    });
  });

  group('SettingsStore — serialized writes', () {
    test('update bases its mutation on the latest stored value, not a stale copy', () async {
      final store = SettingsStore(MemoryKeyValueBackend(writeDelay: const Duration(milliseconds: 20)));
      final results = await Future.wait([
        store.update((c) => c.copyWith(allowScreenshots: false)),
        store.update((c) => c.copyWith(allowScreenshots: !c.allowScreenshots)),
      ]);
      expect(results.map((s) => s.allowScreenshots), [false, true]);
      expect((await store.load()).allowScreenshots, isTrue);
    });
  });
}
