import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../models/game_engine.dart';
import '../../models/input_gate.dart';
import '../../services/logger.dart';
import '../../services/script_http_client.dart';
import '../../services/text_translation_service.dart';
import '../engine_runtime.dart';
import 'art3m1s/environment_patch.dart';
import 'art3m1s/media_bridge.dart';
import 'art3m1s/project_charset.dart';
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
  final _translations = <ArtemisFlutterEvent, ArtemisFlutterMessage?>{};
  final _http = ScriptHttpClient();
  late final ArtemisV2MediaHost _media = ArtemisV2MediaHost()
    ..configureAssetReader(_asset);

  @override
  ArtemisV2MediaHost get media => _media;
  ProjectVfs? _vfs;
  ArtemisFileService? _files;
  ArtemisFlutterSession? _session;
  Future<ArtemisHlslCompiler?>? _hlslCompilerDiscovery;
  ArtemisHlslCompiler? _hlslCompiler;
  Set<Digest> _seenHlsl = {};
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
  Future<void>? _closing;
  DateTime? _frameTime;
  Uint8List? _font;
  String? _saveDir;
  String? _reportedOS;
  int _frame = 1, _monotonicNS = 0;
  int _width = 1280, _height = 720;
  bool _angle = false;
  int _outputWidth = 0, _outputHeight = 0;
  int? _textureID;
  int _surfaceRevision = 0;
  bool _environmentPatch = false;
  bool _appBackgrounded = false;
  bool _closed = false;

  bool get _canRun => !_closed && !_appBackgrounded && _residency.isRunning;

  @override
  bool get isInitialized => !_closed;
  @override
  int get stageWidth => _width;
  @override
  int get stageHeight => _height;
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
    if (_residency.releasesPresentation) {
      _surfaceRevision++;
      _textureID = null;
      await _session?.detachSurface();
    }
    await media.setSuspended(!_canRun);
    return _residency;
  }

  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) async {
    if (_closed) return null;
    await _releaseProjectSession();
    if (_closed) return null;
    ProjectVfs open(String charset) => isArchive
        ? ProjectVfs.openArchive(projectPath, charset: charset)
        : ProjectVfs.openDirectory(projectPath, charset: charset);
    _vfs?.close();
    _vfs = open('Shift_JIS');
    _environmentPatch = environmentPatchEnabled;
    final ini = _vfs?.readFile('system.ini');
    if (ini != null && _vfs!.hasArchiveLayers) {
      _vfs?.close();
      _vfs = open(ProjectCharset.detect(ini, platform));
    }
    return ini;
  }

  Uint8List? _asset(String key) {
    final virtual = _environmentPatch
        ? EnvironmentPatch.virtualFile(key)
        : null;
    if (virtual != null) return virtual;
    final bytes = _vfs?.readFile(key);
    return bytes != null &&
            _environmentPatch &&
            EnvironmentPatch.canTransform(key)
        ? EnvironmentPatch.transform(key, bytes)
        : bytes;
  }

  List<({Uint8List source, Uint8List artifact})> _cachedHlslEffects() {
    final files = _vfs;
    if (files == null || _angle) return const [];
    const folder = 'artemis-shaders/ade2/';
    const byteLimit = 16 * 1024 * 1024;
    final entryPattern = RegExp(r'^(.+)\.([a-f0-9]{64})\.ade2$');
    final effects = <({Uint8List source, Uint8List artifact})>[];
    final seen = <String>{};
    var size = 0;
    for (final path in files.listFiles(extension: '.ade2')) {
      if (!path.startsWith(folder)) continue;
      final entry = entryPattern.firstMatch(path.substring(folder.length));
      if (entry == null || seen.contains(entry[2])) continue;
      try {
        final source = _asset(entry[1]!);
        if (source == null ||
            source.isEmpty ||
            source.length > 256 * 1024 ||
            sha256.convert(source).toString() != entry[2]) {
          continue;
        }
        final artifact = files.readFile(path);
        if (artifact == null ||
            artifact.isEmpty ||
            size + source.length + artifact.length > byteLimit) {
          continue;
        }
        seen.add(entry[2]!);
        effects.add((source: source, artifact: artifact));
        size += source.length + artifact.length;
        if (effects.length == 256) break;
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
    ProjectVfs? files,
    ArtemisHlslCompiler? compiler,
    Set<Digest> seen,
  ) async {
    final effects = _cachedHlslEffects();
    seen.addAll(effects.map((effect) => sha256.convert(effect.source)));
    if (files == null || compiler == null) return effects;
    var size = effects.fold(
      0,
      (size, effect) => size + effect.source.length + effect.artifact.length,
    );
    final budget = Stopwatch()..start();
    for (final path in files.listFiles().where(_isHlsl)) {
      if (_closed ||
          !identical(_vfs, files) ||
          seen.length >= 256 ||
          budget.elapsed >= const Duration(seconds: 5)) {
        break;
      }
      Uint8List? source;
      try {
        source = _asset(path);
      } on FileSystemException {
        continue;
      }
      if (source == null ||
          source.isEmpty ||
          source.length > ArtemisHlslCompiler.maxSourceBytes) {
        continue;
      }
      final digest = sha256.convert(source);
      if (seen.contains(digest)) continue;
      final artifact = await compiler.prepare(source);
      if (artifact != null &&
          size + source.length + artifact.length > 16 * 1024 * 1024) {
        continue;
      }
      seen.add(digest);
      if (artifact == null) continue;
      size += source.length + artifact.length;
      effects.add((source: source, artifact: artifact));
    }
    return effects;
  }

  List<Uint8List> _knownGlslSources() {
    final files = _vfs;
    if (files == null || !_angle) return const [];
    const extensions = {'.glsl', '.frag', '.fsh', '.fs'};
    final sources = <Uint8List>[];
    final seen = <Digest>{};
    var size = 0;
    for (final path in files.listFiles()) {
      if (!extensions.any(path.endsWith)) continue;
      try {
        final source = _asset(path);
        if (source == null ||
            source.isEmpty ||
            source.length > 256 * 1024 ||
            size + source.length > 4 * 1024 * 1024) {
          continue;
        }
        if (!seen.add(sha256.convert(source))) continue;
        sources.add(source);
        size += source.length;
        if (sources.length == 256) break;
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
    _angle = backend == 6;
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
  }) async {
    final saveDir = _saveDir;
    if (_closed || saveDir == null) return false;
    await _releaseProjectSession();
    if (_closed) return false;
    final files = _vfs;
    final compiler = _angle || files == null
        ? null
        : await (_hlslCompilerDiscovery ??= ArtemisHlslCompiler.bundled());
    if (_closed || !identical(files, _vfs)) return false;
    final seenHlsl = <Digest>{};
    final hlslEffects = await _prepareHlslEffects(files, compiler, seenHlsl);
    if (_closed || !identical(files, _vfs)) return false;
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
      angle: _angle,
      hlslEffects: hlslEffects,
      compileHlsl: compiler != null,
      glslSources: _knownGlslSources(),
    );
    try {
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
        readAsset: (key) {
          final asset = _asset(key);
          return asset == null ? null : (bytes: asset, modified: null);
        },
      );
      _session = opened.session;
      _hlslCompiler = opened.session.usesDxvk ? compiler : null;
      _seenHlsl = seenHlsl;
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
      _seenHlsl = {};
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

  Future<void> _releaseProjectSession() async {
    final previous = _session;
    if (previous == null) return;
    await _advancing;
    await _backgroundAutosave;
    if (_closed || !identical(_session, previous)) return;
    _session = null;
    _hlslCompiler = null;
    _seenHlsl = {};
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
    final (width, height) = (outputWidth ?? _width, outputHeight ?? _height);
    final revision = ++_surfaceRevision;
    final id = await session.setSurface(width, height);
    if (_closed || revision != _surfaceRevision) return null;
    _outputWidth = width;
    _outputHeight = height;
    return _textureID = id;
  }

  @override
  bool isExitRequested() => _state?.exitRequested ?? false;

  Future<bool> advanceTexture(int deltaMs) => advanceTextureBatch([deltaMs]);

  @override
  Future<bool> advanceTextureBatch(Iterable<int> frameDeltasMs) {
    if (!_canRun || _session == null) {
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
      await _submit(session, _inputs);
      await _submit(session, _replies);
      await _submitHttp(session);
      await _submitTranslations(session);
      if (!_canRun) break;
      await media.pollVideo(session);
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
    if (_closed) {
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
        if (_closed || !identical(_httpRequest, event)) return;
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
    if (_closed || event.epoch != _state?.epoch) return;
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
    if (event.mediaCommand case final command?) {
      final owner = _session;
      if (owner == null || _closed || event.epoch != _state?.epoch) return;
      media.handle(owner, event.epoch, command, (id, status) {
        if (!_closed &&
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
      final compiler = _hlslCompiler;
      final source = fileReply.blob;
      final key = event.metadata['key'];
      if (session != null &&
          compiler != null &&
          source != null &&
          event.domain == 3 &&
          event.kind == 2 &&
          event.metadata['namespace'] == 'asset' &&
          event.metadata['offset'] == '0' &&
          fileReply.metadata['eof'] == true &&
          key is String &&
          _isHlsl(key) &&
          source.isNotEmpty &&
          source.length <= ArtemisHlslCompiler.maxSourceBytes &&
          _seenHlsl.length < 256 &&
          _seenHlsl.add(sha256.convert(source))) {
        final artifact = await compiler.prepare(source);
        if (_closed || !identical(_session, session)) return;
        if (artifact != null) {
          try {
            await session.prepareHlsl(source, artifact);
          } on PlatformException catch (error) {
            Log.warn('[ArtemisV2] DXVK effect unavailable: ${error.code}');
          }
        }
        if (_closed || !identical(_session, session)) return;
      }
      _replies.add(event.reply(fileReply.metadata, blob: fileReply.blob));
      return;
    }
    if (event.domain == 4 && event.kind == 5 && event.requiresReply) {
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
    } else if (event.domain == 4 && event.kind == 3 && !_closed) {
      final action = switch (event.metadata['command']) {
        'fullscreen' => EngineWindowAction.toggleFullscreen,
        'minimize' => EngineWindowAction.minimize,
        _ => null,
      };
      if (action != null) onWindowAction?.call(action);
    } else if (event.domain == 4 && event.kind == 4 && !_closed) {
      final data = event.metadata;
      media.setAvoidMuted(data['mute'] == true);
      _avoid.value = data['visible'] == true
          ? AvoidOverlay(file: data['asset'] as String?)
          : null;
    } else if (event.domain == 4 &&
        event.kind == 2 &&
        !_closed &&
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
  void notifyLifecycle(int state) {
    if (_closed || state < 0 || state > 2) return;
    final backgrounded = state != 2;
    if (_appBackgrounded == backgrounded) return;
    if (backgrounded) _input(4, const {});
    _appBackgrounded = backgrounded;
    final session = _session;
    if (state == 1 && session != null) {
      _backgroundAutosave ??= _saveOnBackground(session).whenComplete(() {
        _backgroundAutosave = null;
      });
    }
    unawaited(
      media.setSuspended(!_canRun).catchError((Object error) {
        Log.warn('[ArtemisV2] media lifecycle: $error');
      }),
    );
  }

  Future<void> _saveOnBackground(ArtemisFlutterSession session) async {
    try {
      await _advancing;
      if (_closed || !identical(_session, session) || _state?.phase != 2) {
        return;
      }
      if (_frameTime != null) {
        await _submit(session, _replies);
        await _step(session);
        if (_frameTime != null) return;
      }
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

  Future<void> _shutdown() async {
    final session = _session;
    try {
      try {
        await _advancing;
        await _backgroundAutosave;
      } on Exception {
        /* The session can still be closed. */
      }
      final state = _state;
      if (session != null && state?.phase == 2) {
        for (var turn = 0; _httpRequest != null && turn < 8; turn++) {
          _httpReply = _httpRequest!.reply({'status': 'cancelled'});
          await _submitHttp(session);
          _nextClock(0);
          await _step(session);
        }
        final message = ArtemisFlutterMessage(
          domain: 1,
          kind: 16,
          epoch: state!.epoch,
          metadata: const {},
        );
        if (await session.submit([message])) {
          for (var turn = 0; turn < 8 && _state?.phase != 4; turn++) {
            _nextClock(0);
            await _step(session);
          }
        }
      }
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
