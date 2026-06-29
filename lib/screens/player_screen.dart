import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/game_entry.dart';
import '../providers/settings_provider.dart';
import '../services/core_bridge.dart';
import '../services/file_provider.dart';
import '../services/logger.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String projectPath;
  final GameSource source;

  const PlayerScreen({
    super.key,
    required this.projectPath,
    required this.source,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final _bridge = CoreBridge();
  Timer? _timer;
  ui.Image? _frameImage;
  bool _frameInFlight = false;
  bool _closing = false;
  int _stageW = 1280;
  int _stageH = 720;
  final FocusNode _gameFocusNode = FocusNode(debugLabel: 'game-input');
  final Set<int> _mouseButtonsDown = <int>{};
  final Set<int> _activePointers = {};

  Offset _ballPos = const Offset(16, 60);
  bool _panelOpen = false;
  Timer? _panelTimer;
  static const _panelAutoHideMs = 4000;

  final _keyboardNode = FocusNode();
  final _keyboardCtrl = TextEditingController();
  String _keyboardLast = '';
  bool _keyboardShown = false;

  // FPS
  double _fps = 0;
  final Stopwatch _frameClock = Stopwatch();
  int _nextFrameUs = 0;
  int _frameIndex = 0;
  int _fpsWindowStartUs = 0;
  int _fpsWindowFrames = 0;
  static const int _targetFrameUs = 1000000 ~/ 60;

  @override
  void initState() {
    super.initState();
    _keyboardCtrl.addListener(_onKeyboardInput);
    _lockOrientation();
    _init();
  }

  Future<void> _init() async {
    await _bridge.initialize();
    if (!mounted || _closing) {
      _bridge.shutdown();
      return;
    }
    if (!_bridge.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Core 库加载失败')));
      }
      return;
    }

    final debugMode = ref.read(settingsProvider).debugMode;
    _bridge.setDebug(debugMode);

    String iniContent;
    if (widget.source == GameSource.pfsArchive) {
      try {
        FileProvider.openPfs(widget.projectPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PFS 库加载失败: $e')));
        }
        return;
      }
      final bytes = FileProvider.readFile('system.ini');
      if (bytes == null) return;
      iniContent = String.fromCharCodes(bytes);
    } else {
      FileProvider.openDirectory(widget.projectPath);
      iniContent = File(
        '${widget.projectPath}${Platform.pathSeparator}system.ini',
      ).readAsStringSync();
    }

    _parseStageSize(iniContent);

    // 存档目录：统一放应用沙箱（getApplicationSupportDirectory）下，不分 PFS/目录
    // 模式——为 iOS 兼容（iOS 沙箱只允许写应用支持目录）。
    //
    // 注意：core 侧已把 s.savepath 前缀拼进相对路径（形如 `savedata/save0001.dat`），
    // 故这里的 saveDir 只是**每个游戏的基准目录**，不再追加 savePath，否则会双重前缀。
    // 用 projectPath 派生稳定的游戏标识作子目录，避免多游戏存档串档。
    final appSupport = await _getAppSupportDir();
    if (!mounted || _closing) {
      _bridge.shutdown();
      return;
    }
    final gameId = _gameIdFor(widget.projectPath);
    final saveDir =
        '$appSupport${Platform.pathSeparator}saves${Platform.pathSeparator}$gameId';
    _bridge.setSaveDir(saveDir);

    _bridge.registerFileReader();
    _bridge.createRuntime(
      _stageW,
      _stageH,
      backend: ref.read(settingsProvider).backend,
    );
    if (!_bridge.loadProject(iniContent)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('项目加载失败')));
      }
      return;
    }

    // 从 CoreBridge 获取实际的舞台尺寸（Rust 端解析 INI 后的准确值）
    _stageW = _bridge.stageWidth;
    _stageH = _bridge.stageHeight;

    if (!mounted || _closing) {
      _bridge.shutdown();
      return;
    }
    setState(() {});
    _startGameLoop();
  }

  void _parseStageSize(String ini) {
    for (final line in ini.split('\n')) {
      final trimmed = line.trim().toUpperCase();
      if (trimmed.startsWith('WIDTH=')) {
        _stageW = int.tryParse(trimmed.split('=').last.trim()) ?? 1280;
      }
      if (trimmed.startsWith('HEIGHT=')) {
        _stageH = int.tryParse(trimmed.split('=').last.trim()) ?? 720;
      }
    }
  }

  /// 由项目路径派生稳定的游戏标识，作为沙箱存档子目录名，避免多游戏串档。
  /// 取路径末段并清洗为文件系统安全字符；为空时退回路径哈希。
  String _gameIdFor(String projectPath) {
    final normalized = projectPath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final last =
        normalized.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
    final cleaned = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.isNotEmpty) return cleaned;
    return 'game_${projectPath.hashCode.toUnsigned(32).toRadixString(16)}';
  }

  /// 获取平台相关的应用支持目录（用于存放存档）。
  Future<String> _getAppSupportDir() async {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/Library/Application Support/art3m1s';
    } else if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          'C:\\Users\\Default';
      return '$appData\\art3m1s';
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/.local/share/art3m1s';
    } else if (Platform.isIOS || Platform.isAndroid) {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    }
    return '/tmp/art3m1s';
  }

  void _startGameLoop() {
    _frameClock
      ..reset()
      ..start();
    _nextFrameUs = _targetFrameUs;
    _frameIndex = 0;
    _fpsWindowStartUs = 0;
    _fpsWindowFrames = 0;

    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      if (_closing || !mounted) return;
      final nowUs = _frameClock.elapsedMicroseconds;
      if (nowUs < _nextFrameUs) return;
      _nextFrameUs += _targetFrameUs;
      if (nowUs - _nextFrameUs > _targetFrameUs * 2) {
        _nextFrameUs = nowUs + _targetFrameUs;
      }

      if (_bridge.isExitRequested()) {
        Log.info('[PlayerScreen] exit requested, popping...');
        _closePlayer();
        return;
      }

      if (_bridge.media.isFullscreenVideoBlocking) {
        return;
      }

      if (_frameInFlight) return;
      _frameInFlight = true;

      final deltaMs = _nextFrameDeltaMs();
      _trackFps(nowUs);
      final pixels = _bridge.advanceAndRender(deltaMs.clamp(0, 100));
      if (_bridge.isExitRequested() && mounted) {
        _frameInFlight = false;
        _closePlayer();
        return;
      }
      if (pixels != null && mounted) {
        _decodeFrame(pixels);
      } else {
        _frameInFlight = false;
      }
    });
  }

  int _nextFrameDeltaMs() {
    final previousMs = (_frameIndex * 1000) ~/ 60;
    _frameIndex += 1;
    final currentMs = (_frameIndex * 1000) ~/ 60;
    return currentMs - previousMs;
  }

  void _trackFps(int nowUs) {
    _fpsWindowFrames += 1;
    final elapsedUs = nowUs - _fpsWindowStartUs;
    if (elapsedUs < 1000000) return;
    _fps = _fpsWindowFrames * 1000000 / elapsedUs;
    _fpsWindowStartUs = nowUs;
    _fpsWindowFrames = 0;
  }

  void _decodeFrame(Uint8List pixels) {
    if (_closing || !mounted) {
      _frameInFlight = false;
      return;
    }
    final w = _stageW;
    final h = _stageH;
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, (image) {
      try {
        if (!mounted) {
          image.dispose();
          return;
        }
        final old = _frameImage;
        _frameImage = image;
        old?.dispose();
        setState(() {});
      } finally {
        _frameInFlight = false;
      }
    });
  }

  @override
  void dispose() {
    _closing = true;
    _unlockOrientation();
    _timer?.cancel();
    _panelTimer?.cancel();
    _frameImage?.dispose();
    _gameFocusNode.dispose();
    _keyboardCtrl.removeListener(_onKeyboardInput);
    _keyboardCtrl.dispose();
    _keyboardNode.dispose();
    _bridge.shutdown();
    super.dispose();
  }

  void _closePlayer() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _panelTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _lockOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _unlockOrientation() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _resetPanelTimer() {
    _panelTimer?.cancel();
    _panelTimer = Timer(const Duration(milliseconds: _panelAutoHideMs), () {
      if (mounted) setState(() => _panelOpen = false);
    });
  }

  void _toggleKeyboard() {
    setState(() {
      _keyboardShown = !_keyboardShown;
      if (_keyboardShown) {
        _keyboardNode.requestFocus();
      } else {
        _keyboardNode.unfocus();
      }
    });
    _resetPanelTimer();
  }

  void _onKeyboardInput() {
    final text = _keyboardCtrl.text;
    if (text == _keyboardLast) return;

    if (text.length > _keyboardLast.length) {
      final added = text.substring(_keyboardLast.length);
      for (final char in added.runes) {
        final key = _charToKey(char);
        if (key != null) {
          _bridge.feedKey(key, true);
          _bridge.feedKey(key, false);
        }
      }
    } else if (text.length < _keyboardLast.length) {
      _bridge.feedKey(8, true);
      _bridge.feedKey(8, false);
    }

    _keyboardLast = '';
    _keyboardCtrl.clear();
  }

  int? _charToKey(int char) {
    if (char == 0x0A) return 13; // enter
    if (char == 0x20) return 32; // space
    if (char == 0x08) return 8;  // backspace
    if (char >= 0x30 && char <= 0x39) return char;
    if (char >= 0x41 && char <= 0x5A) return char;
    if (char >= 0x61 && char <= 0x7A) return char - 32;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final showFps = ref.watch(settingsProvider.select((s) => s.showFps));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_frameImage != null)
            _buildGameView()
          else
            const Center(child: CircularProgressIndicator()),
          _buildVideoLayer(),
          if (showFps) _buildFpsDisplay(),
          _buildFloatingBall(),
          _buildControlPanel(),
          _buildHiddenKeyboard(),
        ],
      ),
    );
  }

  Widget _buildFpsDisplay() {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${_fps.toStringAsFixed(0)} fps',
          style: const TextStyle(
            color: Colors.lime,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBall() {
    return Positioned(
      left: _ballPos.dx,
      top: _ballPos.dy,
      child: GestureDetector(
        onTap: () {
          setState(() => _panelOpen = !_panelOpen);
          if (_panelOpen) _resetPanelTimer();
        },
        onPanUpdate: (d) {
          setState(() => _ballPos += d.delta);
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(180),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white54, width: 1.5),
          ),
          child: const Icon(Icons.menu, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    if (!_panelOpen) return const SizedBox.shrink();
    final showFps = ref.watch(settingsProvider.select((s) => s.showFps));
    final top = _ballPos.dy + 52;
    final left = _ballPos.dx;

    return Positioned(
      top: top,
      left: left,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (_) => _resetPanelTimer(),
        onPointerMove: (_) => _resetPanelTimer(),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            decoration: BoxDecoration(
              color: const Color(0xEE1A1A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _panelBtn(Icons.arrow_back, '退出', _closePlayer),
                _panelBtn(
                  Icons.speed,
                  'FPS ${showFps ? "开" : "关"}',
                  () => ref.read(settingsProvider.notifier).setShowFps(!showFps),
                ),
                _panelBtn(
                  Icons.keyboard,
                  '键盘 ${_keyboardShown ? "开" : "关"}',
                  _toggleKeyboard,
                ),
                IconTheme(
                  data: const IconThemeData(color: Colors.white38, size: 16),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 32),
                        Expanded(
                          child: Text(
                            widget.projectPath.split('/').last,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white24, fontSize: 10),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _panelOpen = false),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close, size: 14),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white54),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildHiddenKeyboard() {
    return Positioned(
      left: -1,
      top: -1,
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0,
        child: TextField(
          focusNode: _keyboardNode,
          controller: _keyboardCtrl,
          maxLines: 1,
          autofocus: false,
          showCursor: false,
          enableInteractiveSelection: false,
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _buildGameView() {
    final image = _frameImage!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;

        // Calculate the actual display rect for the game content
        final scaleX = cw / _stageW;
        final scaleY = ch / _stageH;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final dw = _stageW * scale;
        final dh = _stageH * scale;
        final ox = (cw - dw) / 2;
        final oy = (ch - dh) / 2;

        return KeyboardListener(
          focusNode: _gameFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerHover: (event) =>
                  _feedPointerPosition(event, ox, oy, scale),
              onPointerMove: (event) {
                _feedPointerPosition(event, ox, oy, scale);
                _syncPointerButtons(event.buttons);
              },
              onPointerDown: (event) {
                _activePointers.add(event.pointer);
                if (_activePointers.length >= 2) {
                  _bridge.feedMouseButton(2, true);
                }
                _gameFocusNode.requestFocus();
                _feedPointerPosition(event, ox, oy, scale);
                _syncPointerButtons(event.buttons);
              },
              onPointerUp: (event) {
                if (_activePointers.length >= 2) {
                  _bridge.feedMouseButton(2, false);
                }
                _activePointers.remove(event.pointer);
                _feedPointerPosition(event, ox, oy, scale);
                _syncPointerButtons(event.buttons);
              },
              onPointerCancel: (event) {
                if (_activePointers.length >= 2) {
                  _bridge.feedMouseButton(2, false);
                }
                _activePointers.remove(event.pointer);
                _releasePointerButtons();
              },
            onPointerSignal: _handlePointerSignal,
            child: Center(
              child: SizedBox(
                width: dw,
                height: dh,
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoLayer() {
    return ValueListenableBuilder(
      valueListenable: _bridge.media.videoPlayback,
      builder: (context, playback, _) {
        if (playback == null) {
          return const SizedBox.shrink();
        }
        final video = Center(
          child: AspectRatio(
            aspectRatio: playback.aspectRatio,
            child: playback.view,
          ),
        );

        final fullscreen = video;
        if (!playback.isFullscreen) {
          return Positioned.fill(child: AbsorbPointer(child: fullscreen));
        }

        if (!playback.skippable) {
          return Positioned.fill(child: AbsorbPointer(child: fullscreen));
        }
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _bridge.media.skipVideo,
            child: fullscreen,
          ),
        );
      },
    );
  }

  void _feedPointerPosition(
    PointerEvent event,
    double ox,
    double oy,
    double scale,
  ) {
    final point = _stagePoint(event.localPosition, ox, oy, scale);
    _bridge.feedMouse(point.dx.toInt(), point.dy.toInt());
  }

  Offset _stagePoint(Offset localPosition, double ox, double oy, double scale) {
    final mx = ((localPosition.dx - ox) / scale).clamp(
      0.0,
      _stageW.toDouble() - 1,
    );
    final my = ((localPosition.dy - oy) / scale).clamp(
      0.0,
      _stageH.toDouble() - 1,
    );
    return Offset(mx, my);
  }

  void _syncPointerButtons(int buttons) {
    final pressed = <int>{
      if ((buttons & kPrimaryMouseButton) != 0) 1,
      if ((buttons & kSecondaryMouseButton) != 0) 2,
      if ((buttons & kMiddleMouseButton) != 0) 3,
    };
    for (final button in pressed.difference(_mouseButtonsDown)) {
      _bridge.feedMouseButton(button, true);
    }
    for (final button in _mouseButtonsDown.difference(pressed).toList()) {
      _bridge.feedMouseButton(button, false);
    }
    _mouseButtonsDown
      ..clear()
      ..addAll(pressed);
  }

  void _releasePointerButtons() {
    for (final button in _mouseButtonsDown.toList()) {
      _bridge.feedMouseButton(button, false);
    }
    _mouseButtonsDown.clear();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final key = event.scrollDelta.dy < 0 ? 136 : 137;
    _bridge.feedKey(key, true);
    _bridge.feedKey(key, false);
  }

  void _handleKeyEvent(KeyEvent event) {
    final vk = _virtualKey(event.logicalKey);
    if (vk == null) return;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _bridge.feedKey(vk, true);
    } else if (event is KeyUpEvent) {
      _bridge.feedKey(vk, false);
    }
  }

  int? _virtualKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return 13;
    }
    if (key == LogicalKeyboardKey.escape) return 27;
    if (key == LogicalKeyboardKey.backspace) return 8;
    if (key == LogicalKeyboardKey.tab) return 9;
    if (key == LogicalKeyboardKey.space) return 32;
    if (key == LogicalKeyboardKey.arrowLeft) return 37;
    if (key == LogicalKeyboardKey.arrowUp) return 38;
    if (key == LogicalKeyboardKey.arrowRight) return 39;
    if (key == LogicalKeyboardKey.arrowDown) return 40;
    if (key == LogicalKeyboardKey.pageUp) return 33;
    if (key == LogicalKeyboardKey.pageDown) return 34;
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      return 17;
    }
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return 18;
    }
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return 16;
    }
    if (key == LogicalKeyboardKey.f1) return 112;
    if (key == LogicalKeyboardKey.f2) return 113;
    if (key == LogicalKeyboardKey.f3) return 114;
    if (key == LogicalKeyboardKey.f4) return 115;
    if (key == LogicalKeyboardKey.f5) return 116;
    if (key == LogicalKeyboardKey.f6) return 117;
    if (key == LogicalKeyboardKey.f7) return 118;
    if (key == LogicalKeyboardKey.f8) return 119;
    if (key == LogicalKeyboardKey.f9) return 120;
    if (key == LogicalKeyboardKey.f10) return 121;
    if (key == LogicalKeyboardKey.f11) return 122;
    if (key == LogicalKeyboardKey.f12) return 123;

    final label = key.keyLabel;
    if (label.length == 1) {
      final code = label.toUpperCase().codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) return code;
      if (code >= 0x41 && code <= 0x5A) return code;
    }
    return null;
  }
}
