import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/providers/settings_provider.dart';
import 'package:art3m1s/screens/player_screen.dart';

import 'package:art3m1s/navigation/player_page_route.dart';

void main() {
  testWidgets('player can close while settings initialization is pending', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final settings = _DeferredSettings(ready.future);
    await settings.loaded;
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith((ref) => settings)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PlayerScreen(
            gameId: 'fixture',
            projectPath: 'unused',
            source: GameSource.directory,
            translationEnabled: false,
            translationPatchPath: '',
            environmentPatchEnabled: false,
            addedAt: DateTime(2026),
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

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

class _DeferredSettings extends SettingsNotifier {
  _DeferredSettings(this._deferred);
  final Future<void> _deferred;
  Future<void> get loaded => super.ready;
  @override
  Future<void> get ready => _deferred;
}
