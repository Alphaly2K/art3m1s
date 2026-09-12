import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _GetApiNative = Pointer<_RfvpApiV1> Function(Pointer<UintPtr>);
typedef _GetApi = Pointer<_RfvpApiV1> Function(Pointer<UintPtr>);

typedef _ResourcesCreateNative =
    Int32 Function(Pointer<_RfvpResourcesConfigV1>, Pointer<Uint64>);
typedef _ResourcesDestroyNative = Void Function(Uint64);
typedef _ResourcesClearNative = Void Function(Uint64);
typedef _ResourcesMountDirectoryNative =
    Int32 Function(Uint64, Pointer<Uint8>, UintPtr);
typedef _ResourcesMountPackNative =
    Int32 Function(Uint64, Pointer<Uint8>, UintPtr, Pointer<Uint8>, UintPtr);
typedef _ResourcesSetOverrideNative =
    Int32 Function(Uint64, Pointer<Uint8>, UintPtr, Pointer<Uint8>, UintPtr);
typedef _ResourcesClearOverridesNative = Void Function(Uint64);
typedef _ResourcesSetSaveRootNative =
    Int32 Function(Uint64, Pointer<Uint8>, UintPtr);

typedef _RuntimeCreateNative =
    Int32 Function(Pointer<_RfvpRuntimeConfigV1>, Pointer<Uint64>);
typedef _RuntimeDestroyNative = Void Function(Uint64);
typedef _RuntimeStepNative = Int32 Function(Uint64, Uint32);
typedef _RuntimeIsExitRequestedNative = Int32 Function(Uint64);
typedef _RuntimePushInputNative =
    Int32 Function(Uint64, Pointer<_RfvpInputEventV1>, UintPtr);
typedef _RuntimePollAudioCommandNative =
    Int32 Function(Uint64, Pointer<_RfvpAudioCommandV1>);
typedef _RuntimeCapabilitiesNative = Uint64 Function(Uint64);
typedef _RuntimeAcquireFrameNative = Int32 Function(Uint64, Pointer<Uint64>);

typedef _FrameReleaseNative = Void Function(Uint64);
typedef _FrameGetSizeNative =
    Int32 Function(Uint64, Pointer<Uint32>, Pointer<Uint32>);
typedef _FrameGetCommandsNative = Int32 Function(
  Uint64,
  Pointer<Pointer<_RfvpDrawCommandV1>>,
  Pointer<UintPtr>,
);
typedef _FrameGetTexturesNative = Int32 Function(
  Uint64,
  Pointer<Pointer<_RfvpTextureCommandV1>>,
  Pointer<UintPtr>,
);
typedef _FrameGetHitProxiesNative = Int32 Function(
  Uint64,
  Pointer<Pointer<_RfvpHitProxyV1>>,
  Pointer<UintPtr>,
);

typedef _ResourcesCreateDart =
    int Function(Pointer<_RfvpResourcesConfigV1>, Pointer<Uint64>);
typedef _ResourcesDestroyDart = void Function(int);
typedef _ResourcesClearDart = void Function(int);
typedef _ResourcesMountDirectoryDart =
    int Function(int, Pointer<Uint8>, int);
typedef _ResourcesMountPackDart =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int);
typedef _ResourcesSetOverrideDart =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int);
typedef _ResourcesClearOverridesDart = void Function(int);
typedef _ResourcesSetSaveRootDart = int Function(int, Pointer<Uint8>, int);
typedef _RuntimeCreateDart =
    int Function(Pointer<_RfvpRuntimeConfigV1>, Pointer<Uint64>);
typedef _RuntimeDestroyDart = void Function(int);
typedef _RuntimeStepDart = int Function(int, int);
typedef _RuntimeIsExitRequestedDart = int Function(int);
typedef _RuntimePushInputDart =
    int Function(int, Pointer<_RfvpInputEventV1>, int);
typedef _RuntimePollAudioCommandDart =
    int Function(int, Pointer<_RfvpAudioCommandV1>);
