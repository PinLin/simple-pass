import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/main.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/platform/device_info.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(ScreenGuard.channelName),
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(ScreenGuard.channelName),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(DeviceInfo.channelName),
      null,
    );
  });

  /// [sdkInt] null leaves the call unanswered, like a platform without it.
  void mockSdk(int? sdkInt) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(DeviceInfo.channelName),
        (call) async => call.method == 'sdkInt' ? sdkInt : null,
      );

  Future<void> start(MemoryKeyValueBackend backend) =>
      applyStartupSettings(SettingsStore(backend), ProfileStore(backend), ScreenGuard());

  List<Object?> argsOf(String method) =>
      calls.where((c) => c.method == method).map((c) => (c.arguments as Map).values.single).toList();

  test('follows allowScreenshots; recents thumbnail allowed while nothing is protected', () async {
    await start(MemoryKeyValueBackend());
    expect(argsOf('setSecure'), [false]);
    expect(argsOf('setRecentsScreenshotEnabled'), [true]);
  });

  test('turns FLAG_SECURE on when the backend itself throws', () async {
    await start(_ThrowingBackend());
    expect(argsOf('setSecure'), [true]);
    expect(argsOf('setRecentsScreenshotEnabled'), [false]);
  });

  test('hides the recents thumbnail when a profile is protected', () async {
    final backend = MemoryKeyValueBackend()
      ..seedRaw(ProfileStore.storageKey, '{"profiles":[{"id":"a1","name":"Work","sealed":"x:y","counter":0}]}');
    await start(backend);
    expect(argsOf('setRecentsScreenshotEnabled'), [false]);
  });

  group('secureWindow', () {
    bool secure(bool allowScreenshots, bool appLock, int? sdkInt) =>
        secureWindow(allowScreenshots: allowScreenshots, appLock: appLock, sdkInt: sdkInt);

    test('screenshots off is always secure, with or without the lock and whatever the sdk', () {
      for (final lock in [true, false]) {
        for (final sdk in [null, 32, 33, 36]) {
          expect(secure(false, lock, sdk), isTrue, reason: 'lock $lock sdk $sdk');
        }
      }
    });

    test('screenshots allowed and the lock off is never secure', () {
      for (final sdk in [null, 32, 33, 36]) {
        expect(secure(true, false, sdk), isFalse, reason: 'sdk $sdk');
      }
    });

    test('screenshots allowed with the lock on is secure before sdk 33 and when the sdk is unknown', () {
      expect(secure(true, true, null), isTrue);
      expect(secure(true, true, 29), isTrue);
      expect(secure(true, true, 32), isTrue);
    });

    test('screenshots allowed with the lock on is not secure from sdk 33', () {
      expect(secure(true, true, 33), isFalse);
      expect(secure(true, true, 36), isFalse);
    });
  });

  group('applyStartupSettings and the app lock', () {
    Future<void> startWith(MemoryKeyValueBackend backend) => applyStartupSettings(
      SettingsStore(backend),
      ProfileStore(backend),
      ScreenGuard(),
      deviceInfo: const DeviceInfo(),
    );

    MemoryKeyValueBackend lockOn({bool allowScreenshots = true}) => MemoryKeyValueBackend()
      ..seedRaw(
        SettingsStore.storageKey,
        '{"allowScreenshots":$allowScreenshots,"clipboardClearSeconds":60,"tapToReveal":false,"requireAuth":true}',
      );

    /// A store with one profile sealed, as left by an earlier run with the app lock.
    Future<MemoryKeyValueBackend> sealedBackend() async {
      final backend = MemoryKeyValueBackend();
      final keystore = FakeKeystore();
      final store = ProfileStore(backend, keystore: keystore);
      await store.saveAll([Profile(id: 'a1', name: 'Work', activationCode: 'APSCG-YKKAU-NEZGC-PRDSM', counter: 0)]);
      await store.updateProfile('a1', (p) => p.copyWith(protected: true));
      return backend;
    }

    test('requireAuth on with sdk 32: FLAG_SECURE even though screenshots are allowed', () async {
      mockSdk(32);
      await startWith(lockOn());
      expect(argsOf('setSecure'), [true]);
    });

    test('requireAuth on with sdk 33: screenshots allowed means no FLAG_SECURE', () async {
      mockSdk(33);
      await startWith(lockOn());
      expect(argsOf('setSecure'), [false]);
    });

    test('requireAuth on with an unknown sdk counts as old', () async {
      mockSdk(null);
      await startWith(lockOn());
      expect(argsOf('setSecure'), [true]);
    });

    test('requireAuth on with sdk 33 and screenshots off stays secure', () async {
      mockSdk(33);
      await startWith(lockOn(allowScreenshots: false));
      expect(argsOf('setSecure'), [true]);
    });

    test('requireAuth off and nothing sealed: the sdk does not matter', () async {
      mockSdk(32);
      await startWith(MemoryKeyValueBackend());
      expect(argsOf('setSecure'), [false]);
    });

    test('a sealed profile counts as the lock while requireAuth is undecided, sdk 32', () async {
      mockSdk(32);
      await startWith(await sealedBackend());
      expect(argsOf('setSecure'), [true]);
    });

    test('unreadable profiles count as sealed: FLAG_SECURE on sdk 32, none on sdk 33', () async {
      mockSdk(32);
      await startWith(_ProfilesThrowingBackend());
      expect(argsOf('setSecure'), [true]);
      calls.clear();
      mockSdk(33);
      await startWith(_ProfilesThrowingBackend());
      expect(argsOf('setSecure'), [false]);
    });
  });
}

class _ProfilesThrowingBackend extends MemoryKeyValueBackend {
  @override
  Future<String?> read(String key) async =>
      key == ProfileStore.storageKey ? throw PlatformException(code: 'decrypt', message: 'bad key') : super.read(key);
}

class _ThrowingBackend extends MemoryKeyValueBackend {
  @override
  Future<String?> read(String key) async => throw PlatformException(code: 'decrypt', message: 'bad key');
}
