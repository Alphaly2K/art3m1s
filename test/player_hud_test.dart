import 'package:art3m1s/widgets/player_hud.dart';
import 'package:flutter/widgets.dart';
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
}
