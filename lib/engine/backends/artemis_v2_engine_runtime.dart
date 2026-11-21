import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../models/game_engine.dart';
import '../../models/input_gate.dart';
import '../../models/render_output.dart';
import '../../services/logger.dart';
import '../../services/script_http_client.dart';
import '../../services/text_translation_service.dart';
import '../engine_runtime.dart';
import 'art3m1s/environment_patch.dart';
import 'art3m1s/media_bridge.dart';
import 'art3m1s/project_save_root.dart';
import 'art3m1s/project_vfs.dart';
import 'art3m1s/v2_sdk/artemis_file_service.dart';
import 'art3m1s/v2_sdk/artemis_flutter_session.dart';
import 'art3m1s/v2_sdk/artemis_hlsl_compiler.dart';

typedef _Pixels = ({int width, int height, Uint8List rgba});

final class ArtemisV2EngineRuntime extends UnsupportedEngineRuntime
    implements AsyncTextureRuntime {
  ArtemisV2EngineRuntime({this.onDialogRequested, this.onWindowAction})
    : super(GameEngineKind.art3m1s);

  final void Function(EngineDialogRequest)? onDialogRequested;
  final void Function(EngineWindowAction)? onWindowAction;
  final _title = ValueNotifier<String?>(null);
  final _avoid = ValueNotifier<AvoidOverlay?>(null);
  final _inputs = <ArtemisFlutterMessage>[];
  final _replies = <ArtemisFlutterMessage>[];
  final _mediaFeedback = <ArtemisFlutterMessage>[];
  final _unsupportedShaderLanguages = <String>{};
  final _translations = <ArtemisFlutterEvent, ArtemisFlutterMessage?>{};
  final _http = ScriptHttpClient();
  late final ArtemisV2MediaHost _media = ArtemisV2MediaHost(
    writeVideoAsset: _writeVideoAsset,
  )..configureAssetReader(_asset);

  @override
  ArtemisV2MediaHost get media => _media;
  ProjectVfs? _vfs;
  ArtemisFileService? _files;
  ArtemisFlutterSession? _session;
  Future<ArtemisHlslCompiler?>? _hlslCompilerDiscovery;
  ArtemisHlslCompiler? _hlslCompiler;
  final _preparedHlsl = <Digest>{};
  final _failedRuntimeHlsl = <(String, Digest)>{};
  int _runtimeHlslPrograms = 0;
  ArtemisFlutterState? _state;
  ArtemisFlutterEvent? _dialog;
  ArtemisFlutterEvent? _httpRequest;
  ArtemisFlutterMessage? _httpReply;
  TextTranslationService? _translator;
  ({String id, _Pixels pixels})? _capture;
  EngineSessionState _residency = EngineSessionState.active;
  InputGatePolicy _inputGate = InputGatePolicy.full;
  Future<bool>? _advancing;
  Future<void>? _backgroundAutosave;
  Future<void>? _projectChange;
  Future<void>? _closing;
  DateTime? _frameTime;
  Uint8List? _font;
  String? _saveDir;
  String? _reportedOS;
  int _frame = 1, _monotonicNS = 0;
  int _width = 1280, _height = 720;
  bool _preferAngle = false;
  int _outputWidth = 0, _outputHeight = 0;
  int? _textureID;
  int _surfaceRevision = 0;
  bool _environmentPatch = false;
  int _appLifecycle = 2;
  bool _closed = false;
  bool _finishingSession = false;
  static const _normalWindow = (fullscreen: false, minimized: false);
  var _window = _normalWindow;
  var _submittedWindow = _normalWindow;

  bool get _acceptsSceneServices => !_closed && !_finishingSession;
  bool get _canRun =>
      _acceptsSceneServices && _appLifecycle == 2 && _residency.isRunning;

  @override
  bool get isInitialized => !_closed;
  @override
  int get stageWidth => _width;
  @override
  int get stageHeight => _height;
  @override
  bool get supportsSpatialUpscaling =>
      _session?.supportsSpatialUpscaling ?? false;
  @override
  int? get sharedTextureId => _textureID;
  @override
  int get sharedTextureWidth => _outputWidth;
  @override
  int get sharedTextureHeight => _outputHeight;
  @override
  bool get hasActiveSharedTexture => _textureID != null;
  @override
  ValueListenable<String?> get windowTitle => _title;
  @override
  ValueListenable<AvoidOverlay?> get avoidOverlay => _avoid;
  @override
  EngineSessionState get sessionState => _residency;
  @override
  Set<EngineSessionState> get supportedSessionStates => const {
    EngineSessionState.active,
    EngineSessionState.frozen,
    EngineSessionState.suspended,
  };

  @override
  Future<EngineSessionState> setSessionState(EngineSessionState state) async {
    if (_residency.isRunning && !state.isRunning) _input(4, const {});
    _residency = state == EngineSessionState.hibernated
        ? EngineSessionState.suspended
        : state;
    final releaseSurface = _residency.releasesPresentation;
    if (releaseSurface) {
      _surfaceRevision++;
      _textureID = null;
    }
    await Future.wait([
      media.setSuspended(!_canRun),
      if (releaseSurface) ?_session?.detachSurface(),
    ]);
    return _residency;
  }

  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) => _changeProject(() async {
    if (_closed) return null;
    await _releaseProjectSession();
    if (_closed) return null;
    _vfs?.close();
    _vfs = null;
    final project = ProjectVfs.openWithIni(
      path: projectPath,
      isArchive: isArchive,
      platform: platform,
    );
    _vfs = project.files;
    _environmentPatch = environmentPatchEnabled;
    return project.ini;
  });

  Uint8List? _asset(String key, {int? maxBytes}) => _vfs?.readAsset(
    key,
    environmentPatchEnabled: _environmentPatch,
    maxBytes: maxBytes,
  );

  Future<File?> _writeVideoAsset(
    String key,
    File destination,
    bool Function() isCurrent,
  ) async {
    if (_environmentPatch) {
      final virtual = EnvironmentPatch.virtualFile(key);
      if (virtual != null) return destination.writeAsBytes(virtual);
      if (EnvironmentPatch.canTransform(key)) {
        final bytes = _asset(key);
        return bytes == null ? null : destination.writeAsBytes(bytes);
      }
    }
    return _vfs?.copyFile(key, destination, isCurrent);
  }

  static const _ade2Folder = 'artemis-shaders/ade2/';
  static const _maxPrewarmCandidates = 256;
  static const _maxHlslPrewarmBytes = 16 * 1024 * 1024;
  static const _maxGlslSourceBytes = 256 * 1024;
  static const _maxGlslPrewarmBytes = 4 * 1024 * 1024;
  static const _hlslPrewarmTime = Duration(seconds: 5);
  static const _glslPrewarmTime = Duration(seconds: 5);
  static const _maxRuntimeHlslPrograms = 256;
  static const _maxRecentHlslFailures = 256;

  static bool _isAde2Path(String path) =>
      path.startsWith(_ade2Folder) && path.endsWith('.ade2');

  List<({Uint8List source, Uint8List artifact})> _cachedHlslEffects(
    ProjectVfs files,
    List<String> paths,
    Stopwatch budget,
  ) {
    final entryPattern = RegExp(r'^(.+)\.([a-f0-9]{64})\.ade2$');
    final effects = <({Uint8List source, Uint8List artifact})>[];
    final seen = <String>{};
    var size = 0;
    for (final path in paths.where(_isAde2Path).take(_maxPrewarmCandidates)) {
      final remaining = _maxHlslPrewarmBytes - size;
      if (remaining <= 0 || budget.elapsed >= _hlslPrewarmTime) break;
      final entry = entryPattern.firstMatch(path.substring(_ade2Folder.length));
      if (entry == null || seen.contains(entry[2])) continue;
      try {
        final source = _asset(
          entry[1]!,
          maxBytes: math.min(ArtemisHlslCompiler.maxSourceBytes, remaining),
        );
        if (source == null ||
            source.isEmpty ||
            sha256.convert(source).toString() != entry[2]) {
          continue;
        }
        final artifact = files.readFile(
          path,
          maxBytes: remaining - source.length,
        );
        if (artifact == null || artifact.isEmpty) {
          continue;
        }
        seen.add(entry[2]!);
        effects.add((source: source, artifact: artifact));
        size += source.length + artifact.length;
      } on FileSystemException {
        continue;
      }
    }
    return effects;
  }

  static bool _isHlsl(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.hlsl') || lower.endsWith('.fx');
  }

  Future<List<({Uint8List source, Uint8List artifact})>> _prepareHlslEffects(
    ProjectVfs files,
    List<String> paths,
    ArtemisHlslCompiler? compiler,
    Stopwatch budget,
  ) async {
    final effects = _cachedHlslEffects(files, paths, budget);
    if (compiler == null) return effects;
    final attempted = {
      for (final effect in effects) sha256.convert(effect.source),
    };
    var size = effects.fold(
      0,
      (size, effect) => size + effect.source.length + effect.artifact.length,
    );
    for (final path in paths.where(_isHlsl).take(_maxPrewarmCandidates)) {
      final remaining = _maxHlslPrewarmBytes - size;
      if (remaining <= 0 ||
          _closed ||
          !identical(_vfs, files) ||
          attempted.length >= _maxPrewarmCandidates ||
          budget.elapsed >= _hlslPrewarmTime) {
        break;
      }
      Uint8List? source;
      try {
        source = _asset(
          path,
          maxBytes: math.min(ArtemisHlslCompiler.maxSourceBytes, remaining),
        );
      } on FileSystemException {
        continue;
      }
      if (source == null || source.isEmpty) continue;
      final digest = sha256.convert(source);
      if (!attempted.add(digest)) continue;
      final artifact = await compiler.prepare(
        source,
        timeout: _hlslPrewarmTime - budget.elapsed,
      );
      if (artifact == null ||
          size + source.length + artifact.length > _maxHlslPrewarmBytes) {
        continue;
      }
      size += source.length + artifact.length;
      effects.add((source: source, artifact: artifact));
    }
    return effects;
  }

  Future<Set<Digest>> _finishHlslPrewarm(
    ArtemisFlutterSession session,
    ProjectVfs? files,
    ArtemisHlslCompiler? compiler,
    List<({Uint8List source, Uint8List artifact})> effects,
    Set<int> accepted,
    Stopwatch budget,
  ) async {
    final prepared = <Digest>{};
    var size = 0;
    for (final (index, effect) in effects.indexed) {
      if (accepted.contains(index)) {
        prepared.add(sha256.convert(effect.source));
        size += effect.source.length + effect.artifact.length;
      }
    }
    if (compiler == null || !session.usesDxvk) return prepared;
    bool isCurrent() => !_closed && identical(files, _vfs);
    for (final (index, effect) in effects.indexed) {
      if (accepted.contains(index)) continue;
      final remaining = _hlslPrewarmTime - budget.elapsed;
      if (!isCurrent() || remaining <= Duration.zero) break;
      final artifact = await compiler.prepare(
        effect.source,
        rejectedArtifact: effect.artifact,
        timeout: remaining,
        isCurrent: isCurrent,
        register: (artifact) async =>
            size + effect.source.length + artifact.length <=
                _maxHlslPrewarmBytes &&
            await _registerHlsl(session, effect.source, artifact),
      );
      if (artifact != null) {
        prepared.add(sha256.convert(effect.source));
        size += effect.source.length + artifact.length;
      }
    }
    return prepared;
  }

  Future<void> _prepareRuntimeHlsl(
    ArtemisFlutterSession session,
    String key,
    Uint8List source,
  ) async {
    final digest = sha256.convert(source);
    if (_preparedHlsl.contains(digest) ||
        _runtimeHlslPrograms >= _maxRuntimeHlslPrograms) {
      return;
    }
    final path = ProjectVfs.normalizeRelativePath(key);
    final lookup = (path ?? key, digest);
    if (_failedRuntimeHlsl.contains(lookup)) return;
    Uint8List? artifact;
    if (path != null) {
      try {
        artifact = _vfs?.readFile(
          '$_ade2Folder$path.$digest.ade2',
          maxBytes: ArtemisHlslCompiler.maxArtifactBytes,
        );
      } on FileSystemException {
        // An unreadable sidecar can be replaced by the compiler.
      }
    }
    var prepared =
        artifact != null &&
        artifact.isNotEmpty &&
        await _registerHlsl(session, source, artifact);
    if (!prepared) {
      final compiled = await _hlslCompiler?.prepare(
        source,
        rejectedArtifact: artifact,
        isCurrent: () => _acceptsSceneServices && identical(_session, session),
        register: (artifact) => _registerHlsl(session, source, artifact),
      );
      prepared = compiled != null;
    }
    if (!identical(_session, session)) return;
    if (prepared) {
      _preparedHlsl.add(digest);
      _runtimeHlslPrograms++;
    } else {
      if (_failedRuntimeHlsl.length == _maxRecentHlslFailures) {
        _failedRuntimeHlsl.remove(_failedRuntimeHlsl.first);
      }
      _failedRuntimeHlsl.add(lookup);
    }
  }

  Future<bool> _registerHlsl(
    ArtemisFlutterSession session,
    Uint8List source,
    Uint8List artifact,
  ) async {
    try {
      await session.prepareHlsl(source, artifact);
      return true;
    } on PlatformException catch (error) {
      Log.warn('[ArtemisV2] DXVK effect unavailable: ${error.code}');
      return false;
    }
  }

  static bool _isGlsl(String path) =>
      const {'.glsl', '.frag', '.fsh', '.fs'}.any(path.endsWith);

  List<Uint8List> _knownGlslSources(Iterable<String> paths, Stopwatch budget) {
    final sources = <Uint8List>[];
    final seen = <Digest>{};
    var size = 0;
    for (final path in paths.take(_maxPrewarmCandidates)) {
      final remaining = _maxGlslPrewarmBytes - size;
      if (remaining <= 0 || budget.elapsed >= _glslPrewarmTime) break;
      try {
        final source = _asset(
          path,
          maxBytes: math.min(_maxGlslSourceBytes, remaining),
        );
        if (source == null || source.isEmpty) continue;
        if (!seen.add(sha256.convert(source))) continue;
        sources.add(source);
        size += source.length;
      } on FileSystemException {
        continue;
      }
    }
    return sources;
  }

  @override
  void setSaveDir(String dir) => _saveDir = dir;
  @override
  void setReportedOs(String? os) => _reportedOS = os;
  @override
  void configureInputGate(InputGatePolicy gate) => _inputGate = gate;

  @override
  void configureTranslation(TextTranslationService? service) {
    if (_closed) {
      if (service != null) unawaited(service.dispose());
      return;
    }
    final previous = _translator;
    if (identical(previous, service)) return;
    _translator = service;
    for (final request in _translations.keys) {
      _translations[request] = request.reply({'status': 'cancelled'});
    }
    if (previous != null) unawaited(previous.dispose());
  }

  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) {
    _width = stageWidth;
    _height = stageHeight;
    _preferAngle = backend == 6;
  }

  @override
  bool setFontOverride(Uint8List bytes) {
    _font = bytes;
    return true;
  }

  @override
  void clearFontOverride() => _font = null;

  @override
  Future<bool> loadProjectBytes(
    Uint8List iniContent, {
    String platform = 'WINDOWS',
  }) => _changeProject(() => _loadProjectBytes(iniContent, platform));

  Future<bool> _loadProjectBytes(Uint8List iniContent, String platform) async {
    final saveDir = _saveDir;
    if (_closed || saveDir == null) return false;
    await _releaseProjectSession();
    if (_closed) return false;
    final files = _vfs;
    final canUseDxvk =
        !_preferAngle &&
        files != null &&
        await ArtemisFlutterSession.hasDxvkRuntime();
    if (_closed || !identical(files, _vfs)) return false;
    final paths = files?.listFiles() ?? const <String>[];
    final glsl = paths.where(_isGlsl);
    final hasHlsl =
        canUseDxvk && paths.any((path) => _isHlsl(path) || _isAde2Path(path));
    // Scripts can load shaders outside the prewarm scan.
    final mixedShaders = !_preferAngle;
    final portPrefersGlsl = switch (platform.trim().toUpperCase()) {
      'ANDROID' || 'IOS' || 'WASM' || 'SWITCH' => true,
      _ => false,
    };
    final angle =
        _preferAngle || (glsl.isNotEmpty && (portPrefersGlsl || !hasHlsl));
    final compiler = canUseDxvk
        ? await (_hlslCompilerDiscovery ??= ArtemisHlslCompiler.bundled())
        : null;
    if (_closed || !identical(files, _vfs)) return false;
    final hlslBudget = Stopwatch()..start();
    final hlslEffects = canUseDxvk
        ? await _prepareHlslEffects(files, paths, compiler, hlslBudget)
        : const <({Uint8List source, Uint8List artifact})>[];
    if (_closed || !identical(files, _vfs)) return false;
    final glslBudget = Stopwatch()..start();
    final glslSources = _knownGlslSources(glsl, glslBudget);
    final opened = await ArtemisFlutterSession.open(
      ini: iniContent,
      platform: platform,
      hostCaps:
          ArtemisFileService.capabilities |
          ArtemisMediaCommand.capability |
          artemisProjectSavePathCapability |
          (onDialogRequested == null ? 0 : 2) |
          8 |
          (_translator?.hostTranslationEnabled == true ? 16 : 0),
      reportedOS: _reportedOS,
      screenshots: true,
      angle: angle,
      mixedShaders: mixedShaders,
      hlslEffects: hlslEffects,
      hlslOnDemand: canUseDxvk,
      glslSources: glslSources,
      glslPrewarmBudget: _glslPrewarmTime - glslBudget.elapsed,
      hlslPrewarmBudget: _hlslPrewarmTime - hlslBudget.elapsed,
    );
    try {
      final preparedHlsl = await _finishHlslPrewarm(
        opened.session,
        files,
        compiler,
        hlslEffects,
        opened.preparedHlsl,
        hlslBudget,
      );
      final events = await opened.session.pollEvents();
      if (_closed || !identical(files, _vfs)) {
        await opened.session.close();
        return false;
      }
      final started = events.isEmpty ? null : events.first;
      final savePath = started?.metadata['save_path'];
      if (started?.domain != 1 ||
          started?.kind != 1 ||
          started?.epoch != opened.state.epoch ||
          savePath is! String) {
        throw const FormatException('Missing Artemis project save path');
      }
      final layout = resolveArtemisProjectSaveRoot(
        Directory(saveDir),
        savePath,
      );
      if (layout.conflict) {
        Log.warn(
          '[ArtemisV2] Using the project save folder; preview saves remain separate.',
        );
      }
      _files = ArtemisFileService(
        saveRoot: layout.directory,
        readAsset: (key, {int? maxBytes}) {
          final asset = _asset(key, maxBytes: maxBytes);
          return asset == null ? null : (bytes: asset, modified: null);
        },
      );
      _session = opened.session;
      _hlslCompiler = opened.session.usesDxvk ? compiler : null;
      _preparedHlsl.addAll(preparedHlsl);
      _updateState(opened.state);
      for (final event in events) {
        await _event(event);
      }
    } on Exception catch (error) {
      Log.warn('[ArtemisV2] Could not open the project save folder: $error');
      _files?.close();
      _files = null;
      _session = null;
      _hlslCompiler = null;
      _preparedHlsl.clear();
      _failedRuntimeHlsl.clear();
      _runtimeHlslPrograms = 0;
      await opened.session.close();
      return false;
    }
    final font = _font;
    if (font != null) {
      final message = ArtemisFlutterMessage(
        domain: 1,
        kind: 17,
        epoch: opened.state.epoch,
        metadata: const {},
        blob: font,
      );
      if (!await opened.session.submit([message])) {
        throw StateError('Could not submit the default font');
      }
    }
    return !_closed;
  }

  Future<T> _changeProject<T>(Future<T> Function() change) async {
    final previous = _projectChange;
    final settled = Completer<void>();
    final pending = settled.future;
    _projectChange = pending;
    try {
      await previous;
      return await change();
    } finally {
      if (identical(_projectChange, pending)) _projectChange = null;
      settled.complete();
    }
  }

  Future<void> _releaseProjectSession() async {
    final previous = _session;
    if (previous == null) return;
    await _advancing;
    await _backgroundAutosave;
    if (_closed || !identical(_session, previous)) return;
    try {
      await _finishSession(previous);
    } on Exception catch (error) {
      Log.warn('[ArtemisV2] project shutdown: $error');
    }
    _session = null;
    _hlslCompiler = null;
    _preparedHlsl.clear();
    _failedRuntimeHlsl.clear();
    _runtimeHlslPrograms = 0;
    _mediaFeedback.clear();
    _translations.clear();
    _inputs.clear();
    _replies.clear();
    _dialog = null;
    _avoid.value = null;
    _files?.close();
    _files = null;
    _state = null;
    _frame = 1;
    _frameTime = null;
    _textureID = null;
    _surfaceRevision++;
    _cancelHttp();
    try {
      await media.resetProject();
    } finally {
      await previous.close();
    }
  }

  @override
  Future<int?> enableSharedTexture({
    int? outputWidth,
    int? outputHeight,
  }) async {
    final session = _session;
    if (session == null || _closed || !_residency.isRunning) return null;
    final stage = (_width, _height);
    var (width, height) = (outputWidth ?? stage.$1, outputHeight ?? stage.$2);
    final revision = ++_surfaceRevision;
    bool isCurrent() =>
        !_closed &&
        identical(session, _session) &&
        revision == _surfaceRevision;

    final spatialScale =
        session.supportsSpatialUpscaling &&
            width > stage.$1 &&
            height > stage.$2
        ? authoredSceneRenderScale(
            stageWidth: stage.$1,
            stageHeight: stage.$2,
            outputWidth: width,
            outputHeight: height,
          )
        : null;
    int id;
    try {
      id = await session.setSurface(width, height, spatialScale: spatialScale);
    } on PlatformException catch (error) {
      if (!isCurrent()) return null;
      _textureID = null;
      if ((width, height) == stage) rethrow;
      Log.warn(
        '[ArtemisV2] output resize failed (${error.code}), using stage size',
      );
      (width, height) = stage;
      try {
        id = await session.setSurface(width, height);
      } on PlatformException {
        if (!isCurrent()) return null;
        rethrow;
      }
    }
    if (!isCurrent()) return null;
    _outputWidth = width;
    _outputHeight = height;
    return _textureID = id;
  }

  @override
  bool isExitRequested() => _state?.exitRequested ?? false;

  Future<bool> advanceTexture(int deltaMs) => advanceTextureBatch([deltaMs]);

  @override
  Future<bool> advanceTextureBatch(Iterable<int> frameDeltasMs) {
    if (!_canRun || _session == null || _projectChange != null) {
      return Future.value(false);
    }
    if (_backgroundAutosave case final pending?) {
      return pending.then((_) => advanceTextureBatch(frameDeltasMs));
    }
    return _advancing ??= _advance(_session!, frameDeltasMs).whenComplete(() {
      _advancing = null;
    });
  }

  Future<bool> _advance(
    ArtemisFlutterSession session,
    Iterable<int> frameDeltasMs,
  ) async {
    var stepped = false;
    for (final deltaMs in frameDeltasMs) {
      if (!_canRun || isExitRequested()) break;
      if (!await _submitWindowState(session)) break;
      await _submit(session, _inputs);
      await _submit(session, _replies);
      await _submitHttp(session);
      await _submitTranslations(session);
      if (!_canRun) break;
      // Give the last video frame a presentation before polling for its end.
      if (!stepped) await media.pollVideo(session);
      await _submitMedia(session);
      if (!_canRun) break;
      _nextClock(deltaMs);
      await _step(session);
      stepped = true;
      // A service can suspend execution on this frame across vsyncs.
      if (_frameTime != null) break;
    }
    return stepped &&
        _canRun &&
        _textureID != null &&
        await session.present() != null;
  }

  void _nextClock(int deltaMs) {
    if (_frameTime != null) return;
    _monotonicNS += deltaMs * 1000000;
    _frameTime = DateTime.now();
  }

  Future<void> _step(
    ArtemisFlutterSession session, {
    bool backgroundAutosave = false,
  }) async {
    final time = backgroundAutosave ? DateTime.now() : _frameTime!;
    for (var turn = 0; backgroundAutosave || turn < 32; turn++) {
      final result = await session.step(
        frame: _frame,
        monotonicNS: _monotonicNS,
        time: time,
        backgroundAutosave: backgroundAutosave,
      );
      _updateState(result.state);
      var sawEvents = false;
      while (true) {
        final events = await session.pollEvents();
        if (events.isEmpty) break;
        sawEvents = true;
        for (final event in events) {
          if (event.domain == 6 && event.requiresReply) {
            final status = await _screenshot(session, event);
            _replies.add(event.reply({'status': status}));
          } else {
            await _event(event);
          }
        }
      }
      final replied = await _submit(session, _replies);
      // HTTP waits allow onEnterFrame to run, including script cancellation.
      final blocking = backgroundAutosave
          ? 1
          : 1 | 16 | (_httpRequest == null ? 2 : 0);
      if (!result.backpressured && result.state.waitFlags & blocking == 0) {
        if (!backgroundAutosave) {
          _frame++;
          _frameTime = null;
        }
        return;
      }
      if (!replied && !sawEvents) return;
    }
  }

  Future<bool> _submit(
    ArtemisFlutterSession session,
    List<ArtemisFlutterMessage> queue,
  ) async {
    if (queue.isEmpty) return false;
    final batch = queue.take(128).toList(growable: false);
    if (!await session.submit(batch)) return false;
    queue.removeRange(0, batch.length);
    return true;
  }

  void _updateState(ArtemisFlutterState state) {
    if (state.epoch != _state?.epoch || state.phase == 4) {
      _unsupportedShaderLanguages.clear();
      _submittedWindow = _normalWindow;
      _capture = null;
      _cancelHttp();
      _translations.clear();
      media.reset();
      _mediaFeedback.clear();
    }
    _state = state;
    if (state.width > 0 && state.height > 0) {
      _width = state.width;
      _height = state.height;
    }
  }

  void _cancelHttp() {
    _http.cancel();
    _httpRequest = null;
    _httpReply = null;
  }

  void _startHttp(ArtemisFlutterEvent event) {
    _cancelHttp();
    _httpRequest = event;
    if (!_acceptsSceneServices) {
      _httpReply = event.reply({'status': 'cancelled'});
      return;
    }
    final budget = event.metadata['max_response_bytes'];
    final limit = budget is String ? int.tryParse(budget) : null;
    if (limit == null || limit < 0) {
      _httpReply = event.reply({'status': 'io_error'});
      return;
    }
    _http.start(
      event.metadata,
      maxResponseBytes: limit.clamp(0, 32 * 1024 * 1024),
      readFile: _asset,
      onComplete: (status, body) {
        if (!_acceptsSceneServices || !identical(_httpRequest, event)) return;
        _httpReply = status == 0
            ? event.reply({'status': 'io_error'})
            : event.reply({'status': 'ok', 'status_code': status}, blob: body);
      },
    );
  }

  Future<void> _submitHttp(ArtemisFlutterSession session) async {
    final reply = _httpReply;
    if (reply == null) return;
    try {
      if (!await session.submit([reply])) return;
    } on PlatformException catch (error) {
      if (error.code != 'stale_reply') rethrow;
    }
    if (identical(_httpReply, reply)) _cancelHttp();
  }

  void _translate(ArtemisFlutterEvent event) {
    if (!_acceptsSceneServices || event.epoch != _state?.epoch) return;
    if (_translations.length >= 64) {
      _translations[event] = event.reply({'status': 'limit'});
      return;
    }
    final translator = _translator;
    final text = event.metadata['text'];
    if (translator == null ||
        !translator.hostTranslationEnabled ||
        text is! String) {
      _translations[event] = event.reply({'status': 'unsupported'});
      return;
    }
    _translations[event] = null;
    translator.enqueue(
      text,
      ruby: event.metadata['ruby'] as String?,
      onComplete: (value) {
        if (_closed ||
            !identical(_translator, translator) ||
            !_translations.containsKey(event)) {
          return;
        }
        _translations[event] = event.reply(switch (value) {
          null || '' => {'status': 'unsupported'},
          _ when utf8.encode(value).length > 64 * 1024 => {'status': 'limit'},
          _ => {'status': 'ok', 'text': value},
        });
      },
    );
  }

  Future<void> _submitTranslations(ArtemisFlutterSession session) async {
    final pending = _translations.entries
        .where((entry) => entry.value != null)
        .take(32)
        .toList();
    for (final entry in pending) {
      try {
        if (!await session.submit([entry.value!])) return;
      } on PlatformException catch (error) {
        if (error.code != 'stale_reply') rethrow;
      }
      _translations.remove(entry.key);
    }
  }

  Future<void> _submitMedia(ArtemisFlutterSession session) async {
    for (var i = 0; i < 128 && _mediaFeedback.isNotEmpty; i++) {
      final message = _mediaFeedback.first;
      try {
        if (!await session.submit([message])) return;
      } on PlatformException catch (error) {
        if (error.code != 'stale_reply') rethrow;
      }
      if (_mediaFeedback.isNotEmpty &&
          identical(_mediaFeedback.first, message)) {
        _mediaFeedback.removeAt(0);
      }
    }
  }

  Future<String> _screenshot(
    ArtemisFlutterSession session,
    ArtemisFlutterEvent event,
  ) async {
    if (event.epoch != _state?.epoch) return 'cancelled';
    final metadata = event.metadata;
    try {
      switch (event.kind) {
        case 1:
          final frame = metadata['render_frame_id'];
          if (frame is! String) return 'io_error';
          final pixels = await session.capture(frame);
          _capture = (id: event.request, pixels: pixels);
          return 'ok';
        case 2:
          final capture = _capture;
          if (capture == null || metadata['capture_id'] != capture.id) {
            return 'io_error';
          }
          final key = metadata['key'];
          if (metadata['namespace'] != 'save' ||
              key is! String ||
              !key.endsWith('.png')) {
            return 'denied';
          }
          final pixels = capture.pixels;
          final width = metadata['width'] ?? pixels.width;
          final height = metadata['height'] ?? pixels.height;
          if (width is! int ||
              height is! int ||
              width < 1 ||
              width > 8192 ||
              height < 1 ||
              height > 8192 ||
              width * height > 16 * 1024 * 1024) {
            return 'denied';
          }
          final png = await _encodePng(pixels, width, height);
          return _files?.replaceSave(int.parse(event.epoch), key, png) ??
              'cancelled';
        default:
          return 'unsupported';
      }
    } on Exception catch (error) {
      Log.warn('[ArtemisV2] screenshot: $error');
      return 'io_error';
    }
  }

  Future<void> _event(ArtemisFlutterEvent event) async {
    if (event.domain == 7 && event.kind == 2 && !event.requiresReply) {
      if (!_closed && event.epoch == _state?.epoch && Log.debugEnabled) {
        final line = utf8.decode(event.blob, allowMalformed: true);
        Log.debug('[ArtemisV2] [Lua] $line');
      }
      return;
    }
    if (event.domain == 7 && event.kind == 1) {
      final language = event.metadata['language'];
      if (event.epoch == _state?.epoch &&
          language is String &&
          (language == 'hlsl' || language == 'glsl') &&
          _unsupportedShaderLanguages.add(language)) {
        Log.warn(
          '[ArtemisV2] The selected renderer does not support '
          '${language.toUpperCase()} effects for this project.',
        );
      }
      return;
    }
    if (event.mediaCommand case final command?) {
      final owner = _session;
      if (owner == null ||
          !_acceptsSceneServices ||
          event.epoch != _state?.epoch) {
        return;
      }
      media.handle(owner, event.epoch, command, (id, status) {
        if (_acceptsSceneServices &&
            identical(_session, owner) &&
            event.epoch == _state?.epoch) {
          _mediaFeedback.add(event.playbackStatus(id, status));
        }
      });
      return;
    }
    final fileReply = _files?.handle(
      ArtemisFileEvent(
        event.domain,
        event.kind,
        int.parse(event.epoch),
        event.requiresReply,
        event.metadata,
        event.blob,
      ),
    );
    if (fileReply != null) {
      final session = _session;
      final source = fileReply.blob;
      final key = event.metadata['key'];
      final language = event.metadata['shader_language'];
      if (_acceptsSceneServices &&
          session != null &&
          session.usesDxvk &&
          source != null &&
          event.domain == 3 &&
          event.kind == 2 &&
          event.metadata['namespace'] == 'asset' &&
          event.metadata['offset'] == '0' &&
          fileReply.metadata['eof'] == true &&
          key is String &&
          (language == 'hlsl' || (language == null && _isHlsl(key))) &&
          source.isNotEmpty &&
          source.length <= ArtemisHlslCompiler.maxSourceBytes) {
        await _prepareRuntimeHlsl(session, key, source);
        if (!identical(_session, session)) return;
      }
      _replies.add(event.reply(fileReply.metadata, blob: fileReply.blob));
      return;
    }
    if (event.domain == 1 && event.kind == 4) {
      if (event.metadata['save_status'] == 'failed') {
        Log.warn(
          '[ArtemisV2] Final save failed: ${event.metadata['reason']} '
          '(${event.metadata['files_written']} files written)',
        );
      }
    } else if (event.domain == 1 &&
        event.kind == 5 &&
        event.epoch == _state?.epoch &&
        !event.requiresReply &&
        event.metadata['status'] == 'failed') {
      final operation = switch (event.metadata['operation']) {
        'autosave' => 'Automatic save',
        'save' => 'Save',
        'load' => 'Load',
        _ => null,
      };
      if (operation != null) {
        final files = event.metadata['files_written'];
        final progress = files is int ? ' ($files files written)' : '';
        Log.warn(
          '[ArtemisV2] $operation failed: '
          '${event.metadata['reason']}$progress',
        );
      }
    } else if (event.domain == 4 && event.kind == 5 && event.requiresReply) {
      _startHttp(event);
    } else if (event.domain == 4 && event.kind == 6) {
      final request = _httpRequest;
      if (request?.epoch == event.epoch &&
          request?.request == event.metadata['request_id']) {
        _cancelHttp();
      }
    } else if (event.domain == 4 && event.kind == 7 && event.requiresReply) {
      _translate(event);
    } else if (event.domain == 4 && event.kind == 1) {
      _title.value = event.metadata['text'] as String?;
    } else if (event.domain == 4 && event.kind == 3 && _acceptsSceneServices) {
      final action = switch (event.metadata['command']) {
        'fullscreen' => EngineWindowAction.toggleFullscreen,
        'minimize' => EngineWindowAction.minimize,
        _ => null,
      };
      if (action != null) onWindowAction?.call(action);
    } else if (event.domain == 4 && event.kind == 4 && _acceptsSceneServices) {
      final data = event.metadata;
      media.setAvoidMuted(data['mute'] == true);
      _avoid.value = data['visible'] == true
          ? AvoidOverlay(file: data['asset'] as String?)
          : null;
    } else if (event.domain == 4 &&
        event.kind == 2 &&
        _acceptsSceneServices &&
        onDialogRequested != null) {
      _dialog = event;
      final metadata = event.metadata;
      onDialogRequested!(
        EngineDialogRequest(
          title: metadata['title'] as String? ?? '',
          message: metadata['message'] as String? ?? '',
          hasCancel: metadata['allow_cancel'] == true,
          hasTextField: metadata['initial_text'] != null,
          textFieldSize: int.tryParse(
            metadata['max_characters'] as String? ?? '',
          ),
          initialText: metadata['initial_text'] as String? ?? '',
        ),
      );
    } else if (event.requiresReply) {
      _replies.add(event.reply({'status': 'unsupported'}));
    }
  }

  @override
  bool submitDialog(bool accepted, String text) {
    final dialog = _dialog;
    if (dialog == null) return false;
    _dialog = null;
    _replies.add(
      dialog.reply({'status': 'ok', 'accepted': accepted, 'text': text}),
    );
    return true;
  }

  void _input(int kind, Map<String, Object?> metadata) {
    final state = _state;
    if (!_canRun || state == null) return;
    _inputs.add(
      ArtemisFlutterMessage(
        domain: 2,
        kind: kind,
        epoch: state.epoch,
        metadata: metadata,
      ),
    );
  }

  void _key(int? code, bool down) {
    if (code != null) _input(1, {'code': code, 'down': down});
  }

  @override
  void feedKey(int keyCode, bool pressed) =>
      _key(_inputGate.filterKey(keyCode), pressed);
  @override
  void feedForwardedKey(int keyCode, bool pressed) =>
      _key(_inputGate.filterForwardedKey(keyCode), pressed);
  @override
  void feedMouse(int x, int y) {
    if (_inputGate.mouseMove) _input(2, {'x': x, 'y': y});
  }

  @override
  void feedMouseButton(int button, bool pressed) {
    if (_inputGate.mouseButtons && button >= 0 && button < 3) {
      _key([1, 2, 4][button], pressed);
    }
  }

  @override
  void feedClick() {
    feedMouseButton(0, true);
    feedMouseButton(0, false);
  }

  @override
  void feedTouch(int id, int phase, int x, int y) {
    if (_inputGate.touch && phase >= 0 && phase < 3) {
      _input(3, {
        'id': id,
        'phase': ['down', 'move', 'up'][phase],
        'x': x,
        'y': y,
      });
    }
  }

  @override
  void feedWheel(double deltaX, double deltaY) {
    if (!_inputGate.wheelToKeys || deltaY == 0) return;
    final code = deltaY > 0 ? 136 : 137;
    feedForwardedKey(code, true);
    feedForwardedKey(code, false);
  }

  @override
  void setWindowStateBits({bool? fullscreen, bool? minimized}) {
    if (_closed) return;
    _window = (
      fullscreen: fullscreen ?? _window.fullscreen,
      minimized: minimized ?? _window.minimized,
    );
  }

  Future<bool> _submitWindowState(ArtemisFlutterSession session) async {
    final window = _window;
    if (window == _submittedWindow) return true;
    final accepted = await session.submit([
      ArtemisFlutterMessage(
        domain: 2,
        kind: 6,
        epoch: _state!.epoch,
        metadata: {
          'fullscreen': window.fullscreen,
          'minimized': window.minimized,
        },
      ),
    ]);
    if (accepted) _submittedWindow = window;
    return accepted;
  }

  @override
  void notifyLifecycle(int state) {
    if (_closed || state < 0 || state > 2 || _appLifecycle == state) return;
    final wasForeground = _appLifecycle == 2;
    final foreground = state == 2;
    if (wasForeground && !foreground) _input(4, const {});
    _appLifecycle = state;
    final session = _session;
    if (state == 1 && session != null && _acceptsSceneServices) {
      _backgroundAutosave ??= _saveOnBackground(session).whenComplete(() {
        _backgroundAutosave = null;
      });
    }
    if (wasForeground != foreground) {
      unawaited(
        media.setSuspended(!_canRun).catchError((Object error) {
          Log.warn('[ArtemisV2] media lifecycle: $error');
        }),
      );
    }
  }

  Future<void> _saveOnBackground(ArtemisFlutterSession session) async {
    try {
      await _advancing;
      if (!_acceptsSceneServices ||
          !identical(_session, session) ||
          _state?.phase != 2) {
        return;
      }
      if (_frameTime != null) {
        await _submit(session, _replies);
        await _step(session);
        if (_frameTime != null) return;
      }
      if (!await _submitWindowState(session)) return;
      await _step(session, backgroundAutosave: true);
    } on Exception catch (error) {
      Log.warn('[ArtemisV2] background autosave: $error');
    }
  }

  @override
  void shutdown() => unawaited(close());

  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    _textureID = null;
    _http.cancel();
    _translations.clear();
    media.reset();
    _mediaFeedback.clear();
    return _closing = _shutdown();
  }

  Future<void> _finishSession(ArtemisFlutterSession session) async {
    final state = _state;
    if (state == null || state.phase != 2) return;
    _finishingSession = true;
    _http.cancel();
    try {
      final message = ArtemisFlutterMessage(
        domain: 1,
        kind: 16,
        epoch: state.epoch,
        metadata: const {},
      );
      var accepted = false;
      for (var turn = 0; turn < 8 && _state?.phase != 4; turn++) {
        if (_httpRequest case final request?) {
          _httpReply = request.reply({'status': 'cancelled'});
          await _submitHttp(session);
        }
        if (!accepted) {
          if (_dialog != null) submitDialog(false, '');
          await _submit(session, _replies);
          accepted = await session.submit([message]);
        }
        _nextClock(0);
        await _step(session);
      }
      if (_state?.phase != 4) {
        Log.warn('[ArtemisV2] Shutdown ended before Core confirmed closure');
      }
    } finally {
      _finishingSession = false;
    }
  }

  Future<void> _shutdown() async {
    await _projectChange;
    final session = _session;
    try {
      try {
        await _advancing;
        await _backgroundAutosave;
      } on Exception {
        /* The session can still be closed. */
      }
      if (session != null) await _finishSession(session);
    } on Exception catch (error) {
      Log.warn('[ArtemisV2] shutdown: $error');
    } finally {
      try {
        await session?.close();
      } on Exception catch (error) {
        Log.warn('[ArtemisV2] close: $error');
      }
      _files?.close();
      _vfs?.close();
      _cancelHttp();
      _capture = null;
      _session = null;
      final translator = _translator;
      _translator = null;
      await translator?.dispose();
      await media.dispose();
    }
  }
}

Future<Uint8List> _encodePng(_Pixels pixels, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels.rgba);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: pixels.width,
      height: pixels.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('Cannot encode screenshot');
    return Uint8List.sublistView(png);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
