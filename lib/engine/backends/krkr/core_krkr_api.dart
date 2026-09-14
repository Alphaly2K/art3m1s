import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int art3m1sKrkrStatusOk = 0;
const int art3m1sKrkrStatusNoFrame = 1;
const int art3m1sKrkrStatusNoCommand = 2;
const int art3m1sKrkrStatusUnsupported = -4;

const int art3m1sKrkrInputKey = 1;
const int art3m1sKrkrInputText = 2;
const int art3m1sKrkrInputPointerMove = 3;
const int art3m1sKrkrInputPointerButton = 4;
const int art3m1sKrkrInputWheel = 5;
const int art3m1sKrkrInputFocus = 6;
const int art3m1sKrkrInputQuit = 7;

const int art3m1sKrkrInputPhaseDown = 0;
const int art3m1sKrkrInputPhaseUp = 1;
const int art3m1sKrkrInputPhaseRepeat = 2;
const int art3m1sKrkrInputPhaseMove = 3;

const int art3m1sKrkrPointerLeft = 1 << 0;
const int art3m1sKrkrPointerRight = 1 << 1;
const int art3m1sKrkrPointerMiddle = 1 << 2;

const int art3m1sKrkrAudioCreateStream = 1;
const int art3m1sKrkrAudioSubmitPcm = 2;
const int art3m1sKrkrAudioPlay = 3;
const int art3m1sKrkrAudioPause = 4;
const int art3m1sKrkrAudioStop = 5;
const int art3m1sKrkrAudioSetParams = 6;
const int art3m1sKrkrAudioDestroyStream = 7;
const int art3m1sKrkrAudioMasterVolume = 8;

const int art3m1sKrkrAudioFormatI16 = 1;
const int art3m1sKrkrAudioFormatF32 = 2;
const int art3m1sKrkrAudioFormatI8 = 3;
const int art3m1sKrkrAudioFormatI24 = 4;
const int art3m1sKrkrAudioFormatI32 = 5;

typedef _GetApiNative = Pointer<_Art3m1sKrkrApiV1> Function(Pointer<UintPtr>);
typedef _GetApiDart = Pointer<_Art3m1sKrkrApiV1> Function(Pointer<UintPtr>);
typedef _ProbeProjectNative = Int32 Function(
  Pointer<Char>,
  Pointer<_KrkrProbeV1>,
);
typedef _ProbeProjectDart = int Function(Pointer<Char>, Pointer<_KrkrProbeV1>);
typedef _RuntimeCreateNative = Int32 Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<_KrkrRuntimeConfigV1>,
  Pointer<Uint64>,
);
typedef _RuntimeCreateDart = int Function(
  Pointer<Char>,
  Pointer<Char>,
  Pointer<_KrkrRuntimeConfigV1>,
  Pointer<Uint64>,
);
typedef _RuntimeDestroyNative = Void Function(Uint64);
typedef _RuntimeDestroyDart = void Function(int);
typedef _RuntimeStageNative = Uint32 Function(Uint64);
typedef _RuntimeStageDart = int Function(int);
typedef _RuntimePushInputNative = Int32 Function(
  Uint64,
  Pointer<_KrkrInputEventV1>,
  UintPtr,
);
typedef _RuntimePushInputDart = int Function(
  int,
  Pointer<_KrkrInputEventV1>,
  int,
);
typedef _RuntimeTickNative = Int32 Function(Uint64);
typedef _RuntimeTickDart = int Function(int);
typedef _RuntimeAcquireFrameNative = Int32 Function(
  Uint64,
  Pointer<_KrkrFrameV1>,
);
typedef _RuntimeAcquireFrameDart = int Function(int, Pointer<_KrkrFrameV1>);
typedef _RuntimeReleaseFrameNative = Int32 Function(Uint64, Uint64);
typedef _RuntimeReleaseFrameDart = int Function(int, int);
typedef _RuntimePollAudioCommandNative = Int32 Function(
  Uint64,
  Pointer<_KrkrAudioCommandV1>,
);
typedef _RuntimePollAudioCommandDart = int Function(
  int,
  Pointer<_KrkrAudioCommandV1>,
);
typedef _RuntimeSubmitAudioConsumedNative = Int32 Function(
  Uint64,
  Pointer<_KrkrAudioConsumedV1>,
);
typedef _RuntimeSubmitAudioConsumedDart = int Function(
  int,
  Pointer<_KrkrAudioConsumedV1>,
);
typedef _RuntimeIsExitRequestedNative = Int32 Function(Uint64);
typedef _RuntimeIsExitRequestedDart = int Function(int);
typedef _RuntimeSetExternalSurfaceNative = Int32 Function(
  Uint64,
  Int32,
  Pointer<Void>,
  Uint32,
  Uint32,
);
typedef _RuntimeSetExternalSurfaceDart = int Function(
  int,
  int,
  Pointer<Void>,
  int,
  int,
);

