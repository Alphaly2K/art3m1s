import 'package:art3m1s/controllers/mobile_touchpad.dart';
import 'package:art3m1s/providers/settings_provider.dart';
import 'package:art3m1s/services/core_bridge.dart';
import 'package:art3m1s/widgets/engine_dialog.dart';
import 'package:art3m1s/widgets/mobile_game_cursor.dart';
import 'package:art3m1s/widgets/mobile_touchpad_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('移动触摸板指针', () {
    test('按显示缩放换算相对位移', () {
      final pointer = MobileTouchpadPointer(stageWidth: 1280, stageHeight: 720);

      expect(
        pointer.moveBy(const Offset(20, -10), 0.5),
        const Offset(680, 340),
      );
    });

    test('移动和舞台尺寸变化都会约束指针边界', () {
      final pointer = MobileTouchpadPointer(stageWidth: 1280, stageHeight: 720);

      expect(
        pointer.moveBy(const Offset(10000, -10000), 1),
        const Offset(1279, 0),
      );
      pointer.updateStageSize(800, 600);
      expect(pointer.position, const Offset(799, 0));
    });
  });

  test('触摸板开关默认关闭并可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SettingsNotifier();
    await notifier.ready;
    expect(notifier.state.mobileTouchpadEnabled, isFalse);

    await notifier.setMobileTouchpadEnabled(true);
    expect(notifier.state.mobileTouchpadEnabled, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'mobile_touchpad_enabled',
      ),
      isTrue,
    );
    notifier.dispose();

    final restored = SettingsNotifier();
    await restored.ready;
    expect(restored.state.mobileTouchpadEnabled, isTrue);
    restored.dispose();
  });

  testWidgets('轻点发送一次点击，长按移动保持拖拽直到抬起', (tester) async {
    var taps = 0;
    var dragStarts = 0;
    var dragEnds = 0;
    final moves = <Offset>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 300,
          child: MobileTouchpadSurface(
            onTap: () => taps += 1,
            onMove: moves.add,
            onDragStart: () => dragStarts += 1,
            onDragEnd: () => dragEnds += 1,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(MobileTouchpadSurface));
    expect(taps, 1);

    await tester.drag(find.byType(MobileTouchpadSurface), const Offset(40, 20));
    expect(moves, isNotEmpty);
    expect(
      moves.fold<double>(0, (sum, delta) => sum + delta.dx),
      greaterThan(0),
    );
    moves.clear();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MobileTouchpadSurface)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    expect(dragStarts, 1);
    expect(dragEnds, 0);

    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    expect(moves, isNotEmpty);
    expect(moves.last.dx, closeTo(24, 0.01));
    expect(moves.last.dy, closeTo(12, 0.01));

    await gesture.up();
    await tester.pump();
    expect(dragEnds, 1);
  });

  testWidgets('移动端光标使用同画布绘制的系统箭头', (tester) async {
    await tester.pumpWidget(const Center(child: MobileGameCursor()));

    expect(find.byType(CustomPaint), findsOneWidget);
    expect(find.byIcon(Icons.near_me), findsNothing);
    expect(
      tester.getSize(find.byType(MobileGameCursor)),
      MobileGameCursor.size,
    );
  });

  testWidgets('引擎输入框允许提交空字符串且安全结束输入焦点', (tester) async {
    EngineDialogResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showEngineDialog(
                context,
                const EngineDialogRequest(
                  title: 'Name',
                  message: '',
                  hasCancel: false,
                  hasTextField: true,
                  textFieldSize: 10,
                  initialText: 'initial',
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result?.accepted, isTrue);
    expect(result?.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
