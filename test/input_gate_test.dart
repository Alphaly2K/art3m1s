import 'package:art3m1s/models/input_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputGatePolicy', () {
    test('full profile passes everything through unchanged', () {
      const gate = InputGatePolicy.full;
      expect(gate.filterKey(13), 13);
      expect(gate.filterKey(27), 27);
      expect(gate.keyboard, isTrue);
      expect(gate.mouseButtons, isTrue);
      expect(gate.mouseMove, isTrue);
      expect(gate.touch, isTrue);
      expect(gate.wheelToKeys, isTrue);
      expect(gate.twoFingerRightClick, isTrue);
      expect(gate.knownProfile, InputGateProfile.full);
      expect(gate.isFull, isTrue);
    });

    test('touchOnly drops keyboard and forwarding, keeps touch and buttons', () {
      const gate = InputGatePolicy.touchOnly;
      expect(gate.filterKey(13), isNull);
      expect(gate.filterKey(65), isNull);
      expect(gate.keyboard, isFalse);
      expect(gate.mouseMove, isFalse);
      expect(gate.wheelToKeys, isFalse);
      expect(gate.twoFingerRightClick, isFalse);
      // 触屏 tap 在 core 里就是鼠标左键，必须保留。
      expect(gate.mouseButtons, isTrue);
      expect(gate.touch, isTrue);
      expect(gate.knownProfile, InputGateProfile.touchOnly);
    });

    test('blocked keys are dropped while other keys pass', () {
      const gate = InputGatePolicy(blockedKeys: {27, 13});
      expect(gate.filterKey(27), isNull);
      expect(gate.filterKey(13), isNull);
      expect(gate.filterKey(32), 32);
    });

    test('key remap applies after the blocklist and keeps press/release pairs', () {
      const gate = InputGatePolicy(
        blockedKeys: {27},
        keyRemap: {13: 32, 65: 66},
      );
      // Esc 被拦，不进入重映射。
      expect(gate.filterKey(27), isNull);
      expect(gate.filterKey(13), 32);
      expect(gate.filterKey(65), 66);
      // 未映射的键原样通过。
      expect(gate.filterKey(37), 37);
    });

    test('json round trip preserves custom rules', () {
      const gate = InputGatePolicy(
        keyboard: true,
        mouseMove: false,
        blockedKeys: {8, 9},
        keyRemap: {13: 32},
      );
      final restored = InputGatePolicy.fromJson(gate.toJson());
      expect(restored.filterKey(8), isNull);
      expect(restored.filterKey(9), isNull);
      expect(restored.filterKey(13), 32);
      expect(restored.mouseMove, isFalse);
      expect(restored.touch, isTrue);
      expect(restored.knownProfile, isNull);
    });

    test('null json falls back to full pass-through', () {
      final gate = InputGatePolicy.fromJson(null);
      expect(gate.isFull, isTrue);
    });

    test('malformed json entries are skipped instead of crashing', () {
      final gate = InputGatePolicy.fromJson({
        'blockedKeys': ['x', 13, null],
        'keyRemap': {'13': 'oops', 'bad': 32, '27': 9},
      });
      expect(gate.blockedKeys, {13});
      expect(gate.keyRemap, {27: 9});
    });
  });
}
