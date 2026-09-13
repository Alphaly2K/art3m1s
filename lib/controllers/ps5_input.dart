import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// PS5 壳使用的语义化手柄动作。
enum Ps5InputAction {
  up,
  down,
  left,
  right,
  accept,
  back,
  previous,
  next,
  menu,
}

/// 将 Flutter 在 macOS / Windows / Linux 上暴露的手柄按键归一到语义动作。
///
/// Windows 当前把 Xbox A/B 映射为 [LogicalKeyboardKey.gameButton8/9]，
/// 其它平台多使用 [LogicalKeyboardKey.gameButtonA/B]；两套都保留，避免每个
/// 页面各自判断。方向键继续复用 Flutter 的统一焦点遍历。
Ps5InputAction? ps5InputAction(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.gameButton16) {
    return Ps5InputAction.up;
  }
  if (key == LogicalKeyboardKey.arrowDown) return Ps5InputAction.down;
  if (key == LogicalKeyboardKey.arrowLeft) return Ps5InputAction.left;
  if (key == LogicalKeyboardKey.arrowRight) return Ps5InputAction.right;
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.gameButtonA ||
      key == LogicalKeyboardKey.gameButton8) {
    return Ps5InputAction.accept;
  }
  if (key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.gameButtonB ||
      key == LogicalKeyboardKey.gameButton9) {
    return Ps5InputAction.back;
  }
  if (key == LogicalKeyboardKey.gameButtonLeft1 ||
      key == LogicalKeyboardKey.gameButtonLeft2 ||
      key == LogicalKeyboardKey.gameButton13) {
    return Ps5InputAction.previous;
  }
  if (key == LogicalKeyboardKey.gameButtonRight1 ||
      key == LogicalKeyboardKey.gameButtonRight2 ||
      key == LogicalKeyboardKey.gameButton12) {
    return Ps5InputAction.next;
  }
  if (key == LogicalKeyboardKey.gameButtonStart ||
      key == LogicalKeyboardKey.gameButtonMode) {
    return Ps5InputAction.menu;
  }
  return null;
}

class Ps5PreviousSectionIntent extends Intent {
  const Ps5PreviousSectionIntent();
}

class Ps5NextSectionIntent extends Intent {
  const Ps5NextSectionIntent();
}

class Ps5MenuIntent extends Intent {
  const Ps5MenuIntent();
}

Map<ShortcutActivator, Intent> get ps5GamepadShortcuts => const {
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonB): DismissIntent(),
  SingleActivator(LogicalKeyboardKey.gameButton9): DismissIntent(),
  SingleActivator(LogicalKeyboardKey.gameButton16): DirectionalFocusIntent(
    TraversalDirection.up,
  ),
  SingleActivator(LogicalKeyboardKey.gameButtonLeft1):
      Ps5PreviousSectionIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonLeft2):
      Ps5PreviousSectionIntent(),
  SingleActivator(LogicalKeyboardKey.gameButton13): Ps5PreviousSectionIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonRight1): Ps5NextSectionIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonRight2): Ps5NextSectionIntent(),
  SingleActivator(LogicalKeyboardKey.gameButton12): Ps5NextSectionIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonStart): Ps5MenuIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonMode): Ps5MenuIntent(),
};
