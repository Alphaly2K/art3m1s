import 'package:art3m1s/adaptive/cupertino_chrome.dart';
import 'package:art3m1s/adaptive/miuix_chrome.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Cupertino list dividers use equal left and right margins', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: CupertinoSymmetricListSection(
            children: [
              CupertinoListTile(title: Text('A')),
              CupertinoListTile(title: Text('B')),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CupertinoSymmetricDivider), findsOneWidget);

    final tileRect = tester.getRect(find.byType(CupertinoListTile).first);
    final dividerRect = tester.getRect(find.byType(CupertinoSymmetricDivider));
    expect(
      dividerRect.left - tileRect.left,
      CupertinoSymmetricListSection.dividerInset,
    );
    expect(
      tileRect.right - dividerRect.right,
      CupertinoSymmetricListSection.dividerInset,
    );
  });

  testWidgets('Miuix settings groups do not draw row dividers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MiuixTheme(
          data: MiuixThemeData.light(),
          child: const MiuixSettingsGroup(
            title: '设置',
            children: [Text('A'), Text('B')],
          ),
        ),
      ),
    );

    expect(find.byType(MiuixHorizontalDivider), findsNothing);
  });
}
