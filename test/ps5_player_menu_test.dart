import 'package:art3m1s/adaptive/ps5_chrome.dart';
import 'package:art3m1s/widgets/ps5_player_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('player route guard consumes menu keys and blocks route pop', (
    tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Ps5PlayerRouteGuard(
          onToggleMenu: () => toggles++,
          child: const Scaffold(
            body: Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump();

    final guard = tester.widget<PopScope>(find.byType(PopScope));
    expect(guard.canPop, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(toggles, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(toggles, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await tester.pump();
    expect(toggles, 2);
  });

  testWidgets('PS5 player menu exposes and operates useful game controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: _MenuProbe()));
    await tester.pump();

    expect(find.byKey(const ValueKey('ps5-player-menu')), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('截图'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('音量'), findsOneWidget);
    expect(find.text('电源'), findsOneWidget);
    expect(find.byTooltip('搜索'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('ps5-player-action-screenshot')),
    );
    await tester.pump();
    expect(_MenuProbeState.screenshots, 1);

    await tester.tap(find.byKey(const ValueKey('ps5-player-action-power')));
    await tester.pump();
    expect(find.text('关闭 Art3m1s'), findsOneWidget);
    expect(find.text('退出大屏幕模式'), findsOneWidget);
    expect(find.text('关闭电源'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('关闭 Art3m1s'), findsNothing);
    expect(find.byKey(const ValueKey('ps5-player-menu')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await tester.pump();

    expect(find.byKey(const ValueKey('ps5-player-menu')), findsNothing);
    expect(find.text('resumed'), findsOneWidget);
  });

  testWidgets('PS5 player menu ignores repeated toggle keys', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: _MenuProbe()));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byKey(const ValueKey('ps5-player-menu')), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await tester.pump();
    expect(find.byKey(const ValueKey('ps5-player-menu')), findsNothing);
  });
}

class _MenuProbe extends StatefulWidget {
  const _MenuProbe();

  @override
  State<_MenuProbe> createState() => _MenuProbeState();
}

class _MenuProbeState extends State<_MenuProbe> {
  static int screenshots = 0;

  bool _open = true;
  bool _showFps = false;

  @override
  Widget build(BuildContext context) {
    return Ps5ChromeScope(
      enabled: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF36556B), Color(0xFF0C1118)],
                ),
              ),
            ),
            if (_open)
              Ps5PlayerMenu(
                title: 'Marvel\'s Spider-Man: Miles Morales',
                showFps: _showFps,
                addedAt: DateTime(2026, 9, 13),
                lastPlayedAt: DateTime(2026, 9, 12, 21, 30),
                sessionStartedAt: DateTime(2026, 9, 13, 22, 0),
                engineLabel: 'Artemis',
                sourceLabel: '工程目录',
                masterVolume: 0.6,
                now: () => DateTime(2026, 9, 13, 22, 15),
                onShowFpsChanged: (value) => setState(() => _showFps = value),
                onResume: () => setState(() => _open = false),
                onExit: _noop,
                onScreenshot: () => _MenuProbeState.screenshots++,
                onVolumeChanged: _noopVolume,
                onExitBigScreen: _noop,
                onCloseApp: _noop,
              )
            else
              const Center(child: Text('resumed')),
          ],
        ),
      ),
    );
  }
}

void _noop() {}

void _noopVolume(double value) {}
