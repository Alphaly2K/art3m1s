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
import 'krkr/core_krkr_api.dart';

/// KRKRSDL3 adapter exposed through art3m1s-core's public KRKR ABI.
///
/// The current native backend is macOS-only and publishes RGBA frames. Audio
/// sample consumption is clocked here so KRKR can continue filling its buffers;
/// speaker playback remains deliberately disabled until a streaming PCM host is
/// available.
class KrkrEngineRuntime implements EngineRuntime {
  KrkrEngineRuntime({this.engineCursorControlEnabled = true});

  final bool? engineCursorControlEnabled;
  final ValueNotifier<bool> _cursorHidden = ValueNotifier(false);
  final ValueNotifier<AvoidOverlay?> _avoidOverlay = ValueNotifier(null);
  final ValueNotifier<String?> _windowTitle = ValueNotifier(null);
  final _KrkrMutedMediaHost _media = _KrkrMutedMediaHost();
  final Map<int, _KrkrAudioClock> _audioStreams = {};

  DynamicLibrary? _library;
  CoreKrkrApiV1? _api;
  TextTranslationService? _translation;
  InputGatePolicy _inputGate = InputGatePolicy.full;
  String? _projectPath;
  String? _saveDirectory;
  int _runtime = 0;
  int _stageWidth = 0;
  int _stageHeight = 0;
  int _pointerX = 0;
  int _pointerY = 0;
  bool _initialized = false;
  bool _exitRequested = false;
  bool _reportedMutedAudio = false;

