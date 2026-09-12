import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/game_engine.dart';
import '../../models/input_gate.dart';
import '../../services/logger.dart';
import '../../services/profiler_snapshot.dart';
import '../../services/text_translation_service.dart';
import '../engine_runtime.dart';
import '../media_bridge.dart';
import 'rfvp/core_rfvp_api.dart';

/// RFVP core adapter for the Host engine contract.
///
/// The Art3m1s core library owns RFVP's native runtime, GPU backend and frame
/// adaptation. Dart only passes paths, input, lifecycle and audio commands.
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

  static const MethodChannel _sharedTextureChannel = MethodChannel(
    'moe.alphaly.art3m1s/shared_texture',
  );

  DynamicLibrary? _library;
  CoreRfvpApiV1? _api;
  int _runtime = 0;
  bool _initialized = false;
  bool _exitRequested = false;
  String? _lastError;
  int _stageWidth = 0;
  int _stageHeight = 0;
  int _pointerX = 0;
  int _pointerY = 0;
  String? _projectDirectory;
  String? _saveDirectory;
  InputGatePolicy _inputGate = InputGatePolicy.full;
  TextTranslationService? _translation;

  int? _sharedTextureId;
  int? _sharedTextureKind;
  bool _sharedTextureAttached = false;
  bool _sharedTextureHandlerAttached = false;
  int _sharedTextureWidth = 0;
  int _sharedTextureHeight = 0;

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
      _library = _openCoreLibrary();
      final api = CoreRfvpApiV1.tryLoad(_library!);
      if (api == null) {
        throw StateError('art3m1s-core 未导出 RFVP API v1');
      }
      _api = api;
      _initialized = true;
      Log.info('[RfvpEngineRuntime] 使用 art3m1s_rfvp_get_api_v1');
    } catch (error) {
      _lastError = error.toString();
      Log.error('[RfvpEngineRuntime] RFVP 后端加载失败: $error');
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
    _saveDirectory = dir;
    try {
      final directory = Directory(dir);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
    } catch (error) {
      Log.warn('[RfvpEngineRuntime] 创建存档目录失败: $dir: $error');
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
    _projectDirectory = projectPath;
    final ini = File('$projectPath${Platform.pathSeparator}system.ini');
    if (!ini.existsSync()) {
      // RFVP discovers HCB and .bin packs directly; FVP games do not require
      // the Artemis system.ini contract.
      return Uint8List(0);
    }
    return ini.readAsBytes();
  }

  @override
  void registerFileReader() {
    final directory = _projectDirectory;
    if (directory == null) {
      Log.warn('[RfvpEngineRuntime] 项目目录尚未准备');
      return;
    }
    Log.info('[RfvpEngineRuntime] 项目目录将由 Rust 宿主挂载: $directory');
  }

  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) {
    final api = _api;
    final projectDirectory = _projectDirectory;
    if (api == null || projectDirectory == null) return;

    _runtime = api.createRuntime(
      gameRoot: projectDirectory,
      saveRoot: _saveDirectory,
      width: stageWidth,
      height: stageHeight,
      backend: backend,
      nls: art3m1sRfvpNlsShiftJis,
    );
    if (_runtime <= 0) {
      _lastError = 'runtime create failed (${api.lastStatus})';
      Log.error('[RfvpEngineRuntime] $_lastError');
      return;
    }
    _lastError = null;
    _stageWidth = api.stageWidth(_runtime);
    _stageHeight = api.stageHeight(_runtime);
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
  bool get hasActiveSharedTexture =>
      _sharedTextureId != null && _sharedTextureAttached;

  @override
  int? get sharedTextureId => _sharedTextureId;

  @override
  int get sharedTextureWidth => _sharedTextureWidth;

  @override
  int get sharedTextureHeight => _sharedTextureHeight;

  @override
  Future<int?> enableSharedTexture({
    int? outputWidth,
    int? outputHeight,
  }) async {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return null;
    final width = math.max(outputWidth ?? _stageWidth, _stageWidth);
    final height = math.max(outputHeight ?? _stageHeight, _stageHeight);
    if (_sharedTextureAttached &&
        _sharedTextureId != null &&
        _sharedTextureWidth == width &&
        _sharedTextureHeight == height) {
      return _sharedTextureId;
    }

    try {
      _detachSharedTexture();
      final raw = await _sharedTextureChannel.invokeMapMethod<String, dynamic>(
        'create',
        {'width': width, 'height': height},
      );
      if (raw == null ||
          !_attachSharedTexture(raw, width: width, height: height)) {
        await _sharedTextureChannel.invokeMethod<void>('release');
        _sharedTextureId = null;
        _sharedTextureKind = null;
        return null;
      }
      if (!_sharedTextureHandlerAttached) {
        _sharedTextureChannel.setMethodCallHandler(_handleSharedTextureCall);
        _sharedTextureHandlerAttached = true;
      }
      Log.info(
        '[RfvpEngineRuntime] 共享纹理已启用: id=$_sharedTextureId '
        '${_sharedTextureWidth}x$_sharedTextureHeight '
        '(stage=${_stageWidth}x$_stageHeight)',
      );
      return _sharedTextureId;
    } catch (error) {
      Log.warn('[RfvpEngineRuntime] 共享纹理不可用，使用 RGBA 回读: $error');
      _sharedTextureId = null;
      _sharedTextureKind = null;
      unawaited(
        _sharedTextureChannel.invokeMethod<void>('release').catchError((_) {}),
      );
      return null;
    }
  }

  bool _attachSharedTexture(
    Map<dynamic, dynamic> descriptor, {
    int? width,
    int? height,
  }) {
    final api = _api;
    final runtime = _runtime;
    final textureId = (descriptor['textureId'] as num?)?.toInt();
    if (api == null || runtime <= 0 || textureId == null) return false;
    final surfaceWidth = width ?? _sharedTextureWidth;
    final surfaceHeight = height ?? _sharedTextureHeight;
    if (surfaceWidth <= 0 || surfaceHeight <= 0) return false;

    final candidates = <(int?, int?)>[
      (
        (descriptor['kind'] as num?)?.toInt(),
        (descriptor['handle'] as num?)?.toInt(),
      ),
      (
        (descriptor['fallbackKind'] as num?)?.toInt(),
        (descriptor['fallbackHandle'] as num?)?.toInt(),
      ),
    ];
    for (final (kind, handle) in candidates) {
      if (kind == null || handle == null || handle == 0) continue;
      final attached =
          api.setExternalSurface(
            runtime,
            kind,
            Pointer<Void>.fromAddress(handle),
            surfaceWidth,
            surfaceHeight,
          ) !=
          0;
      if (!attached) continue;
      _sharedTextureId = textureId;
      _sharedTextureKind = kind;
      _sharedTextureAttached = true;
      _sharedTextureWidth = surfaceWidth;
      _sharedTextureHeight = surfaceHeight;
      return true;
    }
    return false;
  }

  Future<void> _handleSharedTextureCall(MethodCall call) async {
    switch (call.method) {
      case 'surfaceCleanup':
        _detachSharedTexture();
      case 'surfaceAvailable':
        final descriptor = call.arguments;
        if (descriptor is Map && !_attachSharedTexture(descriptor)) {
          Log.warn('[RfvpEngineRuntime] 无法重新绑定共享纹理 surface');
        }
    }
  }

  void _detachSharedTexture() {
    final api = _api;
    final runtime = _runtime;
    if (api != null && runtime > 0 && _sharedTextureAttached) {
      api.clearExternalSurface(runtime);
    }
    _sharedTextureAttached = false;
  }

  @override
  bool isExitRequested() {
    final api = _api;
    final runtime = _runtime;
    if (_exitRequested) return true;
    if (api == null || runtime <= 0) return false;
    _exitRequested = api.isExitRequested(runtime);
    return _exitRequested;
  }

  @override
  bool advanceWithoutRender(int deltaMs) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return false;
    final status = api.step(runtime, deltaMs.clamp(1, 1000));
    _drainAudio();
    return status == art3m1sRfvpStatusOk;
  }

  @override
  int advanceAndPresent(int deltaMs) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0 || !_sharedTextureAttached) return -1;
    final result = api.advanceAndPresent(runtime, deltaMs.clamp(1, 1000));
    _drainAudio();
    if (result > 0 && (_sharedTextureKind == 2 || _sharedTextureKind == 3)) {
      unawaited(
        _sharedTextureChannel.invokeMethod<void>('frameAvailable').catchError((
          Object error,
        ) {
          Log.warn('[RfvpEngineRuntime] 共享纹理帧通知失败: $error');
        }),
      );
    } else if (result < 0) {
      Log.warn('[RfvpEngineRuntime] 共享纹理提交失败，回退到 RGBA 路径');
      _detachSharedTexture();
    }
    return result;
  }

  @override
  Uint8List? advanceAndRender(int deltaMs) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return null;
    final pixels = api.advanceAndRender(runtime, deltaMs.clamp(1, 1000));
    _drainAudio();
    return pixels;
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
      art3m1sRfvpAudioLoadEncoded => EngineAudioCommandKind.loadEncoded,
      art3m1sRfvpAudioCreateStream => EngineAudioCommandKind.createStream,
      art3m1sRfvpAudioSubmitI16 => EngineAudioCommandKind.submitI16,
      art3m1sRfvpAudioSubmitF32 => EngineAudioCommandKind.submitF32,
      art3m1sRfvpAudioPlay => EngineAudioCommandKind.play,
      art3m1sRfvpAudioStop => EngineAudioCommandKind.stop,
      art3m1sRfvpAudioPause => EngineAudioCommandKind.pause,
      art3m1sRfvpAudioResume => EngineAudioCommandKind.resume,
      art3m1sRfvpAudioSetParams => EngineAudioCommandKind.setParams,
      art3m1sRfvpAudioDestroyStream => EngineAudioCommandKind.destroyStream,
      art3m1sRfvpAudioMasterVolume => EngineAudioCommandKind.masterVolume,
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
      RfvpCoreInputEvent(
        kind: art3m1sRfvpInputPointerMove,
        code: 0,
        phase: art3m1sRfvpInputPhaseMove,
        x: x,
        y: y,
      ),
    ]);
  }

  @override
  void feedClick() {
    if (!_inputGate.mouseButtons) return;
    _pushInput([
      RfvpCoreInputEvent(
        kind: art3m1sRfvpInputPointerButton,
        code: art3m1sRfvpPointerLeft,
        phase: art3m1sRfvpInputPhaseDown,
        x: _pointerX,
        y: _pointerY,
      ),
      RfvpCoreInputEvent(
        kind: art3m1sRfvpInputPointerButton,
        code: art3m1sRfvpPointerLeft,
        phase: art3m1sRfvpInputPhaseUp,
        x: _pointerX,
        y: _pointerY,
      ),
    ]);
  }

  @override
  void feedMouseButton(int button, bool pressed) {
    if (!_inputGate.mouseButtons) return;
    final code = switch (button) {
      2 => art3m1sRfvpPointerRight,
      3 => art3m1sRfvpPointerMiddle,
      _ => art3m1sRfvpPointerLeft,
    };
    _pushInput([
      RfvpCoreInputEvent(
        kind: art3m1sRfvpInputPointerButton,
        code: code,
        phase: pressed ? art3m1sRfvpInputPhaseDown : art3m1sRfvpInputPhaseUp,
        x: _pointerX,
        y: _pointerY,
      ),
    ]);
  }

  @override
  void feedTouch(int id, int phase, int x, int y) {
    if (!_inputGate.touch) return;
    final nativePhase = switch (phase) {
      0 => art3m1sRfvpInputPhaseDown,
      1 => art3m1sRfvpInputPhaseMove,
      2 => art3m1sRfvpInputPhaseUp,
      _ => art3m1sRfvpInputPhaseMove,
    };
    _pushInput([
      RfvpCoreInputEvent(
        kind: art3m1sRfvpInputTouch,
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
      RfvpCoreInputEvent(
        kind: art3m1sRfvpInputKey,
        code: keyCode,
        phase: pressed ? art3m1sRfvpInputPhaseDown : art3m1sRfvpInputPhaseUp,
      ),
    ]);
  }

  void _pushInput(List<RfvpCoreInputEvent> events) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0 || events.isEmpty) return;
    final status = api.feedInput(runtime, events);
    if (status != art3m1sRfvpStatusOk) {
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
          RfvpCoreInputEvent(
            kind: art3m1sRfvpInputQuit,
            code: 0,
            phase: art3m1sRfvpInputPhaseDown,
          ),
        ]);
      case 1:
        _pushInput(const [
          RfvpCoreInputEvent(kind: art3m1sRfvpInputFocus, code: 0, phase: 0),
        ]);
      case 2:
        _pushInput(const [
          RfvpCoreInputEvent(kind: art3m1sRfvpInputFocus, code: 0, phase: 1),
        ]);
    }
  }

  void _shutdownNative() {
    final api = _api;
    final runtime = _runtime;
    _detachSharedTexture();
    if (_sharedTextureId != null) {
      unawaited(_sharedTextureChannel.invokeMethod<void>('release'));
    }
    if (_sharedTextureHandlerAttached) {
      _sharedTextureChannel.setMethodCallHandler(null);
      _sharedTextureHandlerAttached = false;
    }
    _runtime = 0;
    _projectDirectory = null;
    _initialized = false;
    _sharedTextureId = null;
    _sharedTextureKind = null;
    _sharedTextureWidth = 0;
    _sharedTextureHeight = 0;
    if (api != null && runtime > 0) {
      api.destroyRuntime(runtime);
    }
    _api = null;
    _library = null;
  }

  static DynamicLibrary _openCoreLibrary() {
    final configured = Platform.environment['ART3M1S_CORE_LIBRARY'];
    if (configured != null && configured.isNotEmpty) {
      return DynamicLibrary.open(configured);
    }
    if (Platform.isIOS) return DynamicLibrary.process();
    final name = Platform.isMacOS
        ? 'libart3m1s_core.dylib'
        : Platform.isWindows
        ? 'art3m1s_core.dll'
        : 'libart3m1s_core.so';
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      if (Platform.isAndroid) rethrow;
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      return DynamicLibrary.open('${executableDirectory.path}/$name');
    }
  }
}
