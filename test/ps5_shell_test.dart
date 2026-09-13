import 'dart:io';

import 'package:art3m1s/adaptive/ps5_chrome.dart';
import 'package:art3m1s/controllers/ps5_input.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/providers/library_provider.dart';
import 'package:art3m1s/services/storage_service.dart';
import 'package:art3m1s/shell/ps5_shell.dart';
import 'package:art3m1s/widgets/ps5_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('gamepad keys map to PS5 semantic actions', () {
    expect(
      ps5InputAction(LogicalKeyboardKey.gameButtonA),
      Ps5InputAction.accept,
    );
    expect(
      ps5InputAction(LogicalKeyboardKey.gameButton8),
      Ps5InputAction.accept,
    );
    expect(ps5InputAction(LogicalKeyboardKey.gameButtonB), Ps5InputAction.back);
    expect(ps5InputAction(LogicalKeyboardKey.gameButton9), Ps5InputAction.back);
    expect(ps5InputAction(LogicalKeyboardKey.gameButton16), Ps5InputAction.up);
    expect(
      ps5InputAction(LogicalKeyboardKey.gameButtonStart),
      Ps5InputAction.menu,
    );
  });

  testWidgets('PS5 file picker confirms with a gamepad key', (tester) async {
    final root = Directory.systemTemp.createTempSync('ps5-picker-test');
    Directory('${root.path}${Platform.pathSeparator}game-a').createSync();
    String? selected;
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Ps5ChromeScope(
          enabled: true,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      selected = await showPs5FilePicker(
                        context,
                        mode: Ps5FilePickerMode.directory,
                        title: '选择游戏文件夹',
                        initialDirectory: root.path,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('game-a').evaluate().isNotEmpty) break;
    }
    expect(find.byKey(const ValueKey('ps5-file-picker')), findsOneWidget);
    expect(find.text('game-a'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(selected, root.path);
    expect(find.byKey(const ValueKey('ps5-file-picker')), findsNothing);
  });

  testWidgets('Game Library replaces Media and exposes the PS5 filter menu', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWith(
            (ref) => _FakeLibraryNotifier([
              GameEntry(
                name: 'Library sample',
                path: '/tmp/library-sample',
                source: GameSource.directory,
                engine: GameEngineKind.art3m1s,
                addedAt: DateTime(2026, 9, 13),
              ),
            ]),
          ),
        ],
        child: const Ps5ShellApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2100));

    expect(find.text('Media'), findsNothing);
    expect(find.text('Game Library'), findsOneWidget);
    expect(find.byType(Ps5FocusShine), findsWidgets);

    await tester.tap(find.byTooltip('项目操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);
    expect(find.byType(PopupMenuItem<int>), findsNothing);
    await tester.tapAt(const Offset(1500, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    await tester.tap(find.text('Game Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('ps5-game-library-page')), findsOneWidget);
    expect(find.text('Your Collection'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ps5-library-filter-button')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsOneWidget);
    expect(find.text('Sort by'), findsWidgets);
    expect(find.text('Filters'), findsOneWidget);

    await tester.tapAt(const Offset(1500, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byType(Ps5GameLibraryGlyph));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('ps5-settings-screen')), findsOneWidget);
    expect(find.text('关于 Art3m1s'), findsOneWidget);

    await tester.tap(find.text('关于 Art3m1s'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Flutter App'), findsOneWidget);
  });
}

class _FakeLibraryNotifier extends LibraryNotifier {
  _FakeLibraryNotifier(List<GameEntry> entries)
    : super(StorageService.instance) {
    state = entries;
  }
}
