import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../models/game_engine.dart';
import '../../models/input_gate.dart';
import '../../services/logger.dart';
import '../engine_runtime.dart';
import '../shared_texture_session.dart';
import 'siglus/core_siglus_api.dart';

/// Siglus VM with the common art3m1s-render GPU backend. The VM is confined
/// to the same Dart isolate/native thread from creation through destruction.
class SiglusEngineRuntime extends UnsupportedEngineRuntime {
  SiglusEngineRuntime() : super(GameEngineKind.siglus);

  static const MethodChannel _textureChannel = MethodChannel(
    'moe.alphaly.art3m1s/shared_texture',
  );

  CoreSiglusApiV1? _api;
  int _runtime = 0;
  int _width = 0;
  int _height = 0;
  int _pointerX = 0;
  int _pointerY = 0;
  String? _projectPath;
  InputGatePolicy _inputGate = InputGatePolicy.full;
  bool _exitRequested = false;
  EngineSessionState _state = EngineSessionState.active;
  Future<void> _transition = Future<void>.value();
  int? _textureId;
  int? _textureKind;
  int _textureWidth = 0;
  int _textureHeight = 0;
  bool _textureAttached = false;
  bool _handlerAttached = false;

  @override
  bool get isInitialized => _api != null;
  @override
  int get stageWidth => _width;
  @override
  int get stageHeight => _height;
  @override
  Set<EngineSessionState> get supportedSessionStates => const {
    EngineSessionState.active,
    EngineSessionState.frozen,
    EngineSessionState.suspended,
  };
  @override
  EngineSessionState get sessionState => _state;

  @override
  Future<EngineSessionState> setSessionState(EngineSessionState state) {
    final target = supportedSessionStates.contains(state)
        ? state
        : EngineSessionState.suspended;
    final pending = _transition.then((_) async {
      if (_state == target) return;
      _state = target;
      await media.setSuspended(target != EngineSessionState.active);
      if (target.releasesPresentation) {
        await SharedTextureSessionCoordinator.release(this);
      }
    });
    _transition = pending.catchError((Object _) {});
    return pending.then((_) => target);
  }