  @override
  GameEngineKind get kind => GameEngineKind.krkr;
  @override
  bool get isInitialized => _initialized;
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
    if (!Platform.isMacOS) {
      Log.error('[KrkrEngineRuntime] KRKRSDL3 upstream backend 当前仅支持 macOS');
      return;
    }
    try {
      _library = _openCoreLibrary();
      _api = CoreKrkrApiV1.tryLoad(_library!);
      if (_api == null) {
        throw StateError('art3m1s-core 未导出兼容的 KRKR API v1');
      }
      _initialized = true;
      Log.info('[KrkrEngineRuntime] 使用 art3m1s_krkr_get_api_v1');
    } catch (error) {
      Log.error('[KrkrEngineRuntime] KRKR 后端加载失败: $error');
      _shutdownNative();
    }
  }

  @override
  void shutdown() {
    _shutdownNative();
    final translation = _translation;
    _translation = null;
    if (translation != null) unawaited(translation.dispose());
    _media.dispose();
  }

  void _shutdownNative() {
    final api = _api;
    final runtime = _runtime;
    _runtime = 0;
    if (api != null && runtime > 0) api.destroyRuntime(runtime);
    _audioStreams.clear();
    _initialized = false;
    _exitRequested = false;
    _api = null;
    _library = null;
  }

  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) async {
    if (isArchive) throw UnsupportedError('KRKR 不支持 PFS 归档项目');
    final api = _api;
    if (api == null) return null;
    final probe = api.probeProject(projectPath);
    if (probe == null || !probe.isKrkr) {
      throw StateError('目录中没有可识别的 XP3/TJS Kirikiri 入口');
    }
    _projectPath = projectPath;
    return Uint8List(0);
  }

  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) {
    final api = _api;
    final projectPath = _projectPath;
    if (api == null || projectPath == null) return;
    // The upstream shim currently rejects a non-empty save root. Keep the app
    // save directory reserved, but let KRKR use the game's own savedata path.
    if (_saveDirectory != null) {
      Log.warn('[KrkrEngineRuntime] 独立存档目录尚未接入，暂用游戏自身 savedata');
    }
    _runtime = api.createRuntime(
      gameRoot: projectPath,
      width: stageWidth,
      height: stageHeight,
    );
    if (_runtime <= 0) {
      Log.error(
        '[KrkrEngineRuntime] runtime create failed (${api.lastStatus})',
      );
      return;
    }
    _stageWidth = api.stageWidth(_runtime);
    _stageHeight = api.stageHeight(_runtime);
    _exitRequested = false;
  }

  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) =>
      _runtime > 0;

  @override
  bool advanceWithoutRender(int deltaMs) => _tick(deltaMs);

  @override
  Uint8List? advanceAndRender(int deltaMs) {
    if (!_tick(deltaMs)) return null;
    final api = _api;
    if (api == null || _runtime <= 0) return null;
    final frame = api.acquireFrame(_runtime);
    if (frame == null) return null;
    _stageWidth = frame.width;
    _stageHeight = frame.height;
    return frame.pixels;
  }

  bool _tick(int deltaMs) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return false;
    final status = api.tick(runtime);
    _drainAudio(deltaMs.clamp(0, 1000));
    if (status != art3m1sKrkrStatusOk) {
      _exitRequested = true;
      Log.error('[KrkrEngineRuntime] runtime tick failed ($status)');
      return false;
    }
    return true;
  }

  void _drainAudio(int deltaMs) {
    final api = _api;
    final runtime = _runtime;
    if (api == null || runtime <= 0) return;
    while (true) {
      final command = api.pollAudioCommand(runtime);
      if (command == null) break;
      if (!_reportedMutedAudio) {
        _reportedMutedAudio = true;
        Log.warn('[KrkrEngineRuntime] 已接收 KRKR PCM，真实扬声器输出尚未接入');
      }
      switch (command.kind) {
        case art3m1sKrkrAudioCreateStream:
          _audioStreams[command.streamId] = _KrkrAudioClock(
            sampleRate: command.sampleRate,
          );
        case art3m1sKrkrAudioSubmitPcm:
          _audioStreams[command.streamId]?.appendedSamples +=
              command.sampleCount;
        case art3m1sKrkrAudioPlay:
          _audioStreams[command.streamId]?.playing = true;
        case art3m1sKrkrAudioPause:
          _audioStreams[command.streamId]?.playing = false;
        case art3m1sKrkrAudioStop:
          _audioStreams[command.streamId]?.reset();
        case art3m1sKrkrAudioDestroyStream:
          _audioStreams.remove(command.streamId);
        case art3m1sKrkrAudioSetParams:
        case art3m1sKrkrAudioMasterVolume:
          break;
      }
    }
    for (final entry in _audioStreams.entries) {
      final stream = entry.value;
      if (!stream.playing || stream.sampleRate <= 0) continue;
      stream.fractionalSamples += deltaMs * stream.sampleRate / 1000;
      final advance = stream.fractionalSamples.floor();
      stream.fractionalSamples -= advance;
      final consumed = (stream.consumedSamples + advance).clamp(
        0,
        stream.appendedSamples,
      );
      if (consumed == stream.consumedSamples) continue;
      stream.consumedSamples = consumed;
      api.submitAudioConsumed(
        runtime,
        streamId: entry.key,
        consumedSamples: consumed,
      );
    }
  }

  void _pushInput(List<KrkrCoreInputEvent> events) {
    final api = _api;
    if (api == null || _runtime <= 0 || events.isEmpty) return;
    final status = api.pushInput(_runtime, events);
    if (status != art3m1sKrkrStatusOk) {
      Log.warn('[KrkrEngineRuntime] input rejected ($status)');
    }
  }

  @override
  void feedMouse(int x, int y) {
    if (!_inputGate.mouseMove) return;
    _pointerX = x;
    _pointerY = y;
    _pushInput([
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputPointerMove,
        phase: art3m1sKrkrInputPhaseMove,
        x: x,
        y: y,
      ),
    ]);
  }

  @override
  void feedClick() {
    if (!_inputGate.mouseButtons) return;
    _pushInput([
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputPointerButton,
        code: art3m1sKrkrPointerLeft,
        phase: art3m1sKrkrInputPhaseDown,
        x: _pointerX,
        y: _pointerY,
      ),
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputPointerButton,
        code: art3m1sKrkrPointerLeft,
        phase: art3m1sKrkrInputPhaseUp,
        x: _pointerX,
        y: _pointerY,
      ),
    ]);
  }

  @override
  void feedMouseButton(int button, bool pressed) {
    if (!_inputGate.mouseButtons) return;
    final code = switch (button) {
      2 => art3m1sKrkrPointerRight,
      3 => art3m1sKrkrPointerMiddle,
      _ => art3m1sKrkrPointerLeft,
    };
    _pushInput([
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputPointerButton,
        code: code,
        phase: pressed ? art3m1sKrkrInputPhaseDown : art3m1sKrkrInputPhaseUp,
        x: _pointerX,
        y: _pointerY,
      ),
    ]);
  }

  @override
  void feedTouch(int id, int phase, int x, int y) {
    if (!_inputGate.touch) return;
    _pointerX = x;
    _pointerY = y;
    final events = <KrkrCoreInputEvent>[
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputPointerMove,
        phase: art3m1sKrkrInputPhaseMove,
        x: x,
        y: y,
        id: id,
      ),
    ];
    if (phase == 0 || phase == 2) {
      events.add(
        KrkrCoreInputEvent(
          kind: art3m1sKrkrInputPointerButton,
          code: art3m1sKrkrPointerLeft,
          phase: phase == 0
              ? art3m1sKrkrInputPhaseDown
              : art3m1sKrkrInputPhaseUp,
          x: x,
          y: y,
          id: id,
        ),
      );
    }
    _pushInput(events);
  }

  @override
  void feedKey(int keyCode, bool pressed) {
    final mapped = _inputGate.filterKey(keyCode);
    if (mapped != null) _pushKey(mapped, pressed);
  }

  @override
  void feedForwardedKey(int keyCode, bool pressed) {
    final mapped = _inputGate.filterForwardedKey(keyCode);
    if (mapped == null) return;
    // PlayerScreen's legacy wheel forwarding uses these Artemis virtual keys.
    if (pressed && (mapped == 136 || mapped == 137)) {
      feedWheel(0, mapped == 136 ? 1 : -1);
      return;
    }
    _pushKey(mapped, pressed);
  }

  void _pushKey(int keyCode, bool pressed) {
    _pushInput([
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputKey,
        code: keyCode,
        phase: pressed ? art3m1sKrkrInputPhaseDown : art3m1sKrkrInputPhaseUp,
      ),
    ]);
  }

  @override
  void feedWheel(double deltaX, double deltaY) {
    final value = deltaY.round();
    if (value == 0) return;
    _pushInput([
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputWheel,
        x: _pointerX,
        y: _pointerY,
        value: value,
      ),
    ]);
  }

  @override
  bool isExitRequested() {
    final api = _api;
    if (_exitRequested) return true;
    if (api == null || _runtime <= 0) return false;
    _exitRequested = api.isExitRequested(_runtime);
    return _exitRequested;
  }

  @override
  void notifyLifecycle(int state) {
    if (state == 0) {
      _pushInput(const [KrkrCoreInputEvent(kind: art3m1sKrkrInputQuit)]);
      return;
    }
    _pushInput([
      KrkrCoreInputEvent(
        kind: art3m1sKrkrInputFocus,
        phase: state == 2 ? art3m1sKrkrInputPhaseDown : art3m1sKrkrInputPhaseUp,
      ),
    ]);
  }

  @override
  void setSaveDir(String dir) {
    _saveDirectory = dir;
  }

  @override
  void configureInputGate(InputGatePolicy gate) => _inputGate = gate;
  @override
  void configureTranslation(TextTranslationService? service) {
    if (identical(_translation, service)) return;
    final previous = _translation;
    _translation = service;
    if (previous != null) unawaited(previous.dispose());
  }

  @override
  void registerFileReader() {}
  @override
  void setDebug(bool enabled) {}
  @override
  void setDamageVisualization(bool enabled) {}
  @override
  void setReportedOs(String? os) {}
  @override
  bool setEmoteBackend(int backend) => false;
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
  int advanceAndPresent(int deltaMs) => -1;
  @override
  bool setProfilerEnabled(bool enabled) => false;
  @override
  ProfilerSnapshot? readProfilerSnapshot() => null;
  @override
  bool submitDialog(bool accepted, String text) => false;
  @override
  void notifyMouseActivity() {}
  @override
  void setWindowStateBits({bool? fullscreen, bool? minimized}) {}

  static DynamicLibrary _openCoreLibrary() {
    final configured = Platform.environment['ART3M1S_CORE_LIBRARY'];
    if (configured != null && configured.isNotEmpty) {
      return DynamicLibrary.open(configured);
    }
    final name = Platform.isMacOS
        ? 'libart3m1s_core.dylib'
        : Platform.isWindows
        ? 'art3m1s_core.dll'
        : 'libart3m1s_core.so';
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      return DynamicLibrary.open('${executableDirectory.path}/$name');
    }
  }
}

class _KrkrAudioClock {
  _KrkrAudioClock({required this.sampleRate});
  final int sampleRate;
  bool playing = false;
  int appendedSamples = 0;
  int consumedSamples = 0;
  double fractionalSamples = 0;

  void reset() {
    playing = false;
    appendedSamples = 0;
    consumedSamples = 0;
    fractionalSamples = 0;
  }
}

class _KrkrMutedMediaHost implements EngineMediaHost {
  final ValueNotifier<EngineVideoPlayback?> _videoPlayback = ValueNotifier(
    null,
  );
  final ValueNotifier<bool> _fullscreenVideoBlocking = ValueNotifier(false);
  @override
  ValueListenable<EngineVideoPlayback?> get videoPlayback => _videoPlayback;
  @override
  ValueListenable<bool> get fullscreenVideoBlocking => _fullscreenVideoBlocking;
  @override
  bool get isFullscreenVideoBlocking => false;
  @override
  void handleEngineAudioCommand(EngineAudioCommand command) {}
  @override
  Future<void> skipVideo() async {}

  void dispose() {
    _videoPlayback.dispose();
    _fullscreenVideoBlocking.dispose();
  }
}
