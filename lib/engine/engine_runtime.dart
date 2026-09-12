import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/game_engine.dart';
import '../models/input_gate.dart';
import '../services/profiler_snapshot.dart';
import '../services/text_translation_service.dart';

enum EngineRenderQuality { native, quality, balanced, performance }

class EngineDialogRequest {
  const EngineDialogRequest({
    required this.title,
    required this.message,
    required this.hasCancel,
    required this.hasTextField,
    required this.textFieldSize,
    required this.initialText,
  });

  factory EngineDialogRequest.fromJson(Map<String, dynamic> json) {
    return EngineDialogRequest(
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      hasCancel: json['hasCancel'] == true,
      hasTextField: json['textfield'] == true,
      textFieldSize: switch (json['textfieldSize']) {
        final num value when value > 0 => value.toInt(),
        _ => null,
      },
      initialText: json['initialText']?.toString() ?? '',
    );
  }

  final String title;
  final String message;
  final bool hasCancel;
  final bool hasTextField;
  final int? textFieldSize;
  final String initialText;
}

/// 紧急回避覆盖状态（`avoid` 事件）。`file` 为覆盖图资源名，null 表示纯黑。
class AvoidOverlay {
  const AvoidOverlay({this.file});
  final String? file;
}

/// Host-owned video presentation callback shared by all engines.
class EngineVideoPlayback {
  const EngineVideoPlayback({
    required this.id,
    required this.view,
    required this.aspectRatio,
    required this.skippable,
  });

  final String? id;
  final Widget view;
  final double aspectRatio;
  final bool skippable;

  bool get isFullscreen => id == null;
}

/// Backend-neutral audio command consumed by the host media implementation.
enum EngineAudioCommandKind {
  loadEncoded,
  createStream,
  submitI16,
  submitF32,
  play,
  stop,
  pause,
  resume,
  setParams,
  destroyStream,
  masterVolume,
}

class EngineAudioCommand {
  const EngineAudioCommand({
    required this.kind,
    required this.streamId,
    required this.id,
    required this.channel,
    required this.payload,
    this.sampleRate = 0,
    this.channels = 0,
    this.repeat = false,
    this.fadeMs = 0,
    this.volume = 1,
    this.pan = 0,
  });

  final EngineAudioCommandKind kind;
  final int streamId;
  final String id;
  final String channel;
  final Uint8List payload;
  final int sampleRate;
  final int channels;
  final bool repeat;
  final int fadeMs;
  final double volume;
  final double pan;
}

abstract interface class EngineMediaHost {
  ValueListenable<EngineVideoPlayback?> get videoPlayback;
  ValueListenable<bool> get fullscreenVideoBlocking;
  bool get isFullscreenVideoBlocking;
  void handleEngineAudioCommand(EngineAudioCommand command);
  Future<void> skipVideo();
}

/// Engine-facing host operations.
///
/// `PlayerScreen` and other Host features depend on this contract instead of
/// importing backend implementations or either native library directly.
abstract interface class EngineRuntime {
  GameEngineKind get kind;

  bool get isInitialized;
  int get stageWidth;
  int get stageHeight;
  ValueListenable<bool> get cursorHidden;
  ValueListenable<AvoidOverlay?> get avoidOverlay;
  ValueListenable<String?> get windowTitle;
  EngineMediaHost get media;

  Future<void> initialize();
  void shutdown();

  void setDebug(bool enabled);
  void setDamageVisualization(bool enabled);
  void setSaveDir(String dir);
  void configureTranslation(TextTranslationService? service);
  void configureInputGate(InputGatePolicy gate);
  void registerFileReader();

  void createRuntime(int stageWidth, int stageHeight, {int backend = 0});
  void setReportedOs(String? os);
  bool setEmoteBackend(int backend);
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'});

