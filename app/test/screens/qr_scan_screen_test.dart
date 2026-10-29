import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart' show CameraLensDirection;
import 'package:simple_pass/l10n/app_locale.dart';
import 'package:simple_pass/screens/qr_scan_screen.dart';

import '../test_helpers.dart';

/// One started preview: which lens, and the callbacks the screen gave it.
class _Preview {
  _Preview(this.lens, this.onReady, this.onError, this.onCode);

  final CameraLensDirection lens;
  final VoidCallback onReady;
  final ValueChanged<Object> onError;
  final ValueChanged<String> onCode;
}

void main() {
  late List<_Preview> previews;
  late List<Object?> popped;

  setUp(() {
    previews = [];
    popped = [];
  });

  Widget preview({
    required CameraLensDirection lens,
    required VoidCallback onReady,
    required ValueChanged<Object> onError,
    required ValueChanged<String> onCode,
  }) {
    previews.add(_Preview(lens, onReady, onError, onCode));
    return Text('preview ${lens.name}');
  }

  Future<void> open(WidgetTester tester, Future<List<CameraLensDirection>> Function() cameras) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: appSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => popped.add(
                  await Navigator.of(context).push(
                    MaterialPageRoute<String>(
                      builder: (_) => QrScanScreen(
                        listCameras: cameras,
                        buildPreview: preview,
                        startTimeout: const Duration(seconds: 5),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  const failed = 'The camera couldn\'t be started. Use "From photo" or enter the secret key by hand.';
  const none = 'No camera this app can use was found. Use "From photo" or enter the secret key by hand.';

  testWidgets('a device with only a front camera scans with it and returns the code', (tester) async {
    await open(tester, () async => [CameraLensDirection.front]);
    expect(previews.single.lens, CameraLensDirection.front);
    previews.single.onReady();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(const ValueKey('scanErrorMessage')), findsNothing);
    previews.single.onCode('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP');
    previews.single.onCode('second frame');
    await tester.pumpAndSettle();
    expect(popped, ['otpauth://totp/x?secret=JBSWY3DPEHPK3PXP']);
  });

  testWidgets('the back camera goes first; when it fails the front one is tried', (tester) async {
    await open(tester, () async => [CameraLensDirection.front, CameraLensDirection.back]);
    expect(previews.last.lens, CameraLensDirection.back);
    previews.last.onError(Exception('No available camera can be found'));
    await tester.pumpAndSettle();
    expect(previews.last.lens, CameraLensDirection.front);
    expect(find.text('preview front'), findsOneWidget);
    expect(find.byKey(const ValueKey('scanErrorMessage')), findsNothing);
  });

  testWidgets('when every camera fails, it says so and points to the alternatives', (tester) async {
    await open(tester, () async => [CameraLensDirection.back, CameraLensDirection.front]);
    previews.last.onError(Exception('back'));
    await tester.pumpAndSettle();
    final front = previews.last;
    front.onError(Exception('front'));
    await tester.pumpAndSettle();
    expect(find.text(failed), findsOneWidget);
    expect(find.textContaining('preview'), findsNothing);
    // A late error from an abandoned camera changes nothing.
    previews.first.onError(Exception('late'));
    await tester.pumpAndSettle();
    expect(find.text(failed), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(popped, [null]);
  });

  testWidgets('a camera that never starts or reports counts as failed after the timeout', (tester) async {
    await open(tester, () async => [CameraLensDirection.back]);
    expect(find.text('preview back'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text(failed), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(failed), findsOneWidget);
  });

  for (final (name, lister) in [
    ('no cameras', () async => <CameraLensDirection>[]),
    ('listing cameras throws', () async => throw Exception('camera service down')),
  ]) {
    testWidgets('$name: explains there is no usable camera', (tester) async {
      await open(tester, lister);
      expect(previews, isEmpty);
      expect(find.text(none), findsOneWidget);
    });
  }

  testWidgets('zh_Hant_TW messages', (tester) async {
    await pumpLocalized(
      tester,
      QrScanScreen(listCameras: () async => [], buildPreview: preview),
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
    );
    await tester.pumpAndSettle();
    expect(find.text('找不到可用的相機。請改用「從相片匯入」，或手動輸入私密金鑰。'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
  });
}
