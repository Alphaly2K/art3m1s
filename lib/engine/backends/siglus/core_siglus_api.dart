import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _GetApiNative = Pointer<_SiglusApiV1> Function(Pointer<UintPtr>);
typedef _GetApiDart = Pointer<_SiglusApiV1> Function(Pointer<UintPtr>);
typedef _GetApiV2Native = Pointer<_SiglusApiV2> Function(Pointer<UintPtr>);
typedef _GetApiV2Dart = Pointer<_SiglusApiV2> Function(Pointer<UintPtr>);
typedef _CreateWithSaveDirNative =
    Int32 Function(Pointer<Char>, Pointer<Char>, Int32, Pointer<Uint64>);
typedef _CreateWithSaveDirDart =
    int Function(Pointer<Char>, Pointer<Char>, int, Pointer<Uint64>);
typedef _ProbeNative = Int32 Function(Pointer<Char>);
typedef _ProbeDart = int Function(Pointer<Char>);
typedef _CreateNative = Int32 Function(Pointer<Char>, Int32, Pointer<Uint64>);
typedef _CreateDart = int Function(Pointer<Char>, int, Pointer<Uint64>);
typedef _DestroyNative = Void Function(Uint64);
typedef _DestroyDart = void Function(int);
typedef _StageNative = Uint32 Function(Uint64);
typedef _StageDart = int Function(int);
typedef _SurfaceNative =
    Int32 Function(Uint64, Int32, Pointer<Void>, Uint32, Uint32);
typedef _SurfaceDart = int Function(int, int, Pointer<Void>, int, int);
typedef _TickNative =
    Int32 Function(
      Uint64,
      Uint32,
      Int32,
      Pointer<Uint8>,
      UintPtr,
      Pointer<UintPtr>,
    );
typedef _TickDart =
    int Function(int, int, int, Pointer<Uint8>, int, Pointer<UintPtr>);
typedef _InputNative =
    Int32 Function(Uint64, Int32, Int32, Int32, Int32, Int32);
typedef _InputDart = int Function(int, int, int, int, int, int);
typedef _ExitNative = Int32 Function(Uint64);
typedef _ExitDart = int Function(int);
typedef _ErrorNative = UintPtr Function(Pointer<Uint8>, UintPtr);
typedef _ErrorDart = int Function(Pointer<Uint8>, int);
typedef _GetDiagnosticsNative =
    Pointer<_SiglusDiagnosticsApiV1> Function(Pointer<UintPtr>);
typedef _GetDiagnosticsDart =
    Pointer<_SiglusDiagnosticsApiV1> Function(Pointer<UintPtr>);
typedef _LogNextBytesNative = UintPtr Function();
typedef _LogNextBytesDart = int Function();
typedef _PollLogNative = UintPtr Function(Pointer<Uint8>, UintPtr);
typedef _PollLogDart = int Function(Pointer<Uint8>, int);
typedef _SetDebugNative = Int32 Function(Uint64, Int32);
typedef _SetDebugDart = int Function(int, int);
typedef _GetAudioNative = Pointer<_SiglusAudioApiV1> Function(Pointer<UintPtr>);
typedef _GetAudioDart = Pointer<_SiglusAudioApiV1> Function(Pointer<UintPtr>);
typedef _RenderPcmNative = Int32 Function(Uint64, Pointer<Float>, UintPtr);
typedef _RenderPcmDart = int Function(int, Pointer<Float>, int);

final class _SiglusAudioApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint64()
  external int magic;
  @Uint32()
  external int sampleRate;
  @Uint32()
  external int channels;
  external Pointer<NativeFunction<_RenderPcmNative>> runtimeRenderPcm;
}

class CoreSiglusAudioV1 {
  CoreSiglusAudioV1._(this._table);
  final Pointer<_SiglusAudioApiV1> _table;

  int get sampleRate => _table.ref.sampleRate;
  int get channels => _table.ref.channels;

