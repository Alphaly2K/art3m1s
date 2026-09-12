import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _GetApiNative = Pointer<_CoreApiV1> Function(Pointer<UintPtr>);
typedef _GetApi = Pointer<_CoreApiV1> Function(Pointer<UintPtr>);

typedef _HostEventsCreateNative = Pointer<Void> Function();
typedef _HostEventsDestroyNative = Void Function(Pointer<Void>);
typedef _HostEventsEnableNative = Void Function(Pointer<Void>, Int32);
typedef _HostEventsNextNative = UintPtr Function(Pointer<Void>);
typedef _HostEventsPollNative =
    UintPtr Function(Pointer<Void>, Pointer<Uint8>, UintPtr, Pointer<Uint32>);
typedef _SetFontListNative =
    Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Uint8>, UintPtr);
typedef _SetWindowStateNative = Void Function(Pointer<Void>, Int32);
typedef _SetTextReplacementsNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, UintPtr);
typedef _SetTextTranslationEnabledNative = Void Function(Pointer<Void>, Int32);
typedef _HostEventsClearNative = Void Function(Pointer<Void>);
typedef _ClearNative = Void Function();

typedef _ResourcesCreateNative = Pointer<Void> Function();
typedef _ResourcesDestroyNative = Void Function(Pointer<Void>);
typedef _ResourcesClearNative = Void Function(Pointer<Void>);
typedef _ResourcesMountDirectoryNative =
    Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _ResourcesMountPfsNative =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ResourcesSetSaveDirNative =
    Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _ResourcesSetOverrideNative =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, UintPtr);

typedef _RuntimeCreateNative = Pointer<Void> Function(Uint32, Uint32, Int32);
typedef _RuntimeDestroyNative = Void Function(Pointer<Void>);
typedef _RuntimeSetResourcesNative =
    Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _RuntimeSetRuntimeMediaEnabledNative =
    Void Function(Pointer<Void>, Int32);
typedef _RuntimeAdvancePresentNative = Int32 Function(Pointer<Void>, Uint32);
typedef _RuntimeAdvanceWithoutRenderNative =
    Int32 Function(Pointer<Void>, Uint32);
typedef _RuntimeStageNative = Uint32 Function(Pointer<Void>);
typedef _RuntimeLoadProjectNative =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _RuntimeLoadProjectBytesNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, UintPtr, Pointer<Utf8>);
typedef _RuntimePixelBufferSizeNative = Uint32 Function(Pointer<Void>);
typedef _RuntimeAdvanceRenderNative =
    Uint32 Function(Pointer<Void>, Uint32, Pointer<Uint8>, Uint32);
typedef _RuntimeSetExternalSurfaceNative =
    Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32, Uint32);
typedef _RuntimeClearExternalSurfaceNative = Void Function(Pointer<Void>);
typedef _RuntimeFeedMouseNative = Void Function(Pointer<Void>, Int32, Int32);
typedef _RuntimeFeedClickNative = Void Function(Pointer<Void>);
typedef _RuntimeFeedMouseButtonNative =
    Void Function(Pointer<Void>, Uint32, Int32);
typedef _RuntimeFeedTouchNative =
    Void Function(Pointer<Void>, Uint32, Uint8, Int32, Int32);
typedef _RuntimeFeedKeyNative = Void Function(Pointer<Void>, Uint32, Int32);
typedef _RuntimeSubmitDialogNative =
    Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _RuntimeSubmitTextTranslationNative =
    Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>);
typedef _RuntimeSetReportedOsNative =
    Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _RuntimeSetEmoteBackendNative = Int32 Function(Pointer<Void>, Int32);
typedef _RuntimeConfigureSpatialUpscaleNative =
    Int32 Function(Pointer<Void>, Float, Float);
typedef _RuntimeSetRenderQualityPresetNative =
    Int32 Function(Pointer<Void>, Int32);
