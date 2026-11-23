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
import 'katze/katze_game_host.dart';

final class KatzeEngineRuntime extends UnsupportedEngineRuntime {
  KatzeEngineRuntime({this.onWindowAction}) : super(GameEngineKind.katze);

  final void Function(EngineWindowAction)? onWindowAction;
  bool? _fullscreen;

  DynamicLibrary? _library;
  KatzeGameHost? _game;
  String? _directory;
  String _encoding = '';
  String _saveDirectory = '';
  InputGatePolicy _gate = InputGatePolicy.full;
  EngineSessionState _state = EngineSessionState.active;
  bool _foreground = true;
  bool _minimized = false;
  bool _exit = false;
  int _milliseconds = 0;
  int? _touch;

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
    final manifest = await GameManifest.loadForProject(
      projectPath,
      GameSource.directory,
      engine: GameEngineKind.katze,
    );
    final settings = await startup.readAsBytes();
    _directory = projectPath;
    _encoding =
        manifest?.katzeScriptEncoding ??
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
    _game?.close();
    _game = null;
  }

  @override
  bool isExitRequested() => _exit;

  @override
  bool advanceWithoutRender(int deltaMs) {
    final game = _game;
    if (game == null || !_state.isRunning || _exit) return false;
    _milliseconds += deltaMs.clamp(0, 100);
    _exit = !game.step(increment: 1, milliseconds: _milliseconds);
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
    return !_exit;
  }

  @override
  Uint8List? advanceAndRender(int deltaMs) {
    if (!advanceWithoutRender(deltaMs)) return null;
    final pixels = _game!.present();
    for (var i = 0; i < pixels.length; i += 4) {
      final blue = pixels[i];
      pixels[i] = pixels[i + 2];
      pixels[i + 2] = blue;
    }
    return pixels;
  }

  void mixStereo(int sampleRate, Pointer<Float> output, int frames) {
    final game = _game;
    if (game == null || !_state.isRunning) {
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
    if (!_gate.touch || !_foreground || !_state.isRunning) return;
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