  static CoreSiglusAudioV1? tryLoad(DynamicLibrary library) {
    final _GetAudioDart getApi;
    try {
      getApi = library.lookupFunction<_GetAudioNative, _GetAudioDart>(
        'art3m1s_siglus_get_audio_api_v1',
      );
    } catch (_) {
      return null;
    }
    final size = calloc<UintPtr>();
    try {
      final table = getApi(size);
      return size.value == sizeOf<_SiglusAudioApiV1>() ? _from(table) : null;
    } finally {
      calloc.free(size);
    }
  }

  static CoreSiglusAudioV1? _from(Pointer<_SiglusAudioApiV1> table) {
    if (table == nullptr ||
        table.ref.structSize != sizeOf<_SiglusAudioApiV1>() ||
        table.ref.abiVersion != 1 ||
        table.ref.magic != 0x315641534d334152 ||
        table.ref.sampleRate != 48000 ||
        table.ref.channels != 2 ||
        table.ref.runtimeRenderPcm == nullptr) {
      return null;
    }
    return CoreSiglusAudioV1._(table);
  }

  Uint8List? renderPcm(int runtime, int frames) {
    if (frames <= 0 || frames > 4800) return null;
    final buffer = calloc<Float>(frames * channels);
    try {
      final status = _table.ref.runtimeRenderPcm.asFunction<_RenderPcmDart>()(
        runtime,
        buffer,
        frames,
      );
      if (status != 0) return null;
      return Uint8List.fromList(
        buffer.cast<Uint8>().asTypedList(frames * channels * 4),
      );
    } finally {
      calloc.free(buffer);
    }
  }
}

final class _SiglusDiagnosticsApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint64()
  external int magic;
  external Pointer<NativeFunction<_LogNextBytesNative>> logNextBytes;
  external Pointer<NativeFunction<_PollLogNative>> pollLog;
  external Pointer<NativeFunction<_SetDebugNative>> runtimeSetDebug;
}

class SiglusLogRecord {
  const SiglusLogRecord(this.level, this.message);
  final int level;
  final String message;
}

class CoreSiglusDiagnosticsV1 {
  CoreSiglusDiagnosticsV1._(this._table);
  final Pointer<_SiglusDiagnosticsApiV1> _table;

  static CoreSiglusDiagnosticsV1? tryLoad(DynamicLibrary library) {
    final _GetDiagnosticsDart getApi;
    try {
      getApi = library
          .lookupFunction<_GetDiagnosticsNative, _GetDiagnosticsDart>(
            'art3m1s_siglus_get_diagnostics_api_v1',
          );
    } catch (_) {
      return null;
    }
    final size = calloc<UintPtr>();
    try {
      final table = getApi(size);
      return size.value == sizeOf<_SiglusDiagnosticsApiV1>()
          ? _from(table)
          : null;
    } finally {
      calloc.free(size);
    }
  }

  static CoreSiglusDiagnosticsV1? _from(
    Pointer<_SiglusDiagnosticsApiV1> table,
  ) {
    if (table == nullptr ||
        table.ref.structSize != sizeOf<_SiglusDiagnosticsApiV1>() ||
        table.ref.abiVersion != 1 ||
        table.ref.magic != 0x315647534d334152 ||
        table.ref.logNextBytes == nullptr ||
        table.ref.pollLog == nullptr ||
        table.ref.runtimeSetDebug == nullptr) {
      return null;
    }
    return CoreSiglusDiagnosticsV1._(table);
  }

  int setDebug(int runtime, bool enabled) => _table.ref.runtimeSetDebug
      .asFunction<_SetDebugDart>()(runtime, enabled ? 1 : 0);

  List<SiglusLogRecord> pollLogs() {
    final next = _table.ref.logNextBytes.asFunction<_LogNextBytesDart>()();
    if (next <= 0 || next > 16 * 1024 + 8) return const [];
    final buffer = calloc<Uint8>(64 * 1024);
    try {
      final written = _table.ref.pollLog.asFunction<_PollLogDart>()(
        buffer,
        64 * 1024,
      );
      if (written <= 0 || written > 64 * 1024) return const [];
      final bytes = buffer.asTypedList(written);
      final view = ByteData.sublistView(bytes);
      final records = <SiglusLogRecord>[];
      var offset = 0;
      while (offset + 8 <= written) {
        final level = view.getUint32(offset, Endian.little);
        final length = view.getUint32(offset + 4, Endian.little);
        if (length > 16 * 1024 || offset + 8 + length > written) break;
        records.add(
          SiglusLogRecord(
            level,
            utf8.decode(
              bytes.sublist(offset + 8, offset + 8 + length),
              allowMalformed: true,
            ),
          ),
        );
        offset += 8 + length;
      }
      return records;
    } finally {
      calloc.free(buffer);
    }
  }
}

