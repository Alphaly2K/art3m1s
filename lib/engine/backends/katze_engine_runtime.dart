import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../../models/game_engine.dart';
import '../../models/game_entry.dart';
import '../../models/input_gate.dart';
import '../../services/logger.dart';
import '../../services/game_manifest.dart';
import '../engine_runtime.dart';
import '../native_library.dart';
import '../shared_texture_session.dart';
import 'katze/katze_game_host.dart';

final class KatzeEngineRuntime extends UnsupportedEngineRuntime
    implements AsyncTextureRuntime, AsyncPixelRuntime {
  KatzeEngineRuntime({this.onWindowAction, this.onDialogRequested})
    : super(GameEngineKind.katze);

  final void Function(EngineWindowAction)? onWindowAction;
  final void Function(EngineDialogRequest)? onDialogRequested;
  int? _dialogRequest;
  bool? _fullscreen;

  DynamicLibrary? _library;
  KatzeGameHost? _game;
  String? _directory;
  String scriptEncoding = '';
  String _encoding = '';
  String _saveDirectory = '';
  InputGatePolicy _gate = InputGatePolicy.full;
  EngineSessionState _state = EngineSessionState.active;
  bool _foreground = true;
  bool _minimized = false;
  bool _focused = true;
  int _focusRevision = 0;
  bool _exit = false;
  int _milliseconds = 0;
  int? _touch;
  int? _textureId;
  bool _changingTexture = false;
  int _textureWidth = 0;
  int _textureHeight = 0;

  @override
  bool get requiresSharedTexture => false;
  @override
  bool get hasActiveSharedTexture => _game != null && _textureId != null;
  @override
  int? get sharedTextureId => hasActiveSharedTexture ? _textureId : null;
  @override
  int get sharedTextureWidth => _textureWidth;
  @override
  int get sharedTextureHeight => _textureHeight;

  @override
  Future<int?> enableSharedTexture({
    int? outputWidth,
    int? outputHeight,
  }) async {
    final game = _game;
    if (game == null || !game.supportsSharedTexture || !_state.isRunning) {
      return null;
    }
    final width = outputWidth ?? game.width;
    final height = outputHeight ?? game.height;
    if (_textureId != null &&
        width == _textureWidth &&
        height == _textureHeight) {
      return _textureId;
    }
    try {
      final id = await SharedTextureSessionCoordinator.runWithOwnership<int?>(
        this,
        _releaseSharedTexture,
        () async {
          if (!identical(_game, game) || !_state.isRunning) return null;
          _changingTexture = true;
          try {
            await _releaseSharedTexture();
            await game.waitForFrame();
            if (!identical(_game, game) || !_state.isRunning) return null;
            final descriptor = await SharedTextureHost.create(width, height);
            final id = descriptor?['textureId'];
            final handle = descriptor?['handle'];
            if (!identical(_game, game) ||
                !_state.isRunning ||
                descriptor?['kind'] != 2 ||
                id is! int ||
                handle is! int ||
                handle == 0 ||
                !game.attachSurface(handle, width, height)) {
              await SharedTextureHost.release();
              return null;
            }
            _textureId = id;
            _textureWidth = width;
            _textureHeight = height;
            Log.info('[Katze] Metal shared texture enabled ${width}x$height');
            return id;
          } finally {
            _changingTexture = false;
          }
        },
      );
      if (id == null) await SharedTextureSessionCoordinator.release(this);
      return id;
    } catch (error) {
      Log.warn('[Katze] Shared texture initialization failed: $error');
      await SharedTextureSessionCoordinator.release(this);
      return null;
    }
  }

  Future<void> _releaseSharedTexture() async {
    if (_textureId == null) return;
    final wasChanging = _changingTexture;
    _changingTexture = true;
    _textureId = null;
    _textureWidth = 0;
    _textureHeight = 0;
    try {
      final game = _game;
      if (game != null) {
        await game.waitForFrame();
        if (identical(_game, game)) game.detachSurface();
      }
      await SharedTextureHost.release();
    } catch (error) {
      Log.warn('[Katze] Shared texture release failed: $error');
    } finally {
      _changingTexture = wasChanging;
    }
  }

  @override
  Future<bool> advanceTextureBatch(Iterable<int> frameDeltasMs) async {
    final game = _game;
    final textureId = _textureId;
    if (game == null || textureId == null) return false;
    final revision = _focusRevision;
    bool canPresent() =>
        identical(_game, game) &&
        _focused &&
        _focusRevision == revision &&
        _textureId == textureId;
    if (!await _advanceBatch(game, frameDeltasMs, canPresent) ||
        !canPresent()) {
      return false;
    }
    final presented = await game.presentSurface();
    if (!canPresent()) return false;
    if (!presented) {
      Log.warn(
        '[Katze] Metal presentation failed. Returning to software output.',
      );
      await SharedTextureSessionCoordinator.release(this);
      return false;
    }
    try {
      await SharedTextureHost.frameAvailable();
      return canPresent();
    } catch (error) {
      Log.warn('[Katze] Shared texture notification failed: $error');
      if (_textureId == textureId) {
        await SharedTextureSessionCoordinator.release(this);
      }
      return false;
    }
  }

  @override
  bool get supportsAsyncPixels => _game?.supportsAsyncPixels ?? false;

  @override
  Future<Uint8List?> advancePixelBatch(Iterable<int> frameDeltasMs) async {
    final game = _game;
    if (game == null || !game.supportsAsyncPixels) return null;
    final revision = _focusRevision;
    bool canPresent() =>
        identical(_game, game) &&
        _focused &&
        _focusRevision == revision &&
        _textureId == null &&
        !_changingTexture;
    if (!await _advanceBatch(game, frameDeltasMs, canPresent) ||
        !canPresent()) {
      return null;
    }
    final pixels = await game.presentPixelsAsync();
    if (pixels == null || !canPresent()) return null;
    return _rgba(pixels);
  }

  Future<bool> _advanceBatch(
    KatzeGameHost game,
    Iterable<int> frameDeltasMs,
    bool Function() canPresent,
  ) async {
    var advanced = false;
    final deltas = frameDeltasMs.iterator;
    while (canPresent() &&
        !_exit &&
        _dialogRequest == null &&
        deltas.moveNext()) {
      _milliseconds += deltas.current.clamp(0, 100);
      final running = await game.stepAsync(_milliseconds);
      if (!identical(_game, game) || !_finishStep(game, running)) return false;
      advanced = true;
    }
    return advanced && canPresent();
  }

  @override
  bool get isInitialized => _library != null;
  @override
  int get stageWidth => _game?.width ?? 0;
  @override
  int get stageHeight => _game?.height ?? 0;
  @override
  Set<EngineSessionState> get supportedSessionStates => const {
    EngineSessionState.active,
    EngineSessionState.frozen,
  };
  @override
  EngineSessionState get sessionState => _state;

  @override
  Future<void> initialize() async {
    try {
      _library = openKatzeHostLibrary();
    } catch (error) {
      Log.error('[Katze] Cannot load native host: $error');
    }
  }

  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) async {
    if (isArchive) return null;
    final sep = Platform.pathSeparator;
    final startup = File('$projectPath${sep}config${sep}startup.xml');
    if (!await startup.exists()) return null;
    final manifest = scriptEncoding.isEmpty
        ? await GameManifest.loadForProject(
            projectPath,
            GameSource.directory,
            engine: GameEngineKind.katze,
          )
        : null;
    final settings = await startup.readAsBytes();
    _directory = projectPath;
    _encoding = scriptEncoding.isNotEmpty
        ? scriptEncoding
        : manifest?.katzeScriptEncoding ??
              Platform.environment['KATZE_GAME_ENCODING'] ??
              '';
    return settings;
  }

  @override
  void setSaveDir(String dir) => _saveDirectory = dir;

  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) {
    final library = _library;
    final directory = _directory;
    if (library == null || directory == null) return false;
    _closeGame();
    try {
      final game = KatzeGameHost.open(
        library,
        directory,
        encoding: _encoding,
        saveDirectory: _saveDirectory,
        onScriptMessage: (text) => Log.debug('[Katze] [Script] $text'),
      );
      _game = game;
      game.reportWindow(fullscreen: _fullscreen);
      _milliseconds = 0;
      _exit = false;
      _syncFocus();
      return true;
    } catch (error) {
      _closeGame();
      Log.error('[Katze] Cannot start game: $error');
      return false;
    }
  }

  @override
  void shutdown() {
    try {
      _closeGame();
    } finally {
      _library = null;
      _directory = null;
    }
  }

  void _closeGame() {
    _touch = null;
    _dialogRequest = null;
    final game = _game;
    _game = null;
    try {
      game?.close();
    } catch (error) {
      Log.warn('[Katze] Session shutdown failed: $error');
    } finally {
      unawaited(SharedTextureSessionCoordinator.release(this));
    }
  }

  @override
  bool isExitRequested() => _exit;

  @override
  bool advanceWithoutRender(int deltaMs) {
    final game = _game;
    if (game == null || !_focused || _exit) return false;
    if (_dialogRequest != null) return true;
    _milliseconds += deltaMs.clamp(0, 100);
    return _finishStep(
      game,
      game.step(increment: 1, milliseconds: _milliseconds),
    );
  }

  bool _finishStep(KatzeGameHost game, bool running) {
    _exit = !running;
    var command = game.takeWindowAction();
    while (command != 0) {
      final action = switch (command) {
        1 => EngineWindowAction.toggleFullscreen,
        2 => EngineWindowAction.minimize,
        _ => null,
      };
      if (action != null) onWindowAction?.call(action);
      command = game.takeWindowAction();
    }
    if (!_exit && _dialogRequest == null && onDialogRequested != null) {
      if (game.textEntry() case (final id, final initialText)) {
        _dialogRequest = id;
        onDialogRequested!(
          EngineDialogRequest(
            title: '文字输入',
            message: '',
            hasCancel: true,
            hasTextField: true,
            textFieldSize: null,
            initialText: initialText,
          ),
        );
      }
    }
    return !_exit;
  }

  @override
  bool submitDialog(bool accepted, String text) {
    final id = _dialogRequest;
    if (id == null) return false;
    _dialogRequest = null;
    return _game?.completeTextEntry(id, accepted ? text : null) ?? false;
  }

  @override
  Uint8List? advanceAndRender(int deltaMs) {
    if (_dialogRequest != null || !advanceWithoutRender(deltaMs)) return null;
    return _rgba(_game!.present());
  }

  Uint8List _rgba(Uint8List pixels) {
    for (var i = 0; i < pixels.length; i += 4) {
      final blue = pixels[i];
      pixels[i] = pixels[i + 2];
      pixels[i + 2] = blue;
    }
    return pixels;
  }

  void mixStereo(int sampleRate, Pointer<Float> output, int frames) {
    final game = _game;
    if (game == null || !_focused) {
      output.asTypedList(frames * 2).fillRange(0, frames * 2, 0);
    } else {
      game.mixStereo(sampleRate, output, frames);
    }
  }

  @override
  Future<EngineSessionState> setSessionState(EngineSessionState state) async {
    _state = state == EngineSessionState.active
        ? state
        : EngineSessionState.frozen;
    _syncFocus();
    if (!_state.isRunning) await SharedTextureSessionCoordinator.release(this);
    return _state;
  }

  @override
  void setWindowStateBits({bool? fullscreen, bool? minimized}) {
    if (fullscreen != null) {
      _fullscreen = fullscreen;
      _game?.reportWindow(fullscreen: fullscreen);
    }
    if (minimized != null && minimized != _minimized) {
      _minimized = minimized;
      _syncFocus();
    }
  }

  @override
  void notifyLifecycle(int state) {
    _foreground = state == 2;
    _syncFocus();
  }

  void _syncFocus() {
    final focused = _foreground && !_minimized && _state.isRunning;
    if (_focused != focused) {
      _focused = focused;
      _focusRevision++;
    }
    if (!focused) _touch = null;
    final game = _game;
    if (game == null) return;
    game.focus(focused);
    if (focused && Platform.environment['KATZE_OFFSCREEN_AUDIO'] != '1') {
      game.startDeviceAudio();
    } else {
      game.stopDeviceAudio();
    }
  }

  @override
  void configureInputGate(InputGatePolicy gate) => _gate = gate;

  @override
  void feedMouse(int x, int y) {
    if (_gate.mouseMove) _game?.pointer(x, y);
  }

  @override
  void feedMouseButton(int button, bool pressed) {
    if (_gate.mouseButtons) _game?.button(1, button, pressed);
  }

  @override
  void feedClick() {
    feedMouseButton(1, true);
    feedMouseButton(1, false);
  }

  @override
  void feedKey(int keyCode, bool pressed) {
    final code = _gate.filterKey(keyCode);
    if (code != null) _game?.button(0, code, pressed);
  }

  @override
  void feedForwardedKey(int keyCode, bool pressed) {
    final code = _gate.filterForwardedKey(keyCode);
    if (code == null) return;
    if (code == 136 || code == 137) {
      if (pressed) feedWheel(0, code == 136 ? 1 : -1);
    } else {
      _game?.button(0, code, pressed);
    }
  }

  @override
  void feedWheel(double deltaX, double deltaY) {
    if (!_gate.wheelToKeys || !deltaY.isFinite || deltaY == 0) return;
    _game?.button(1, deltaY > 0 ? 6 : 7, true);
  }

  @override
  void feedTouch(int id, int phase, int x, int y) {
    if (!_gate.touch || !_focused) return;
    if (phase == 0 && _touch == null) _touch = id;
    if (_touch != id) return;
    _game?.pointer(x, y);
    if (phase == 0) _game?.button(1, 1, true);
    if (phase >= 2) {
      _touch = null;
      _game?.button(1, 1, false);
    }
  }
}
