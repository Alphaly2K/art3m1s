import 'package:art3m1s/adaptive/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blocking progress can update and close', (tester) async {
    late BuildContext overlayContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            overlayContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final progress = showBlockingProgress(
      overlayContext,
      title: '正在导入游戏',
      message: '准备中…',
    );
    expect(progress, isNotNull);
    await tester.pump();
    expect(find.text('准备中…'), findsOneWidget);

    progress!.update('已复制 1 个文件');
    await tester.pump();
    expect(find.text('已复制 1 个文件'), findsOneWidget);

    progress.close();
    await tester.pump();
    expect(find.text('正在导入游戏'), findsNothing);
  });
}