final class _SiglusApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint32()
  external int magic;
  external Pointer<NativeFunction<_ProbeNative>> probeProject;
  external Pointer<NativeFunction<_CreateNative>> runtimeCreate;
  external Pointer<NativeFunction<_DestroyNative>> runtimeDestroy;
  external Pointer<NativeFunction<_StageNative>> runtimeStageWidth;
  external Pointer<NativeFunction<_StageNative>> runtimeStageHeight;
  external Pointer<NativeFunction<_SurfaceNative>> runtimeSetExternalSurface;
  external Pointer<NativeFunction<_TickNative>> runtimeTick;
  external Pointer<NativeFunction<_InputNative>> runtimeInput;
  external Pointer<NativeFunction<_ExitNative>> runtimeIsExitRequested;
  external Pointer<NativeFunction<_ErrorNative>> lastError;
}

final class _SiglusApiV2 extends Struct {
  external _SiglusApiV1 base;
  external Pointer<NativeFunction<_CreateWithSaveDirNative>>
  runtimeCreateWithSaveDir;
}

class CoreSiglusApiV1 {
  CoreSiglusApiV1._(this._table, [this._createWithSaveDir]);

  static const ok = 0;
  static const invalidHandle = -2;
  static const inputMove = 0;
  static const inputButton = 1;
  static const inputTouch = 2;
  static const inputKey = 3;
  static const inputWheel = 4;
  static const tickAdvance = 0;
  static const tickReadback = 1;
  static const tickPresent = 2;

  final Pointer<_SiglusApiV1> _table;
  final _CreateWithSaveDirDart? _createWithSaveDir;

  bool get supportsSaveDirectory => _createWithSaveDir != null;

  static CoreSiglusApiV1? tryLoad(DynamicLibrary library) {
    final size = calloc<UintPtr>();
    try {
      if (library.providesSymbol('art3m1s_siglus_get_api_v2')) {
        final getV2 = library.lookupFunction<_GetApiV2Native, _GetApiV2Dart>(
          'art3m1s_siglus_get_api_v2',
        );
        final table = getV2(size);
        if (size.value == sizeOf<_SiglusApiV2>()) {
          final runtime = _fromV2(table);
          if (runtime != null) return runtime;
        }
      }
      if (!library.providesSymbol('art3m1s_siglus_get_api_v1')) return null;
      final getV1 = library.lookupFunction<_GetApiNative, _GetApiDart>(
        'art3m1s_siglus_get_api_v1',
      );
      final table = getV1(size);
      if (table == nullptr || size.value != sizeOf<_SiglusApiV1>()) return null;
      return _valid(table.ref, size.value, 1) ? CoreSiglusApiV1._(table) : null;
    } finally {
      calloc.free(size);
    }
  }

  static CoreSiglusApiV1? _fromV2(Pointer<_SiglusApiV2> table) {
    if (table == nullptr) return null;
    final api = table.ref;
    final create = api.runtimeCreateWithSaveDir;
    if (!_valid(api.base, sizeOf<_SiglusApiV2>(), 2) || create == nullptr) {
      return null;
    }
    return CoreSiglusApiV1._(
      table.cast<_SiglusApiV1>(),
      create.asFunction<_CreateWithSaveDirDart>(),
    );
  }

  static bool _valid(_SiglusApiV1 api, int size, int version) =>
      api.structSize == size &&
      api.abiVersion == version &&
      api.magic == 0x53494731 &&
      api.probeProject != nullptr &&
      api.runtimeCreate != nullptr &&
      api.runtimeDestroy != nullptr &&
      api.runtimeStageWidth != nullptr &&
      api.runtimeStageHeight != nullptr &&
      api.runtimeSetExternalSurface != nullptr &&
      api.runtimeTick != nullptr &&
      api.runtimeInput != nullptr &&
      api.runtimeIsExitRequested != nullptr &&
      api.lastError != nullptr;

