import 'package:art3m1s/services/media_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaOperationGate', () {
    test('同一声音 key 只保留最新异步命令', () {
      final gate = MediaOperationGate();

      final play = gate.begin('se:10');
      final replacement = gate.begin('se:10');

      expect(gate.isCurrent(play), isFalse);
      expect(gate.isCurrent(replacement), isTrue);
    });

    test('不同声音 id 仍可同时播放', () {
      final gate = MediaOperationGate();

      final first = gate.begin('se:11');
      final second = gate.begin('se:12');

      expect(gate.isCurrent(first), isTrue);
      expect(gate.isCurrent(second), isTrue);
    });

    test('stop 与 stop-all 会使尚未完成的创建失效', () {
      final gate = MediaOperationGate();

      final stopped = gate.begin('voice:3');
      gate.invalidate('voice:3');
      expect(gate.isCurrent(stopped), isFalse);

      final beforeStopAll = gate.begin('bgm');
      gate.invalidateAll();
      expect(gate.isCurrent(beforeStopAll), isFalse);

      final afterStopAll = gate.begin('bgm');
      expect(gate.isCurrent(afterStopAll), isTrue);
    });
  });
}
