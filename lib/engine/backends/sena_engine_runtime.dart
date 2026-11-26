import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../models/game_engine.dart';
import '../../models/input_gate.dart';
import '../../services/logger.dart';
import '../engine_runtime.dart';
import '../native_library.dart';

typedef _Stat =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _Read =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint64, Pointer<Uint8>, Size);
typedef _Write =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Size);

final class _Files extends Struct {
  @Uint32()
  external int size;
  external Pointer<Void> context;
  external Pointer<NativeFunction<_Stat>> stat;
  external Pointer<NativeFunction<_Read>> read;
  external Pointer<NativeFunction<_Write>> write;
}

final class _Api extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int version;
  external Pointer<
    NativeFunction<Int32 Function(Pointer<_Files>, Pointer<Uint64>)>
  >
  open;
  external Pointer<NativeFunction<Int32 Function(Uint64)>> close;
  external Pointer<
    NativeFunction<
      Int32 Function(Uint64, Uint32, Pointer<Uint32>, Pointer<Uint32>)
    >
  >
  tick;
  external Pointer<NativeFunction<Int32 Function(Uint64, Pointer<Uint8>, Size)>>
  rgba;
  external Pointer<NativeFunction<Int32 Function(Uint64, Pointer<Int16>, Size)>>
  pcm;
  external Pointer<
    NativeFunction<
      Int32 Function(Uint64, Uint32, Int32, Int32, Int32, Pointer<Utf8>)
    >
  >
  input;
  external Pointer<NativeFunction<Size Function(Pointer<Uint8>, Size)>>
  lastError;
  external Pointer<NativeFunction<Int32 Function(Uint64, Uint32)>> deviceAudio;
}

class SenaEngineRuntime extends UnsupportedEngineRuntime {
  SenaEngineRuntime() : super(GameEngineKind.sena);

  Pointer<_Api> _api = nullptr;
  int _session = 0;
  String? _project;
  String? _saves;
  int _width = 1280;
  int _height = 720;
  bool _ended = false;
  InputGatePolicy _gate = InputGatePolicy.full;
  EngineSessionState _state = EngineSessionState.active;
  final _buttons = <int>{};
  final _keys = <String>{};
  int? _touchId;
  NativeCallable<_Stat>? _stat;
  NativeCallable<_Read>? _read;
  NativeCallable<_Write>? _write;
  final _projectEntries = <String, Map<String, FileSystemEntity>>{};

  @override
  bool get isInitialized => _api != nullptr;
  @override
  int get stageWidth => _width;
  @override
  int get stageHeight => _height;
  @override
  EngineSessionState get sessionState => _state;
  @override
  Set<EngineSessionState> get supportedSessionStates => const {
    EngineSessionState.active,
    EngineSessionState.suspended,
  };

  @override
  Future<EngineSessionState> setSessionState(EngineSessionState state) async {
    if (state != EngineSessionState.active) _releaseInputs();
    _state = state == EngineSessionState.active
        ? EngineSessionState.active
        : EngineSessionState.suspended;
    if (_session != 0) _audio(_state == EngineSessionState.active ? 3 : 2);
    return _state;
  }

  @override
  Future<void> initialize() async {
    try {
      final library = openEngineCoreLibrary();
      final api = library
          .lookupFunction<Pointer<_Api> Function(), Pointer<_Api> Function()>(
            'art3m1s_sena_get_api_v1',
          )();
      if (api != nullptr &&
          api.ref.version == 1 &&
          api.ref.size >= sizeOf<_Api>()) {
        _api = api;
      }
    } catch (error) {
      Log.warn('[Sena] 原生接口不可用: $error');
    }
  }

  @override
  Future<Uint8List?> prepareProject({
    required String projectPath,
    required bool isArchive,
    required bool environmentPatchEnabled,
    required String platform,
  }) async {
    if (isArchive || !await Directory(projectPath).exists()) return null;
    _project = await Directory(projectPath).resolveSymbolicLinks();
    _projectEntries.clear();
    return Uint8List(0);
  }

  @override
  void setSaveDir(String dir) => _saves = dir;
  @override
  void configureInputGate(InputGatePolicy gate) {
    _releaseInputs();
    _gate = gate;
  }

