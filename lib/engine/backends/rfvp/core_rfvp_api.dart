import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _GetApiNative = Pointer<_Art3m1sRfvpApiV1> Function(Pointer<UintPtr>);
typedef _GetApi = Pointer<_Art3m1sRfvpApiV1> Function(Pointer<UintPtr>);

typedef _RuntimeCreateNative =
    Int32 Function(
      Pointer<Uint8>,
      UintPtr,
      Pointer<Uint8>,
      UintPtr,
      Uint32,
      Uint32,
      Int32,
      Uint32,
      Pointer<Uint64>,
    );
typedef _RuntimeCreateDart =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      int,
      int,
      int,
      int,
      Pointer<Uint64>,
    );
typedef _RuntimeDestroyNative = Void Function(Uint64);
typedef _RuntimeDestroyDart = void Function(int);
typedef _RuntimeStepNative = Int32 Function(Uint64, Uint32);
typedef _RuntimeStepDart = int Function(int, int);
typedef _RuntimeIsExitRequestedNative = Int32 Function(Uint64);
typedef _RuntimeIsExitRequestedDart = int Function(int);
typedef _RuntimeStageNative = Uint32 Function(Uint64);
typedef _RuntimeStageDart = int Function(int);
typedef _RuntimeCapabilitiesNative = Uint64 Function(Uint64);
typedef _RuntimeCapabilitiesDart = int Function(int);
typedef _RuntimePixelBufferSizeNative = Uint32 Function(Uint64);
typedef _RuntimePixelBufferSizeDart = int Function(int);
typedef _RuntimeFeedInputNative =
    Int32 Function(Uint64, Pointer<_InputEventV1>, UintPtr);
typedef _RuntimeFeedInputDart = int Function(int, Pointer<_InputEventV1>, int);
typedef _RuntimePollAudioCommandNative =
    Int32 Function(Uint64, Pointer<_AudioCommandV1>);
typedef _RuntimePollAudioCommandDart =
    int Function(int, Pointer<_AudioCommandV1>);
typedef _RuntimeSetExternalSurfaceNative =
    Int32 Function(Uint64, Int32, Pointer<Void>, Uint32, Uint32);
typedef _RuntimeSetExternalSurfaceDart =
    int Function(int, int, Pointer<Void>, int, int);
typedef _RuntimeClearExternalSurfaceNative = Void Function(Uint64);
typedef _RuntimeClearExternalSurfaceDart = void Function(int);
typedef _RuntimeAdvanceAndPresentNative = Int32 Function(Uint64, Uint32);
typedef _RuntimeAdvanceAndPresentDart = int Function(int, int);
typedef _RuntimeAdvanceAndRenderNative =
    Uint32 Function(Uint64, Uint32, Pointer<Uint8>, Uint32);
typedef _RuntimeAdvanceAndRenderDart =
    int Function(int, int, Pointer<Uint8>, int);
typedef RfvpLogCallbackNative =
    Void Function(Uint32, Pointer<Uint8>, UintPtr, Pointer<Void>);
typedef RfvpLogCallbackDart =
    void Function(int, Pointer<Uint8>, int, Pointer<Void>);
typedef _RuntimeSetLogCallbackNative =
    Void Function(
      Pointer<NativeFunction<RfvpLogCallbackNative>>,
      Pointer<Void>,
    );
typedef _RuntimeSetLogCallbackDart =
    void Function(
      Pointer<NativeFunction<RfvpLogCallbackNative>>,
      Pointer<Void>,
    );

const int art3m1sRfvpStatusOk = 0;
const int art3m1sRfvpStatusNoFrame = 1;
const int art3m1sRfvpStatusNoCommand = 2;
const int art3m1sRfvpStatusInvalidArgument = -1;
const int art3m1sRfvpStatusInvalidHandle = -2;
const int art3m1sRfvpStatusEngine = -3;
const int art3m1sRfvpStatusUnsupported = -4;
const int art3m1sRfvpStatusOutOfMemory = -5;

const int art3m1sRfvpNlsShiftJis = 1;
const int art3m1sRfvpNlsGbk = 2;
const int art3m1sRfvpNlsUtf8 = 3;

