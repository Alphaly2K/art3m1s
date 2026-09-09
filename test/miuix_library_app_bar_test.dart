import 'package:art3m1s/shell/miuix_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Miuix library add button sits on the large title row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MiuixTheme(
          data: MiuixThemeData.light(),
          child: MiuixScaffold(
            topBar: MiuixLibraryTopBar(onAdd: () {}),
            content: (_) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('资料库').last);
    final addButton = tester.getRect(find.byType(MiuixIconButton));
    expect(addButton.center.dy, closeTo(title.center.dy, 18));
    expect(addButton.center.dy, greaterThan(title.top - 8));
  });
}