  File? _file(String key, {bool write = false}) {
    final parts = key.split('/');
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.contains('\\') ||
          part.contains(':'),
    )) {
      return null;
    }
    if (parts.first == 'save' && parts.length > 1) {
      final root = _saves;
      if (root == null) return null;
      return File([root, ...parts.skip(1)].join(Platform.pathSeparator));
    }
    if (write || _project == null) return null;
    var current = _project!;
    for (var index = 0; index < parts.length; index++) {
      final entries = _projectEntries.putIfAbsent(
        current,
        () => {
          for (final entry in Directory(current).listSync(followLinks: false))
            if (entry is File || entry is Directory)
              entry.path.split(Platform.pathSeparator).last.toLowerCase():
                  entry,
        },
      );
      final entry = entries[parts[index].toLowerCase()];
      if (index == parts.length - 1) return entry is File ? entry : null;
      if (entry is! Directory) return null;
      current = entry.path;
    }
    return null;
  }

  @override
  void createRuntime(int stageWidth, int stageHeight, {int backend = 0}) {
    if (_api == nullptr ||
        _project == null ||
        _saves == null ||
        _session != 0) {
      return;
    }
    _stat = NativeCallable<_Stat>.isolateLocal((
      Pointer<Void> _,
      Pointer<Utf8> key,
      Pointer<Uint64> size,
      Pointer<Uint64> modified,
    ) {
      final file = _file(key.toDartString());
      if (file == null) return 1;
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) return 1;
      size.value = stat.size;
      modified.value = stat.modified.millisecondsSinceEpoch.clamp(
        0,
        0x7fffffffffffffff,
      );
      return 0;
    }, exceptionalReturn: -1);
    _read = NativeCallable<_Read>.isolateLocal((
      Pointer<Void> _,
      Pointer<Utf8> key,
      int offset,
      Pointer<Uint8> output,
      int length,
    ) {
      final file = _file(key.toDartString());
      if (file == null || !file.existsSync()) return 1;
      if (length == 0) return 0;
      final handle = file.openSync();
      try {
        handle.setPositionSync(offset);
        final buffer = output.asTypedList(length);
        var read = 0;
        while (read < length) {
          final n = handle.readIntoSync(buffer, read);
          if (n == 0) return -1;
          read += n;
        }
        return 0;
      } finally {
        handle.closeSync();
      }
    }, exceptionalReturn: -1);
    _write = NativeCallable<_Write>.isolateLocal((
      Pointer<Void> _,
      Pointer<Utf8> key,
      Pointer<Uint8> data,
      int length,
    ) {
      final file = _file(key.toDartString(), write: true);
      if (file == null) return -1;
      if (data == nullptr) {
        if (!file.existsSync()) return 1;
        file.deleteSync();
        return 0;
      }
      file.parent.createSync(recursive: true);
      final temporary = file.parent.createTempSync('.sena-');
      try {
        final staged = File('${temporary.path}${Platform.pathSeparator}save');
        staged.writeAsBytesSync(data.asTypedList(length), flush: true);
        staged.renameSync(file.path);
      } finally {
        temporary.deleteSync(recursive: true);
      }
      return 0;
    }, exceptionalReturn: -1);
    final status = using((arena) {
      final files = arena<_Files>();
      files.ref
        ..size = sizeOf<_Files>()
        ..context = nullptr
        ..stat = _stat!.nativeFunction
        ..read = _read!.nativeFunction
        ..write = _write!.nativeFunction;
      final out = arena<Uint64>();
      final status =
          _api.ref.open
              .asFunction<int Function(Pointer<_Files>, Pointer<Uint64>)>()(
            files,
            out,
          );
      _session = out.value;
      return status;
    });
    if (status != 0) {
      _logError();
      shutdown();
      return;
    }
    _advance(1, allowSuspended: true);
    if (_audio(0) != 0) _logError();
    if (_state != EngineSessionState.active) _audio(2);
  }

  int _audio(int action) => _api.ref.deviceAudio
      .asFunction<int Function(int, int)>()(_session, action);

  void _logError() {
    final read = _api.ref.lastError
        .asFunction<int Function(Pointer<Uint8>, int)>();
    final length = read(nullptr, 0);
    if (length == 0) return;
    using((arena) {
      final out = arena<Uint8>(length);
      Log.warn(
        '[Sena] ${utf8.decode(out.asTypedList(read(out, length)), allowMalformed: true)}',
      );
    });
  }

  @override
  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) =>
      _session != 0 && !_ended;

  bool _advance(int deltaMs, {bool allowSuspended = false}) {
    if (_session == 0 ||
        _ended ||
        (!allowSuspended && _state != EngineSessionState.active)) {
      return false;
    }
    return using((arena) {
      final width = arena<Uint32>();
      final height = arena<Uint32>();
      final status = _api.ref.tick
          .asFunction<
            int Function(int, int, Pointer<Uint32>, Pointer<Uint32>)
          >()(_session, deltaMs.clamp(1, 250), width, height);
      if (status < 0) {
        _logError();
        _ended = true;
        return false;
      }
      _width = width.value;
      _height = height.value;
      _ended = status == 1;
      return true;
    });
  }

  @override
  bool advanceWithoutRender(int deltaMs) => _advance(deltaMs);

  @override
  Uint8List? advanceAndRender(int deltaMs) {
    if (!_advance(deltaMs)) return null;
    return using((arena) {
      final size = _width * _height * 4;
      final buffer = arena<Uint8>(size);
      final status =
          _api.ref.rgba.asFunction<int Function(int, Pointer<Uint8>, int)>()(
            _session,
            buffer,
            size,
          );
      return status == 0 ? Uint8List.fromList(buffer.asTypedList(size)) : null;
    });
  }

  @override
  bool isExitRequested() => _ended;

  void _input(int kind, {int code = 0, int x = 0, int y = 0, String? key}) {
    if (_session == 0 || _state != EngineSessionState.active) return;
    using((arena) {
      final name = key?.toNativeUtf8(allocator: arena) ?? nullptr;
      _api.ref.input
          .asFunction<int Function(int, int, int, int, int, Pointer<Utf8>)>()(
        _session,
        kind,
        code,
        x,
        y,
        name,
      );
    });
  }

  @override
  void feedMouse(int x, int y) {
    if (_gate.mouseMove) _input(0, x: x, y: y);
  }

  @override
  void feedClick() {
    feedMouseButton(0, true);
    feedMouseButton(0, false);
  }

  @override
  void feedMouseButton(int button, bool pressed) {
    if (!_gate.mouseButtons ||
        _session == 0 ||
        _state != EngineSessionState.active ||
        button < 0 ||
        button > 2) {
      return;
    }
    final changed = pressed ? _buttons.add(button) : _buttons.remove(button);
    if (changed && (button != 0 || _touchId == null)) {
      _input(pressed ? 1 : 2, code: button);
    }
  }

  @override
  void feedTouch(int id, int phase, int x, int y) {
    if (!_gate.touch || _session == 0 || _state != EngineSessionState.active) {
      return;
    }
    if (phase == 0 && _touchId == null) {
      _touchId = id;
      _input(0, x: x, y: y);
      if (!_buttons.contains(0)) _input(1);
    } else if (_touchId == id) {
      _input(0, x: x, y: y);
      if (phase == 2 || phase == 3) {
        _touchId = null;
        if (!_buttons.contains(0)) _input(2);
      }
    }
  }

  @override
  void feedWheel(double deltaX, double deltaY) {
    if (deltaX.isFinite && deltaY.isFinite) {
      _input(5, x: deltaX.round(), y: deltaY.round());
    }
  }

  void _key(int? code, bool pressed) {
    if (code == null || _session == 0 || _state != EngineSessionState.active) {
      return;
    }
    if (code == 136 || code == 137) {
      if (pressed) feedWheel(0, code == 136 ? 1 : -1);
      return;
    }
    final name = switch (code) {
      8 => 'Backspace',
      9 => 'Tab',
      13 => 'Enter',
      16 => 'Shift',
      17 => 'Control',
      18 => 'Alt',
      27 => 'Escape',
      32 => 'Space',
      37 => 'ArrowLeft',
      38 => 'ArrowUp',
      39 => 'ArrowRight',
      40 => 'ArrowDown',
      46 => 'Delete',
      >= 48 && <= 90 => String.fromCharCode(code),
      _ => null,
    };
    if (name != null) {
      _input(pressed ? 3 : 4, key: name);
      if (pressed) {
        _keys.add(name);
      } else {
        _keys.remove(name);
      }
    }
  }

  @override
  void feedKey(int keyCode, bool pressed) =>
      _key(_gate.filterKey(keyCode), pressed);

  @override
  void feedForwardedKey(int keyCode, bool pressed) =>
      _key(_gate.filterForwardedKey(keyCode), pressed);

  void _releaseInputs() {
    if (_touchId != null) _buttons.add(0);
    for (final button in _buttons) {
      _input(2, code: button);
    }
    for (final key in _keys) {
      _input(4, key: key);
    }
    _buttons.clear();
    _keys.clear();
    _touchId = null;
  }

  @override
  void shutdown() {
    _releaseInputs();
    if (_session != 0) {
      _api.ref.close.asFunction<int Function(int)>()(_session);
      _session = 0;
    }
    _stat?.close();
    _read?.close();
    _write?.close();
    _stat = null;
    _read = null;
    _write = null;
    _projectEntries.clear();
    _ended = false;
  }
}