  /// Mounts a project's resource tree and returns its `system.ini` bytes.
  ///
  /// Backends own archive/directory handling and encoding detection. Callers
  /// must not inspect engine-specific resource providers directly.
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  });

  bool setFontOverride(Uint8List bytes);
  void clearFontOverride();

  bool get supportsSpatialUpscaling;
  bool setRenderQuality(EngineRenderQuality quality);
  bool configureSpatialUpscale(double renderScale, {double sharpness = 0});

  bool get hasActiveSharedTexture;
  int? get sharedTextureId;
  int get sharedTextureWidth;
  int get sharedTextureHeight;
  Future<int?> enableSharedTexture({int? outputWidth, int? outputHeight});

  bool isExitRequested();
  bool advanceWithoutRender(int deltaMs);
  int advanceAndPresent(int deltaMs);
  Uint8List? advanceAndRender(int deltaMs);

  bool setProfilerEnabled(bool enabled);
  ProfilerSnapshot? readProfilerSnapshot();

  void feedMouse(int x, int y);
  void feedClick();
  void feedMouseButton(int button, bool pressed);
  void feedTouch(int id, int phase, int x, int y);
  void feedKey(int keyCode, bool pressed);
  void feedForwardedKey(int keyCode, bool pressed);
  bool submitDialog(bool accepted, String text);
  void notifyMouseActivity();

  void setWindowStateBits({bool? fullscreen, bool? minimized});
  void notifyLifecycle(int state);
}

/// No-op runtime used when a build has not installed a backend yet.
///
/// Keeping this object valid lets PlayerScreen show a normal initialization
/// failure instead of crashing during widget construction.
class UnsupportedEngineRuntime implements EngineRuntime {
  UnsupportedEngineRuntime(this.kind);

  @override
  final GameEngineKind kind;

  final ValueNotifier<bool> _cursorHidden = ValueNotifier(false);
  final ValueNotifier<AvoidOverlay?> _avoidOverlay = ValueNotifier(null);
  final ValueNotifier<String?> _windowTitle = ValueNotifier(null);
  @override
  late final EngineMediaHost media = _UnsupportedEngineMediaHost();

  @override
  bool get isInitialized => false;
  @override
  int get stageWidth => 0;
  @override
  int get stageHeight => 0;
  @override
  ValueListenable<bool> get cursorHidden => _cursorHidden;
  @override
  ValueListenable<AvoidOverlay?> get avoidOverlay => _avoidOverlay;
  @override
  ValueListenable<String?> get windowTitle => _windowTitle;

  @override
  Future<void> initialize() async {}
  @override
  void shutdown() {}
  @override
  void setDebug(bool enabled) {}
  @override
  void setDamageVisualization(bool enabled) {}
  @override
  void setSaveDir(String dir) {}
  @override
  void configureTranslation(TextTranslationService? service) {}
  @override
  void configureInputGate(InputGatePolicy gate) {}
  @override
  void registerFileReader() {}
  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) {}
  @override
  void setReportedOs(String? os) {}
  @override
  bool setEmoteBackend(int backend) => false;
  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) =>
      false;
  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) async => null;
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
  bool isExitRequested() => false;
  @override
  bool advanceWithoutRender(int deltaMs) => false;
  @override
  int advanceAndPresent(int deltaMs) => 0;
  @override
  Uint8List? advanceAndRender(int deltaMs) => null;
  @override
  bool setProfilerEnabled(bool enabled) => false;
  @override
  ProfilerSnapshot? readProfilerSnapshot() => null;
  @override
  void feedMouse(int x, int y) {}
  @override
  void feedClick() {}
  @override
  void feedMouseButton(int button, bool pressed) {}
  @override
  void feedTouch(int id, int phase, int x, int y) {}
  @override
  void feedKey(int keyCode, bool pressed) {}
  @override
  void feedForwardedKey(int keyCode, bool pressed) {}
  @override
  bool submitDialog(bool accepted, String text) => false;
  @override
  void notifyMouseActivity() {}
  @override
  void setWindowStateBits({bool? fullscreen, bool? minimized}) {}
  @override
  void notifyLifecycle(int state) {}
}

class _UnsupportedEngineMediaHost implements EngineMediaHost {
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
}
