import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:art3m1s/main.dart';

void main() {
  testWidgets('App renders library', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: Art3m1sApp()));
    await tester.pumpAndSettle();

    expect(find.text('库中暂无项目'), findsOneWidget);
  });
}
