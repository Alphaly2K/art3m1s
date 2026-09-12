import 'package:art3m1s/engine/backends/art3m1s_engine_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('宿主光标策略', () {
    test('非 Windows 宿主忽略脚本的永久隐藏命令', () {
      final runtime = Art3m1sEngineRuntime(engineCursorControlEnabled: false);

      runtime.applyMouseConfig({'hide': 1, 'autohide': 0});

      expect(runtime.cursorHidden.value, isFalse);
    });

    test('Windows 宿主保留缺省参数并响应显式显示', () {
      final runtime = Art3m1sEngineRuntime(engineCursorControlEnabled: true);

      runtime.applyMouseConfig({'hide': 1});
      expect(runtime.cursorHidden.value, isTrue);

      runtime.applyMouseConfig({'left': 100, 'top': 100});
      expect(runtime.cursorHidden.value, isTrue);

      runtime.applyMouseConfig({'hide': 0});
      expect(runtime.cursorHidden.value, isFalse);
    });

    testWidgets('自动隐藏超时后鼠标移动会重新显示', (tester) async {
      final runtime = Art3m1sEngineRuntime(engineCursorControlEnabled: true);

      runtime.applyMouseConfig({'hide': 0, 'autohide': 100});
      expect(runtime.cursorHidden.value, isFalse);

      await tester.pump(const Duration(milliseconds: 101));
      expect(runtime.cursorHidden.value, isTrue);

      runtime.notifyMouseActivity();
      expect(runtime.cursorHidden.value, isFalse);

      runtime.applyMouseConfig({'autohide': 0});
      await tester.pump(const Duration(milliseconds: 101));
      expect(runtime.cursorHidden.value, isFalse);
    });
  });
}
