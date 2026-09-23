import 'dart:io';

import 'package:art3m1s/adaptive/ps5_chrome.dart';
import 'package:art3m1s/controllers/ps5_input.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/providers/library_provider.dart';
import 'package:art3m1s/services/storage_service.dart';
import 'package:art3m1s/shell/ps5_shell.dart';
import 'package:art3m1s/widgets/ps5_file_picker.dart';
import 'package:flutter/gestures.dart';
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
                screenshotPath: File(
                  'assets/branding/art3m1s-logo-v1.png',
                ).absolute.path,
              ),
            ]),
          ),
        ],
        child: const Ps5ShellApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2100));

    expect(find.text('Media'), findsNothing);
    expect(find.text('资源库'), findsOneWidget);
    expect(find.byType(Ps5FocusShine), findsWidgets);
    final carousel = tester.widget<Focus>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Focus &&
            widget.focusNode?.debugLabel == 'PS5 home carousel',
      ),
    );
    expect(carousel.focusNode?.hasFocus, isTrue);
    expect(find.text('上次游玩'), findsOneWidget);
    expect(find.text('加入资料库'), findsOneWidget);
    expect(find.text('运行引擎'), findsOneWidget);
    expect(find.text('来源'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('ps5-home-top-bar-opacity')),
          )
          .opacity,
      1,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('添加游戏'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('添加游戏'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('添加游戏'), findsNothing);
    final carouselOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('ps5-game-tile-/tmp/library-sample')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(carouselOpacity.opacity, 0);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('ps5-home-top-bar-opacity')),
          )
          .opacity,
      0,
    );
    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(
      tester
          .widget<Ps5IconButton>(
            find.ancestor(
              of: find.byTooltip('搜索'),
              matching: find.byType(Ps5IconButton),
            ),
          )
          .size,
      60,
    );
    expect(
      find.byKey(const ValueKey('ps5-home-screenshot-/tmp/library-sample')),
      findsOneWidget,
    );
    final collapsedCover = tester.widget<AnimatedPositioned>(
      find.byKey(const ValueKey('ps5-collapsed-game-cover')),
    );
    expect(collapsedCover.left, 56);
    expect(collapsedCover.top, 24);
    expect(collapsedCover.width, 78);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey('ps5-home-screenshot-/tmp/library-sample'),
            ),
          )
          .left,
      closeTo(56, 0.1),
    );

    final playAction = tester.widget<FocusableActionDetector>(
      find.byWidgetPredicate(
        (widget) =>
            widget is FocusableActionDetector &&
            widget.focusNode?.debugLabel == 'PS5 home play action',
      ),
    );
    final moreAction = tester.widget<FocusableActionDetector>(
      find.byWidgetPredicate(
        (widget) =>
            widget is FocusableActionDetector &&
            widget.focusNode?.debugLabel == 'PS5 home more action',
      ),
    );
    final screenshotAction = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: find.byKey(
          const ValueKey('ps5-home-screenshot-/tmp/library-sample'),
        ),
        matching: find.byType(FocusableActionDetector),
      ),
    );
    expect(playAction.focusNode?.hasFocus, isTrue);
    expect(screenshotAction.focusNode?.hasFocus, isFalse);

    // 左右键只在操作按钮排内移动，最右侧不能越到上方截图。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(moreAction.focusNode?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(moreAction.focusNode?.hasFocus, isTrue);
    expect(screenshotAction.focusNode?.hasFocus, isFalse);

    // 从任一操作按钮按上方向键进入当前游戏截图。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(screenshotAction.focusNode?.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ps5-screenshot-preview')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('ps5-home-top-bar-chrome-opacity')),
          )
          .opacity,
      0,
    );
    final previewImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('ps5-screenshot-preview')),
        matching: find.byType(Image),
      ),
    );
    expect(previewImage.alignment, Alignment.center);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('ps5-screenshot-preview')), findsNothing);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('ps5-home-top-bar-chrome-opacity')),
          )
          .opacity,
      1,
    );
    expect(screenshotAction.focusNode?.hasFocus, isTrue);
    // 截图卡继续按 Tab 回到轮播；方向上键也保留同样的返回语义。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byKey(
                const ValueKey('ps5-game-tile-/tmp/library-sample'),
              ),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      1,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('ps5-home-top-bar-opacity')),
          )
          .opacity,
      1,
    );

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('ps5-game-tile-/tmp/library-sample')),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsNothing);

    await tester.tap(find.byTooltip('项目操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);
    expect(find.byType(PopupMenuItem<int>), findsNothing);
    final heroMenu = tester.getRect(
      find.byKey(const ValueKey('ps5-list-menu')),
    );
    final heroMenuButton = tester.getRect(find.byTooltip('项目操作'));
    expect(heroMenu.left, greaterThan(heroMenuButton.right));
    await tester.tapAt(const Offset(1500, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    await tester.tap(find.text('资源库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('ps5-game-library-page')), findsOneWidget);
    expect(find.text('全部游戏'), findsOneWidget);
    expect(find.text('已安装'), findsWidgets);
    expect(find.text('Kirikiri'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('ps5-game-library-tile-/tmp/library-sample')),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final gridMenu = tester.getRect(
      find.byKey(const ValueKey('ps5-list-menu')),
    );
    expect(gridMenu.center.dx, closeTo(800, 1));
    expect(gridMenu.center.dy, closeTo(500, 1));
    await tester.tapAt(const Offset(1500, 900));
    await tester.pump(const Duration(milliseconds: 220));

    await tester.tap(find.byKey(const ValueKey('ps5-library-filter-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsOneWidget);
    expect(find.text('排序方式'), findsWidgets);
    expect(find.text('筛选'), findsOneWidget);
    expect(find.text('最近游玩'), findsWidgets);
    expect(find.text('名称（A - Z）'), findsOneWidget);
    expect(find.text('名称（Z - A）'), findsOneWidget);
    expect(find.textContaining('Purchased Date'), findsNothing);
    final filterButton = tester.getRect(
      find.byKey(const ValueKey('ps5-library-filter-button')),
    );
    final filterMenu = tester.getRect(
      find.byKey(const ValueKey('ps5-list-menu')),
    );
    expect(filterMenu.left, greaterThan(filterButton.right));

    await tester.tapAt(const Offset(1500, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text('主页'));
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

  testWidgets('Esc never exits big screen; gamepad B exits only at home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var exitCalls = 0;
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
        child: Ps5ShellApp(
          onExitBigScreen: () async {
            exitCalls++;
            return true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2100));

    // 首页按 Esc：不退出。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(exitCalls, 0);

    // 三点菜单打开时按 B：关闭菜单，不退出。
    await tester.tap(find.byTooltip('项目操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(exitCalls, 0);
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsNothing);

    // 三点菜单打开时按 Esc：关闭菜单，不退出。
    await tester.tap(find.byTooltip('项目操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(exitCalls, 0);
    expect(find.byKey(const ValueKey('ps5-list-menu')), findsNothing);

    // 设置页打开时按 Esc：关闭设置页，不退出大屏。
    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('ps5-settings-screen')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(exitCalls, 0);
    expect(find.byKey(const ValueKey('ps5-settings-screen')), findsNothing);

    // 设置页打开时按手柄 B：关闭设置页，不退出大屏。
    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('ps5-settings-screen')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(exitCalls, 0);
    expect(find.byKey(const ValueKey('ps5-settings-screen')), findsNothing);

    // 首页按手柄 B：退出大屏。
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(exitCalls, 1);
  });
}

class _FakeLibraryNotifier extends LibraryNotifier {
  _FakeLibraryNotifier(List<GameEntry> entries)
    : super(StorageService.instance) {
    state = entries;
  }
}