const int art3m1sRfvpInputKey = 1;
const int art3m1sRfvpInputText = 2;
const int art3m1sRfvpInputPointerMove = 3;
const int art3m1sRfvpInputPointerButton = 4;
const int art3m1sRfvpInputWheel = 5;
const int art3m1sRfvpInputTouch = 6;
const int art3m1sRfvpInputFocus = 7;
const int art3m1sRfvpInputQuit = 8;

const int art3m1sRfvpInputPhaseDown = 0;
const int art3m1sRfvpInputPhaseUp = 1;
const int art3m1sRfvpInputPhaseRepeat = 2;
const int art3m1sRfvpInputPhaseMove = 3;

const int art3m1sRfvpPointerLeft = 1 << 0;
const int art3m1sRfvpPointerRight = 1 << 1;
const int art3m1sRfvpPointerMiddle = 1 << 2;

const int art3m1sRfvpAudioLoadEncoded = 1;
const int art3m1sRfvpAudioCreateStream = 2;
const int art3m1sRfvpAudioSubmitI16 = 3;
const int art3m1sRfvpAudioSubmitF32 = 4;
const int art3m1sRfvpAudioPlay = 5;
const int art3m1sRfvpAudioStop = 6;
const int art3m1sRfvpAudioPause = 7;
const int art3m1sRfvpAudioResume = 8;
const int art3m1sRfvpAudioSetParams = 9;
const int art3m1sRfvpAudioDestroyStream = 10;
const int art3m1sRfvpAudioMasterVolume = 11;

final class _InputEventV1 extends Struct {
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

final class _AudioCommandV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int kind;

  @Uint32()
  external int streamId;

  @Uint32()
  external int sampleFormat;

  @Uint32()
  external int encodedKind;

  @Uint32()
  external int sampleRate;

  @Uint32()
  external int channels;

  @Uint32()
  external int repeat;

  @Uint32()
  external int fadeMs;

  @Float()
  external double volume;

  @Float()
  external double pan;

  @UintPtr()
  external int sampleCount;

  external Pointer<Uint8> payload;

  @UintPtr()
  external int payloadSize;

  @Array(2)
  external Array<Uint64> reserved;
}

final class _Art3m1sRfvpApiV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int abiVersion;

  @Uint64()
  external int magic;

  external Pointer<NativeFunction<_RuntimeCreateNative>> runtimeCreate;
  external Pointer<NativeFunction<_RuntimeDestroyNative>> runtimeDestroy;
  external Pointer<NativeFunction<_RuntimeStepNative>> runtimeStep;
  external Pointer<NativeFunction<_RuntimeIsExitRequestedNative>>
  runtimeIsExitRequested;
  external Pointer<NativeFunction<_RuntimeStageNative>> runtimeStageWidth;
  external Pointer<NativeFunction<_RuntimeStageNative>> runtimeStageHeight;
  external Pointer<NativeFunction<_RuntimeCapabilitiesNative>>
  runtimeCapabilities;
  external Pointer<NativeFunction<_RuntimePixelBufferSizeNative>>
  runtimePixelBufferSize;
  external Pointer<NativeFunction<_RuntimeFeedInputNative>> runtimeFeedInput;
  external Pointer<NativeFunction<_RuntimePollAudioCommandNative>>
  runtimePollAudioCommand;
  external Pointer<NativeFunction<_RuntimeSetExternalSurfaceNative>>
  runtimeSetExternalSurface;
  external Pointer<NativeFunction<_RuntimeClearExternalSurfaceNative>>
  runtimeClearExternalSurface;
  external Pointer<NativeFunction<_RuntimeAdvanceAndPresentNative>>
  runtimeAdvanceAndPresent;
  external Pointer<NativeFunction<_RuntimeAdvanceAndRenderNative>>
  runtimeAdvanceAndRender;
  external Pointer<NativeFunction<_RuntimeSetLogCallbackNative>>
  runtimeSetLogCallback;
}

