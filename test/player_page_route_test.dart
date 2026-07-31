import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:art3m1s/navigation/player_page_route.dart';

void main() {
  test(
    'PlayerPageRoute disables interactive back gestures on every platform',
    () {
      final route = PlayerPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );

      expect(route.popGestureEnabled, isFalse);
    },
  );

  testWidgets('PlayerPageRoute still allows explicit Navigator.pop', (
    WidgetTester tester,
  ) async {
    late PlayerPageRoute<void> playerRoute;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              playerRoute = PlayerPageRoute<void>(
                builder: (_) => const _PlayerPage(),
              );
              Navigator.of(context).push(playerRoute);
            },
            child: const Text('launch'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();

    expect(playerRoute.popGestureEnabled, isFalse);

    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    expect(find.text('launch'), findsOneWidget);
    expect(find.text('exit'), findsNothing);
  });

  testWidgets('ordinary routes keep their default gesture policy', (
    WidgetTester tester,
  ) async {
    late MaterialPageRoute<void> ordinaryRoute;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              ordinaryRoute = MaterialPageRoute<void>(
                builder: (_) => const _PlayerPage(),
              );
              Navigator.of(context).push(ordinaryRoute);
            },
            child: const Text('launch'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();

    expect(ordinaryRoute.popGestureEnabled, isTrue);
  });
}

class _PlayerPage extends StatelessWidget {
  const _PlayerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('exit'),
        ),
      ),
    );
  }
}