typedef _RuntimeCapabilitiesDart = int Function(int);
typedef _RuntimeAcquireFrameDart = int Function(int, Pointer<Uint64>);
typedef _FrameReleaseDart = void Function(int);
typedef _FrameGetSizeDart = int Function(int, Pointer<Uint32>, Pointer<Uint32>);
typedef _FrameGetCommandsDart = int Function(
  int,
  Pointer<Pointer<_RfvpDrawCommandV1>>,
  Pointer<UintPtr>,
);
typedef _FrameGetTexturesDart = int Function(
  int,
  Pointer<Pointer<_RfvpTextureCommandV1>>,
  Pointer<UintPtr>,
);
typedef _FrameGetHitProxiesDart = int Function(
  int,
  Pointer<Pointer<_RfvpHitProxyV1>>,
  Pointer<UintPtr>,
);

const int rfvpStatusOk = 0;
const int rfvpStatusNoFrame = 1;
const int rfvpStatusNoCommand = 2;
const int rfvpStatusInvalidArgument = -1;
const int rfvpStatusInvalidHandle = -2;
const int rfvpStatusInvalidState = -3;
const int rfvpStatusNotFound = -4;
const int rfvpStatusInvalidData = -5;
const int rfvpStatusUnsupported = -6;
const int rfvpStatusOutOfMemory = -7;
const int rfvpStatusBusy = -8;
const int rfvpStatusIo = -9;
const int rfvpStatusEngine = -10;

const int rfvpNlsShiftJis = 1;
const int rfvpNlsGbk = 2;
const int rfvpNlsUtf8 = 3;

const int rfvpInputKey = 1;
const int rfvpInputText = 2;
const int rfvpInputPointerMove = 3;
const int rfvpInputPointerButton = 4;
const int rfvpInputWheel = 5;
const int rfvpInputTouch = 6;
const int rfvpInputFocus = 7;
const int rfvpInputQuit = 8;

const int rfvpInputPhaseDown = 0;
const int rfvpInputPhaseUp = 1;
const int rfvpInputPhaseRepeat = 2;
const int rfvpInputPhaseMove = 3;

const int rfvpPointerLeft = 1 << 0;
const int rfvpPointerRight = 1 << 1;
const int rfvpPointerMiddle = 1 << 2;

const int rfvpTextureCreate = 1;
const int rfvpTextureUpdate = 2;
const int rfvpTextureDestroy = 3;

const int rfvpTextureFormatRgba8 = 1;
const int rfvpTextureFormatLumaA8 = 2;

const int rfvpDrawImage = 1;
const int rfvpDrawGlyph = 2;
const int rfvpDrawSolid = 3;

const int rfvpDrawFlagHasClip = 1 << 0;
const int rfvpDrawFlagHasSrcRect = 1 << 3;

const int rfvpHitProxyEnabled = 1 << 0;
const int rfvpHitProxyVisible = 1 << 1;

const int rfvpAudioLoadEncoded = 1;
const int rfvpAudioCreateStream = 2;
const int rfvpAudioSubmitI16 = 3;
const int rfvpAudioSubmitF32 = 4;
const int rfvpAudioPlay = 5;
const int rfvpAudioStop = 6;
const int rfvpAudioPause = 7;
const int rfvpAudioResume = 8;
const int rfvpAudioSetParams = 9;
const int rfvpAudioDestroyStream = 10;
const int rfvpAudioMasterVolume = 11;

const int rfvpCapabilityAudioCommands = 1 << 10;

final class _RfvpResourcesConfigV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int flags;

  @Uint32()
  external int nls;

  @Uint32()
  external int reserved0;

  external Pointer<Uint8> saveRootUtf8;

  @UintPtr()
  external int saveRootLen;

  @Array(4)
  external Array<Uint64> reserved;
}

final class _RfvpRuntimeConfigV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int flags;

  @Uint64()
  external int resources;

  @Uint32()
  external int requestedWidth;

  @Uint32()
  external int requestedHeight;

  @Array(4)
  external Array<Uint64> reserved;
}

final class _RfvpInputEventV1 extends Struct {
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

final class _RfvpAudioCommandV1 extends Struct {
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

final class _RfvpColorV1 extends Struct {
  @Float()
  external double r;

  @Float()
  external double g;

  @Float()
  external double b;

  @Float()
  external double a;
}

final class _RfvpRectU16V1 extends Struct {
  @Uint16()
  external int x;

  @Uint16()
  external int y;

  @Uint16()
  external int width;

  @Uint16()
  external int height;
}

final class _RfvpRectI32V1 extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;

  @Int32()
  external int width;

  @Int32()
  external int height;
}

final class _RfvpVertexV1 extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double u;

  @Float()
  external double v;

