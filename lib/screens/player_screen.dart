import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../controllers/mobile_touchpad.dart';
import '../controllers/two_finger_gesture.dart';
import '../models/game_entry.dart';
import '../models/input_gate.dart';
import '../providers/settings_provider.dart';
import '../services/app_data_paths.dart';
import '../services/core_bridge.dart';
import '../services/file_provider.dart';
import '../services/game_manifest.dart';
import '../services/logger.dart';
import '../services/profiler_snapshot.dart';
import '../services/project_charset.dart';
import '../services/text_translation_service.dart';
import '../widgets/engine_dialog.dart';
import '../widgets/mobile_game_cursor.dart';
import '../widgets/mobile_touchpad_surface.dart';
import '../widgets/player_hud.dart';
import '../widgets/profiler_overlay.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String gameId;
  final String projectPath;
  final GameSource source;
  final bool translationEnabled;
  final String translationPatchPath;
  final bool environmentPatchEnabled;
  final bool experimentalElunaEnabled;

  /// 输入门控策略（来自资料库条目/项目补丁），默认全放行。
  final InputGatePolicy inputGate;

  /// 项目清单指定的覆盖字体（游戏内相对路径）；空串表示无。
  final String fontOverridePath;

  /// 上报给脚本的机种串覆盖（来自资料库条目/项目补丁）；空串跟随项目平台。
  final String reportedOs;

  /// system.ini 启动段（来自该游戏的 manifest）。
  final String runtimePlatform;

  final String? manifestPath;

  const PlayerScreen({
    super.key,
    required this.gameId,
    required this.projectPath,
    required this.source,
    required this.translationEnabled,
    required this.translationPatchPath,
    required this.environmentPatchEnabled,
    required this.experimentalElunaEnabled,
    this.inputGate = InputGatePolicy.full,
    this.fontOverridePath = '',
    this.reportedOs = '',
    this.runtimePlatform = 'WINDOWS',
    this.manifestPath,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final CoreBridge _bridge;
  late final Ticker _gameTicker;
  ui.Image? _frameImage;
  bool _sharedTextureReady = false;
  bool _frameInFlight = false;
  bool _closing = false;
  GameEntry? _activeConfig;
  int _stageW = 1280;
  int _stageH = 720;
  final FocusNode _gameFocusNode = FocusNode(debugLabel: 'game-input');
  final Set<int> _mouseButtonsDown = <int>{};
  final Set<int> _activePointers = {};

  /// 各活动指针的最近位置（双指手势中点计算用）。
  final Map<int, Offset> _pointerPositions = {};
  final TwoFingerGestureTracker _twoFingerGesture = TwoFingerGestureTracker();
  bool _twoFingerPointerRouting = false;
  late final MobileTouchpadPointer _touchpadPointer;
  late final ValueNotifier<Offset> _touchpadCursorPosition;
  bool _touchpadDragging = false;

  final _keyboardNode = FocusNode();
  final _keyboardCtrl = TextEditingController();
  String _keyboardLast = '';
  bool _keyboardShown = false;
  bool _engineDialogOpen = false;

  // FPS
  final ValueNotifier<double> _fpsNotifier = ValueNotifier(0);
  final ValueNotifier<ProfilerSnapshot?> _profilerNotifier = ValueNotifier(
    null,
  );
  Timer? _profilerTimer;
  bool _profilerEnabled = false;
  bool _appActive = true;
  bool _gameLoopStarted = false;
  final Stopwatch _frameClock = Stopwatch();
  int _nextFrameUs = 0;
  int _frameIndex = 0;
  int _fpsWindowStartUs = 0;
  int _fpsWindowFrames = 0;
  static const int _targetFrameUs = 1000000 ~/ 60;
  static const int _maxCatchUpTicks = 8;

  @override
  void initState() {
    super.initState();
    Log.startRuntimeSession();
    _bridge = CoreBridge(onDialogRequested: _showEngineDialog);
    _gameTicker = createTicker(_onGameTick);
    _bridge.media.fullscreenVideoBlocking.addListener(_syncGameTicker);
    _touchpadPointer = MobileTouchpadPointer(
      stageWidth: _stageW,
      stageHeight: _stageH,
    );
    _touchpadCursorPosition = ValueNotifier(_touchpadPointer.position);
    WidgetsBinding.instance.addObserver(this);
    _keyboardCtrl.addListener(_onKeyboardInput);
    _lockOrientation();
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 生命周期 → core：驱动 [autosave allow=1]（切后台自动存档）+ 同步最小化位。
    switch (state) {
      case AppLifecycleState.resumed:
        _appActive = true;
        _syncGameTicker();
        _bridge.setWindowStateBits(minimized: false);
        _bridge.notifyLifecycle(2); // 回前台
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appActive = false;
        _syncGameTicker();
        _endTouchpadDrag();
        _bridge.setWindowStateBits(minimized: true);
        _bridge.notifyLifecycle(1); // 切后台
      case AppLifecycleState.inactive:
        _appActive = false;
        _syncGameTicker();
        _endTouchpadDrag();
      case AppLifecycleState.detached:
        _appActive = false;
        _syncGameTicker();
        _endTouchpadDrag();
        _bridge.notifyLifecycle(0); // 退出
    }
  }

  Future<void> _showEngineDialog(EngineDialogRequest request) async {
    if (!mounted || _closing || _engineDialogOpen) return;
    _engineDialogOpen = true;
    try {
      final result = await showEngineDialog(context, request);
      if (!_closing) {
        _bridge.submitDialog(result?.accepted == true, result?.text ?? '');
      }
    } finally {
      _engineDialogOpen = false;
      if (mounted && !_closing) {
        _gameFocusNode.requestFocus();
      }
    }
  }

  Future<void> _init() async {
    await ref.read(settingsProvider.notifier).ready;
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

    final settings = ref.read(settingsProvider);
    final baseConfig = GameEntry(
      id: widget.gameId,
      name: widget.gameId,
      path: widget.projectPath,
      source: widget.source,
      addedAt: DateTime.fromMillisecondsSinceEpoch(0),
      translationEnabled: widget.translationEnabled,
      translationPatchPath: widget.translationPatchPath,
      environmentPatchEnabled: widget.environmentPatchEnabled,
      experimentalElunaEnabled: widget.experimentalElunaEnabled,
      inputGate: widget.inputGate,
      fontOverridePath: widget.fontOverridePath,
      reportedOs: widget.reportedOs,
      runtimePlatform: widget.runtimePlatform,
      manifestPath: widget.manifestPath,
    );
    final config = _activeConfig = await GameManifest.loadEntrySettings(
      baseConfig,
    );
    _bridge.setDebug(settings.debugMode);
    _bridge.setDamageVisualization(
      settings.debugMode && settings.damageVisualization,
    );
    final runtimePlatform = config.runtimePlatform;

    Uint8List iniContent;
    if (widget.source == GameSource.pfsArchive) {
      try {
        FileProvider.openPfs(
          widget.projectPath,
          environmentPatchEnabled: config.environmentPatchEnabled,
        );
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
      iniContent = bytes;
      final charset = ProjectCharset.detect(iniContent, runtimePlatform);
      FileProvider.openPfs(
        widget.projectPath,
        archiveEncoding: charset,
        environmentPatchEnabled: config.environmentPatchEnabled,
      );
    } else {
      FileProvider.openDirectory(
        widget.projectPath,
        environmentPatchEnabled: config.environmentPatchEnabled,
      );
      iniContent = File(
        '${widget.projectPath}${Platform.pathSeparator}system.ini',
      ).readAsBytesSync();
    }

    _parseStageSize(iniContent);

    // 存档目录：统一放应用沙箱内，不分 PFS/目录模式。
    // iOS 使用 Documents/Art3m1s/Saves，方便通过 Files app 导入导出。
    //
    // 注意：core 侧已把 s.savepath 前缀拼进相对路径（形如 `savedata/save0001.dat`），
    // 故这里的 saveDir 只是**每个游戏的基准目录**，不再追加 savePath，否则会双重前缀。
    // 用资料库映射中的稳定游戏 ID 作子目录，避免多游戏存档串档。
    await AppDataPaths.ensureInitialized();
    if (!mounted || _closing) {
      _bridge.shutdown();
      return;
    }
    // 资料库 ID 才是游戏身份；不能使用 root.pfs 等常见 basename，
    // 否则不同游戏会共用存档与翻译缓存。
    final gameId = widget.gameId;
    final saves = await AppDataPaths.savesDirectory();
    final saveDir = '${saves.path}${Platform.pathSeparator}$gameId';
    _bridge.setSaveDir(saveDir);

    if (config.translationEnabled) {
      final translations = await AppDataPaths.translationsDirectory();
      final translation = await TextTranslationService.create(
        settings: ref.read(settingsProvider).translation,
        patchPath: config.translationPatchPath,
        cacheFile: File(
          '${translations.path}${Platform.pathSeparator}$gameId.pb',
        ),
      );
      if (!mounted || _closing) {
        await translation.dispose();
        _bridge.shutdown();
        return;
      }
      _bridge.configureTranslation(translation);
    }
    // 覆盖字体是 core 的进程级全局设置：每次启动显式安装或清除，
    // 避免上一局游戏的覆盖泄漏到本局。清单字体不依赖翻译开关。
    await _applyFontOverride();

    // 输入门控：项目补丁/资料库条目的环境特化过滤，在 bridge 出口统一生效。
    _bridge.configureInputGate(config.inputGate);

    _bridge.registerFileReader();
    final renderBackend = ref.read(settingsProvider).backend;
    final renderQuality = ref.read(settingsProvider).renderQuality;
    _bridge.createRuntime(_stageW, _stageH, backend: renderBackend);
    _bridge.setRenderQualityPreset(renderQuality.ffiValue);
    // 机种上报覆盖（runtime 已建、项目未加载；空串=跟随平台）。
    _bridge.setReportedOs(config.reportedOs);
    if (config.experimentalElunaEnabled && !_bridge.setEmoteBackend(1)) {
      Log.warn('[E-Mote] 当前 Core 未包含实验性 Eluna 后端，已保留内置实现');
    }
    _setProfilerEnabled(settings.debugMode && settings.profilerOverlay);
    if (!_bridge.loadProjectBytes(iniContent, platform: runtimePlatform)) {
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
    _touchpadPointer.updateStageSize(_stageW, _stageH);
    _touchpadCursorPosition.value = _touchpadPointer.position;

    // 移动端以及 macOS Metal/ANGLE 把 core 的最终 render target 提交给
    // Flutter 外部纹理。只有显式选择的 macOS CGL reference backend
    // 保留 RGBA 回读路径；旧 core/宿主仍会自动回退。
    if (Platform.isAndroid ||
        Platform.isIOS ||
        (Platform.isMacOS && renderBackend != 5)) {
      await _bridge.enableSharedTexture();
    }

    if (!mounted || _closing) {
      _bridge.shutdown();
      return;
    }
    setState(() {});
    _startGameLoop();
  }

  /// 安装本局覆盖字体；无可用来源或安装失败时清除（覆盖是 core 进程级全局
  /// 设置，不能残留到下一局）。
  Future<void> _applyFontOverride() async {
    final resolved = await _resolveFontOverrideBytes();
    if (resolved == null) {
      _bridge.clearFontOverride();
      return;
    }
    final (bytes, source) = resolved;
    if (_bridge.setFontOverride(bytes)) {
      Log.info('[字体] 已安装覆盖字体: $source');
    } else {
      Log.warn('[字体] 覆盖字体安装失败（core 过旧或字体非法）: $source');
      _bridge.clearFontOverride();
    }
  }

  /// 覆盖字体字节来源：翻译设置里用户显式选择的字体（仅翻译开启时）优先，
  /// 其次是项目清单自带的游戏内字体；都没有返回 null。
  Future<(Uint8List, String)?> _resolveFontOverrideBytes() async {
    final config = _activeConfig;
    final globalPath = config?.translationEnabled == true
        ? ref.read(settingsProvider).translation.fontPath
        : '';
    if (globalPath.isNotEmpty) {
      try {
        return (await File(globalPath).readAsBytes(), globalPath);
      } catch (error) {
        Log.warn('[字体] 覆盖字体读取失败: $globalPath: $error');
        return null;
      }
    }
    if (config != null && config.fontOverridePath.isNotEmpty) {
      final bytes = await GameManifest.readGameFile(
        config.path,
        config.source,
        config.fontOverridePath,
      );
      if (bytes == null) {
        Log.warn('[字体] 清单覆盖字体读取失败: ${config.fontOverridePath}');
        return null;
      }
      return (bytes, config.fontOverridePath);
    }
    return null;
  }

  void _parseStageSize(Uint8List ini) {
    final asciiCompatible = String.fromCharCodes(
      ini.map((byte) => byte < 0x80 ? byte : 0x20),
    );
    for (final line in asciiCompatible.split('\n')) {
      final trimmed = line.trim().toUpperCase();
      if (trimmed.startsWith('WIDTH=')) {
        _stageW = int.tryParse(trimmed.split('=').last.trim()) ?? 1280;
      }
      if (trimmed.startsWith('HEIGHT=')) {
        _stageH = int.tryParse(trimmed.split('=').last.trim()) ?? 720;
      }
    }
  }

  void _startGameLoop() {
    _frameClock
      ..reset()
      ..start();
    _nextFrameUs = _targetFrameUs;
    _frameIndex = 0;
    _fpsWindowStartUs = 0;
    _fpsWindowFrames = 0;
    _gameLoopStarted = true;
    _syncGameTicker();
  }

  void _syncGameTicker() {
    final shouldRun =
        _gameLoopStarted &&
        !_closing &&
        _appActive &&
        !_bridge.media.isFullscreenVideoBlocking;
    if (shouldRun) {
      if (_gameTicker.isActive) return;
      // Paused/background/fullscreen-video time does not belong to the script
      // clock. Resume at the next vsync instead of catching paused time up.
      _nextFrameUs = _frameClock.elapsedMicroseconds;
      _gameTicker.start();
    } else if (_gameTicker.isActive) {
      _gameTicker.stop();
    }
  }

  void _onGameTick(Duration _) {
    if (_closing || !mounted) return;
    final nowUs = _frameClock.elapsedMicroseconds;
    if (nowUs < _nextFrameUs) return;
    final overdueUs = nowUs - _nextFrameUs;
    final dueTicks = (1 + overdueUs ~/ _targetFrameUs).clamp(
      1,
      _maxCatchUpTicks,
    );
    _nextFrameUs += _targetFrameUs * dueTicks;
    if (nowUs - _nextFrameUs > _targetFrameUs * 2) {
      _nextFrameUs = nowUs + _targetFrameUs;
    }

    if (_bridge.isExitRequested()) {
      Log.info('[PlayerScreen] exit requested, popping...');
      _closePlayer();
      return;
    }

    // 口型 CSV 以 60 Hz 每次 onEnterFrame 消费一个采样。显示链繁忙或一次
    // vsync 回调迟到时，先补齐逻辑 tick，只在最后一次尝试回读和显示画面。
    for (var tick = 0; tick < dueTicks - 1; tick++) {
      _bridge.advanceWithoutRender(_nextFrameDeltaMs());
    }
    if (_bridge.hasActiveSharedTexture) {
      final deltaMs = _nextFrameDeltaMs();
      _trackFps(nowUs);
      final result = _bridge.advanceAndPresent(deltaMs.clamp(0, 100));
      if (_bridge.isExitRequested() && mounted) {
        _closePlayer();
        return;
      }
      if (result > 0 && !_sharedTextureReady && mounted) {
        _sharedTextureReady = true;
        setState(() {});
      }
      return;
    }
    if (_frameInFlight) {
      _bridge.advanceWithoutRender(_nextFrameDeltaMs());
      return;
    }

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
    _fpsNotifier.value = _fpsWindowFrames * 1000000 / elapsedUs;
    _fpsWindowStartUs = nowUs;
    _fpsWindowFrames = 0;
  }

  void _setProfilerEnabled(bool enabled) {
    if (_profilerEnabled == enabled || !_bridge.isInitialized) return;
    _profilerTimer?.cancel();
    _profilerTimer = null;
    _profilerEnabled = enabled && _bridge.setProfilerEnabled(enabled);
    if (!_profilerEnabled) {
      _bridge.setProfilerEnabled(false);
      _profilerNotifier.value = null;
      return;
    }
    _profilerTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_closing || !mounted) return;
      final snapshot = _bridge.readProfilerSnapshot();
      if (snapshot != null) _profilerNotifier.value = snapshot;
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
    WidgetsBinding.instance.removeObserver(this);
    _unlockOrientation();
    _bridge.media.fullscreenVideoBlocking.removeListener(_syncGameTicker);
    _gameTicker.dispose();
    _profilerTimer?.cancel();
    if (_profilerEnabled) _bridge.setProfilerEnabled(false);
    _endTouchpadDrag();
    _touchpadCursorPosition.dispose();
    _fpsNotifier.dispose();
    _profilerNotifier.dispose();
    _frameImage?.dispose();
    _gameFocusNode.dispose();
    _keyboardCtrl.removeListener(_onKeyboardInput);
    _keyboardCtrl.dispose();
    _keyboardNode.dispose();
    _bridge.shutdown();
    Log.endRuntimeSession();
    super.dispose();
  }

  void _closePlayer() {
    if (_closing) return;
    _closing = true;
    _syncGameTicker();
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

  void _toggleKeyboard() {
    setState(() {
      _keyboardShown = !_keyboardShown;
      if (_keyboardShown) {
        _keyboardNode.requestFocus();
      } else {
        _keyboardNode.unfocus();
      }
    });
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
    if (char == 0x08) return 8; // backspace
    if (char >= 0x30 && char <= 0x39) return char;
    if (char >= 0x41 && char <= 0x5A) return char;
    if (char >= 0x61 && char <= 0x7A) return char - 32;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final showFps = ref.watch(settingsProvider.select((s) => s.showFps));
    final showProfiler = ref.watch(
      settingsProvider.select((s) => s.debugMode && s.profilerOverlay),
    );
    final touchpadEnabled = ref.watch(
      settingsProvider.select((s) => s.mobileTouchpadEnabled),
    );
    if (showProfiler != _profilerEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closing) _setProfilerEnabled(showProfiler);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if ((_sharedTextureReady && _bridge.sharedTextureId != null) ||
              _frameImage != null)
            _buildCursorAwareGameView()
          else
            const Center(child: CircularProgressIndicator()),
          _buildVideoLayer(),
          if (showFps) _buildFpsDisplay(),
          if (showProfiler) ProfilerOverlay(snapshot: _profilerNotifier),
          PlayerHud(
            title: widget.projectPath.split(RegExp(r'[/\\]')).last,
            showFps: showFps,
            keyboardShown: _keyboardShown,
            touchpadEnabled: touchpadEnabled,
            showTouchpadToggle: Platform.isAndroid || Platform.isIOS,
            showKeyboardToggle: Platform.isAndroid || Platform.isIOS,
            onShowFpsChanged: (value) =>
                ref.read(settingsProvider.notifier).setShowFps(value),
            onToggleKeyboard: _toggleKeyboard,
            onTouchpadChanged: _setTouchpadEnabled,
            onExit: _closePlayer,
          ),
          _buildHiddenKeyboard(),
          _buildAvoidOverlay(),
        ],
      ),
    );
  }

  Widget _buildCursorAwareGameView() {
    return ValueListenableBuilder<bool>(
      valueListenable: _bridge.cursorHidden,
      builder: (context, cursorHidden, child) => MouseRegion(
        cursor: cursorHidden ? SystemMouseCursors.none : MouseCursor.defer,
        child: child,
      ),
      child: _buildGameView(),
    );
  }

  /// 紧急回避覆盖（[avoid] + keyconfig role15）：core 触发时静音并发 ui_command，
  /// 宿主即时以全屏不透明遮罩隐藏画面（避免旁人看到游戏内容）。再次触发时撤除。
  Widget _buildAvoidOverlay() {
    return ValueListenableBuilder<AvoidOverlay?>(
      valueListenable: _bridge.avoidOverlay,
      builder: (context, avoid, _) {
        if (avoid == null) return const SizedBox.shrink();
        return const Positioned.fill(child: ColoredBox(color: Colors.black));
      },
    );
  }

  /// Immersive mode zeros [MediaQuery.padding], so overlays must use
  /// [MediaQuery.viewPadding]. Large-radius screens also need a floor so
  /// the badge is not clipped by the corner curve.
  EdgeInsets _overlaySafeInset(BuildContext context) {
    final view = MediaQuery.viewPaddingOf(context);
    const gap = 8.0;
    final extraTop = Platform.isMacOS ? 28.0 : 0.0;
    final corner = (Platform.isIOS || Platform.isAndroid) ? 20.0 : 8.0;
    double axis(double inset, [double extra = 0]) =>
        (inset > corner ? inset : corner) + gap + extra;

    return EdgeInsets.only(
      left: axis(view.left),
      top: axis(view.top, extraTop),
      right: axis(view.right),
      bottom: axis(view.bottom),
    );
  }

  Widget _buildFpsDisplay() {
    final inset = _overlaySafeInset(context);
    return Positioned(
      top: inset.top,
      left: inset.left,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ValueListenableBuilder<double>(
          valueListenable: _fpsNotifier,
          builder: (context, fps, _) => Text(
            '${fps.toStringAsFixed(0)} fps',
            style: const TextStyle(
              color: Colors.lime,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
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
    final touchpadEnabled =
        (Platform.isAndroid || Platform.isIOS) &&
        ref.watch(settingsProvider.select((s) => s.mobileTouchpadEnabled));

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

        Widget gameInput = KeyboardListener(
          focusNode: _gameFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: (event) {
              if (!_twoFingerPointerRouting) {
                _feedPointerPosition(event, ox, oy, scale);
              }
            },
            onPointerMove: (event) {
              if (touchpadEnabled && event.kind == PointerDeviceKind.touch) {
                return;
              }
              if (event.kind == PointerDeviceKind.touch) {
                _pointerPositions[event.pointer] = event.localPosition;
                if (_twoFingerPointerRouting) {
                  _handleTwoFingerMove();
                  _feedTouch(event, 1, ox, oy, scale);
                  return;
                }
              }
              _feedPointerPosition(event, ox, oy, scale);
              _feedTouch(event, 1, ox, oy, scale);
              _syncPointerButtons(event.buttons);
            },
            onPointerDown: (event) {
              if (touchpadEnabled && event.kind == PointerDeviceKind.touch) {
                _gameFocusNode.requestFocus();
                return;
              }
              if (event.kind == PointerDeviceKind.touch) {
                _pointerPositions[event.pointer] = event.localPosition;
                _activePointers.add(event.pointer);
                _beginTwoFingerGesture();
              }
              _gameFocusNode.requestFocus();
              if (!_twoFingerPointerRouting) {
                _feedPointerPosition(event, ox, oy, scale);
                _syncPointerButtons(event.buttons);
              }
              _feedTouch(event, 0, ox, oy, scale);
            },
            onPointerUp: (event) {
              if (touchpadEnabled && event.kind == PointerDeviceKind.touch) {
                return;
              }
              final routed =
                  event.kind == PointerDeviceKind.touch &&
                  _twoFingerPointerRouting;
              if (event.kind == PointerDeviceKind.touch) {
                _endTwoFingerGesture();
                _activePointers.remove(event.pointer);
                _pointerPositions.remove(event.pointer);
              }
              if (!routed) {
                _feedPointerPosition(event, ox, oy, scale);
                _syncPointerButtons(event.buttons);
              }
              _feedTouch(event, 2, ox, oy, scale);
              if (_activePointers.isEmpty) {
                _twoFingerPointerRouting = false;
              }
            },
            onPointerCancel: (event) {
              if (touchpadEnabled && event.kind == PointerDeviceKind.touch) {
                return;
              }
              if (event.kind == PointerDeviceKind.touch) {
                _endTwoFingerGesture(cancelled: true);
                _activePointers.remove(event.pointer);
                _pointerPositions.remove(event.pointer);
              }
              _feedTouch(event, 2, ox, oy, scale);
              _releasePointerButtons();
              if (_activePointers.isEmpty) {
                _twoFingerPointerRouting = false;
              }
            },
            onPointerSignal: _handlePointerSignal,
            child: Center(
              child: SizedBox(
                width: dw,
                height: dh,
                child:
                    _bridge.hasActiveSharedTexture &&
                        _bridge.sharedTextureId != null
                    ? Texture(
                        textureId: _bridge.sharedTextureId!,
                        filterQuality: FilterQuality.medium,
                      )
                    : RawImage(image: _frameImage, fit: BoxFit.fill),
              ),
            ),
          ),
        );

        if (touchpadEnabled) {
          gameInput = MobileTouchpadSurface(
            onTap: _tapTouchpad,
            onMove: (delta) => _moveTouchpad(delta, scale),
            onDragStart: _beginTouchpadDrag,
            onDragEnd: _endTouchpadDrag,
            child: gameInput,
          );
          gameInput = Stack(
            fit: StackFit.expand,
            children: [
              gameInput,
              IgnorePointer(
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _touchpadCursorPosition,
                  builder: (context, position, _) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          left: ox + position.dx * scale,
                          top: oy + position.dy * scale,
                          child: const MobileGameCursor(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        }

        return gameInput;
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
    if (event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad) {
      _bridge.notifyMouseActivity();
    }
    final point = _stagePoint(event.localPosition, ox, oy, scale);
    _touchpadPointer.setPosition(point);
    _touchpadCursorPosition.value = point;
    _bridge.feedMouse(point.dx.toInt(), point.dy.toInt());
  }

  void _moveTouchpad(Offset delta, double scale) {
    final point = _touchpadPointer.moveBy(delta, scale);
    _touchpadCursorPosition.value = point;
    _bridge.feedMouse(point.dx.toInt(), point.dy.toInt());
  }

  void _tapTouchpad() {
    _bridge.feedMouseButton(1, true);
    _bridge.feedMouseButton(1, false);
  }

  void _beginTouchpadDrag() {
    if (_touchpadDragging) return;
    _touchpadDragging = true;
    _bridge.feedMouseButton(1, true);
  }

  void _endTouchpadDrag() {
    if (!_touchpadDragging) return;
    _touchpadDragging = false;
    _bridge.feedMouseButton(1, false);
  }

  void _setTouchpadEnabled(bool enabled) {
    _endTouchpadDrag();
    _releasePointerButtons();
    _activePointers.clear();
    _pointerPositions.clear();
    _twoFingerGesture.reset();
    _twoFingerPointerRouting = false;
    ref.read(settingsProvider.notifier).setMobileTouchpadEnabled(enabled);
  }

  /// 把真实触摸事件转发给 core（驱动 getTouchCount/Point、flick、多点触控）。
  /// 只对触摸类指针发；鼠标/触控板仍走原鼠标路径。phase：0=down/1=move/2=up。
  void _feedTouch(
    PointerEvent event,
    int phase,
    double ox,
    double oy,
    double scale,
  ) {
    if (event.kind != PointerDeviceKind.touch) return;
    final point = _stagePoint(event.localPosition, ox, oy, scale);
    _bridge.feedTouch(event.pointer, phase, point.dx.toInt(), point.dy.toInt());
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

  InputGatePolicy get _effectiveInputGate =>
      _activeConfig?.inputGate ?? widget.inputGate;

  List<Offset> get _activePointerPositions => [
    for (final pointer in _activePointers) _pointerPositions[pointer]!,
  ];

  /// 右键不在第二指落下时发出；等到抬起才判定是点按还是拖动。
  void _beginTwoFingerGesture() {
    if (_activePointers.length < 2) return;
    _twoFingerPointerRouting = true;
    _releasePointerButtons();
    _twoFingerGesture.begin(_activePointerPositions);
  }

  void _endTwoFingerGesture({bool cancelled = false}) {
    final tapped = _twoFingerGesture.end(cancelled: cancelled);
    if (tapped && _effectiveInputGate.twoFingerRightClick) {
      _bridge.feedMouseButton(2, true);
      _bridge.feedMouseButton(2, false);
    }
  }

  void _handleTwoFingerMove() {
    if (_activePointers.length != 2) return;
    for (final key in _twoFingerGesture.move(
      _activePointerPositions,
      scrollEnabled:
          Platform.isAndroid ||
          Platform.isIOS ||
          _effectiveInputGate.twoFingerScrollWheel,
    )) {
      _emitForwardedWheelKey(key);
    }
  }

  void _emitForwardedWheelKey(int vk) {
    _bridge.feedForwardedKey(vk, true);
    _bridge.feedForwardedKey(vk, false);
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
    // 核心没有独立滚轮入口；宿主转为标准 VK_UP/VK_DOWN。
    if (!_effectiveInputGate.wheelToKeys) return;
    if (event is! PointerScrollEvent) return;
    final key = event.scrollDelta.dy < 0 ? 38 : 40;
    _emitForwardedWheelKey(key);
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
