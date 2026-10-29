import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/models/profile.dart';
import 'package:simple_pass/platform/screen_guard.dart';
import 'package:simple_pass/screens/otp_helpers.dart';
import 'package:simple_pass/screens/profile_list_screen.dart';
import 'package:simple_pass/storage/profile_store.dart';
import 'package:simple_pass/storage/settings_store.dart';

import '../fakes/fake_keystore.dart';
import '../fakes/memory_key_value_backend.dart';
import '../test_helpers.dart';

const _base32Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

Profile _mobilePassTime() => Profile(
  id: 'mp',
  name: 'MobilePASS time',
  activationCode: 'AERUK-Z4JVP-G66AJ-DBACL',
  policy: '75817049',
  counter: 0,
);

Profile _totp({required bool mobilePassTime}) => Profile(
  id: mobilePassTime ? 'mpt' : 'totp',
  name: mobilePassTime ? 'TOTP from 2000' : 'TOTP',
  activationCode: '',
  kind: ProfileKind.totp,
  key: _base32Secret,
  mobilePassTime: mobilePassTime,
  counter: 0,
);

final _profiles = [_mobilePassTime(), _totp(mobilePassTime: true), _totp(mobilePassTime: false)];

void main() {
  final unsetClocks = {'the Unix epoch': DateTime.utc(1970), 'the eve of 2000': DateTime.utc(1999, 12, 31, 23, 59, 59)};

  group('a clock before the epoch a time-based profile counts from', () {
    for (final MapEntry(key: label, value: clock) in unsetClocks.entries) {
      test('at $label: no code, and nothing throws', () {
        for (final p in _profiles) {
          final countsFrom2000 = p.id != 'totp';
          expect(clockBeforeEpoch(p, clock), countsFrom2000, reason: p.id);
          expect(otpForProfile(p, now: clock), countsFrom2000 ? isNull : isNotNull, reason: p.id);
          expect(() => secondsUntilProfileCode(p, clock), returnsNormally, reason: p.id);
        }
      });

      testWidgets('at $label: rows stay blank with no error, and fill in once the clock is set', (tester) async {
        var now = clock;
        final store = ProfileStore(MemoryKeyValueBackend(), keystore: FakeKeystore());
        await store.saveAll(_profiles);
        await pumpLocalized(
          tester,
          ProfileListScreen(
            profileStore: store,
            settingsStore: SettingsStore(MemoryKeyValueBackend()),
            screenGuard: ScreenGuard(),
            now: () => now,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final error in ['Invalid stored key', 'Invalid Activation Code', 'Invalid Policy String']) {
          expect(find.text(error), findsNothing, reason: error);
        }
        final errorColor = Theme.of(tester.element(find.byType(ProfileListScreen))).colorScheme.error;
        final errorTexts = tester.widgetList<Text>(find.byType(Text)).where((t) => t.style?.color == errorColor);
        expect(errorTexts.map((t) => t.data), isEmpty);
        for (final id in ['mp', 'mpt']) {
          expect(find.byKey(ValueKey('codeNotYet-$id')), findsOneWidget, reason: id);
          expect(find.byKey(ValueKey('profileCountdown-$id')), findsNothing, reason: id);
        }
        // Counting from 1970, the plain TOTP already has a code.
        expect(find.byKey(const ValueKey('codeNotYet-totp')), findsNothing);
        expect(find.byKey(const ValueKey('profileCountdown-totp')), findsOneWidget);
        expect(find.text(formatOtpForDisplay(otpForProfile(_profiles[2], now: clock)!)), findsOneWidget);

        now = DateTime.utc(2026, 1, 1, 0, 0, 10);
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        for (final p in _profiles) {
          expect(find.byKey(ValueKey('codeNotYet-${p.id}')), findsNothing, reason: p.id);
          expect(find.byKey(ValueKey('profileCountdown-${p.id}')), findsOneWidget, reason: p.id);
          expect(find.text(formatOtpForDisplay(otpForProfile(p, now: now)!)), findsOneWidget, reason: p.id);
        }
      });
    }
  });
}
