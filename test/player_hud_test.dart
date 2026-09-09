import 'package:art3m1s/widgets/player_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(800, 400);
  const pad = EdgeInsets.zero;

  test('settles to a left peek when dragged near the left edge', () {
    final settled = PlayerHudGeometry.settle(const Offset(10, 80), size, pad);
    expect(settled.dock, PlayerHudDock.left);
    expect(
      settled.pos.dx,
      -(PlayerHudGeometry.ballSize - PlayerHudGeometry.peek),
    );
  });

  test('settles to a right peek when dragged near the right edge', () {
    final settled = PlayerHudGeometry.settle(const Offset(770, 80), size, pad);
    expect(settled.dock, PlayerHudDock.right);
    expect(settled.pos.dx, size.width - PlayerHudGeometry.peek);
  });

  test('keeps a free position away from the edges', () {
    final settled = PlayerHudGeometry.settle(const Offset(120, 80), size, pad);
    expect(settled.dock, PlayerHudDock.none);
    expect(settled.pos.dx, 120);
  });

  test('undock restores an inset position on the same side', () {
    final left = PlayerHudGeometry.undock(PlayerHudDock.left, 80, size, pad);
    expect(left.dx, PlayerHudGeometry.margin);
    final right = PlayerHudGeometry.undock(PlayerHudDock.right, 80, size, pad);
    expect(
      right.dx,
      size.width - PlayerHudGeometry.ballSize - PlayerHudGeometry.margin,
    );
  });

  test('free dragging keeps the whole ball inside the safe bounds', () {
    final topLeft = PlayerHudGeometry.clampFree(
      const Offset(-500, -500),
      size,
      const EdgeInsets.fromLTRB(10, 20, 30, 40),
    );
    expect(topLeft, const Offset(22, 32));

    final bottomRight = PlayerHudGeometry.clampFree(
      const Offset(2000, 2000),
      size,
      const EdgeInsets.fromLTRB(10, 20, 30, 40),
    );
    expect(bottomRight, const Offset(712, 302));
  });

  test('docked ball clamps vertically after viewport changes', () {
    final ball = PlayerHudGeometry.dockedPos(
      PlayerHudDock.right,
      999,
      size,
      const EdgeInsets.only(bottom: 20),
    );
    expect(ball.dx, size.width - PlayerHudGeometry.peek);
    expect(ball.dy, 322);
  });

  testWidgets('HUD starts docked and mostly hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PlayerHud(
                title: 'test',
                showFps: false,
                keyboardShown: false,
                touchpadEnabled: false,
                showTouchpadToggle: false,
                showKeyboardToggle: false,
                onShowFpsChanged: _noopBool,
                onToggleKeyboard: _noop,
                onTouchpadChanged: _noopBool,
                onExit: _noop,
              ),
            ],
          ),
        ),
      ),
    );

    final positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    expect(
      positioned.left,
      -(PlayerHudGeometry.ballSize - PlayerHudGeometry.peek),
    );
  });
}

void _noop() {}

void _noopBool(bool _) {}