final class _KrkrProbeV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int flags;
  @Uint32()
  external int preferredKind;
  @Uint32()
  external int hasDataXp3;
  @Uint32()
  external int rootXp3Count;
  @Uint32()
  external int hasStartupTjs;
  @Uint32()
  external int hasPatchTjs;
  @Uint32()
  external int hasSystemInitializeTjs;
  @Array(4)
  external Array<Uint64> reserved;
}

final class _KrkrRuntimeConfigV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int flags;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int audioSampleRate;
  @Uint32()
  external int audioChannels;
  @Array(4)
  external Array<Uint64> reserved;
}

final class _KrkrInputEventV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int kind;
  @Uint32()
  external int code;
  @Uint32()
  external int phase;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int value;
  @Uint32()
  external int modifiers;
  @Uint64()
  external int id;
}

final class _KrkrFrameV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int format;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int stride;
  @Uint32()
  external int flags;
  @Uint64()
  external int frameId;
  @Uint64()
  external int generation;
  external Pointer<Uint8> pixels;
  @UintPtr()
  external int pixelsLength;
  @Array(2)
  external Array<Uint64> reserved;
}

final class _KrkrAudioCommandV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int kind;
  @Uint32()
  external int streamId;
  @Uint32()
  external int sampleFormat;
  @Uint32()
  external int sampleRate;
  @Uint32()
  external int channels;
  @Uint64()
  external int sampleCount;
  @Float()
  external double volume;
  @Float()
  external double pan;
  external Pointer<Uint8> payload;
  @UintPtr()
  external int payloadSize;
  @Array(2)
  external Array<Uint64> reserved;
}

final class _KrkrAudioConsumedV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int streamId;
  @Uint64()
  external int consumedSamples;
  @Uint64()
  external int generation;
  @Array(2)
  external Array<Uint64> reserved;
}

final class _Art3m1sKrkrApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint64()
  external int magic;
  external Pointer<NativeFunction<_ProbeProjectNative>> probeProject;
  external Pointer<NativeFunction<_RuntimeCreateNative>> runtimeCreate;
  external Pointer<NativeFunction<_RuntimeDestroyNative>> runtimeDestroy;
  external Pointer<NativeFunction<_RuntimeStageNative>> runtimeStageWidth;
  external Pointer<NativeFunction<_RuntimeStageNative>> runtimeStageHeight;
  external Pointer<NativeFunction<_RuntimeStageNative>> runtimePixelBufferSize;
  external Pointer<NativeFunction<_RuntimePushInputNative>> runtimePushInput;
  external Pointer<NativeFunction<_RuntimeTickNative>> runtimeTick;
  external Pointer<NativeFunction<_RuntimeAcquireFrameNative>>
  runtimeAcquireFrame;
  external Pointer<NativeFunction<_RuntimeReleaseFrameNative>>
  runtimeReleaseFrame;
  external Pointer<NativeFunction<_RuntimePollAudioCommandNative>>
  runtimePollAudioCommand;
  external Pointer<NativeFunction<_RuntimeSubmitAudioConsumedNative>>
  runtimeSubmitAudioConsumed;
  external Pointer<NativeFunction<_RuntimeIsExitRequestedNative>>
  runtimeIsExitRequested;
  external Pointer<NativeFunction<_RuntimeSetExternalSurfaceNative>>
  runtimeSetExternalSurface;
}

