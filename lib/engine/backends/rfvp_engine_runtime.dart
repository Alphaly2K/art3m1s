import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/game_engine.dart';
import '../../models/input_gate.dart';
import '../../services/logger.dart';
import '../../services/profiler_snapshot.dart';
import '../../services/text_translation_service.dart';
import '../engine_runtime.dart';
import '../media_bridge.dart';
import 'rfvp/rfvp_api.dart';
import 'rfvp/rfvp_software_renderer.dart';

/// RFVP core adapter for the Host engine contract.
///
/// RFVP owns VM/animation state and emits backend-neutral draw, texture, and
/// audio commands. This adapter keeps the dynamic library and ABI handles
/// isolated from `art3m1s-core`.
class RfvpEngineRuntime implements EngineRuntime {
  RfvpEngineRuntime({this.engineCursorControlEnabled = true});

  final bool? engineCursorControlEnabled;

  final ValueNotifier<bool> _cursorHidden = ValueNotifier(false);
  final ValueNotifier<AvoidOverlay?> _avoidOverlay = ValueNotifier(null);
  final ValueNotifier<String?> _windowTitle = ValueNotifier(null);
  late final MediaBridge _media = MediaBridge(
    onVideoFinished: (_) {},
    onSoundFinished: (_) {},
  );
  final RfvpSoftwareRenderer _renderer = RfvpSoftwareRenderer();

  DynamicLibrary? _library;
  RfvpApiV1? _api;
  int _resources = 0;
  int _runtime = 0;
  bool _initialized = false;
  bool _exitRequested = false;
  String? _lastError;
  int _stageWidth = 0;
  int _stageHeight = 0;
  int _pointerX = 0;
  int _pointerY = 0;
  String? _projectDirectory;
  InputGatePolicy _inputGate = InputGatePolicy.full;
  TextTranslationService? _translation;

  @override
  GameEngineKind get kind => GameEngineKind.rfvp;

  @override
  bool get isInitialized => _initialized;

  String? get lastError => _lastError;

  @override
  int get stageWidth => _stageWidth;

  @override
  int get stageHeight => _stageHeight;

  @override
  ValueListenable<bool> get cursorHidden => _cursorHidden;

  @override
  ValueListenable<AvoidOverlay?> get avoidOverlay => _avoidOverlay;

  @override
  ValueListenable<String?> get windowTitle => _windowTitle;

  @override
  EngineMediaHost get media => _media;

  @override
  Future<void> initialize() async {
    try {
      _lastError = null;
      _library = _openLibrary();
      final api = RfvpApiV1.tryLoad(_library!);
      if (api == null) {
        throw StateError('RFVP 缺少 rfvp_get_api_v1 或 ABI 版本不兼容');
      }
      _api = api;
      _resources = api.createResources(nls: rfvpNlsShiftJis);
      if (_resources <= 0) {
        throw StateError('RFVP 创建资源句柄失败');
      }
      _initialized = true;
      Log.info('[RfvpEngineRuntime] 使用 rfvp_get_api_v1');
    } catch (error) {
      _lastError = error.toString();
      Log.error('[RfvpEngineRuntime] RFVP 库加载失败: $error');
      _shutdownNative();
    }
  }

  @override
  void shutdown() {
    _shutdownNative();
    unawaited(_media.dispose());
    final translation = _translation;
    _translation = null;
    if (translation != null) unawaited(translation.dispose());
  }

  @override
  void setDebug(bool enabled) {}

  @override
  void setDamageVisualization(bool enabled) {}

  @override
  void setSaveDir(String dir) {
    final api = _api;
    if (api == null || _resources <= 0) return;
    try {
      final directory = Directory(dir);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      if (api.setSaveRoot(_resources, dir) != rfvpStatusOk) {
        Log.warn('[RfvpEngineRuntime] set save root failed: $dir');
      }
    } catch (error) {
      Log.warn('[RfvpEngineRuntime] set save root failed: $dir: $error');
    }
  }

  @override
  void configureTranslation(TextTranslationService? service) {
    if (identical(_translation, service)) return;
    final previous = _translation;
    _translation = service;
    if (previous != null) unawaited(previous.dispose());
    if (service != null) {
      Log.info('[RfvpEngineRuntime] 翻译服务已预留，等待 text event ABI');
    }
  }