  String get lastError {
    final fn = _table.ref.lastError.asFunction<_ErrorDart>();
    final length = fn(nullptr, 0);
    if (length == 0 || length > 65536) return '';
    final buffer = calloc<Uint8>(length);
    try {
      fn(buffer, length);
      return String.fromCharCodes(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }

  bool probeProject(String path) {
    final nativePath = path.toNativeUtf8();
    try {
      return _table.ref.probeProject.asFunction<_ProbeDart>()(
            nativePath.cast<Char>(),
          ) ==
          1;
    } finally {
      calloc.free(nativePath);
    }
  }

  int createRuntime(String path, {int backend = 0, String? saveDir}) {
    final nativePath = path.toNativeUtf8();
    final create = _createWithSaveDir;
    final nativeSave = create != null && saveDir != null
        ? saveDir.toNativeUtf8()
        : nullptr;
    final handle = calloc<Uint64>();
    try {
      final status = create != null && nativeSave != nullptr
          ? create(
              nativePath.cast<Char>(),
              nativeSave.cast<Char>(),
              backend,
              handle,
            )
          : _table.ref.runtimeCreate.asFunction<_CreateDart>()(
              nativePath.cast<Char>(),
              backend,
              handle,
            );
      if (status != ok) {
        throw StateError('Siglus 创建失败 ($status): $lastError');
      }
      return handle.value;
    } finally {
      calloc.free(nativePath);
      calloc.free(nativeSave);
      calloc.free(handle);
    }
  }

  void destroyRuntime(int handle) =>
      _table.ref.runtimeDestroy.asFunction<_DestroyDart>()(handle);

  int stageWidth(int handle) =>
      _table.ref.runtimeStageWidth.asFunction<_StageDart>()(handle);

  int stageHeight(int handle) =>
      _table.ref.runtimeStageHeight.asFunction<_StageDart>()(handle);

  int setExternalSurface(
    int handle,
    int kind,
    Pointer<Void> ptr,
    int width,
    int height,
  ) => _table.ref.runtimeSetExternalSurface.asFunction<_SurfaceDart>()(
    handle,
    kind,
    ptr,
    width,
    height,
  );

  int input(int handle, int kind, int code, int x, int y, int value) => _table
      .ref
      .runtimeInput
      .asFunction<_InputDart>()(handle, kind, code, x, y, value);

  int tick(int handle, int deltaMs, int mode) =>
      _table.ref.runtimeTick.asFunction<_TickDart>()(
        handle,
        deltaMs.clamp(0, 1000),
        mode,
        nullptr,
        0,
        nullptr,
      );

  Uint8List? render(int handle, int deltaMs, int size) {
    if (size <= 0 || size > 256 * 1024 * 1024) return null;
    final bytes = calloc<Uint8>(size);
    final written = calloc<UintPtr>();
    try {
      final status = _table.ref.runtimeTick.asFunction<_TickDart>()(
        handle,
        deltaMs.clamp(0, 1000),
        tickReadback,
        bytes,
        size,
        written,
      );
      if (status != ok || written.value != size) {
        throw StateError('Siglus 帧回读失败 ($status): $lastError');
      }
      return Uint8List.fromList(bytes.asTypedList(size));
    } finally {
      calloc.free(bytes);
      calloc.free(written);
    }
  }

  bool isExitRequested(int handle) =>
      _table.ref.runtimeIsExitRequested.asFunction<_ExitDart>()(handle) == 1;
}

typedef _OutputActionNative = Int32 Function(Uint64);
typedef _OutputActionDart = int Function(int);
typedef _OutputSuspendNative = Int32 Function(Uint64, Int32);
typedef _OutputSuspendDart = int Function(int, int);
typedef _OutputVolumeNative = Int32 Function(Uint64, Float);
typedef _OutputVolumeDart = int Function(int, double);
typedef _OutputAndroidNative = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _OutputAndroidDart = int Function(Pointer<Void>, Pointer<Void>);
typedef _GetOutputNative =
    Pointer<_SiglusOutputApiV1> Function(Pointer<UintPtr>);
typedef _GetOutputDart = Pointer<_SiglusOutputApiV1> Function(Pointer<UintPtr>);

final class _SiglusOutputApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint64()
  external int magic;
  external Pointer<NativeFunction<_OutputActionNative>> start;
  external Pointer<NativeFunction<_OutputActionNative>> stop;
  external Pointer<NativeFunction<_OutputSuspendNative>> suspend;
  external Pointer<NativeFunction<_OutputVolumeNative>> volume;
  external Pointer<NativeFunction<_OutputAndroidNative>> initializeAndroid;
}

class CoreSiglusOutputV1 {
  CoreSiglusOutputV1._(this._table);
  final Pointer<_SiglusOutputApiV1> _table;

