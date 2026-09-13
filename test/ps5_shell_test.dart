import 'dart:io';

import 'package:art3m1s/adaptive/ps5_chrome.dart';
import 'package:art3m1s/controllers/ps5_input.dart';
import 'package:art3m1s/widgets/ps5_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gamepad keys map to PS5 semantic actions', () {
    expect(
      ps5InputAction(LogicalKeyboardKey.gameButtonA),
      Ps5InputAction.accept,
    );
    expect(
      ps5InputAction(LogicalKeyboardKey.gameButton8),
      Ps5InputAction.accept,
    );
    expect(ps5InputAction(LogicalKeyboardKey.gameButtonB), Ps5InputAction.back);
    expect(ps5InputAction(LogicalKeyboardKey.gameButton9), Ps5InputAction.back);
    expect(ps5InputAction(LogicalKeyboardKey.gameButton16), Ps5InputAction.up);
    expect(
      ps5InputAction(LogicalKeyboardKey.gameButtonStart),
      Ps5InputAction.menu,
    );
  });

  testWidgets('PS5 file picker confirms with a gamepad key', (tester) async {
    final root = Directory.systemTemp.createTempSync('ps5-picker-test');
    Directory('${root.path}${Platform.pathSeparator}game-a').createSync();
    String? selected;
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Ps5ChromeScope(
          enabled: true,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      selected = await showPs5FilePicker(
                        context,
                        mode: Ps5FilePickerMode.directory,
                        title: '选择游戏文件夹',
                        initialDirectory: root.path,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('game-a').evaluate().isNotEmpty) break;
    }
    expect(find.byKey(const ValueKey('ps5-file-picker')), findsOneWidget);
    expect(find.text('game-a'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(selected, root.path);
    expect(find.byKey(const ValueKey('ps5-file-picker')), findsNothing);
  });
}
