import 'package:art3m1s/controllers/wheel_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop deltas map to Artemis wheel keys', () {
    final queue = WheelInputQueue()
      ..addScrollDelta(-1)
      ..addScrollDelta(0);

    expect(queue.take(), WheelInputQueue.wheelUpKey);
    queue.addScrollDelta(1);
    expect(queue.take(), WheelInputQueue.wheelDownKey);
    expect(queue.take(), isNull);
  });

  test('wheel pulses remain distinct and the queue stays bounded', () {
    final queue = WheelInputQueue();
    for (var i = 0; i < WheelInputQueue.maxPending + 3; i++) {
      queue.addKey(WheelInputQueue.wheelUpKey);
    }

    expect(queue.length, WheelInputQueue.maxPending);
    expect(queue.take(), WheelInputQueue.wheelUpKey);

    queue.addKey(WheelInputQueue.wheelDownKey);
    expect(queue.length, 1);
    expect(queue.take(), WheelInputQueue.wheelDownKey);
  });
}