  static CoreSiglusOutputV1? tryLoad(DynamicLibrary library) {
    try {
      final get = library.lookupFunction<_GetOutputNative, _GetOutputDart>(
        'art3m1s_siglus_get_output_api_v1',
      );
      final size = calloc<UintPtr>();
      try {
        final table = get(size);
        return size.value == sizeOf<_SiglusOutputApiV1>() ? _from(table) : null;
      } finally {
        calloc.free(size);
      }
    } catch (_) {
      return null;
    }
  }

  static CoreSiglusOutputV1? _from(Pointer<_SiglusOutputApiV1> table) {
    if (table == nullptr) return null;
    final api = table.ref;
    if (api.structSize != sizeOf<_SiglusOutputApiV1>() ||
        api.abiVersion != 1 ||
        api.magic != 0x31564f534d334152 ||
        api.start == nullptr ||
        api.stop == nullptr ||
        api.suspend == nullptr ||
        api.volume == nullptr ||
        api.initializeAndroid == nullptr) {
      return null;
    }
    return CoreSiglusOutputV1._(table);
  }

  int start(int runtime) =>
      _table.ref.start.asFunction<_OutputActionDart>()(runtime);
  int stop(int runtime) =>
      _table.ref.stop.asFunction<_OutputActionDart>()(runtime);
  int suspend(int runtime, bool suspended) => _table.ref.suspend
      .asFunction<_OutputSuspendDart>()(runtime, suspended ? 1 : 0);
  int volume(int runtime, double volume) =>
      _table.ref.volume.asFunction<_OutputVolumeDart>()(runtime, volume);
  int initializeAndroid(int vm, int context) =>
      _table.ref.initializeAndroid.asFunction<_OutputAndroidDart>()(
        Pointer.fromAddress(vm),
        Pointer.fromAddress(context),
      );
}

final class _SiglusHostApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint64()
  external int magic;
  external Pointer<_SiglusApiV2> runtime;
  external Pointer<_SiglusAudioApiV1> audio;
  external Pointer<_SiglusDiagnosticsApiV1> diagnostics;
  external Pointer<_SiglusOutputApiV1> output;
}

typedef _GetHostApi = Pointer<_SiglusHostApiV1> Function(Pointer<UintPtr>);

typedef _SiglusSessionOp = Int32 Function(Uint64);
typedef _ReadDialog =
    Int32 Function(Uint64, Pointer<Uint8>, UintPtr, Pointer<UintPtr>);
typedef _SubmitDialog = Int32 Function(Uint64, Uint64, Int64);
typedef _SendText = Int32 Function(Uint64, Pointer<Uint8>, UintPtr);

final class _SiglusHostApiV2 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint64()
  external int magic;
  external Pointer<_SiglusHostApiV1> base;
  external Pointer<NativeFunction<_SiglusSessionOp>> enableDialogs;
  external Pointer<NativeFunction<_ReadDialog>> readDialog;
  external Pointer<NativeFunction<_SubmitDialog>> submitDialog;
  external Pointer<NativeFunction<_SendText>> sendText;
}

typedef _GetHostApiV2 = Pointer<_SiglusHostApiV2> Function(Pointer<UintPtr>);

final class CoreSiglusUi {
  CoreSiglusUi._(this._table);

  final Pointer<_SiglusHostApiV2> _table;

  int enableDialogs(int session) =>
      _table.ref.enableDialogs.asFunction<int Function(int)>()(session);

