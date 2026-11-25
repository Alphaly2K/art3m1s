import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/widgets/engine_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('engine choices return the selected script value', (
    tester,
  ) async {
    EngineDialogResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await showEngineDialog(
                  context,
                  const EngineDialogRequest(
                    title: 'Game',
                    message: 'Continue?',
                    hasCancel: false,
                    hasTextField: false,
                    textFieldSize: null,
                    initialText: '',
                    choices: [
                      (label: 'YES', value: 0),
                      (label: 'NO', value: 1),
                      (label: 'CANCEL', value: 2),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Continue?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(result?.choice, 2);
  });
}