  external _RfvpColorV1 color;
}

final class _RfvpTextureCommandV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int kind;

  @Uint32()
  external int textureId;

  @Uint32()
  external int format;

  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint32()
  external int mipCount;

  @Uint32()
  external int rowBytes;

  external _RfvpRectI32V1 rect;

  @Uint64()
  external int generation;

  external Pointer<Uint8> pixels;

  @UintPtr()
  external int pixelsSize;

  @Array(2)
  external Array<Uint64> reserved;
}

final class _RfvpDrawCommandV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int kind;

  @Uint32()
  external int flags;

  @Uint32()
  external int textureId;

  @Uint32()
  external int blend;

  @Uint32()
  external int filter;

  @Uint32()
  external int effectId;

  @Uint32()
  external int meshTopology;

  external _RfvpRectU16V1 srcRect;
  external _RfvpRectI32V1 dstRect;
  external _RfvpRectI32V1 clipRect;
  external _RfvpColorV1 color;

  @Array(4)
  external Array<_RfvpVertexV1> vertices;

  external Pointer<_RfvpVertexV1> mesh;

  @UintPtr()
  external int meshVertexCount;

  external Pointer<Uint8> effectData;

  @UintPtr()
  external int effectDataSize;

  @Array(2)
  external Array<Uint64> reserved;
}

final class _RfvpHitProxyV1 extends Struct {
  @Uint32()
  external int primId;

  @Uint32()
  external int flags;

  external _RfvpRectI32V1 rect;

  @Uint32()
  external int order;

  @Uint32()
  external int reserved0;
}

final class _RfvpApiV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int abiVersion;

  @Uint64()
  external int magic;

  external Pointer<NativeFunction<_ResourcesCreateNative>> resourcesCreate;
  external Pointer<NativeFunction<_ResourcesDestroyNative>> resourcesDestroy;
  external Pointer<NativeFunction<_ResourcesClearNative>> resourcesClear;
  external Pointer<NativeFunction<_ResourcesMountDirectoryNative>>
  resourcesMountDirectory;
  external Pointer<NativeFunction<_ResourcesMountPackNative>> resourcesMountPack;
  external Pointer<NativeFunction<_ResourcesSetOverrideNative>>
  resourcesSetOverride;
  external Pointer<NativeFunction<_ResourcesClearOverridesNative>>
  resourcesClearOverrides;
  external Pointer<NativeFunction<_ResourcesSetSaveRootNative>>
  resourcesSetSaveRoot;

  external Pointer<NativeFunction<_RuntimeCreateNative>> runtimeCreate;
  external Pointer<NativeFunction<_RuntimeDestroyNative>> runtimeDestroy;
  external Pointer<NativeFunction<_RuntimeStepNative>> runtimeStep;
  external Pointer<NativeFunction<_RuntimeIsExitRequestedNative>>
  runtimeIsExitRequested;

  external Pointer<NativeFunction<Void Function(Uint64, Int32)>>
  runtimeEventsEnable;
  external Pointer<NativeFunction<UintPtr Function(Uint64)>>
  runtimeNextEventSize;
  external Pointer<
    NativeFunction<UintPtr Function(Uint64, Pointer<Uint8>, UintPtr, Pointer<Uint32>)>
  >
  runtimePollEvents;

  external Pointer<NativeFunction<_RuntimePushInputNative>> runtimePushInput;
  external Pointer<NativeFunction<Int32 Function(Uint64, Int32)>>
  runtimeSetTextHidpi;
  external Pointer<
    NativeFunction<Int32 Function(Uint64, Pointer<Uint8>, UintPtr, Uint32)>
  >
  runtimeSetTextReplacements;
  external Pointer<NativeFunction<Int32 Function(Uint64, Int32)>>
  runtimeSetTextTranslationEnabled;
  external Pointer<
    NativeFunction<Int32 Function(Uint64, Uint64, Pointer<Uint8>, UintPtr)>
  >
  runtimeSubmitTextTranslation;
  external Pointer<NativeFunction<Int32 Function(Uint64, Int32)>>
  runtimeSetRenderQualityPreset;
  external Pointer<NativeFunction<Int32 Function(Uint64, Int32)>>
  runtimeSetMediaEnabled;
  external Pointer<NativeFunction<Int32 Function(Uint64, Int32)>>
  runtimeNotifyLifecycle;
  external Pointer<NativeFunction<Int32 Function(Uint64, Uint32, Float)>>
  runtimeSetVolume;
  external Pointer<NativeFunction<_RuntimePollAudioCommandNative>>
  runtimePollAudioCommand;
  external Pointer<NativeFunction<_RuntimeCapabilitiesNative>>
  runtimeCapabilities;
  external Pointer<NativeFunction<_RuntimeAcquireFrameNative>>
  runtimeAcquireFrame;

  external Pointer<NativeFunction<_FrameReleaseNative>> frameRelease;
  external Pointer<NativeFunction<_FrameGetSizeNative>> frameGetSize;
  external Pointer<NativeFunction<_FrameGetCommandsNative>> frameGetCommands;
  external Pointer<NativeFunction<_FrameGetTexturesNative>> frameGetTextures;
  external Pointer<NativeFunction<_FrameGetHitProxiesNative>> frameGetHitProxies;
}

