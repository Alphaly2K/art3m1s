import 'package:flutter/foundation.dart';

import '../../models/game_engine.dart';
import '../../models/input_gate.dart';
import '../../services/core_bridge.dart'
    hide AvoidOverlay, EngineDialogRequest, EngineVideoPlayback;
import '../../services/profiler_snapshot.dart';
import '../../services/text_translation_service.dart';
import '../engine_runtime.dart';

/// Artemis core adapter for the Host engine contract.
///
/// All `CoreApiV1`/`DynamicLibrary` details stay inside `CoreBridge`; callers
/// only see [EngineRuntime].
class Art3m1sEngineRuntime implements EngineRuntime {
  Art3m1sEngineRuntime({
    void Function(EngineDialogRequest request)? onDialogRequested,
    bool? engineCursorControlEnabled,
  }) : _bridge = CoreBridge(
         onDialogRequested: onDialogRequested,
         engineCursorControlEnabled: engineCursorControlEnabled,
       );

  final CoreBridge _bridge;

  @override
  GameEngineKind get kind => GameEngineKind.art3m1s;
  @override
  bool get isInitialized => _bridge.isInitialized;
  @override
  int get stageWidth => _bridge.stageWidth;
  @override
  int get stageHeight => _bridge.stageHeight;
  @override
  ValueListenable<bool> get cursorHidden => _bridge.cursorHidden;
  @override
  ValueListenable<AvoidOverlay?> get avoidOverlay => _bridge.avoidOverlay;
  @override
  ValueListenable<String?> get windowTitle => _bridge.windowTitle;
  @override
  EngineMediaHost get media => _bridge.media;

  @override
  Future<void> initialize() => _bridge.initialize();
  @override
  void shutdown() => _bridge.shutdown();

  @override
  void setDebug(bool enabled) => _bridge.setDebug(enabled);
  @override
  void setDamageVisualization(bool enabled) =>
      _bridge.setDamageVisualization(enabled);
  @override
  void setSaveDir(String dir) => _bridge.setSaveDir(dir);
  @override
  void configureTranslation(TextTranslationService? service) =>
      _bridge.configureTranslation(service);
  @override
  void configureInputGate(InputGatePolicy gate) =>
      _bridge.configureInputGate(gate);
  @override
  void registerFileReader() => _bridge.registerFileReader();

  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) =>
      _bridge.createRuntime(stageWidth, stageHeight, backend: backend);
  @override
  void setReportedOs(String? os) => _bridge.setReportedOs(os);
  @override
  bool setEmoteBackend(int backend) => _bridge.setEmoteBackend(backend);
  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) =>
      _bridge.loadProjectBytes(iniContent, platform: platform);

  @override
  bool setFontOverride(Uint8List bytes) => _bridge.setFontOverride(bytes);
  @override
  void clearFontOverride() => _bridge.clearFontOverride();

  @override
  bool get supportsSpatialUpscaling => _bridge.supportsSpatialUpscaling;
  @override
  bool setRenderQuality(EngineRenderQuality quality) =>
      _bridge.setRenderQualityPreset(quality.index);
  @override
  bool configureSpatialUpscale(double renderScale, {double sharpness = 0}) =>
      _bridge.configureSpatialUpscale(renderScale, sharpness: sharpness);

  @override
  bool get hasActiveSharedTexture => _bridge.hasActiveSharedTexture;
  @override
  int? get sharedTextureId => _bridge.sharedTextureId;
  @override
  int get sharedTextureWidth => _bridge.sharedTextureWidth;
  @override
  int get sharedTextureHeight => _bridge.sharedTextureHeight;
  @override
  Future<int?> enableSharedTexture({int? outputWidth, int? outputHeight}) =>
      _bridge.enableSharedTexture(
        outputWidth: outputWidth,
        outputHeight: outputHeight,
      );

  @override
  bool isExitRequested() => _bridge.isExitRequested();
  @override
  bool advanceWithoutRender(int deltaMs) =>
      _bridge.advanceWithoutRender(deltaMs);
  @override
  int advanceAndPresent(int deltaMs) => _bridge.advanceAndPresent(deltaMs);
  @override
  Uint8List? advanceAndRender(int deltaMs) => _bridge.advanceAndRender(deltaMs);

  @override
  bool setProfilerEnabled(bool enabled) => _bridge.setProfilerEnabled(enabled);
  @override
  ProfilerSnapshot? readProfilerSnapshot() => _bridge.readProfilerSnapshot();

  @override
  void feedMouse(int x, int y) => _bridge.feedMouse(x, y);
  @override
  void feedClick() => _bridge.feedClick();
  @override
  void feedMouseButton(int button, bool pressed) =>
      _bridge.feedMouseButton(button, pressed);
  @override
  void feedTouch(int id, int phase, int x, int y) =>
      _bridge.feedTouch(id, phase, x, y);
  @override
  void feedKey(int keyCode, bool pressed) => _bridge.feedKey(keyCode, pressed);
  @override
  void feedForwardedKey(int keyCode, bool pressed) =>
      _bridge.feedForwardedKey(keyCode, pressed);
  @override
  bool submitDialog(bool accepted, String text) =>
      _bridge.submitDialog(accepted, text);
  @override
  void notifyMouseActivity() => _bridge.notifyMouseActivity();

  @override
  void setWindowStateBits({bool? fullscreen, bool? minimized}) =>
      _bridge.setWindowStateBits(fullscreen: fullscreen, minimized: minimized);
  @override
  void notifyLifecycle(int state) => _bridge.notifyLifecycle(state);
}