  @override
  void configureInputGate(InputGatePolicy gate) {
    _inputGate = gate;
  }

  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) async {
    if (isArchive) {
      throw UnsupportedError('RFVP 暂不支持 PFS 归档项目');
    }
    final ini = File('$projectPath${Platform.pathSeparator}system.ini');
    if (!ini.existsSync()) {
      _projectDirectory = null;
      return null;
    }
    _projectDirectory = projectPath;
    return ini.readAsBytes();
  }

  @override
  void registerFileReader() {
    final api = _api;
    if (api == null || _resources <= 0) return;
    final directory = _projectDirectory;
    if (directory == null) {
      Log.warn('[RfvpEngineRuntime] 项目目录尚未准备');
      return;
    }
    api.clearResources(_resources);
    final status = api.mountDirectory(_resources, directory);
    if (status != rfvpStatusOk) {
      _lastError = 'mount directory failed: $directory ($status)';
      Log.error('[RfvpEngineRuntime] $_lastError');
      return;
    }
    Log.info('[RfvpEngineRuntime] 项目目录已挂载: $directory');
  }

  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) {
    final api = _api;
    if (api == null || _resources <= 0) return;
    _runtime = api.createRuntime(
      resources: _resources,
      requestedWidth: stageWidth,
      requestedHeight: stageHeight,
    );
    if (_runtime <= 0) {
      _lastError = 'runtime create failed (${api.lastStatus})';
      Log.error('[RfvpEngineRuntime] $_lastError');
      return;
    }
    _lastError = null;
    _stageWidth = stageWidth;
    _stageHeight = stageHeight;
    _exitRequested = false;
  }

  @override
  void setReportedOs(String? os) {}

  @override
  bool setEmoteBackend(int backend) => false;

  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) =>
      _runtime > 0;

  @override
  bool setFontOverride(Uint8List bytes) => false;

  @override
  void clearFontOverride() {}

  @override
  bool get supportsSpatialUpscaling => false;

  @override
  bool setRenderQuality(EngineRenderQuality quality) => false;

  @override
  bool configureSpatialUpscale(double renderScale, {double sharpness = 0}) =>
      false;

  @override
  bool get hasActiveSharedTexture => false;

  @override
  int? get sharedTextureId => null;

  @override
  int get sharedTextureWidth => 0;

  @override
  int get sharedTextureHeight => 0;

  @override
  Future<int?> enableSharedTexture({
    int? outputWidth,
    int? outputHeight,
  }) async => null;

  @override
  bool isExitRequested() {
    if (_exitRequested) return true;
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return false;
    return api.isExitRequested(runtime);
  }

  @override
  bool advanceWithoutRender(int deltaMs) => _step(deltaMs);

  @override
  int advanceAndPresent(int deltaMs) {
    final pixels = advanceAndRender(deltaMs);
    return pixels == null ? -1 : 1;
  }

  @override
  Uint8List? advanceAndRender(int deltaMs) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0 || !_step(deltaMs)) return null;
    final frame = api.acquireFrame(runtime);
    if (frame == null) return null;
    _stageWidth = frame.width;
    _stageHeight = frame.height;
    try {
      return _renderer.render(frame);
    } catch (error, stackTrace) {
      Log.error('[RfvpEngineRuntime] frame render failed: $error\n$stackTrace');
      return null;
    }
  }

  bool _step(int deltaMs) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return false;
    final status = api.step(runtime, deltaMs.clamp(1, 1000));
    if (status != rfvpStatusOk) {
      Log.error('[RfvpEngineRuntime] runtime step failed: $status');
      return false;
    }
    _drainAudio();
    return true;
  }

  void _drainAudio() {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return;
    while (true) {
      final command = api.pollAudioCommand(runtime);
      if (command == null) return;
      _media.handleEngineAudioCommand(
        EngineAudioCommand(
          kind: _engineAudioKind(command.kind),
          streamId: command.streamId,
          id: 'rfvp:${command.streamId}',
          channel: command.streamId < 0x1000 ? 'bgm' : 'se',
          payload: command.payload,
          sampleRate: command.sampleRate,
          channels: command.channels,
          repeat: command.repeat,
          fadeMs: command.fadeMs,
          volume: command.volume,
          pan: command.pan,
        ),
      );
    }
  }

  static EngineAudioCommandKind _engineAudioKind(int kind) {
    return switch (kind) {
      rfvpAudioLoadEncoded => EngineAudioCommandKind.loadEncoded,
      rfvpAudioCreateStream => EngineAudioCommandKind.createStream,
      rfvpAudioSubmitI16 => EngineAudioCommandKind.submitI16,
      rfvpAudioSubmitF32 => EngineAudioCommandKind.submitF32,
      rfvpAudioPlay => EngineAudioCommandKind.play,
      rfvpAudioStop => EngineAudioCommandKind.stop,
      rfvpAudioPause => EngineAudioCommandKind.pause,
      rfvpAudioResume => EngineAudioCommandKind.resume,
      rfvpAudioSetParams => EngineAudioCommandKind.setParams,
      rfvpAudioDestroyStream => EngineAudioCommandKind.destroyStream,
      rfvpAudioMasterVolume => EngineAudioCommandKind.masterVolume,
      _ => EngineAudioCommandKind.destroyStream,
    };
  }

  @override
  bool setProfilerEnabled(bool enabled) => false;

  @override
  ProfilerSnapshot? readProfilerSnapshot() => null;

  @override
  void feedMouse(int x, int y) {
    if (!_inputGate.mouseMove) return;
    _pointerX = x;
    _pointerY = y;
    _pushInput([
      RfvpInputEvent(
        kind: rfvpInputPointerMove,
        code: 0,
        phase: rfvpInputPhaseMove,
        x: x,
        y: y,
      ),
    ]);
  }

  @override
  void feedClick() {
    if (!_inputGate.mouseButtons) return;
    _pushInput([
      RfvpInputEvent(
        kind: rfvpInputPointerButton,
        code: rfvpPointerLeft,
        phase: rfvpInputPhaseDown,
        x: _pointerX,
        y: _pointerY,
      ),
      RfvpInputEvent(
        kind: rfvpInputPointerButton,
        code: rfvpPointerLeft,
        phase: rfvpInputPhaseUp,
        x: _pointerX,
        y: _pointerY,
      ),
    ]);
  }

  @override
  void feedMouseButton(int button, bool pressed) {
    if (!_inputGate.mouseButtons) return;
    final code = switch (button) {
      2 => rfvpPointerRight,
      3 => rfvpPointerMiddle,
      _ => rfvpPointerLeft,
    };
    _pushInput([
      RfvpInputEvent(
        kind: rfvpInputPointerButton,
        code: code,
        phase: pressed ? rfvpInputPhaseDown : rfvpInputPhaseUp,
        x: _pointerX,
        y: _pointerY,
      ),
    ]);
  }

  @override
  void feedTouch(int id, int phase, int x, int y) {
    if (!_inputGate.touch) return;
    final nativePhase = switch (phase) {
      0 => rfvpInputPhaseDown,
      1 => rfvpInputPhaseMove,
      2 => rfvpInputPhaseUp,
      _ => rfvpInputPhaseMove,
    };
    _pushInput([
      RfvpInputEvent(
        kind: rfvpInputTouch,
        code: 0,
        phase: nativePhase,
        x: x,
        y: y,
        id: id,
      ),
    ]);
  }

  @override
  void feedKey(int keyCode, bool pressed) {
    final mapped = _inputGate.filterKey(keyCode);
    if (mapped == null) return;
    _pushKey(mapped, pressed);
  }

  @override
  void feedForwardedKey(int keyCode, bool pressed) {
    final mapped = _inputGate.filterForwardedKey(keyCode);
    if (mapped == null) return;
    _pushKey(mapped, pressed);
  }

  void _pushKey(int keyCode, bool pressed) {
    _pushInput([
      RfvpInputEvent(
        kind: rfvpInputKey,
        code: keyCode,
        phase: pressed ? rfvpInputPhaseDown : rfvpInputPhaseUp,
      ),
    ]);
  }

  void _pushInput(List<RfvpInputEvent> events) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0 || events.isEmpty) return;
    final status = api.pushInput(runtime, events);
    if (status != rfvpStatusOk) {
      Log.warn('[RfvpEngineRuntime] input rejected: $status');
    }
  }

  @override
  bool submitDialog(bool accepted, String text) => false;

  @override
  void notifyMouseActivity() {}

  @override
  void setWindowStateBits({bool? fullscreen, bool? minimized}) {}

  @override
  void notifyLifecycle(int state) {
    switch (state) {
      case 0:
        _exitRequested = true;
        _pushInput(const [
          RfvpInputEvent(
            kind: rfvpInputQuit,
            code: 0,
            phase: rfvpInputPhaseDown,
          ),
        ]);
      case 1:
        _pushInput(const [
          RfvpInputEvent(kind: rfvpInputFocus, code: 0, phase: 0),
        ]);
      case 2:
        _pushInput(const [
          RfvpInputEvent(kind: rfvpInputFocus, code: 0, phase: 1),
        ]);
    }
  }

  void _shutdownNative() {
    final api = _api;
    final runtime = _runtime;
    final resources = _resources;
    _runtime = 0;
    _resources = 0;
    _projectDirectory = null;
    _initialized = false;
    _renderer.reset();
    if (api != null) {
      if (runtime > 0) api.destroyRuntime(runtime);
      if (resources > 0) api.destroyResources(resources);
    }
    _api = null;
    _library = null;
  }

  static DynamicLibrary _openLibrary() {
    final configured = Platform.environment['RFVP_LIBRARY'];
    if (configured != null && configured.isNotEmpty) {
      return DynamicLibrary.open(configured);
    }
    if (Platform.isIOS) return DynamicLibrary.process();
    final name = Platform.isMacOS
        ? 'librfvp.dylib'
        : Platform.isWindows
        ? 'rfvp.dll'
        : 'librfvp.so';
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      if (Platform.isAndroid) rethrow;
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      return DynamicLibrary.open('${executableDirectory.path}/$name');
    }
  }
}
