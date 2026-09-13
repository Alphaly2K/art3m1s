import 'package:art3m1s/shell/desktop_shell_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('windowed state stays on the standard desktop shell', () async {
    final window = _FakeDesktopWindow();
    final controller = DesktopShellController(window: window);
    addTearDown(controller.dispose);

    await controller.syncWindowState();

    expect(controller.mode, DesktopShellMode.standard);
    expect(controller.isFullScreen, isFalse);
  });

  test(
    'big screen mode is entered only after the window is fullscreen',
    () async {
      final window = _FakeDesktopWindow();
      final controller = DesktopShellController(window: window);
      addTearDown(controller.dispose);

      final entered = await controller.enterBigScreen();

      expect(entered, isTrue);
      expect(window.fullScreen, isTrue);
      expect(controller.mode, DesktopShellMode.bigScreen);
    },
  );

  test(
    'failed fullscreen transition leaves the standard shell active',
    () async {
      final window = _FakeDesktopWindow(acceptFullScreen: false);
      final controller = DesktopShellController(window: window);
      addTearDown(controller.dispose);

      final entered = await controller.enterBigScreen();

      expect(entered, isFalse);
      expect(controller.mode, DesktopShellMode.standard);
    },
  );

  test('native fullscreen changes drive the shell mode', () async {
    final window = _FakeDesktopWindow();
    final controller = DesktopShellController(window: window);
    addTearDown(controller.dispose);

    window.emitFullScreen(true);
    expect(controller.mode, DesktopShellMode.bigScreen);

    window.emitFullScreen(false);
    expect(controller.mode, DesktopShellMode.standard);
  });

  test(
    'system fullscreen changes are recovered without a plugin event',
    () async {
      final window = _FakeDesktopWindow();
      final controller = DesktopShellController(window: window);
      addTearDown(controller.dispose);

      window.fullScreen = true;
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(controller.mode, DesktopShellMode.bigScreen);
    },
  );
}

class _FakeDesktopWindow implements DesktopWindowApi {
  _FakeDesktopWindow({this.acceptFullScreen = true});

  final bool acceptFullScreen;
  final List<ValueChanged<bool>> _listeners = [];
  bool fullScreen = false;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setFullScreen(bool value) async {
    if (!acceptFullScreen) return;
    fullScreen = value;
    emitFullScreen(value);
  }

  void emitFullScreen(bool value) {
    fullScreen = value;
    for (final listener in List<ValueChanged<bool>>.from(_listeners)) {
      listener(value);
    }
  }

  @override
  void addFullScreenListener(ValueChanged<bool> listener) {
    _listeners.add(listener);
  }

  @override
  void removeFullScreenListener(ValueChanged<bool> listener) {
    _listeners.remove(listener);
  }
}
