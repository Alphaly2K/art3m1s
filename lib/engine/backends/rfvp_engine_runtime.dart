import 'dart:async';
import 'dart:convert';
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
import '../shared_texture_session.dart';
import 'rfvp/core_rfvp_api.dart';
import 'rfvp/rfvp_media_host.dart';

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
  late final RfvpMediaHost _media = RfvpMediaHost();

  static const MethodChannel _sharedTextureChannel = MethodChannel(
    'moe.alphaly.art3m1s/shared_texture',
  );

  DynamicLibrary? _library;
  CoreRfvpApiV1? _api;
  int _runtime = 0;
  bool _initialized = false;
  EngineSessionState _sessionState = EngineSessionState.active;
  Future<void> _sessionTransition = Future<void>.value();
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

  /// 最近请求的覆盖字体字节（null = 无覆盖）。RFVP 的覆盖是 per-runtime：
  bool _debug = false;
  bool _damageVisualization = false;

  /// 运行时尚未创建时先缓存，createRuntime 成功后再推送。
  Uint8List? _fontOverrideBytes;

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
  Set<EngineSessionState> get supportedSessionStates => const {
    EngineSessionState.active,
    EngineSessionState.frozen,
    EngineSessionState.suspended,
  };

  @override
  EngineSessionState get sessionState => _sessionState;

  @override
  Future<EngineSessionState> setSessionState(EngineSessionState state) {
    final target = supportedSessionStates.contains(state)
        ? state
        : EngineSessionState.suspended;
    final transition = _sessionTransition.then((_) async {
      if (_sessionState == target) return;
      _sessionState = target;
      if (target == EngineSessionState.active) {
        await _media.setSuspended(false);
        notifyLifecycle(2);
        return;
      }
      notifyLifecycle(1);
      await _media.setSuspended(true);
      if (target.releasesPresentation) {
        await SharedTextureSessionCoordinator.release(this);
      }
    });
    _sessionTransition = transition.catchError((_) {});
    return transition.then((_) => target);
  }

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
      // 日志走拉取式队列：不在 native 侧注册 NativeCallable，避免在
      // 越狱/注入环境触发 Dart 回调蹦床崩溃。
      _drainNativeLogs();
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
  void setDebug(bool enabled) {
    // 调试模式打开引擎全部分类的 trace（vm/syscall/prim/prim_tree/motion/
    // render，bit0-5）；关闭时交还 RFVP_TRACE* 环境变量。trace 走 info 级
    // 日志，由每帧 _drainNativeLogs 汇入宿主日志。
    _debug = enabled;
    _pushTraceMask();
  }

  void _pushTraceMask() {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return;
    final status = api.setTraceMask(runtime, _debug ? 0x3F : -1);
    if (status != art3m1sRfvpStatusOk &&
        status != art3m1sRfvpStatusUnsupported) {
      Log.warn('[RfvpEngineRuntime] trace mask 设置失败: $status');
    }
  }

  @override
  void setDamageVisualization(bool enabled) {
    _damageVisualization = enabled;
    _pushDamageVisualization();
  }

  void _pushDamageVisualization() {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return;
    final status = api.setDamageVisualization(runtime, _damageVisualization);
    if (status != art3m1sRfvpStatusOk &&
        status != art3m1sRfvpStatusUnsupported) {
      Log.warn('[RfvpEngineRuntime] 脏区可视化切换失败: $status');
    }
  }

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
    _syncTextTranslation();
  }

  void _syncTextTranslation() {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return;
    final service = _translation;
    if (service == null || !service.hostTranslationEnabled) {
      api.setTextTranslationEnabled(runtime, false);
      api.setTextReplacements(runtime, null);
      return;
    }
    if (api.setTextReplacements(
          runtime,
          jsonEncode(service.hostReplacementTable),
        ) !=
        art3m1sRfvpStatusOk) {
      Log.warn('[RfvpEngineRuntime] 翻译替换表提交失败');
    }
    api.setTextTranslationEnabled(runtime, service.hostOnlineEnabled);
  }

  void _drainTextEvents() {
    final api = _api;
    final runtime = _runtime;
    final service = _translation;
    if (api == null || runtime <= 0 || service == null) return;
    for (final event in api.pollTextEvents(runtime)) {
      service.enqueue(
        event.source,
        ruby: event.ruby,
        onComplete: (translated) {
          // 翻译异步完成；引擎按 serial 丢弃过期结果，直接提交即可。
          api.submitTextTranslation(runtime, event.serial, translated);
        },
      );
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
    _drainNativeLogs(api);
    if (_runtime <= 0) {
      _lastError = 'runtime create failed (${api.lastStatus})';
      Log.error('[RfvpEngineRuntime] $_lastError');
      return;
    }
    _lastError = null;
    _stageWidth = api.stageWidth(_runtime);
    _stageHeight = api.stageHeight(_runtime);
    _exitRequested = false;
    _syncTextTranslation();
    _pushFontOverride();
    _pushTraceMask();
    _pushDamageVisualization();
  }

  @override
  void setReportedOs(String? os) {}

  @override
  bool setEmoteBackend(int backend) => false;

  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) =>
      _runtime > 0;

  /// 安装运行时覆盖字体（TTF/OTF 字节）。RFVP 的覆盖按 runtime 生效：
  /// 运行时已存在时立即推送，否则缓存到 createRuntime 之后。
  /// 返回 false 表示 core 过旧（未导出字体覆盖槽位）或 core 拒绝该字体。
  @override
  bool setFontOverride(Uint8List bytes) {
    final api = _api;
    if (api == null || bytes.isEmpty) return false;
    if (!api.supportsFontOverride) {
      Log.info('[RfvpEngineRuntime] 当前 core 不支持运行时字体覆盖');
      return false;
    }
    _fontOverrideBytes = Uint8List.fromList(bytes);
    return _pushFontOverride();
  }

  /// 清除运行时覆盖字体，恢复游戏脚本字体。
  @override
  void clearFontOverride() {
    _fontOverrideBytes = null;
    _pushFontOverride();
  }

  /// 把缓存的覆盖字体推送到已创建的 runtime；runtime 未建时不动作
  /// （createRuntime 成功路径会补推）。返回 core 是否接受了当前状态。
  bool _pushFontOverride() {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return true;
    final bytes = _fontOverrideBytes;
    final status = bytes == null
        ? api.clearFontOverride(runtime)
        : api.setFontOverride(runtime, bytes);
    if (status != art3m1sRfvpStatusOk) {
      Log.warn('[RfvpEngineRuntime] 覆盖字体提交失败: $status');
      return false;
    }
    return true;
  }

  @override
  bool get supportsSpatialUpscaling {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return false;
    return api.capabilities(runtime) & art3m1sRfvpCapabilitySpatialUpscaling !=
        0;
  }

  @override
  bool setRenderQuality(EngineRenderQuality quality) => false;

  @override
  bool configureSpatialUpscale(double renderScale, {double sharpness = 0}) {
    // Surface attachment already configures the backend-native spatial pass
    // from the final output extent. Keep this host contract truthful so the
    // PlayerScreen can request higher-resolution output textures.
    return _sharedTextureAttached &&
        supportsSpatialUpscaling &&
        renderScale > 0 &&
        renderScale <= 1;
  }

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
      final textureId =
          await SharedTextureSessionCoordinator.runWithOwnership<int?>(
            this,
            _releaseSharedTextureForSession,
            () async {
              if (_sessionState != EngineSessionState.active) return null;
              if (!_sharedTextureHandlerAttached) {
                _sharedTextureChannel.setMethodCallHandler(
                  _handleSharedTextureCall,
                );
                _sharedTextureHandlerAttached = true;
              }
              _detachSharedTexture();
              final raw = await _sharedTextureChannel
                  .invokeMapMethod<String, dynamic>('create', {
                    'width': width,
                    'height': height,
                  });
              if (raw == null ||
                  !_attachSharedTexture(raw, width: width, height: height)) {
                Log.warn('[RfvpEngineRuntime] 共享纹理 attach 失败，使用 RGBA 回读');
                return null;
              }
              Log.info(
                '[RfvpEngineRuntime] 共享纹理已启用: id=$_sharedTextureId '
                '${_sharedTextureWidth}x$_sharedTextureHeight '
                '(stage=${_stageWidth}x$_stageHeight)',
              );
              return _sharedTextureId;
            },
          );
      if (textureId == null) {
        await SharedTextureSessionCoordinator.release(this);
      }
      return textureId;
    } catch (error) {
      Log.warn('[RfvpEngineRuntime] 共享纹理不可用，使用 RGBA 回读: $error');
      _sharedTextureId = null;
      _sharedTextureKind = null;
      await SharedTextureSessionCoordinator.release(this);
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
      final status = api.setExternalSurface(
        runtime,
        kind,
        Pointer<Void>.fromAddress(handle),
        surfaceWidth,
        surfaceHeight,
      );
      // RFVP reports status 0 on success; this differs from the legacy
      // Art3m1s boolean-style external surface API.
      if (status != art3m1sRfvpStatusOk) continue;
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

  Future<void> _releaseSharedTextureForSession() async {
    _detachSharedTexture();
    try {
      if (_sharedTextureId != null) {
        await _sharedTextureChannel.invokeMethod<void>('release');
      }
    } catch (error) {
      Log.warn('[RfvpEngineRuntime] 共享纹理释放失败: $error');
    }
    if (_sharedTextureHandlerAttached) {
      _sharedTextureChannel.setMethodCallHandler(null);
      _sharedTextureHandlerAttached = false;
    }
    _sharedTextureId = null;
    _sharedTextureKind = null;
    _sharedTextureWidth = 0;
    _sharedTextureHeight = 0;
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
    if (_sessionState != EngineSessionState.active) return false;
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return false;
    final status = api.step(runtime, deltaMs.clamp(1, 1000));
    _drainAudio();
    _drainTextEvents();
    _drainNativeLogs();
    _drainNativeLogs(api);
    return status == art3m1sRfvpStatusOk;
  }

  @override
  int advanceAndPresent(int deltaMs) {
    if (_sessionState != EngineSessionState.active) return -1;
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0 || !_sharedTextureAttached) return -1;
    final result = api.advanceAndPresent(runtime, deltaMs.clamp(1, 1000));
    _drainAudio();
    _drainTextEvents();
    _drainNativeLogs();
    _drainNativeLogs(api);
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
    if (_sessionState != EngineSessionState.active) return null;
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return null;
    final pixels = api.advanceAndRender(runtime, deltaMs.clamp(1, 1000));
    _drainAudio();
    _drainTextEvents();
    _drainNativeLogs();
    _drainNativeLogs(api);
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
  bool setProfilerEnabled(bool enabled) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return false;
    return api.setProfilerEnabled(runtime, enabled) == art3m1sRfvpStatusOk;
  }

  @override
  ProfilerSnapshot? readProfilerSnapshot() {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return null;
    final json = api.profilerSnapshot(runtime);
    if (json == null || json.isEmpty) return null;
    try {
      return ProfilerSnapshot.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (error) {
      Log.warn('[RfvpEngineRuntime] profiler snapshot 解析失败: $error');
      return null;
    }
  }

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

  /// RFVP 核心有独立滚轮事件：正 deltaY 表示向上滚动，单位与桌面
  /// winit LineDelta 一致（一格 = 1）。小于一格的残余由调用方按帧
  /// 脉冲化，这里直接透传取整后的值。
  @override
  void feedWheel(double deltaX, double deltaY) {
    final dx = deltaX.round();
    final dy = deltaY.round();
    if (dx == 0 && dy == 0) return;
    _pushInput([
      RfvpCoreInputEvent(
        kind: art3m1sRfvpInputWheel,
        code: 0,
        phase: 0,
        x: dx,
        y: dy,
      ),
    ]);
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
    unawaited(SharedTextureSessionCoordinator.abandon(this));
    _runtime = 0;
    _projectDirectory = null;
    _initialized = false;
    _sharedTextureId = null;
    _sharedTextureKind = null;
    _sharedTextureWidth = 0;
    _sharedTextureHeight = 0;
    try {
      if (api != null && runtime > 0) {
        api.destroyRuntime(runtime);
      }
    } finally {
      _drainNativeLogs(api);
    }
    _api = null;
    _library = null;
  }

  void _drainNativeLogs([CoreRfvpApiV1? api]) {
    api ??= _api;
    if (api == null) return;
    for (final record in api.drainLogs()) {
      final text = '[RFVP] ${record.message}';
      switch (String.fromCharCode(record.level)) {
        case 'E':
          Log.error(text);
        case 'W':
          Log.warn(text);
        case 'D':
        case 'T':
          Log.debug(text);
        default:
          Log.info(text);
      }
    }
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