class KrkrCoreProbe {
  const KrkrCoreProbe({required this.preferredKind});
  final int preferredKind;
  bool get isKrkr => preferredKind != 0;
}

class KrkrCoreInputEvent {
  const KrkrCoreInputEvent({
    required this.kind,
    this.code = 0,
    this.phase = 0,
    this.x = 0,
    this.y = 0,
    this.value = 0,
    this.modifiers = 0,
    this.id = 0,
  });

  final int kind;
  final int code;
  final int phase;
  final int x;
  final int y;
  final int value;
  final int modifiers;
  final int id;
}

class KrkrCoreFrame {
  const KrkrCoreFrame({
    required this.width,
    required this.height,
    required this.generation,
    required this.pixels,
  });
  final int width;
  final int height;
  final int generation;
  final Uint8List pixels;
}

class KrkrCoreAudioCommand {
  const KrkrCoreAudioCommand({
    required this.kind,
    required this.streamId,
    required this.sampleFormat,
    required this.sampleRate,
    required this.channels,
    required this.sampleCount,
    required this.volume,
    required this.pan,
    required this.payload,
  });
  final int kind;
  final int streamId;
  final int sampleFormat;
  final int sampleRate;
  final int channels;
  final int sampleCount;
  final double volume;
  final double pan;
  final Uint8List payload;
}

class CoreKrkrApiV1 {
  CoreKrkrApiV1._(this._pointer);

  static const int _abiVersion = 1;
  static const int _abiMagic = 0x31564b524d334152; // "RA3MKRV1"
  final Pointer<_Art3m1sKrkrApiV1> _pointer;
  int _lastStatus = art3m1sKrkrStatusOk;

  int get lastStatus => _lastStatus;
  static int get apiTableSize => sizeOf<_Art3m1sKrkrApiV1>();
  static int get probeSize => sizeOf<_KrkrProbeV1>();
  static int get runtimeConfigSize => sizeOf<_KrkrRuntimeConfigV1>();
  static int get inputEventSize => sizeOf<_KrkrInputEventV1>();
  static int get frameSize => sizeOf<_KrkrFrameV1>();
  static int get audioCommandSize => sizeOf<_KrkrAudioCommandV1>();
  static int get audioConsumedSize => sizeOf<_KrkrAudioConsumedV1>();

  static CoreKrkrApiV1? tryLoad(DynamicLibrary library) {
    final _GetApiDart getApi;
    try {
      getApi = library.lookupFunction<_GetApiNative, _GetApiDart>(
        'art3m1s_krkr_get_api_v1',
      );
    } catch (_) {
      return null;
    }
    final size = calloc<UintPtr>();
    try {
      final pointer = getApi(size);
      if (pointer == nullptr) return null;
      final table = pointer.ref;
      if (table.structSize != sizeOf<_Art3m1sKrkrApiV1>() ||
          size.value != sizeOf<_Art3m1sKrkrApiV1>() ||
          table.abiVersion != _abiVersion ||
          table.magic != _abiMagic ||
          table.probeProject == nullptr ||
          table.runtimeCreate == nullptr ||
          table.runtimeDestroy == nullptr ||
          table.runtimeStageWidth == nullptr ||
          table.runtimeStageHeight == nullptr ||
          table.runtimePixelBufferSize == nullptr ||
          table.runtimePushInput == nullptr ||
          table.runtimeTick == nullptr ||
          table.runtimeAcquireFrame == nullptr ||
          table.runtimeReleaseFrame == nullptr ||
          table.runtimePollAudioCommand == nullptr ||
          table.runtimeSubmitAudioConsumed == nullptr ||
          table.runtimeIsExitRequested == nullptr ||
          table.runtimeSetExternalSurface == nullptr) {
        return null;
      }
      return CoreKrkrApiV1._(pointer);
    } finally {
      calloc.free(size);
    }
  }

