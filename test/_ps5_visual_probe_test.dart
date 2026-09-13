import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/providers/library_provider.dart';
import 'package:art3m1s/services/storage_service.dart';
import 'package:art3m1s/shell/ps5_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('PS5 shell visual probe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWith(
            (ref) => _FakeLibraryNotifier([
              GameEntry(
                name: "Marvel's Spider-Man: Miles Morales",
                path: '/tmp/spider-man',
                source: GameSource.directory,
                engine: GameEngineKind.art3m1s,
                addedAt: DateTime(2026, 9, 13),
                coverPath: 'assets/branding/art3m1s-logo-v1.png',
              ),
              GameEntry(
                name: "ASTRO's PLAYROOM",
                path: '/tmp/astro',
                source: GameSource.directory,
                engine: GameEngineKind.art3m1s,
                addedAt: DateTime(2026, 9, 12),
                coverPath: 'assets/branding/art3m1s-logo-v1.png',
              ),
            ]),
          ),
        ],
        child: const Ps5ShellApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final selectedTile = tester.widget<AnimatedScale>(
      find.byKey(const ValueKey('ps5-game-tile-/tmp/spider-man')),
    );
    final unselectedTile = tester.widget<AnimatedScale>(
      find.byKey(const ValueKey('ps5-game-tile-/tmp/astro')),
    );
    expect(selectedTile.scale, 1.22);
    expect(selectedTile.alignment, Alignment.topCenter);
    expect(unselectedTile.scale, 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ps5-game-tile-/tmp/spider-man')),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
    await expectLater(
      find.byType(Ps5ShellApp),
      matchesGoldenFile('ps5-shell-probe.png'),
    );
  });
}

class _FakeLibraryNotifier extends LibraryNotifier {
  _FakeLibraryNotifier(List<GameEntry> entries)
    : super(StorageService.instance) {
    state = entries;
  }
}
