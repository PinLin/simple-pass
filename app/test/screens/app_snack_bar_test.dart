import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_pass/screens/app_snack_bar.dart';

void main() {
  testWidgets('a snackbar with an action still disappears after its duration', (tester) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    messenger.showSnackBar(
      appSnackBar(
        messenger,
        'Marked',
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
        duration: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Marked'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Marked'), findsNothing);
  });
}