  Map<String, dynamic>? readDialog(int session) {
    final read = _table.ref.readDialog
        .asFunction<int Function(int, Pointer<Uint8>, int, Pointer<UintPtr>)>();
    final required = calloc<UintPtr>();
    try {
      if (read(session, nullptr, 0, required) != CoreSiglusApiV1.ok ||
          required.value == 0) {
        return null;
      }
      final capacity = required.value;
      final buffer = calloc<Uint8>(capacity);
      try {
        if (read(session, buffer, capacity, required) != CoreSiglusApiV1.ok ||
            required.value == 0 ||
            required.value > capacity) {
          return null;
        }
        return jsonDecode(utf8.decode(buffer.asTypedList(required.value)))
            as Map<String, dynamic>;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(required);
    }
  }

  int submitDialog(int session, int id, int value) => _table.ref.submitDialog
      .asFunction<int Function(int, int, int)>()(session, id, value);

  bool sendText(int session, String text) {
    final bytes = utf8.encode(text);
    if (bytes.isEmpty) return false;
    final buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return _table.ref.sendText
              .asFunction<int Function(int, Pointer<Uint8>, int)>()(
            session,
            buffer,
            bytes.length,
          ) ==
          1;
    } finally {
      calloc.free(buffer);
    }
  }
}

typedef _CreateFrameRuntime =
    Int32 Function(Pointer<Char>, Pointer<Char>, Pointer<Uint64>);
typedef _AcquireFrame = Int32 Function(Uint64, Pointer<Uint64>);
typedef _FrameView = Int32 Function(Uint64, Pointer<Void>);
typedef _TextureView = Int32 Function(Uint64, Uint32, Pointer<Void>);
typedef _ConfigurePresenter = Int32 Function(Uint64, Int32);

final class _SiglusFrameApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  external Pointer<NativeFunction<_CreateFrameRuntime>> createRuntime;
  external Pointer<NativeFunction<_AcquireFrame>> acquire;
  external Pointer<NativeFunction<_FrameView>> view;
  external Pointer<NativeFunction<_TextureView>> texture;
  external Pointer<NativeFunction<_SiglusSessionOp>> release;
  external Pointer<NativeFunction<_ConfigurePresenter>> configurePresenter;
  external Pointer<NativeFunction<_SiglusSessionOp>> presentLatest;
  external Pointer<NativeFunction<_ReadDialog>> readbackLatest;
}

final class _SiglusHostFramesV2 extends Struct {
  external _SiglusHostApiV2 base;
  external Pointer<_SiglusFrameApiV1> frames;
}

final class CoreSiglusFrames {
  CoreSiglusFrames._(this._table);

  final Pointer<_SiglusFrameApiV1> _table;
  static const noFrame = 1;

  int createRuntime(String project, String? saveDir, CoreSiglusApiV1 runtime) {
    final path = project.toNativeUtf8(allocator: calloc);
    final save = saveDir?.toNativeUtf8(allocator: calloc) ?? nullptr;
    final out = calloc<Uint64>();
    try {
      final status = _table.ref.createRuntime
          .asFunction<
            int Function(Pointer<Char>, Pointer<Char>, Pointer<Uint64>)
          >()(path.cast(), save.cast(), out);
      if (status != CoreSiglusApiV1.ok || out.value == 0) {
        throw StateError('Siglus 会话创建失败 ($status): ${runtime.lastError}');
      }
      return out.value;
    } finally {
      calloc.free(path);
      if (save != nullptr) calloc.free(save);
      calloc.free(out);
    }
  }

  int configurePresenter(int session, int backend) => _table
      .ref
      .configurePresenter
      .asFunction<int Function(int, int)>()(session, backend);

  int presentLatest(int session) =>
      _table.ref.presentLatest.asFunction<int Function(int)>()(session);

