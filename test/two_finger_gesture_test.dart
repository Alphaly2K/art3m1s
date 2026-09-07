import 'package:art3m1s/controllers/two_finger_gesture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two-finger tap resolves only when released', () {
    final gesture = TwoFingerGestureTracker()
      ..begin(const [Offset(0, 0), Offset(20, 0)]);
    expect(gesture.active, isTrue);
    expect(gesture.end(), isTrue);
    expect(gesture.end(), isFalse);
  });

  test('drag takes priority over tap and emits wheel notches', () {
    final gesture = TwoFingerGestureTracker()
      ..begin(const [Offset(0, 0), Offset(20, 0)]);
    expect(
      gesture.move(const [Offset(0, 45), Offset(20, 45)], scrollEnabled: true),
      [136],
    );
    expect(gesture.end(), isFalse);
  });

  test('first movement and cancellation both suppress a tap', () {
    final moved = TwoFingerGestureTracker()
      ..begin(const [Offset(0, 0), Offset(20, 0)])
      ..move(const [Offset(0, 7), Offset(20, 7)], scrollEnabled: false);
    expect(moved.end(), isFalse);

    final cancelled = TwoFingerGestureTracker()
      ..begin(const [Offset(0, 0), Offset(20, 0)]);
    expect(cancelled.end(cancelled: true), isFalse);
  });
}
