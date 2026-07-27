import 'package:art3m1s/services/core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('宿主光标策略', () {
    test('非 Windows 宿主忽略脚本的永久隐藏命令', () {
      final bridge = CoreBridge(engineCursorControlEnabled: false);

      bridge.applyMouseConfig({'hide': 1, 'autohide': 0});

      expect(bridge.cursorHidden.value, isFalse);
    });

    test('Windows 宿主保留缺省参数并响应显式显示', () {
      final bridge = CoreBridge(engineCursorControlEnabled: true);

      bridge.applyMouseConfig({'hide': 1});
      expect(bridge.cursorHidden.value, isTrue);

      bridge.applyMouseConfig({'left': 100, 'top': 100});
      expect(bridge.cursorHidden.value, isTrue);

      bridge.applyMouseConfig({'hide': 0});
      expect(bridge.cursorHidden.value, isFalse);
    });

    testWidgets('自动隐藏超时后鼠标移动会重新显示', (tester) async {
      final bridge = CoreBridge(engineCursorControlEnabled: true);

      bridge.applyMouseConfig({'hide': 0, 'autohide': 100});
      expect(bridge.cursorHidden.value, isFalse);

      await tester.pump(const Duration(milliseconds: 101));
      expect(bridge.cursorHidden.value, isTrue);

      bridge.notifyMouseActivity();
      expect(bridge.cursorHidden.value, isFalse);

      bridge.applyMouseConfig({'autohide': 0});
      await tester.pump(const Duration(milliseconds: 101));
      expect(bridge.cursorHidden.value, isFalse);
    });
  });
}