  @override
  Future<void> initialize() async {
    if (!Platform.isMacOS) {
      Log.warn('[SiglusEngineRuntime] 当前 Siglus 宿主仅在 macOS 验证');
      return;
    }
    try {
      final configured = Platform.environment['ART3M1S_CORE_LIBRARY'];
      DynamicLibrary library;
      if (configured != null && configured.isNotEmpty) {
        library = DynamicLibrary.open(configured);
      } else {
        try {
          library = DynamicLibrary.open('libart3m1s_core.dylib');
        } catch (_) {
          library = DynamicLibrary.open(
            '${File(Platform.resolvedExecutable).parent.path}/libart3m1s_core.dylib',
          );
        }
      }
      _api = CoreSiglusApiV1.tryLoad(library);
      if (_api == null) {
        throw StateError(
          'art3m1s-core 未导出兼容的 Siglus API v1；请使用 --features siglus-engine 构建',
        );
      }
      Log.info('[SiglusEngineRuntime] 使用 art3m1s_siglus_get_api_v1');
    } catch (error) {
      Log.error('[SiglusEngineRuntime] 初始化失败: $error');
    }
  }

  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) async {
    if (isArchive) throw UnsupportedError('Siglus 不支持 PFS 归档');
    final api = _api;
    if (api == null) return null;
    if (!api.probeProject(projectPath)) {
      throw StateError('目录中没有可识别的 Scene.pck / Gameexe.dat 或 Gameexe.ini');
    }
    _projectPath = projectPath;
    return Uint8List(0);
  }

  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) {
    final api = _api;
    final path = _projectPath;
    if (api == null || path == null || _runtime != 0) return;
    try {
      _runtime = api.createRuntime(path, backend: backend);
      _width = api.stageWidth(_runtime);
      _height = api.stageHeight(_runtime);
      _exitRequested = false;
      Log.info('[SiglusEngineRuntime] 舞台 ${_width}x$_height');
    } catch (error) {
      Log.error('[SiglusEngineRuntime] 创建失败: $error');
    }
  }

  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) =>
      _runtime != 0;

  @override
  void configureInputGate(InputGatePolicy gate) => _inputGate = gate;

  void _input(int kind, int code, int x, int y, int value) {
    final api = _api;
    if (api == null || _runtime == 0 || _state != EngineSessionState.active) {
      return;
    }
    final status = api.input(_runtime, kind, code, x, y, value);
    if (status != CoreSiglusApiV1.ok) {
      Log.warn('[SiglusEngineRuntime] 输入被拒绝 ($status)');
    }
  }

  @override
  void feedMouse(int x, int y) {
    if (!_inputGate.mouseMove) return;
    _pointerX = x;
    _pointerY = y;
    _input(CoreSiglusApiV1.inputMove, 0, x, y, 0);
  }

  @override
  void feedClick() {
    if (!_inputGate.mouseButtons) return;
    feedMouseButton(1, true);
    feedMouseButton(1, false);
  }

  @override
  void feedMouseButton(int button, bool pressed) {
    if (!_inputGate.mouseButtons) return;
    _input(
      CoreSiglusApiV1.inputButton,
      button,
      _pointerX,
      _pointerY,
      pressed ? 1 : 0,
    );
  }

  @override
  void feedTouch(int id, int phase, int x, int y) {
    if (!_inputGate.touch) return;
    _pointerX = x;
    _pointerY = y;
    _input(CoreSiglusApiV1.inputTouch, phase, x, y, 0);
  }

  @override
  void feedKey(int keyCode, bool pressed) {
    final code = _inputGate.filterKey(keyCode);
    if (code != null) {
      _input(CoreSiglusApiV1.inputKey, code, 0, 0, pressed ? 1 : 0);
    }
  }

  @override
  void feedForwardedKey(int keyCode, bool pressed) {
    final code = _inputGate.filterForwardedKey(keyCode);
    if (code == null) return;
    if (pressed && (code == 136 || code == 137)) {
      feedWheel(0, code == 136 ? 1 : -1);
    } else {
      _input(CoreSiglusApiV1.inputKey, code, 0, 0, pressed ? 1 : 0);
    }
  }

  @override
  void feedWheel(double deltaX, double deltaY) {
    final delta = deltaY.round();
    if (delta != 0) _input(CoreSiglusApiV1.inputWheel, 0, 0, 0, delta);
  }

  bool _tick(int deltaMs, int mode) {
    final api = _api;
    if (api == null || _runtime == 0 || _state != EngineSessionState.active) {
      return false;
    }
    final status = api.tick(_runtime, deltaMs, mode);
    if (status != CoreSiglusApiV1.ok) {
      _exitRequested = true;
      Log.error('[SiglusEngineRuntime] 帧处理失败 ($status): ${api.lastError}');
      return false;
    }
    _exitRequested = api.isExitRequested(_runtime);
    return true;
  }

  @override
  bool advanceWithoutRender(int deltaMs) =>
      _tick(deltaMs, CoreSiglusApiV1.tickAdvance);

  @override
  Uint8List? advanceAndRender(int deltaMs) {
    final api = _api;
    if (api == null || _runtime == 0 || _state != EngineSessionState.active) {
      return null;
    }
    try {
      final frame = api.render(_runtime, deltaMs, _width * _height * 4);
      _exitRequested = api.isExitRequested(_runtime);
      return frame;
    } catch (error) {
      _exitRequested = true;
      Log.error('[SiglusEngineRuntime] 渲染失败: $error');
      return null;
    }
  }

  @override
  bool isExitRequested() =>
      _exitRequested ||
      (_runtime != 0 && _api?.isExitRequested(_runtime) == true);

  @override
  bool get hasActiveSharedTexture => _textureId != null && _textureAttached;
  @override
  int? get sharedTextureId => _textureId;
  @override
  int get sharedTextureWidth => _textureWidth;
  @override
  int get sharedTextureHeight => _textureHeight;

  @override
  Future<int?> enableSharedTexture({
    int? outputWidth,
    int? outputHeight,
  }) async {
    if (_api == null || _runtime == 0) return null;
    final width = math.max(outputWidth ?? _width, _width);
    final height = math.max(outputHeight ?? _height, _height);
    if (_textureAttached &&
        _textureId != null &&
        _textureWidth == width &&
        _textureHeight == height) {
      return _textureId;
    }
    try {
      final id = await SharedTextureSessionCoordinator.runWithOwnership<int?>(
        this,
        _releaseTexture,
        () async {
          if (_state != EngineSessionState.active) return null;
          if (!_handlerAttached) {
            _textureChannel.setMethodCallHandler(_handleTextureCall);
            _handlerAttached = true;
          }
          _detachTexture();
          final descriptor = await _textureChannel
              .invokeMapMethod<String, dynamic>('create', {
                'width': width,
                'height': height,
              });
          if (descriptor == null ||
              !_attachTexture(descriptor, width, height)) {
            Log.warn('[SiglusEngineRuntime] 共享纹理不可用，退回 RGBA');
            return null;
          }
          return _textureId;
        },
      );
      if (id == null) await SharedTextureSessionCoordinator.release(this);
      return id;
    } catch (error) {
      Log.warn('[SiglusEngineRuntime] 共享纹理失败: $error');
      await SharedTextureSessionCoordinator.release(this);
      return null;
    }
  }

  bool _attachTexture(Map<dynamic, dynamic> descriptor, int width, int height) {
    final api = _api;
    final id = (descriptor['textureId'] as num?)?.toInt();
    if (api == null || _runtime == 0 || id == null) return false;
    for (final (kind, handle) in [
      (
        (descriptor['kind'] as num?)?.toInt(),
        (descriptor['handle'] as num?)?.toInt(),
      ),
      (
        (descriptor['fallbackKind'] as num?)?.toInt(),
        (descriptor['fallbackHandle'] as num?)?.toInt(),
      ),
    ]) {
      if (kind == null || handle == null || handle == 0) continue;
      final status = api.setExternalSurface(
        _runtime,
        kind,
        Pointer<Void>.fromAddress(handle),
        width,
        height,
      );
      if (status != CoreSiglusApiV1.ok) continue;
      _textureId = id;
      _textureKind = kind;
      _textureAttached = true;
      _textureWidth = width;
      _textureHeight = height;
      return true;
    }
    return false;
  }

  Future<void> _handleTextureCall(MethodCall call) async {
    switch (call.method) {
      case 'surfaceCleanup':
        _detachTexture();
      case 'surfaceAvailable':
        if (call.arguments case final Map descriptor) {
          if (!_attachTexture(descriptor, _textureWidth, _textureHeight)) {
            Log.warn('[SiglusEngineRuntime] 无法重新绑定共享纹理');
          }
        }
    }
  }

  void _detachTexture() {
    if (_textureAttached && _api != null && _runtime != 0) {
      _api!.setExternalSurface(_runtime, 0, nullptr, 0, 0);
    }
    _textureAttached = false;
  }

  Future<void> _releaseTexture() async {
    _detachTexture();
    if (_textureId != null) {
      try {
        await _textureChannel.invokeMethod<void>('release');
      } catch (error) {
        Log.warn('[SiglusEngineRuntime] 共享纹理释放失败: $error');
      }
    }
    if (_handlerAttached) {
      _textureChannel.setMethodCallHandler(null);
      _handlerAttached = false;
    }
    _textureId = null;
    _textureKind = null;
    _textureWidth = 0;
    _textureHeight = 0;
  }

  @override
  int advanceAndPresent(int deltaMs) {
    if (!_textureAttached) return -1;
    if (!_tick(deltaMs, CoreSiglusApiV1.tickPresent)) {
      _detachTexture();
      return -1;
    }
    if (_textureKind == 2 || _textureKind == 3) {
      unawaited(
        _textureChannel
            .invokeMethod<void>('frameAvailable')
            .catchError(
              (Object error) => Log.warn('[SiglusEngineRuntime] 帧通知失败: $error'),
            ),
      );
    }
    return 1;
  }

  @override
  void shutdown() {
    _detachTexture();
    if (_textureId != null) {
      unawaited(_textureChannel.invokeMethod<void>('release'));
    }
    if (_handlerAttached) _textureChannel.setMethodCallHandler(null);
    _handlerAttached = false;
    unawaited(SharedTextureSessionCoordinator.abandon(this));
    if (_runtime != 0) _api?.destroyRuntime(_runtime);
    _runtime = 0;
    _api = null;
    _textureId = null;
    _textureKind = null;
    _textureWidth = 0;
    _textureHeight = 0;
    _width = 0;
    _height = 0;
    _exitRequested = false;
  }
}
