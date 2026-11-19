import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

enum DesktopShellMode { standard, bigScreen }

class DesktopShellScope extends InheritedWidget {
  const DesktopShellScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final DesktopShellController controller;

  static DesktopShellController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopShellScope>()
      ?.controller;

  @override
  bool updateShouldNotify(DesktopShellScope oldWidget) =>
      controller != oldWidget.controller;
}

/// 窗口全屏能力的窄接口，便于在不启动桌面插件的情况下测试切换逻辑。
abstract interface class DesktopWindowApi {
  Future<bool> isFullScreen();

  Future<void> setFullScreen(bool value);
}

class WindowManagerDesktopWindowApi implements DesktopWindowApi {
  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);
}

class DesktopShellController extends ChangeNotifier {
  DesktopShellController({DesktopWindowApi? window})
    : _window = window ?? WindowManagerDesktopWindowApi();

  static const _transitionTimeout = Duration(seconds: 2);
  static const _pollInterval = Duration(milliseconds: 50);

  final DesktopWindowApi _window;
  DesktopShellMode _mode = DesktopShellMode.standard;
  bool _transitioning = false;
  bool _disposed = false;
  Object? _playerWindowOwner;
  bool? _playerPreviousFullScreen;

  DesktopShellMode get mode => _mode;

  Future<bool> enterBigScreen() async => _setMode(DesktopShellMode.bigScreen);

  Future<bool> exitBigScreen() async => _setMode(DesktopShellMode.standard);

  bool _setMode(DesktopShellMode mode) {
    if (_disposed) return false;
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
    return true;
  }

  Future<bool> togglePlayerFullScreen(Object player) =>
      _changePlayerFullScreen(player);

  Future<bool> exitPlayerFullScreen(Object player) =>
      _changePlayerFullScreen(player, expected: false);

  Future<bool> _changePlayerFullScreen(Object player, {bool? expected}) async {
    if (_disposed || _transitioning) return false;
    if (_playerWindowOwner != null && !identical(_playerWindowOwner, player)) {
      return false;
    }
    final wasFullScreen = await _readFullScreenState();
    if (_disposed || _transitioning || wasFullScreen == null) return false;
    if (_playerWindowOwner != null && !identical(_playerWindowOwner, player)) {
      return false;
    }
    final target = expected ?? !wasFullScreen;
    if (wasFullScreen == target) return true;
    _playerPreviousFullScreen ??= wasFullScreen;
    _playerWindowOwner = player;
    return _changeFullScreen(target);
  }

  Future<void> releasePlayerFullScreen(Object player) async {
    if (_disposed || !identical(_playerWindowOwner, player)) return;
    final previousFullScreen = _playerPreviousFullScreen!;
    final current = await _readFullScreenState();
    if (current != null && current != previousFullScreen) {
      await _changeFullScreen(previousFullScreen);
    }
    _playerWindowOwner = null;
    _playerPreviousFullScreen = null;
  }

  Future<bool> _changeFullScreen(bool expected) async {
    if (_disposed || _transitioning) return false;
    _transitioning = true;
    try {
      await _window.setFullScreen(expected);
      return await _waitForFullScreen(expected);
    } catch (_) {
      return false;
    } finally {
      _transitioning = false;
    }
  }

  Future<bool?> _readFullScreenState() async {
    try {
      return await _window.isFullScreen();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _waitForFullScreen(bool expected) async {
    final deadline = DateTime.now().add(_transitionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _readFullScreenState() == expected) return true;
      await Future<void>.delayed(_pollInterval);
    }
    return await _readFullScreenState() == expected;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