class RfvpCoreInputEvent {
  const RfvpCoreInputEvent({
    required this.kind,
    required this.code,
    required this.phase,
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

class RfvpCoreAudioCommand {
  const RfvpCoreAudioCommand({
    required this.kind,
    required this.streamId,
    required this.sampleFormat,
    required this.encodedKind,
    required this.sampleRate,
    required this.channels,
    required this.repeat,
    required this.fadeMs,
    required this.volume,
    required this.pan,
    required this.sampleCount,
    required this.payload,
  });

  final int kind;
  final int streamId;
  final int sampleFormat;
  final int encodedKind;
  final int sampleRate;
  final int channels;
  final bool repeat;
  final int fadeMs;
  final double volume;
  final double pan;
  final int sampleCount;
  final Uint8List payload;
}

class CoreRfvpApiV1 {
  CoreRfvpApiV1._(this._pointer);

  static const int _abiVersion = 1;
  static const int _abiMagic = 0x315646524d334152; // "RA3MRFV1"

  final Pointer<_Art3m1sRfvpApiV1> _pointer;
  int _lastStatus = art3m1sRfvpStatusOk;

  int get lastStatus => _lastStatus;

  static int get apiTableSize => sizeOf<_Art3m1sRfvpApiV1>();
  static int get inputEventSize => sizeOf<_InputEventV1>();
  static int get audioCommandSize => sizeOf<_AudioCommandV1>();

  static CoreRfvpApiV1? tryLoad(DynamicLibrary library) {
    final _GetApi getApi;
    try {
      getApi = library.lookupFunction<_GetApiNative, _GetApi>(
        'art3m1s_rfvp_get_api_v1',
      );
    } catch (_) {
      return null;
    }
    final size = calloc<UintPtr>();
    try {
      final pointer = getApi(size);
      if (pointer == nullptr) return null;
      final ref = pointer.ref;
      if (ref.abiVersion != _abiVersion || ref.magic != _abiMagic) return null;
      if (ref.structSize < sizeOf<_Art3m1sRfvpApiV1>()) return null;
      if (size.value < sizeOf<_Art3m1sRfvpApiV1>()) return null;
      return CoreRfvpApiV1._(pointer);
    } finally {
      calloc.free(size);
    }
  }

  int createRuntime({
    required String gameRoot,
    String? saveRoot,
    required int width,
    required int height,
    required int backend,
    int nls = art3m1sRfvpNlsShiftJis,
  }) {
    final nativeRoot = gameRoot.toNativeUtf8();
    final nativeSave = saveRoot?.toNativeUtf8();
    final out = calloc<Uint64>();
    try {
      final status =
          _pointer.ref.runtimeCreate.asFunction<_RuntimeCreateDart>()(
            nativeRoot.cast<Uint8>(),
            nativeRoot.length,
            nativeSave == null ? nullptr : nativeSave.cast<Uint8>(),
            nativeSave?.length ?? 0,
            width,
            height,
            backend,
            nls,
            out,
          );
      _lastStatus = status;
      if (status != art3m1sRfvpStatusOk) return 0;
      return out.value;
    } finally {
      calloc.free(out);
      if (nativeSave != null) malloc.free(nativeSave);
      malloc.free(nativeRoot);
    }
  }

  void destroyRuntime(int runtime) {
    if (runtime <= 0) return;
    _pointer.ref.runtimeDestroy.asFunction<_RuntimeDestroyDart>()(runtime);
  }

  int step(int runtime, int deltaMs) {
    final status = _pointer.ref.runtimeStep.asFunction<_RuntimeStepDart>()(
      runtime,
      deltaMs,
    );
    _lastStatus = status;
    return status;
  }

  bool isExitRequested(int runtime) {
    return _pointer.ref.runtimeIsExitRequested
            .asFunction<_RuntimeIsExitRequestedDart>()(runtime) !=
        0;
  }

  int stageWidth(int runtime) =>
      _pointer.ref.runtimeStageWidth.asFunction<_RuntimeStageDart>()(runtime);

  int stageHeight(int runtime) =>
      _pointer.ref.runtimeStageHeight.asFunction<_RuntimeStageDart>()(runtime);

  int capabilities(int runtime) => _pointer.ref.runtimeCapabilities
      .asFunction<_RuntimeCapabilitiesDart>()(runtime);

  int pixelBufferSize(int runtime) => _pointer.ref.runtimePixelBufferSize
      .asFunction<_RuntimePixelBufferSizeDart>()(runtime);

  void setLogCallback(
    Pointer<NativeFunction<RfvpLogCallbackNative>> callback,
    Pointer<Void> userData,
  ) {
    _pointer.ref.runtimeSetLogCallback.asFunction<_RuntimeSetLogCallbackDart>()(
      callback,
      userData,
    );
  }

  int feedInput(int runtime, List<RfvpCoreInputEvent> events) {
    if (events.isEmpty) return art3m1sRfvpStatusOk;
    final native = calloc<_InputEventV1>(events.length);
    try {
      for (var index = 0; index < events.length; index++) {
        final event = events[index];
        native[index]
          ..structSize = sizeOf<_InputEventV1>()
          ..kind = event.kind
          ..code = event.code
          ..phase = event.phase
          ..x = event.x
          ..y = event.y
          ..value = event.value
          ..modifiers = event.modifiers
          ..id = event.id;
      }
      final status = _pointer.ref.runtimeFeedInput
          .asFunction<_RuntimeFeedInputDart>()(runtime, native, events.length);
      _lastStatus = status;
      return status;
    } finally {
      calloc.free(native);
    }
  }

  RfvpCoreAudioCommand? pollAudioCommand(int runtime) {
    final command = calloc<_AudioCommandV1>();
    try {
      final status = _pointer.ref.runtimePollAudioCommand
          .asFunction<_RuntimePollAudioCommandDart>()(runtime, command);
      _lastStatus = status;
      if (status == art3m1sRfvpStatusNoCommand) return null;
      if (status != art3m1sRfvpStatusOk) return null;
      final ref = command.ref;
      final payload = ref.payloadSize == 0
          ? Uint8List(0)
          : Uint8List.fromList(ref.payload.asTypedList(ref.payloadSize));
      return RfvpCoreAudioCommand(
        kind: ref.kind,
        streamId: ref.streamId,
        sampleFormat: ref.sampleFormat,
        encodedKind: ref.encodedKind,
        sampleRate: ref.sampleRate,
        channels: ref.channels,
        repeat: ref.repeat != 0,
        fadeMs: ref.fadeMs,
        volume: ref.volume,
        pan: ref.pan,
        sampleCount: ref.sampleCount,
        payload: payload,
      );
    } finally {
      calloc.free(command);
    }
  }

  int setExternalSurface(
    int runtime,
    int kind,
    Pointer<Void> handle,
    int width,
    int height,
  ) {
    final status =
        _pointer.ref.runtimeSetExternalSurface
            .asFunction<_RuntimeSetExternalSurfaceDart>()(
          runtime,
          kind,
          handle,
          width,
          height,
        );
    _lastStatus = status;
    return status;
  }

  void clearExternalSurface(int runtime) {
    _pointer.ref.runtimeClearExternalSurface
        .asFunction<_RuntimeClearExternalSurfaceDart>()(runtime);
  }

  int advanceAndPresent(int runtime, int deltaMs) {
    final status = _pointer.ref.runtimeAdvanceAndPresent
        .asFunction<_RuntimeAdvanceAndPresentDart>()(runtime, deltaMs);
    _lastStatus = status;
    return status;
  }

  Uint8List? advanceAndRender(int runtime, int deltaMs) {
    final capacity = pixelBufferSize(runtime);
    if (capacity <= 0) return null;
    final pixels = calloc<Uint8>(capacity);
    try {
      final written =
          _pointer.ref.runtimeAdvanceAndRender
              .asFunction<_RuntimeAdvanceAndRenderDart>()(
            runtime,
            deltaMs,
            pixels,
            capacity,
          );
      if (written <= 0) return null;
      return Uint8List.fromList(pixels.asTypedList(written));
    } finally {
      calloc.free(pixels);
    }
  }
}