class RfvpColor {
  const RfvpColor(this.r, this.g, this.b, this.a);

  final double r;
  final double g;
  final double b;
  final double a;
}

class RfvpVertex {
  const RfvpVertex({
    required this.x,
    required this.y,
    required this.u,
    required this.v,
    required this.color,
  });

  final double x;
  final double y;
  final double u;
  final double v;
  final RfvpColor color;
}

class RfvpRectI32 {
  const RfvpRectI32(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

class RfvpRectU16 {
  const RfvpRectU16(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

class RfvpDrawCommand {
  const RfvpDrawCommand({
    required this.kind,
    required this.flags,
    required this.textureId,
    required this.blend,
    required this.filter,
    required this.effectId,
    required this.meshTopology,
    required this.srcRect,
    required this.dstRect,
    required this.clipRect,
    required this.color,
    required this.vertices,
    required this.mesh,
    required this.effectData,
  });

  final int kind;
  final int flags;
  final int textureId;
  final int blend;
  final int filter;
  final int effectId;
  final int meshTopology;
  final RfvpRectU16 srcRect;
  final RfvpRectI32 dstRect;
  final RfvpRectI32 clipRect;
  final RfvpColor color;
  final List<RfvpVertex> vertices;
  final List<RfvpVertex> mesh;
  final Uint8List effectData;

  bool get hasClip => flags & rfvpDrawFlagHasClip != 0;
  bool get hasSrcRect => flags & rfvpDrawFlagHasSrcRect != 0;
}

class RfvpTextureCommand {
  const RfvpTextureCommand({
    required this.kind,
    required this.textureId,
    required this.format,
    required this.width,
    required this.height,
    required this.mipCount,
    required this.rowBytes,
    required this.rect,
    required this.generation,
    required this.pixels,
  });

  final int kind;
  final int textureId;
  final int format;
  final int width;
  final int height;
  final int mipCount;
  final int rowBytes;
  final RfvpRectI32 rect;
  final int generation;
  final Uint8List pixels;
}

class RfvpHitProxy {
  const RfvpHitProxy({
    required this.primId,
    required this.flags,
    required this.rect,
    required this.order,
  });

  final int primId;
  final int flags;
  final RfvpRectI32 rect;
  final int order;

  bool get enabled => flags & rfvpHitProxyEnabled != 0;
  bool get visible => flags & rfvpHitProxyVisible != 0;
}

class RfvpFrame {
  const RfvpFrame({
    required this.width,
    required this.height,
    required this.commands,
    required this.textures,
    required this.hitProxies,
  });

  final int width;
  final int height;
  final List<RfvpDrawCommand> commands;
  final List<RfvpTextureCommand> textures;
  final List<RfvpHitProxy> hitProxies;
}

class RfvpAudioCommand {
  const RfvpAudioCommand({
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

class RfvpInputEvent {
  const RfvpInputEvent({
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

final class RfvpApiV1 {
  RfvpApiV1._(this._pointer);

  static const int _abiVersion = 1;
  static const int _abiMagic = 0x4950413150564652; // "RFVP1API"

  final Pointer<_RfvpApiV1> _pointer;

  static int get apiTableSize => sizeOf<_RfvpApiV1>();
  static int get resourcesConfigSize => sizeOf<_RfvpResourcesConfigV1>();
  static int get runtimeConfigSize => sizeOf<_RfvpRuntimeConfigV1>();
  static int get inputEventSize => sizeOf<_RfvpInputEventV1>();
  static int get audioCommandSize => sizeOf<_RfvpAudioCommandV1>();
  static int get drawCommandSize => sizeOf<_RfvpDrawCommandV1>();
  static int get textureCommandSize => sizeOf<_RfvpTextureCommandV1>();

  static RfvpApiV1? tryLoad(DynamicLibrary library) {
    final _GetApi getApi;
    try {
      getApi = library.lookupFunction<_GetApiNative, _GetApi>('rfvp_get_api_v1');
    } catch (_) {
      return null;
    }

    final size = calloc<UintPtr>();
    try {
      final pointer = getApi(size);
      if (pointer == nullptr) return null;
      final ref = pointer.ref;
      if (ref.abiVersion != _abiVersion || ref.magic != _abiMagic) return null;
      if (ref.structSize < sizeOf<_RfvpApiV1>()) return null;
      if (size.value < sizeOf<_RfvpApiV1>()) return null;
      return RfvpApiV1._(pointer);
    } finally {
      calloc.free(size);
    }
  }

  int createResources({required int nls, String? saveRoot}) {
    final config = calloc<_RfvpResourcesConfigV1>();
    final saveRootPtr = saveRoot == null ? nullptr : saveRoot.toNativeUtf8();
    final out = calloc<Uint64>();
    try {
      config.ref
        ..structSize = sizeOf<_RfvpResourcesConfigV1>()
        ..flags = 0
        ..nls = nls
        ..reserved0 = 0
        ..saveRootUtf8 = saveRootPtr == nullptr
            ? nullptr
            : saveRootPtr.cast<Uint8>()
        ..saveRootLen = saveRoot == null ? 0 : saveRootPtr.length - 1;
      final status =
          _pointer.ref.resourcesCreate.asFunction<_ResourcesCreateDart>()(
            config,
            out,
          );
      if (status != rfvpStatusOk) return -1;
      return out.value;
    } finally {
      if (saveRootPtr != nullptr) malloc.free(saveRootPtr);
      calloc.free(out);
      calloc.free(config);
    }
  }

  void destroyResources(int handle) {
    if (handle <= 0) return;
    _pointer.ref.resourcesDestroy.asFunction<_ResourcesDestroyDart>()(handle);
  }

  void clearResources(int handle) {
    if (handle <= 0) return;
    _pointer.ref.resourcesClear.asFunction<_ResourcesClearDart>()(handle);
  }

  int mountDirectory(int resources, String path) {
    final native = path.toNativeUtf8();
    try {
      return _pointer.ref.resourcesMountDirectory
          .asFunction<_ResourcesMountDirectoryDart>()(
            resources,
            native.cast<Uint8>(),
            native.length - 1,
          );
    } finally {
      malloc.free(native);
    }
  }

  int mountPack(int resources, String folder, Uint8List bytes) {
    final nativeFolder = folder.toNativeUtf8();
    final nativeBytes = calloc<Uint8>(bytes.length);
    try {
      nativeBytes.asTypedList(bytes.length).setAll(0, bytes);
      return _pointer.ref.resourcesMountPack
          .asFunction<_ResourcesMountPackDart>()(
            resources,
            nativeFolder.cast<Uint8>(),
            nativeFolder.length - 1,
            nativeBytes,
            bytes.length,
          );
    } finally {
      calloc.free(nativeBytes);
      malloc.free(nativeFolder);
    }
  }

  int setOverride(int resources, String path, Uint8List bytes) {
    final nativePath = path.toNativeUtf8();
    final nativeBytes = calloc<Uint8>(bytes.length);
    try {
      nativeBytes.asTypedList(bytes.length).setAll(0, bytes);
      return _pointer.ref.resourcesSetOverride
          .asFunction<_ResourcesSetOverrideDart>()(
            resources,
            nativePath.cast<Uint8>(),
            nativePath.length - 1,
            nativeBytes,
            bytes.length,
          );
    } finally {
      calloc.free(nativeBytes);
      malloc.free(nativePath);
    }
  }

  void clearOverrides(int resources) {
    if (resources <= 0) return;
    _pointer.ref.resourcesClearOverrides
        .asFunction<_ResourcesClearOverridesDart>()(resources);
  }

  int setSaveRoot(int resources, String path) {
    final native = path.toNativeUtf8();
    try {
      return _pointer.ref.resourcesSetSaveRoot
          .asFunction<_ResourcesSetSaveRootDart>()(
            resources,
            native.cast<Uint8>(),
            native.length - 1,
          );
    } finally {
      malloc.free(native);
    }
  }

  int createRuntime({
    required int resources,
    int requestedWidth = 0,
    int requestedHeight = 0,
  }) {
    final config = calloc<_RfvpRuntimeConfigV1>();
    final out = calloc<Uint64>();
    try {
      config.ref
        ..structSize = sizeOf<_RfvpRuntimeConfigV1>()
        ..flags = 0
        ..resources = resources
        ..requestedWidth = requestedWidth
        ..requestedHeight = requestedHeight;
      final status = _pointer.ref.runtimeCreate
          .asFunction<_RuntimeCreateDart>()(config, out);
      if (status != rfvpStatusOk) return -1;
      return out.value;
    } finally {
      calloc.free(out);
      calloc.free(config);
    }
  }

  void destroyRuntime(int handle) {
    if (handle <= 0) return;
    _pointer.ref.runtimeDestroy.asFunction<_RuntimeDestroyDart>()(handle);
  }

  int step(int runtime, int deltaMs) {
    return _pointer.ref.runtimeStep.asFunction<_RuntimeStepDart>()(
      runtime,
      deltaMs,
    );
  }

  bool isExitRequested(int runtime) {
    return _pointer.ref.runtimeIsExitRequested
            .asFunction<_RuntimeIsExitRequestedDart>()(runtime) !=
        0;
  }

  int pushInput(int runtime, List<RfvpInputEvent> events) {
    if (events.isEmpty) return rfvpStatusOk;
    final native = calloc<_RfvpInputEventV1>(events.length);
    try {
      for (var index = 0; index < events.length; index++) {
        final source = events[index];
        native[index]
          ..structSize = sizeOf<_RfvpInputEventV1>()
          ..kind = source.kind
          ..code = source.code
          ..phase = source.phase
          ..x = source.x
          ..y = source.y
          ..value = source.value
          ..modifiers = source.modifiers
          ..id = source.id;
      }
      return _pointer.ref.runtimePushInput
          .asFunction<_RuntimePushInputDart>()(runtime, native, events.length);
    } finally {
      calloc.free(native);
    }
  }

  RfvpAudioCommand? pollAudioCommand(int runtime) {
    final command = calloc<_RfvpAudioCommandV1>();
    try {
      final status = _pointer.ref.runtimePollAudioCommand
          .asFunction<_RuntimePollAudioCommandDart>()(runtime, command);
      if (status == rfvpStatusNoCommand) return null;
      if (status != rfvpStatusOk) return null;
      final ref = command.ref;
      return RfvpAudioCommand(
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
        payload: ref.payloadSize == 0
            ? Uint8List(0)
            : Uint8List.fromList(
                ref.payload.asTypedList(ref.payloadSize),
              ),
      );
    } finally {
      calloc.free(command);
    }
  }

  int capabilities(int runtime) {
    return _pointer.ref.runtimeCapabilities
        .asFunction<_RuntimeCapabilitiesDart>()(runtime);
  }

  RfvpFrame? acquireFrame(int runtime) {
    final outFrame = calloc<Uint64>();
    try {
      final status = _pointer.ref.runtimeAcquireFrame
          .asFunction<_RuntimeAcquireFrameDart>()(runtime, outFrame);
      if (status == rfvpStatusNoFrame) return null;
      if (status != rfvpStatusOk || outFrame.value == 0) return null;
      final frame = outFrame.value;
      try {
        return _readFrame(frame);
      } finally {
        _pointer.ref.frameRelease.asFunction<_FrameReleaseDart>()(frame);
      }
    } finally {
      calloc.free(outFrame);
    }
  }

  RfvpFrame _readFrame(int frame) {
    final width = calloc<Uint32>();
    final height = calloc<Uint32>();
    try {
      final status = _pointer.ref.frameGetSize
          .asFunction<_FrameGetSizeDart>()(frame, width, height);
      if (status != rfvpStatusOk) {
        throw StateError('rfvp_frame_get_size failed: $status');
      }
      return RfvpFrame(
        width: width.value,
        height: height.value,
        commands: _readDrawCommands(frame),
        textures: _readTextures(frame),
        hitProxies: _readHitProxies(frame),
      );
    } finally {
      calloc.free(width);
      calloc.free(height);
    }
  }

  List<RfvpDrawCommand> _readDrawCommands(int frame) {
    final out = calloc<Pointer<_RfvpDrawCommandV1>>();
    final count = calloc<UintPtr>();
    try {
      final status = _pointer.ref.frameGetCommands
          .asFunction<_FrameGetCommandsDart>()(frame, out, count);
      if (status != rfvpStatusOk) return const [];
      final result = <RfvpDrawCommand>[];
      for (var index = 0; index < count.value; index++) {
        result.add(_copyDrawCommand(out.value[index]));
      }
      return result;
    } finally {
      calloc.free(count);
      calloc.free(out);
    }
  }

  List<RfvpTextureCommand> _readTextures(int frame) {
    final out = calloc<Pointer<_RfvpTextureCommandV1>>();
    final count = calloc<UintPtr>();
    try {
      final status = _pointer.ref.frameGetTextures
          .asFunction<_FrameGetTexturesDart>()(frame, out, count);
      if (status != rfvpStatusOk) return const [];
      final result = <RfvpTextureCommand>[];
      for (var index = 0; index < count.value; index++) {
        final source = out.value[index];
        result.add(
          RfvpTextureCommand(
            kind: source.kind,
            textureId: source.textureId,
            format: source.format,
            width: source.width,
            height: source.height,
            mipCount: source.mipCount,
            rowBytes: source.rowBytes,
            rect: _copyRectI32(source.rect),
            generation: source.generation,
            pixels: source.pixelsSize == 0
                ? Uint8List(0)
                : Uint8List.fromList(
                    source.pixels.asTypedList(source.pixelsSize),
                  ),
          ),
        );
      }
      return result;
    } finally {
      calloc.free(count);
      calloc.free(out);
    }
  }

  List<RfvpHitProxy> _readHitProxies(int frame) {
    final out = calloc<Pointer<_RfvpHitProxyV1>>();
    final count = calloc<UintPtr>();
    try {
      final status = _pointer.ref.frameGetHitProxies
          .asFunction<_FrameGetHitProxiesDart>()(frame, out, count);
      if (status != rfvpStatusOk) return const [];
      final result = <RfvpHitProxy>[];
      for (var index = 0; index < count.value; index++) {
        final source = out.value[index];
        result.add(
          RfvpHitProxy(
            primId: source.primId,
            flags: source.flags,
            rect: _copyRectI32(source.rect),
            order: source.order,
          ),
        );
      }
      return result;
    } finally {
      calloc.free(count);
      calloc.free(out);
    }
  }

  static RfvpDrawCommand _copyDrawCommand(_RfvpDrawCommandV1 source) {
    return RfvpDrawCommand(
      kind: source.kind,
      flags: source.flags,
      textureId: source.textureId,
      blend: source.blend,
      filter: source.filter,
      effectId: source.effectId,
      meshTopology: source.meshTopology,
      srcRect: RfvpRectU16(
        source.srcRect.x,
        source.srcRect.y,
        source.srcRect.width,
        source.srcRect.height,
      ),
      dstRect: _copyRectI32(source.dstRect),
      clipRect: _copyRectI32(source.clipRect),
      color: _copyColor(source.color),
      vertices: List<RfvpVertex>.generate(
        4,
        (index) => _copyVertex(source.vertices[index]),
        growable: false,
      ),
      mesh: source.meshVertexCount == 0
          ? const []
          : List<RfvpVertex>.generate(
              source.meshVertexCount,
              (index) => _copyVertex(source.mesh[index]),
              growable: false,
            ),
      effectData: source.effectDataSize == 0
          ? Uint8List(0)
          : Uint8List.fromList(
              source.effectData.asTypedList(source.effectDataSize),
            ),
    );
  }

  static RfvpColor _copyColor(_RfvpColorV1 source) {
    return RfvpColor(source.r, source.g, source.b, source.a);
  }

  static RfvpVertex _copyVertex(_RfvpVertexV1 source) {
    return RfvpVertex(
      x: source.x,
      y: source.y,
      u: source.u,
      v: source.v,
      color: _copyColor(source.color),
    );
  }

  static RfvpRectI32 _copyRectI32(_RfvpRectI32V1 source) {
    return RfvpRectI32(
      source.x,
      source.y,
      source.width,
      source.height,
    );
  }
}