  Uint8List? readbackLatest(int session, int size, CoreSiglusApiV1 runtime) {
    if (size <= 0 || size > 256 * 1024 * 1024) return null;
    final buffer = calloc<Uint8>(size);
    final written = calloc<UintPtr>();
    try {
      final status = _table.ref.readbackLatest
          .asFunction<
            int Function(int, Pointer<Uint8>, int, Pointer<UintPtr>)
          >()(session, buffer, size, written);
      if (status == noFrame) return null;
      if (status != CoreSiglusApiV1.ok || written.value != size) {
        throw StateError('Siglus 帧回读失败 ($status): ${runtime.lastError}');
      }
      return Uint8List.fromList(buffer.asTypedList(size));
    } finally {
      calloc.free(buffer);
      calloc.free(written);
    }
  }
}

final class CoreSiglusHostV1 {
  CoreSiglusHostV1._(
    this.runtime,
    this.audio,
    this.diagnostics,
    this.output,
    this.ui,
    this.frames,
  );

  final CoreSiglusApiV1 runtime;
  final CoreSiglusAudioV1 audio;
  final CoreSiglusDiagnosticsV1 diagnostics;
  final CoreSiglusOutputV1 output;
  final CoreSiglusUi? ui;
  final CoreSiglusFrames? frames;

  /// An older Core can expose each table through its original entry point.
  static CoreSiglusHostV1? tryLoad(DynamicLibrary library) {
    const v1 = 'art3m1s_siglus_get_host_api_v1';
    const v2 = 'art3m1s_siglus_get_host_api_v2';
    final size = calloc<UintPtr>();
    try {
      final Pointer<_SiglusHostApiV1> pointer;
      CoreSiglusUi? ui;
      CoreSiglusFrames? frames;
      if (library.providesSymbol(v2)) {
        final extended = library.lookupFunction<_GetHostApiV2, _GetHostApiV2>(
          v2,
        )(size);
        if (extended == nullptr || size.value < sizeOf<_SiglusHostApiV2>()) {
          throw StateError('Siglus Host API v2 table size mismatch');
        }
        final table = extended.ref;
        if (table.structSize != size.value ||
            table.abiVersion != 2 ||
            table.magic != 0x325648534d334152 ||
            table.enableDialogs == nullptr ||
            table.readDialog == nullptr ||
            table.submitDialog == nullptr ||
            table.sendText == nullptr) {
          throw StateError('Siglus Host API v2 header mismatch');
        }
        pointer = table.base;
        ui = CoreSiglusUi._(extended);
        if (size.value >= sizeOf<_SiglusHostFramesV2>()) {
          final frameTable = extended.cast<_SiglusHostFramesV2>().ref.frames;
          if (frameTable != nullptr) {
            final api = frameTable.ref;
            if (api.structSize < sizeOf<_SiglusFrameApiV1>() ||
                api.abiVersion != 1 ||
                api.createRuntime == nullptr ||
                api.configurePresenter == nullptr ||
                api.presentLatest == nullptr ||
                api.readbackLatest == nullptr) {
              throw StateError('Siglus frame API header mismatch');
            }
            frames = CoreSiglusFrames._(frameTable);
          }
        }
      } else {
        if (!library.providesSymbol(v1)) return null;
        pointer = library.lookupFunction<_GetHostApi, _GetHostApi>(v1)(size);
        if (size.value != sizeOf<_SiglusHostApiV1>()) {
          throw StateError('Siglus Host API v1 table size mismatch');
        }
      }
      if (pointer == nullptr) {
        throw StateError('Siglus Host API base table missing');
      }
      final api = pointer.ref;
      if (api.structSize != sizeOf<_SiglusHostApiV1>() ||
          api.abiVersion != 1 ||
          api.magic != 0x315648534d334152) {
        throw StateError('Siglus Host API header mismatch');
      }
      final runtime = CoreSiglusApiV1._fromV2(api.runtime);
      final audio = CoreSiglusAudioV1._from(api.audio);
      final diagnostics = CoreSiglusDiagnosticsV1._from(api.diagnostics);
      final output = CoreSiglusOutputV1._from(api.output);
      if (runtime == null ||
          audio == null ||
          diagnostics == null ||
          output == null) {
        throw StateError('Siglus Host API contains an incompatible table');
      }
      return CoreSiglusHostV1._(
        runtime,
        audio,
        diagnostics,
        output,
        ui,
        frames,
      );
    } finally {
      calloc.free(size);
    }
  }
}