typedef _RuntimeSetProfilerEnabledNative = Void Function(Pointer<Void>, Int32);
typedef _RuntimeProfilerSnapshotNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32);
typedef _RuntimeSetVolumeNative =
    Void Function(Pointer<Void>, Pointer<Utf8>, Float);
typedef _RuntimeNotifyFinishedNative =
    Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _RuntimeNotifyLifecycleNative = Void Function(Pointer<Void>, Int32);
typedef _RuntimeIsExitRequestedNative = Int32 Function(Pointer<Void>);
typedef _RuntimeBackendCapabilitiesNative = Uint64 Function(Pointer<Void>);
typedef _RuntimeSubmitHttpResultNative =
    Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Int32);
typedef _RuntimeSetStringVariableNative =
    Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ProbeCaptionNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      UintPtr,
      Pointer<Utf8>,
      Pointer<Uint8>,
      Int32,
    );
typedef _SetAnglePathNative = Void Function(Pointer<Utf8>);
typedef _SetDebugNative = Void Function(Int32);
typedef _SetFontOverrideNative = Int32 Function(Pointer<Uint8>, Int32);
typedef _RuntimeUploadVideoLayerFrameNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Uint32,
      Uint32,
      Pointer<Uint8>,
      UintPtr,
    );

final class _CoreApiV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int abiVersion;

  @Uint64()
  external int magic;

  external Pointer<NativeFunction<_HostEventsCreateNative>> hostEventsCreate;
  external Pointer<NativeFunction<_HostEventsDestroyNative>> hostEventsDestroy;
  external Pointer<NativeFunction<_HostEventsEnableNative>> hostEventsEnable;
  external Pointer<NativeFunction<_HostEventsNextNative>> hostEventsNext;
  external Pointer<NativeFunction<_HostEventsPollNative>> pollEvents;
  external Pointer<NativeFunction<_SetFontListNative>> setFontList;
  external Pointer<NativeFunction<_SetWindowStateNative>> setWindowState;
  external Pointer<NativeFunction<_SetTextReplacementsNative>>
  setTextReplacements;
  external Pointer<NativeFunction<_SetTextTranslationEnabledNative>>
  setTextTranslationEnabled;
  external Pointer<NativeFunction<_HostEventsClearNative>> clearHostState;

  external Pointer<NativeFunction<_ResourcesCreateNative>> resourcesCreate;
  external Pointer<NativeFunction<_ResourcesDestroyNative>> resourcesDestroy;
  external Pointer<NativeFunction<_ResourcesClearNative>> resourcesClear;
  external Pointer<NativeFunction<_ResourcesMountDirectoryNative>>
  resourcesMountDirectory;
  external Pointer<NativeFunction<_ResourcesMountPfsNative>> resourcesMountPfs;
  external Pointer<NativeFunction<_ResourcesSetSaveDirNative>>
  resourcesSetSaveDir;
  external Pointer<NativeFunction<_ResourcesSetOverrideNative>>
  resourcesSetOverride;
  external Pointer<NativeFunction<_ResourcesClearNative>>
  resourcesClearOverrides;

  external Pointer<NativeFunction<_RuntimeCreateNative>> runtimeCreate;
  external Pointer<NativeFunction<_RuntimeDestroyNative>> runtimeDestroy;
  external Pointer<NativeFunction<_RuntimeSetResourcesNative>>
  runtimeSetResources;
  external Pointer<NativeFunction<_RuntimeSetRuntimeMediaEnabledNative>>
  runtimeSetRuntimeMediaEnabled;
  external Pointer<NativeFunction<_RuntimeAdvancePresentNative>>
  runtimeAdvanceAndPresent;
  external Pointer<NativeFunction<_RuntimeAdvanceWithoutRenderNative>>
  runtimeAdvanceWithoutRender;
  external Pointer<NativeFunction<_RuntimeStageNative>> runtimeStageWidth;
  external Pointer<NativeFunction<_RuntimeStageNative>> runtimeStageHeight;

  external Pointer<NativeFunction<_RuntimeLoadProjectNative>>
  runtimeLoadProject;
  external Pointer<NativeFunction<_RuntimeLoadProjectBytesNative>>
  runtimeLoadProjectBytes;
  external Pointer<NativeFunction<_RuntimePixelBufferSizeNative>>
  runtimePixelBufferSize;
  external Pointer<NativeFunction<_RuntimeAdvanceRenderNative>>
  runtimeAdvanceAndRender;
  external Pointer<NativeFunction<_RuntimeSetExternalSurfaceNative>>
  runtimeSetExternalSurface;
  external Pointer<NativeFunction<_RuntimeClearExternalSurfaceNative>>
  runtimeClearExternalSurface;
  external Pointer<NativeFunction<_RuntimeFeedMouseNative>> runtimeFeedMouse;
  external Pointer<NativeFunction<_RuntimeFeedClickNative>> runtimeFeedClick;
  external Pointer<NativeFunction<_RuntimeFeedMouseButtonNative>>
  runtimeFeedMouseButton;
  external Pointer<NativeFunction<_RuntimeFeedTouchNative>> runtimeFeedTouch;
  external Pointer<NativeFunction<_RuntimeFeedKeyNative>> runtimeFeedKey;
  external Pointer<NativeFunction<_RuntimeSubmitDialogNative>>
  runtimeSubmitDialog;
  external Pointer<NativeFunction<_RuntimeSubmitTextTranslationNative>>
  runtimeSubmitTextTranslation;
  external Pointer<NativeFunction<_RuntimeSetReportedOsNative>>
  runtimeSetReportedOs;
  external Pointer<NativeFunction<_RuntimeSetEmoteBackendNative>>
  runtimeSetEmoteBackend;
  external Pointer<NativeFunction<_RuntimeConfigureSpatialUpscaleNative>>
  runtimeConfigureSpatialUpscale;
  external Pointer<NativeFunction<_RuntimeSetRenderQualityPresetNative>>
  runtimeSetRenderQualityPreset;
  external Pointer<NativeFunction<_RuntimeSetProfilerEnabledNative>>
  runtimeSetProfilerEnabled;
  external Pointer<NativeFunction<_RuntimeProfilerSnapshotNative>>
  runtimeProfilerSnapshot;
  external Pointer<NativeFunction<_RuntimeSetVolumeNative>> runtimeSetVolume;
  external Pointer<NativeFunction<_RuntimeNotifyFinishedNative>>
  runtimeNotifyVideoFinished;
  external Pointer<NativeFunction<_RuntimeNotifyFinishedNative>>
  runtimeNotifySoundFinished;
  external Pointer<NativeFunction<_RuntimeNotifyLifecycleNative>>
  runtimeNotifyLifecycle;
  external Pointer<NativeFunction<_RuntimeIsExitRequestedNative>>
  runtimeIsExitRequested;
  external Pointer<NativeFunction<_RuntimeBackendCapabilitiesNative>>
  runtimeBackendCapabilities;
  external Pointer<NativeFunction<_RuntimeSubmitHttpResultNative>>
  runtimeSubmitHttpResult;
  external Pointer<NativeFunction<_RuntimeSetStringVariableNative>>
  runtimeSetStringVariable;
  external Pointer<NativeFunction<_ProbeCaptionNative>> probeCaption;
  external Pointer<NativeFunction<_SetAnglePathNative>> setAnglePath;
  external Pointer<NativeFunction<_SetDebugNative>> setDebug;
  external Pointer<NativeFunction<_SetDebugNative>> setDamageVisualization;
  external Pointer<NativeFunction<_SetFontOverrideNative>> setFontOverride;
  external Pointer<NativeFunction<_ClearNative>> clearFontOverride;
  external Pointer<NativeFunction<_RuntimeUploadVideoLayerFrameNative>>
  runtimeUploadVideoLayerFrame;
}