  KrkrCoreProbe? probeProject(String path) {
    final nativePath = path.toNativeUtf8();
    final probe = calloc<_KrkrProbeV1>();
    try {
      probe.ref.structSize = sizeOf<_KrkrProbeV1>();
      final status = _pointer.ref.probeProject.asFunction<_ProbeProjectDart>()(
        nativePath.cast<Char>(),
        probe,
      );
      _lastStatus = status;
      if (status != art3m1sKrkrStatusOk) return null;
      return KrkrCoreProbe(preferredKind: probe.ref.preferredKind);
    } finally {
      calloc.free(probe);
      malloc.free(nativePath);
    }
  }

  int createRuntime({
    required String gameRoot,
    String? saveRoot,
    required int width,
    required int height,
    int backend = 0,
  }) {
    final nativeGameRoot = gameRoot.toNativeUtf8();
    final nativeSaveRoot = saveRoot?.toNativeUtf8();
    final config = calloc<_KrkrRuntimeConfigV1>();
    final output = calloc<Uint64>();
    try {
      config.ref
        ..structSize = sizeOf<_KrkrRuntimeConfigV1>()
        ..flags = backend & 0xff
        ..width = width
        ..height = height
        ..audioSampleRate = 48000
        ..audioChannels = 2;
      final status =
          _pointer.ref.runtimeCreate.asFunction<_RuntimeCreateDart>()(
            nativeGameRoot.cast<Char>(),
            nativeSaveRoot?.cast<Char>() ?? nullptr.cast<Char>(),
            config,
            output,
          );
      _lastStatus = status;
      return status == art3m1sKrkrStatusOk ? output.value : 0;
    } finally {
      calloc.free(output);
      calloc.free(config);
      if (nativeSaveRoot != null) malloc.free(nativeSaveRoot);
      malloc.free(nativeGameRoot);
    }
  }

  void destroyRuntime(int runtime) {
    _pointer.ref.runtimeDestroy.asFunction<_RuntimeDestroyDart>()(runtime);
  }

  int stageWidth(int runtime) =>
      _pointer.ref.runtimeStageWidth.asFunction<_RuntimeStageDart>()(runtime);
  int stageHeight(int runtime) =>
      _pointer.ref.runtimeStageHeight.asFunction<_RuntimeStageDart>()(runtime);

  int tick(int runtime) {
    _lastStatus = _pointer.ref.runtimeTick.asFunction<_RuntimeTickDart>()(
      runtime,
    );
    return _lastStatus;
  }

  int setExternalSurface(
    int runtime,
    int kind,
    Pointer<Void> handle,
    int width,
    int height,
  ) {
    _lastStatus =
        _pointer.ref.runtimeSetExternalSurface
            .asFunction<_RuntimeSetExternalSurfaceDart>()(
          runtime,
          kind,
          handle,
          width,
          height,
        );
    return _lastStatus;
  }

  int clearExternalSurface(int runtime) =>
      setExternalSurface(runtime, 0, nullptr, 0, 0);

  int pushInput(int runtime, List<KrkrCoreInputEvent> events) {
    if (events.isEmpty) return art3m1sKrkrStatusOk;
    final native = calloc<_KrkrInputEventV1>(events.length);
    try {
      for (var index = 0; index < events.length; index++) {
        final source = events[index];
        native[index]
          ..structSize = sizeOf<_KrkrInputEventV1>()
          ..kind = source.kind
          ..code = source.code
          ..phase = source.phase
          ..x = source.x
          ..y = source.y
          ..value = source.value
          ..modifiers = source.modifiers
          ..id = source.id;
      }
      _lastStatus = _pointer.ref.runtimePushInput
          .asFunction<_RuntimePushInputDart>()(runtime, native, events.length);
      return _lastStatus;
    } finally {
      calloc.free(native);
    }
  }

