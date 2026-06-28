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

  // FPS
  double _fps = 0;
  final List<int> _frameTimes = [];
  static const int _fpsSamples = 60;

  @override
  void initState() {
    super.initState();
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
    const frameMs = 16;
    var lastTime = DateTime.now();

    _timer = Timer.periodic(Duration(milliseconds: frameMs), (_) {
      if (_closing || !mounted) return;
      final now = DateTime.now();
      final deltaMs = now.difference(lastTime).inMilliseconds;
      lastTime = now;

      // track FPS
      _frameTimes.add(deltaMs);
      if (_frameTimes.length > _fpsSamples) _frameTimes.removeAt(0);
      final avgMs =
          _frameTimes.fold<int>(0, (a, b) => a + b) / _frameTimes.length;
      _fps = avgMs > 0 ? 1000.0 / avgMs : 0;

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
    _timer?.cancel();
    _frameImage?.dispose();
    _gameFocusNode.dispose();
    _bridge.shutdown();
    super.dispose();
  }

  void _closePlayer() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.projectPath.split('/').last,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closePlayer,
        ),
      ),
      body: Stack(
        children: [
          if (_frameImage != null)
            _buildGameView()
          else
            const Center(child: CircularProgressIndicator()),
          _buildVideoLayer(),
          if (ref.watch(settingsProvider).showFps)
            Positioned(
              top: 4,
              left: 4,
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
            ),
        ],
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
              _gameFocusNode.requestFocus();
              _feedPointerPosition(event, ox, oy, scale);
              _syncPointerButtons(event.buttons);
            },
            onPointerUp: (event) {
              _feedPointerPosition(event, ox, oy, scale);
              _syncPointerButtons(event.buttons);
            },
            onPointerCancel: (_) => _releasePointerButtons(),
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

        if (!playback.isFullscreen) {
          return Positioned.fill(child: IgnorePointer(child: video));
        }

        final fullscreen = video;
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
