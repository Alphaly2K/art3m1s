import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/logger.dart';
import 'file_provider.dart';

typedef LogCallbackNative = Int32 Function(Pointer<Int8> level, Pointer<Int8> msg);
typedef RegisterLogCallbackNative = Void Function(Pointer<NativeFunction<LogCallbackNative>>);

int _logCallback(Pointer<Int8> levelPtr, Pointer<Int8> msgPtr) {
  final level = levelPtr.cast<Utf8>().toDartString();
  final msg = msgPtr.cast<Utf8>().toDartString();
  switch (level) {
    case 'D': Log.debug(msg);
    case 'I': Log.info(msg);
    case 'W': Log.warn(msg);
    case 'E': Log.error(msg);
    default: Log.info(msg);
  }
  return 0;
}

// ── Core FFI type definitions ───────────────────────────────────

typedef RuntimeCreateNative = Pointer<Void> Function(Uint32 w, Uint32 h, Int32 backend);
typedef RuntimeLoadProjectNative = Int32 Function(
    Pointer<Void> rt, Pointer<Utf8> ini, Pointer<Utf8> platform);
typedef RuntimeFeedMouseNative = Void Function(
    Pointer<Void> rt, Int32 x, Int32 y);
typedef RuntimeFeedClickNative = Void Function(Pointer<Void> rt);
typedef RuntimeFeedKeyNative = Void Function(
    Pointer<Void> rt, Uint32 vk, Int32 pressed);
typedef RuntimeAdvanceRenderNative = Uint32 Function(
    Pointer<Void> rt, Uint32 deltaMs, Pointer<Uint8> outPixels, Uint32 capacity);
typedef RuntimeDestroyNative = Void Function(Pointer<Void> rt);

// ── CoreBridge — manages the core runtime lifecycle ─────────────

class CoreBridge {
  bool _initialized = false;
  DynamicLibrary? _lib;
  Pointer<Void>? _runtime;
  int _stageWidth = 1280;
  int _stageHeight = 720;

  bool get isInitialized => _initialized;
  Pointer<Void>? get runtime => _runtime;
  int get stageWidth => _stageWidth;
  int get stageHeight => _stageHeight;

  void _loadLibrary() {
    if (_lib != null) return;
    final name = Platform.isMacOS
        ? 'libart3m1s_core.dylib'
        : Platform.isLinux
            ? 'libart3m1s_core.so'
            : 'art3m1s_core.dll';
    try {
      _lib = DynamicLibrary.open(name);
    } catch (_) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      _lib = DynamicLibrary.open('$exeDir/$name');
    }
  }

  Future<void> initialize() async {
    try {
      _loadLibrary();
    } catch (e) {
      _initialized = true;
      return;
    }
    _registerCallback();
    _initialized = true;
  }

  void _registerCallback() {
    if (_lib == null) return;
    final registerFn = _lib!.lookupFunction<RegisterLogCallbackNative,
        void Function(Pointer<NativeFunction<LogCallbackNative>>)>(
      'art3m1s_register_log_callback',
    );
    final nativeCallable = NativeCallable<LogCallbackNative>.isolateLocal(_logCallback, exceptionalReturn: -1);
    registerFn(nativeCallable.nativeFunction);
  }

  void setDebug(bool enabled) {
    if (_lib == null) return;
    final fn = _lib!.lookupFunction<Void Function(Int32), void Function(int)>('art3m1s_set_debug');
    fn(enabled ? 1 : 0);
  }

  void configureAngle(String libDir) {
    if (_lib == null) return;
    try {
      final fn = _lib!.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('art3m1s_set_angle_path');
      final ptr = libDir.toNativeUtf8();
      fn(ptr);
      malloc.free(ptr);
    } catch (_) {}
  }

  void registerFileReader() {
    if (_lib == null) return;
    FileProvider.register(_lib!);
  }

  void createRuntime(int stageW, int stageH, {int backend = 0}) {
    if (_lib == null) return;
    _stageWidth = stageW;
    _stageHeight = stageH;

    final fn = _lib!.lookupFunction<RuntimeCreateNative,
        Pointer<Void> Function(int, int, int)>('art3m1s_runtime_create');
    _runtime = fn(stageW, stageH, backend);
  }

  bool loadProject(String iniContent) {
    if (_runtime == null || _lib == null) return false;
    final fn = _lib!.lookupFunction<RuntimeLoadProjectNative,
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>(
      'art3m1s_runtime_load_project',
    );
    final iniPtr = iniContent.toNativeUtf8();
    final platPtr = 'WINDOWS'.toNativeUtf8();
    try {
      return fn(_runtime!, iniPtr, platPtr) == 0;
    } finally {
      malloc.free(iniPtr);
      malloc.free(platPtr);
    }
  }

  void feedMouse(int x, int y) {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!.lookupFunction<RuntimeFeedMouseNative,
        void Function(Pointer<Void>, int, int)>('art3m1s_runtime_feed_mouse');
    fn(_runtime!, x, y);
  }

  void feedClick() {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!.lookupFunction<RuntimeFeedClickNative,
        void Function(Pointer<Void>)>('art3m1s_runtime_feed_click');
    fn(_runtime!);
  }

  void feedKey(int vk, bool pressed) {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!.lookupFunction<RuntimeFeedKeyNative,
        void Function(Pointer<Void>, int, int)>('art3m1s_runtime_feed_key');
    fn(_runtime!, vk, pressed ? 1 : 0);
  }

  Uint8List? advanceAndRender(int deltaMs) {
    if (_runtime == null || _lib == null) return null;
    final fn = _lib!.lookupFunction<RuntimeAdvanceRenderNative,
        int Function(Pointer<Void>, int, Pointer<Uint8>, int)>(
      'art3m1s_runtime_advance_and_render',
    );
    final pixelCount = _stageWidth * _stageHeight * 4;
    final out = malloc.allocate<Uint8>(pixelCount);
    try {
      final written = fn(_runtime!, deltaMs, out, pixelCount);
      if (written == 0) return null;
      return Uint8List.fromList(out.asTypedList(written));
    } finally {
      malloc.free(out);
    }
  }

  void shutdown() {
    if (_runtime != null && _lib != null) {
      final fn = _lib!.lookupFunction<RuntimeDestroyNative,
          void Function(Pointer<Void>)>('art3m1s_runtime_destroy');
      fn(_runtime!);
    }
    _runtime = null;
    FileProvider.close();
    _initialized = false;
    _lib = null;
  }
}