  KrkrCoreFrame? acquireFrame(int runtime) {
    final frame = calloc<_KrkrFrameV1>();
    try {
      frame.ref.structSize = sizeOf<_KrkrFrameV1>();
      final status = _pointer.ref.runtimeAcquireFrame
          .asFunction<_RuntimeAcquireFrameDart>()(runtime, frame);
      _lastStatus = status;
      if (status == art3m1sKrkrStatusNoFrame) return null;
      if (status != art3m1sKrkrStatusOk || frame.ref.pixels == nullptr) {
        return null;
      }
      final width = frame.ref.width;
      final height = frame.ref.height;
      final stride = frame.ref.stride;
      final rowBytes = width * 4;
      final required = stride * height;
      if (width <= 0 ||
          height <= 0 ||
          stride < rowBytes ||
          frame.ref.pixelsLength < required) {
        return null;
      }
      final borrowed = frame.ref.pixels.asTypedList(required);
      final pixels = Uint8List(rowBytes * height);
      for (var row = 0; row < height; row++) {
        pixels.setRange(
          row * rowBytes,
          (row + 1) * rowBytes,
          borrowed,
          row * stride,
        );
      }
      return KrkrCoreFrame(
        width: width,
        height: height,
        generation: frame.ref.generation,
        pixels: pixels,
      );
    } finally {
      if (frame.ref.frameId != 0) {
        _pointer.ref.runtimeReleaseFrame.asFunction<_RuntimeReleaseFrameDart>()(
          runtime,
          frame.ref.frameId,
        );
      }
      calloc.free(frame);
    }
  }

  KrkrCoreAudioCommand? pollAudioCommand(int runtime) {
    final command = calloc<_KrkrAudioCommandV1>();
    try {
      command.ref.structSize = sizeOf<_KrkrAudioCommandV1>();
      final status = _pointer.ref.runtimePollAudioCommand
          .asFunction<_RuntimePollAudioCommandDart>()(runtime, command);
      _lastStatus = status;
      if (status == art3m1sKrkrStatusNoCommand) return null;
      if (status != art3m1sKrkrStatusOk) return null;
      final payload =
          command.ref.payload == nullptr || command.ref.payloadSize == 0
          ? Uint8List(0)
          : Uint8List.fromList(
              command.ref.payload.asTypedList(command.ref.payloadSize),
            );
      return KrkrCoreAudioCommand(
        kind: command.ref.kind,
        streamId: command.ref.streamId,
        sampleFormat: command.ref.sampleFormat,
        sampleRate: command.ref.sampleRate,
        channels: command.ref.channels,
        sampleCount: command.ref.sampleCount,
        volume: command.ref.volume,
        pan: command.ref.pan,
        payload: payload,
      );
    } finally {
      calloc.free(command);
    }
  }

  int submitAudioConsumed(
    int runtime, {
    required int streamId,
    required int consumedSamples,
  }) {
    final consumed = calloc<_KrkrAudioConsumedV1>();
    try {
      consumed.ref
        ..structSize = sizeOf<_KrkrAudioConsumedV1>()
        ..streamId = streamId
        ..consumedSamples = consumedSamples;
      _lastStatus = _pointer.ref.runtimeSubmitAudioConsumed
          .asFunction<_RuntimeSubmitAudioConsumedDart>()(runtime, consumed);
      return _lastStatus;
    } finally {
      calloc.free(consumed);
    }
  }

  bool isExitRequested(int runtime) =>
      _pointer.ref.runtimeIsExitRequested
          .asFunction<_RuntimeIsExitRequestedDart>()(runtime) !=
      0;
}