final class CoreApiV1 {
  CoreApiV1._(this._pointer);

  static const int _abiVersion = 1;
  static const int _abiMagic = 0x415254334D314150;

  final Pointer<_CoreApiV1> _pointer;

  static CoreApiV1? tryLoad(DynamicLibrary library) {
    final _GetApi getApi;
    try {
      getApi = library.lookupFunction<_GetApiNative, _GetApi>(
        'art3m1s_get_api_v1',
      );
    } catch (_) {
      return null;
    }

    final size = calloc<UintPtr>();
    try {
      final pointer = getApi(size);
      if (pointer == nullptr) return null;
      final ref = pointer.ref;
      if (ref.abiVersion != _abiVersion ||
          ref.magic != _abiMagic ||
          ref.structSize < sizeOf<_CoreApiV1>()) {
        return null;
      }
      return CoreApiV1._(pointer);
    } finally {
      calloc.free(size);
    }
  }

  int get structSize => _pointer.ref.structSize;

  late final Pointer<Void> Function() createHostEvents = _pointer
      .ref
      .hostEventsCreate
      .asFunction<Pointer<Void> Function()>();
  late final void Function(Pointer<Void>) destroyHostEvents = _pointer
      .ref
      .hostEventsDestroy
      .asFunction<void Function(Pointer<Void>)>();
  late final void Function(Pointer<Void>, int) hostEventsEnable = _pointer
      .ref
      .hostEventsEnable
      .asFunction<void Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>) hostEventsNext = _pointer
      .ref
      .hostEventsNext
      .asFunction<int Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>)
  pollEvents = _pointer.ref.pollEvents
      .asFunction<
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>)
      >();
  late final int Function(Pointer<Void>, int, int, Pointer<Uint8>, int)
  setFontList = _pointer.ref.setFontList
      .asFunction<int Function(Pointer<Void>, int, int, Pointer<Uint8>, int)>();
  late final void Function(Pointer<Void>, int) setWindowState = _pointer
      .ref
      .setWindowState
      .asFunction<void Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>, Pointer<Uint8>, int)
  setTextReplacements = _pointer.ref.setTextReplacements
      .asFunction<int Function(Pointer<Void>, Pointer<Uint8>, int)>();
  late final void Function(Pointer<Void>, int) setTextTranslationEnabled =
      _pointer.ref.setTextTranslationEnabled
          .asFunction<void Function(Pointer<Void>, int)>();
  late final void Function(Pointer<Void>) clearHostState = _pointer
      .ref
      .clearHostState
      .asFunction<void Function(Pointer<Void>)>();

  late final Pointer<Void> Function() createResources = _pointer
      .ref
      .resourcesCreate
      .asFunction<Pointer<Void> Function()>();
  late final void Function(Pointer<Void>) destroyResources = _pointer
      .ref
      .resourcesDestroy
      .asFunction<void Function(Pointer<Void>)>();
  late final void Function(Pointer<Void>) fsClear = _pointer.ref.resourcesClear
      .asFunction<void Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>, Pointer<Utf8>) fsMountDirectory =
      _pointer.ref.resourcesMountDirectory
          .asFunction<int Function(Pointer<Void>, Pointer<Utf8>)>();
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
  fsMountPfs = _pointer.ref.resourcesMountPfs
      .asFunction<int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>();
  late final int Function(Pointer<Void>, Pointer<Utf8>) fsSetSaveDir = _pointer
      .ref
      .resourcesSetSaveDir
      .asFunction<int Function(Pointer<Void>, Pointer<Utf8>)>();
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, int)
  fsSetOverride = _pointer.ref.resourcesSetOverride
      .asFunction<
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, int)
      >();
  late final void Function(Pointer<Void>) fsClearOverrides = _pointer
      .ref
      .resourcesClearOverrides
      .asFunction<void Function(Pointer<Void>)>();
  late final Pointer<Void> Function(int, int, int) createRuntime = _pointer
      .ref
      .runtimeCreate
      .asFunction<Pointer<Void> Function(int, int, int)>();
  late final void Function(Pointer<Void>) destroyRuntime = _pointer
      .ref
      .runtimeDestroy
      .asFunction<void Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>, Pointer<Void>) setRuntimeResources =
      _pointer.ref.runtimeSetResources
          .asFunction<int Function(Pointer<Void>, Pointer<Void>)>();
  bool get hasRuntimeMedia =>
      _pointer.ref.runtimeSetRuntimeMediaEnabled != nullptr;
  late final void Function(Pointer<Void>, int) setRuntimeMediaEnabled = _pointer
      .ref
      .runtimeSetRuntimeMediaEnabled
      .asFunction<void Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>, int) advanceAndPresent = _pointer
      .ref
      .runtimeAdvanceAndPresent
      .asFunction<int Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>, int) advanceWithoutRender = _pointer
      .ref
      .runtimeAdvanceWithoutRender
      .asFunction<int Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>) stageWidth = _pointer
      .ref
      .runtimeStageWidth
      .asFunction<int Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>) stageHeight = _pointer
      .ref
      .runtimeStageHeight
      .asFunction<int Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
  loadProject = _pointer.ref.runtimeLoadProject
      .asFunction<int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>();
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Utf8>)
  loadProjectBytes = _pointer.ref.runtimeLoadProjectBytes
      .asFunction<
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Utf8>)
      >();
  late final int Function(Pointer<Void>) pixelBufferSize = _pointer
      .ref
      .runtimePixelBufferSize
      .asFunction<int Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>, int, Pointer<Uint8>, int)
  advanceAndRender = _pointer.ref.runtimeAdvanceAndRender
      .asFunction<int Function(Pointer<Void>, int, Pointer<Uint8>, int)>();
  late final int Function(Pointer<Void>, int, Pointer<Void>, int, int)
  setExternalSurface = _pointer.ref.runtimeSetExternalSurface
      .asFunction<int Function(Pointer<Void>, int, Pointer<Void>, int, int)>();
  late final void Function(Pointer<Void>) clearExternalSurface = _pointer
      .ref
      .runtimeClearExternalSurface
      .asFunction<void Function(Pointer<Void>)>();
  late final void Function(Pointer<Void>, int, int) feedMouse = _pointer
      .ref
      .runtimeFeedMouse
      .asFunction<void Function(Pointer<Void>, int, int)>();
  late final void Function(Pointer<Void>) feedClick = _pointer
      .ref
      .runtimeFeedClick
      .asFunction<void Function(Pointer<Void>)>();
  late final void Function(Pointer<Void>, int, int) feedMouseButton = _pointer
      .ref
      .runtimeFeedMouseButton
      .asFunction<void Function(Pointer<Void>, int, int)>();
  late final void Function(Pointer<Void>, int, int, int, int) feedTouch =
      _pointer.ref.runtimeFeedTouch
          .asFunction<void Function(Pointer<Void>, int, int, int, int)>();
  late final void Function(Pointer<Void>, int, int) feedKey = _pointer
      .ref
      .runtimeFeedKey
      .asFunction<void Function(Pointer<Void>, int, int)>();
  late final int Function(Pointer<Void>, int, Pointer<Utf8>) submitDialog =
      _pointer.ref.runtimeSubmitDialog
          .asFunction<int Function(Pointer<Void>, int, Pointer<Utf8>)>();
  late final int Function(Pointer<Void>, int, Pointer<Utf8>)
  submitTextTranslation = _pointer.ref.runtimeSubmitTextTranslation
      .asFunction<int Function(Pointer<Void>, int, Pointer<Utf8>)>();
  late final void Function(Pointer<Void>, Pointer<Utf8>) setReportedOs =
      _pointer.ref.runtimeSetReportedOs
          .asFunction<void Function(Pointer<Void>, Pointer<Utf8>)>();
  late final int Function(Pointer<Void>, int) setEmoteBackend = _pointer
      .ref
      .runtimeSetEmoteBackend
      .asFunction<int Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>, double, double)
  configureSpatialUpscale = _pointer.ref.runtimeConfigureSpatialUpscale
      .asFunction<int Function(Pointer<Void>, double, double)>();
  late final int Function(Pointer<Void>, int) setRenderQualityPreset = _pointer
      .ref
      .runtimeSetRenderQualityPreset
      .asFunction<int Function(Pointer<Void>, int)>();
  late final void Function(Pointer<Void>, int) setProfilerEnabled = _pointer
      .ref
      .runtimeSetProfilerEnabled
      .asFunction<void Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>, Pointer<Uint8>, int) profilerSnapshot =
      _pointer.ref.runtimeProfilerSnapshot
          .asFunction<int Function(Pointer<Void>, Pointer<Uint8>, int)>();
  late final void Function(Pointer<Void>, Pointer<Utf8>, double) setVolume =
      _pointer.ref.runtimeSetVolume
          .asFunction<void Function(Pointer<Void>, Pointer<Utf8>, double)>();
  late final void Function(Pointer<Void>, Pointer<Utf8>) notifyVideoFinished =
      _pointer.ref.runtimeNotifyVideoFinished
          .asFunction<void Function(Pointer<Void>, Pointer<Utf8>)>();
  late final void Function(Pointer<Void>, Pointer<Utf8>) notifySoundFinished =
      _pointer.ref.runtimeNotifySoundFinished
          .asFunction<void Function(Pointer<Void>, Pointer<Utf8>)>();
  late final void Function(Pointer<Void>, int) notifyLifecycle = _pointer
      .ref
      .runtimeNotifyLifecycle
      .asFunction<void Function(Pointer<Void>, int)>();
  late final int Function(Pointer<Void>) isExitRequested = _pointer
      .ref
      .runtimeIsExitRequested
      .asFunction<int Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>) backendCapabilities = _pointer
      .ref
      .runtimeBackendCapabilities
      .asFunction<int Function(Pointer<Void>)>();
  late final int Function(Pointer<Void>, int, Pointer<Uint8>, int)
  submitHttpResult = _pointer.ref.runtimeSubmitHttpResult
      .asFunction<int Function(Pointer<Void>, int, Pointer<Uint8>, int)>();
  late final void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
  setStringVariable = _pointer.ref.runtimeSetStringVariable
      .asFunction<void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>();
  late final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Utf8>,
    Pointer<Uint8>,
    int,
  )
  probeCaption = _pointer.ref.probeCaption
      .asFunction<
        int Function(
          Pointer<Void>,
          Pointer<Uint8>,
          int,
          Pointer<Utf8>,
          Pointer<Uint8>,
          int,
        )
      >();
  late final void Function(Pointer<Utf8>) setAnglePath = _pointer
      .ref
      .setAnglePath
      .asFunction<void Function(Pointer<Utf8>)>();
  late final void Function(int) setDebug = _pointer.ref.setDebug
      .asFunction<void Function(int)>();
  late final void Function(int) setDamageVisualization = _pointer
      .ref
      .setDamageVisualization
      .asFunction<void Function(int)>();
  late final int Function(Pointer<Uint8>, int) setFontOverride = _pointer
      .ref
      .setFontOverride
      .asFunction<int Function(Pointer<Uint8>, int)>();
  late final void Function() clearFontOverride = _pointer.ref.clearFontOverride
      .asFunction<void Function()>();
  late final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    int,
    int,
    Pointer<Uint8>,
    int,
  )
  uploadVideoLayerFrame = _pointer.ref.runtimeUploadVideoLayerFrame
      .asFunction<
        int Function(
          Pointer<Void>,
          Pointer<Utf8>,
          int,
          int,
          Pointer<Uint8>,
          int,
        )
      >();
}
