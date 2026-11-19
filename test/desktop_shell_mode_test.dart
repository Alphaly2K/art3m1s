import 'package:art3m1s/shell/desktop_shell_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native window changes leave the selected shell mounted', () async {
    final window = _FakeDesktopWindow()..fullScreen = true;
    final controller = DesktopShellController(window: window);
    addTearDown(controller.dispose);
    final changes = <DesktopShellMode>[];
    controller.addListener(() => changes.add(controller.mode));

    expect(controller.mode, DesktopShellMode.standard);
    expect(await controller.enterBigScreen(), isTrue);
    window.fullScreen = false;
    expect(controller.mode, DesktopShellMode.bigScreen);
    window.fullScreen = true;
    expect(await controller.exitBigScreen(), isTrue);
    expect(window.fullScreen, isTrue);
    expect(changes, [DesktopShellMode.bigScreen, DesktopShellMode.standard]);
    expect(window.requests, isEmpty);
  });

  test('a windowed app can explicitly enter and exit big screen', () async {
    final window = _FakeDesktopWindow();
    final controller = DesktopShellController(window: window);
    addTearDown(controller.dispose);

    expect(await controller.enterBigScreen(), isTrue);
    expect(controller.mode, DesktopShellMode.bigScreen);
    expect(window.fullScreen, isFalse);
    expect(await controller.exitBigScreen(), isTrue);
    expect(controller.mode, DesktopShellMode.standard);
    expect(window.requests, isEmpty);
  });

  test(
    'script fullscreen keeps the player shell and restores the window',
    () async {
      final window = _FakeDesktopWindow();
      final controller = DesktopShellController(window: window);
      addTearDown(controller.dispose);
      final player = Object();

      expect(await controller.togglePlayerFullScreen(player), isTrue);
      expect(window.fullScreen, isTrue);
      expect(controller.mode, DesktopShellMode.standard);
      expect(await controller.togglePlayerFullScreen(Object()), isFalse);

      await controller.releasePlayerFullScreen(player);
      expect(window.fullScreen, isFalse);
      window.fullScreen = true;
      expect(await controller.enterBigScreen(), isTrue);

      expect(await controller.exitPlayerFullScreen(player), isTrue);
      expect(window.fullScreen, isFalse);
      expect(controller.mode, DesktopShellMode.bigScreen);
      await controller.releasePlayerFullScreen(player);
      expect(window.fullScreen, isTrue);
    },
  );
}

class _FakeDesktopWindow implements DesktopWindowApi {
  final requests = <bool>[];
  bool fullScreen = false;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setFullScreen(bool value) async {
    requests.add(value);
    fullScreen = value;
  }
}
