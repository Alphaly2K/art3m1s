import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/logger.dart';
import 'file_provider.dart';
import 'media_bridge.dart';

typedef LogCallbackNative = Int32 Function(Pointer<Int8> level, Pointer<Int8> msg);
typedef RegisterLogCallbackNative = Void Function(Pointer<NativeFunction<LogCallbackNative>>);
typedef MediaCommandCallbackNative = Void Function(
  Pointer<Int8> kind,
  Pointer<Int8> payloadJson,
);
typedef RegisterMediaCommandCallbackNative = Void Function(
  Pointer<NativeFunction<MediaCommandCallbackNative>>,
);

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

void _mediaCommandCallback(Pointer<Int8> kindPtr, Pointer<Int8> payloadPtr) {
  try {
    final kind = kindPtr.cast<Utf8>().toDartString();
    final rawPayload = payloadPtr.cast<Utf8>().toDartString();
    final decoded = jsonDecode(rawPayload);
    final payload = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    CoreBridge._activeBridge?.media.handleCommand(kind, payload);
  } catch (e) {
    Log.error('[CoreBridge] 媒体命令解析失败: $e');
  }
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
typedef RuntimeStageWidthNative = Uint32 Function(Pointer<Void> rt);
typedef RuntimeStageHeightNative = Uint32 Function(Pointer<Void> rt);
typedef RuntimePixelBufferSizeNative = Uint32 Function(Pointer<Void> rt);
typedef RuntimeAdvanceRenderNative = Uint32 Function(
    Pointer<Void> rt, Uint32 deltaMs, Pointer<Uint8> outPixels, Uint32 capacity);
typedef RuntimeIsExitRequestedNative = Int32 Function(Pointer<Void> rt);
typedef RuntimeDestroyNative = Void Function(Pointer<Void> rt);
typedef RuntimeNotifyVideoFinishedNative = Void Function(
    Pointer<Void> rt, Pointer<Utf8> id);
typedef RuntimeNotifySoundFinishedNative = Void Function(
    Pointer<Void> rt, Pointer<Utf8> id);

// ── CoreBridge — manages the core runtime lifecycle ─────────────

class CoreBridge {
  static NativeCallable<LogCallbackNative>? _sharedLogCallable;
  static NativeCallable<MediaCommandCallbackNative>? _sharedMediaCallable;
  static CoreBridge? _activeBridge;

  bool _initialized = false;
  DynamicLibrary? _lib;
  Pointer<Void>? _runtime;
  int _stageWidth = 1280;
  int _stageHeight = 720;
  late final MediaBridge media = MediaBridge(
    onVideoFinished: notifyVideoFinished,
    onSoundFinished: notifySoundFinished,
  );

  bool get isInitialized => _initialized;
  Pointer<Void>? get runtime => _runtime;
  int get stageWidth => _stageWidth;
  int get stageHeight => _stageHeight;

  void _loadLibrary() {
    if (_lib != null) return;
    final name = Platform.isMacOS
        ? 'libart3m1s_core.dylib'
        : Platform.isLinux || Platform.isAndroid
            ? 'libart3m1s_core.so'
            : 'art3m1s_core.dll';
    try {
      _lib = DynamicLibrary.open(name);
    } catch (_) {
      if (!Platform.isAndroid && !Platform.isIOS) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        _lib = DynamicLibrary.open('$exeDir/$name');
      } else {
        rethrow;
      }
    }
  }

  Future<void> initialize() async {
    try {
      _loadLibrary();
    } catch (e) {
      Log.error('[CoreBridge] Core 库加载失败: $e');
      _initialized = false;
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
    _sharedLogCallable ??= NativeCallable<LogCallbackNative>.isolateLocal(
      _logCallback,
      exceptionalReturn: -1,
    );
    registerFn(_sharedLogCallable!.nativeFunction);

    final registerMediaFn = _lib!.lookupFunction<RegisterMediaCommandCallbackNative,
        void Function(Pointer<NativeFunction<MediaCommandCallbackNative>>)>(
      'art3m1s_register_media_command_callback',
    );
    _sharedMediaCallable ??= NativeCallable<MediaCommandCallbackNative>.isolateLocal(
      _mediaCommandCallback,
    );
    _activeBridge = this;
    registerMediaFn(_sharedMediaCallable!.nativeFunction);
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

  void setSaveDir(String dir) {
    if (_lib == null) {
      Log.warn('[CoreBridge] setSaveDir: _lib is null');
      return;
    }
    try {
      // 确保目录存在
      final d = Directory(dir);
      if (!d.existsSync()) {
        d.createSync(recursive: true);
      }
      final fn = _lib!.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('art3m1s_set_save_dir');
      final ptr = dir.toNativeUtf8();
      fn(ptr);
      malloc.free(ptr);
      // 同步告知 FileProvider 存档基准目录，供写/删/读回退使用
      FileProvider.setSaveDir(dir);
      Log.info('[CoreBridge] 存档目录已设置: $dir');
    } catch (e) {
      Log.error('[CoreBridge] setSaveDir 失败 ($dir): $e');
    }
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
      final result = fn(_runtime!, iniPtr, platPtr) == 0;
      if (result) {
        // 加载成功后查询 core 端的实际舞台尺寸
        _updateStageSize();
      }
      return result;
    } finally {
      malloc.free(iniPtr);
      malloc.free(platPtr);
    }
  }

  void _updateStageSize() {
    if (_runtime == null || _lib == null) return;
    try {
      final widthFn = _lib!.lookupFunction<RuntimeStageWidthNative,
          int Function(Pointer<Void>)>('art3m1s_runtime_stage_width');
      final heightFn = _lib!.lookupFunction<RuntimeStageHeightNative,
          int Function(Pointer<Void>)>('art3m1s_runtime_stage_height');
      _stageWidth = widthFn(_runtime!);
      _stageHeight = heightFn(_runtime!);
      Log.info('[CoreBridge] 舞台尺寸已更新: $_stageWidth x $_stageHeight');
    } catch (e) {
      Log.warn('[CoreBridge] 查询舞台尺寸失败: $e');
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

  bool isExitRequested() {
    if (_runtime == null || _lib == null) return false;
    try {
      final fn = _lib!.lookupFunction<RuntimeIsExitRequestedNative,
          int Function(Pointer<Void>)>('art3m1s_runtime_is_exit_requested');
      return fn(_runtime!) != 0;
    } catch (_) {
      return false;
    }
  }

  void notifyVideoFinished(String? id) {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!.lookupFunction<RuntimeNotifyVideoFinishedNative,
        void Function(Pointer<Void>, Pointer<Utf8>)>(
      'art3m1s_runtime_notify_video_finished',
    );
    final idPtr = id == null ? Pointer<Utf8>.fromAddress(0) : id.toNativeUtf8();
    try {
      fn(_runtime!, idPtr);
    } finally {
      if (id != null) malloc.free(idPtr);
    }
  }

  void notifySoundFinished(String? id) {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!.lookupFunction<RuntimeNotifySoundFinishedNative,
        void Function(Pointer<Void>, Pointer<Utf8>)>(
      'art3m1s_runtime_notify_sound_finished',
    );
    final idPtr = id == null ? Pointer<Utf8>.fromAddress(0) : id.toNativeUtf8();
    try {
      fn(_runtime!, idPtr);
    } finally {
      if (id != null) malloc.free(idPtr);
    }
  }

  void shutdown() {
    if (_activeBridge == this) _activeBridge = null;
    unawaited(media.dispose());
    final runtime = _runtime;
    final lib = _lib;
    _runtime = null;
    _initialized = false;

    if (runtime != null && lib != null) {
      try {
        Log.info('[CoreBridge] runtime destroy begin');
        final fn = lib.lookupFunction<RuntimeDestroyNative,
            void Function(Pointer<Void>)>('art3m1s_runtime_destroy');
        fn(runtime);
        Log.info('[CoreBridge] runtime destroy end');
      } catch (e) {
        Log.warn('[CoreBridge] runtime destroy failed: $e');
        // dylib may not export art3m1s_runtime_destroy yet
      }
    }
    FileProvider.close();
    _lib = null;
  }
}
