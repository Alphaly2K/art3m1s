import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:macos_window_utils/macos/ns_window_delegate.dart';
import 'package:macos_window_utils/ns_window_delegate_handler/ns_window_delegate_handle.dart';
import 'package:macos_window_utils/window_manipulator.dart';
import 'package:window_manager/window_manager.dart';

enum DesktopShellMode { standard, bigScreen }

/// 窗口全屏能力的窄接口，便于在不启动桌面插件的情况下测试切换逻辑。
abstract interface class DesktopWindowApi {
  Future<bool> isFullScreen();

  Future<void> setFullScreen(bool value);

  void addFullScreenListener(ValueChanged<bool> listener);

  void removeFullScreenListener(ValueChanged<bool> listener);
}

class WindowManagerDesktopWindowApi implements DesktopWindowApi {
  final Map<ValueChanged<bool>, _DesktopFullScreenRegistration> _listeners = {};

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);

  @override
  void addFullScreenListener(ValueChanged<bool> listener) {
    final registration = _DesktopFullScreenRegistration(listener);
    _listeners[listener] = registration;
    windowManager.addListener(registration.windowListener);
  }

  @override
  void removeFullScreenListener(ValueChanged<bool> listener) {
    final registration = _listeners.remove(listener);
    registration?.dispose();
  }
}

class _DesktopFullScreenRegistration {
  _DesktopFullScreenRegistration(ValueChanged<bool> listener)
    : windowListener = _DesktopFullScreenListener(listener),
      macosHandle = Platform.isMacOS
          ? WindowManipulator.addNSWindowDelegate(
              _MacosFullScreenDelegate(listener),
            )
          : null;

  final _DesktopFullScreenListener windowListener;
  final NSWindowDelegateHandle? macosHandle;

  void dispose() {
    windowManager.removeListener(windowListener);
    macosHandle?.removeFromHandler();
  }
}

class _DesktopFullScreenListener with WindowListener {
  _DesktopFullScreenListener(this.onChanged);

  final ValueChanged<bool> onChanged;

  @override
  void onWindowEnterFullScreen() => onChanged(true);

  @override
  void onWindowLeaveFullScreen() => onChanged(false);
}

class _MacosFullScreenDelegate extends NSWindowDelegate {
  _MacosFullScreenDelegate(this.onChanged);

  final ValueChanged<bool> onChanged;

  @override
  void windowDidEnterFullScreen() => onChanged(true);

  @override
  void windowDidExitFullScreen() => onChanged(false);
}

/// 桌面壳模式完全跟随窗口全屏状态，窗口化时不可能停留在 PS5 大屏壳。
class DesktopShellController extends ChangeNotifier {
  DesktopShellController({DesktopWindowApi? window})
    : _window = window ?? WindowManagerDesktopWindowApi() {
    _window.addFullScreenListener(_handleFullScreenChanged);
    _watchdog = Timer.periodic(_watchdogInterval, (_) {
      unawaited(syncWindowState());
    });
  }

  static const _transitionTimeout = Duration(seconds: 2);
  static const _pollInterval = Duration(milliseconds: 50);
  static const _watchdogInterval = Duration(milliseconds: 600);

  final DesktopWindowApi _window;
  late final Timer _watchdog;
  bool _isFullScreen = false;
  bool _transitioning = false;
  int _stateRevision = 0;
  bool _disposed = false;

  bool get isFullScreen => _isFullScreen;

  DesktopShellMode get mode =>
      _isFullScreen ? DesktopShellMode.bigScreen : DesktopShellMode.standard;

  Future<void> syncWindowState() async {
    final revision = _stateRevision;
    try {
      final fullScreen = await _window.isFullScreen();
      if (revision == _stateRevision) _setFullScreen(fullScreen);
    } catch (_) {
      if (revision == _stateRevision) _setFullScreen(false);
    }
  }

  Future<bool> enterBigScreen() async {
    if (_isFullScreen) return true;
    if (_transitioning) return false;
    _transitioning = true;
    try {
      await _window.setFullScreen(true);
      final entered =
          await _waitForFullScreen(true) || await _readFullScreenState();
      if (entered) _setFullScreen(true);
      return entered;
    } catch (_) {
      return false;
    } finally {
      _transitioning = false;
    }
  }

  Future<bool> exitBigScreen() async {
    if (!_isFullScreen) return true;
    if (_transitioning) return false;
    _transitioning = true;
    try {
      await _window.setFullScreen(false);
      final exited =
          await _waitForFullScreen(false) || !await _readFullScreenState();
      if (exited) _setFullScreen(false);
      return exited;
    } catch (_) {
      return false;
    } finally {
      _transitioning = false;
    }
  }

  Future<bool> _readFullScreenState() async {
    try {
      return await _window.isFullScreen();
    } catch (_) {
      return _isFullScreen;
    }
  }

  Future<bool> _waitForFullScreen(bool expected) async {
    final deadline = DateTime.now().add(_transitionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _readFullScreenState() == expected) return true;
      await Future<void>.delayed(_pollInterval);
    }
    return _readFullScreenState();
  }

  void _handleFullScreenChanged(bool value) {
    _stateRevision++;
    _setFullScreen(value);
  }

  void _setFullScreen(bool value) {
    if (_disposed || _isFullScreen == value) return;
    _isFullScreen = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog.cancel();
    _window.removeFullScreenListener(_handleFullScreenChanged);
    super.dispose();
  }
}
