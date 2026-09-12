import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/engine_runtime.dart';
import '../services/logger.dart';
import '../models/input_gate.dart';
import 'caption_table_probe.dart';
import 'core_api.dart';
import 'file_provider.dart';
import 'media_bridge.dart';
import 'profiler_snapshot.dart';
import 'project_charset.dart';
import 'text_translation_service.dart';

export '../engine/engine_runtime.dart'
    show AvoidOverlay, EngineDialogRequest, EngineVideoPlayback;

typedef HostEventsEnableNative = Void Function(Pointer<Void>, Int32);
typedef HostEventsEnable = void Function(Pointer<Void> events, int enabled);
typedef HostEventsNextNative = UintPtr Function(Pointer<Void>);
typedef HostEventsNext = int Function(Pointer<Void> events);
typedef HostEventsPollNative =
    UintPtr Function(
      Pointer<Void> events,
      Pointer<Uint8> output,
      UintPtr capacity,
      Pointer<Uint32> count,
    );
typedef HostEventsPoll =
    int Function(
      Pointer<Void> events,
      Pointer<Uint8> output,
      int capacity,
      Pointer<Uint32> count,
    );
typedef HostSetFontListNative =
    Int32 Function(
      Pointer<Void> events,
      Int32 monospace,
      Int32 vertical,
      Pointer<Uint8> data,
      UintPtr len,
    );
typedef HostSetFontList =
    int Function(
      Pointer<Void> events,
      int monospace,
      int vertical,
      Pointer<Uint8> data,
      int len,
    );
typedef HostSetWindowStateNative = Void Function(Pointer<Void>, Int32 flags);
typedef HostSetWindowState = void Function(Pointer<Void> events, int flags);
typedef HostSetTextReplacementsNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8> data, UintPtr len);
typedef HostSetTextReplacements =
    int Function(Pointer<Void> events, Pointer<Uint8> data, int len);
typedef HostSetTextTranslationEnabledNative =
    Void Function(Pointer<Void>, Int32 enabled);
typedef HostSetTextTranslationEnabled =
    void Function(Pointer<Void> events, int enabled);
typedef HostClearStateNative = Void Function(Pointer<Void>);
typedef HostClearState = void Function(Pointer<Void> events);

// 生命周期通知：state 0=退出 / 1=切后台 / 2=回前台（驱动 [autosave allow=1]）。
typedef NotifyLifecycleNative = Void Function(Pointer<Void> rt, Int32 state);
typedef NotifyLifecycleDart = void Function(Pointer<Void> rt, int state);

void _dispatchLog(String level, String msg) {
  switch (level) {
    case 'D':
      Log.debug(msg);
    case 'I':
      Log.info(msg);
    case 'W':
      Log.warn(msg);
    case 'E':
      Log.error(msg);
    default:
      Log.info(msg);
  }
}

void _dispatchMediaCommand(String kind, String rawPayload) {
  final decoded = jsonDecode(rawPayload);
  final payload = decoded is Map
      ? decoded.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  CoreBridge._activeBridge?.media.handleCommand(kind, payload);
}

void _dispatchUiCommand(String kind, String rawPayload) {
  final decoded = jsonDecode(rawPayload);
  final payload = decoded is Map
      ? decoded.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  final bridge = CoreBridge._activeBridge;
  if (bridge == null) return;
  switch (kind) {
    case 'dialog_show':
      if (bridge.onDialogRequested != null) {
        final request = EngineDialogRequest.fromJson(payload);
        scheduleMicrotask(() => bridge.onDialogRequested!(request));
      }
    case 'text_translate':
      final serial = (payload['serial'] as num?)?.toInt();
      final text = payload['text']?.toString();
      final ruby = payload['ruby']?.toString();
      if (serial != null && text != null) {
        scheduleMicrotask(
          () => bridge._queueTranslation(serial, text, ruby: ruby),
        );
      }
    case 'avoid':
      // 紧急回避：show 时全屏覆盖（可带图），hide 时撤除。UI 层观察此 notifier。
      final action = payload['action']?.toString();
      if (action == 'show') {
        bridge.avoidOverlay.value = AvoidOverlay(
          file: payload['file']?.toString(),
        );
      } else {
        bridge.avoidOverlay.value = null;
      }
    case 'mouse':
      bridge.applyMouseConfig(payload);
    case 'caption':
      // core 发的字段是 data（events.rs），旧代码读 caption/text 一直取不到值。
      final title =
          payload['data']?.toString() ??
          payload['caption']?.toString() ??
          payload['text']?.toString();
      if (title != null) bridge.windowTitle.value = title;
    case 'write_clipboard':
      final text = payload['text']?.toString();
      if (text != null) {
        scheduleMicrotask(() => Clipboard.setData(ClipboardData(text: text)));
      }
    case 'vibrate':
      scheduleMicrotask(HapticFeedback.mediumImpact);
    case 'statusbar':
      final show = _asBool(payload['show']) || _asBool(payload['visible']);
      scheduleMicrotask(
        () => SystemChrome.setEnabledSystemUIMode(
          show ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
        ),
      );
    case 'openbrowser':
      // [openbrowser]：用系统默认浏览器打开 url。桌面无依赖走 Process.run
      //（open / cmd start / xdg-open）；移动端无外部命令路径，暂不支持。
      final url = payload['url']?.toString();
      if (url != null && url.isNotEmpty) {
        scheduleMicrotask(() => _openInBrowser(url));
      }
    default:
      // 未处理的 kind（http_request/callnative 等）暂由宿主按需扩展。
      break;
  }
}

/// 用系统默认浏览器打开 url（桌面无依赖方案）。Windows 的 `start` 需一个空标题
/// 占位参数，否则含空格/& 的 url 会被当成窗口标题。移动端无外部命令，静默忽略。
Future<void> _openInBrowser(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    } else {
      Log.warn('[CoreBridge] openbrowser 在此平台不支持: $url');
    }
  } catch (e) {
    Log.error('[CoreBridge] openbrowser 失败: $e');
  }
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

int? _asInt(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

// ── Core FFI type definitions ───────────────────────────────────

typedef RuntimeCreateNative =
    Pointer<Void> Function(Uint32 w, Uint32 h, Int32 backend);
typedef RuntimeSetEmoteBackendNative =
    Int32 Function(Pointer<Void> rt, Int32 backend);
typedef RuntimeBackendCapabilitiesNative = Uint64 Function(Pointer<Void> rt);
typedef RuntimeConfigureSpatialUpscaleNative =
    Int32 Function(Pointer<Void> rt, Float renderScale, Float sharpness);
typedef RuntimeLoadProjectNative =
    Int32 Function(Pointer<Void> rt, Pointer<Utf8> ini, Pointer<Utf8> platform);
typedef RuntimeLoadProjectBytesNative =
    Int32 Function(
      Pointer<Void> rt,
      Pointer<Uint8> ini,
      IntPtr iniLen,
      Pointer<Utf8> platform,
    );
typedef RuntimeFeedMouseNative =
    Void Function(Pointer<Void> rt, Int32 x, Int32 y);
typedef RuntimeFeedClickNative = Void Function(Pointer<Void> rt);
typedef RuntimeFeedMouseButtonNative =
    Void Function(Pointer<Void> rt, Uint32 button, Int32 pressed);
typedef RuntimeFeedTouchNative =
    Void Function(Pointer<Void> rt, Uint32 id, Uint8 phase, Int32 x, Int32 y);
// Headless caption 探测（导入时用）：不需要 runtime，只需 lib + 已注册文件读回调。
typedef ProbeCaptionNative =
    Int32 Function(
      Pointer<Uint8> ini,
      IntPtr iniLen,
      Pointer<Utf8> platform,
      Pointer<Uint8> outBuf,
      Int32 cap,
    );
typedef RuntimeFeedKeyNative =
    Void Function(Pointer<Void> rt, Uint32 vk, Int32 pressed);
typedef RuntimeSubmitDialogNative =
    Int32 Function(Pointer<Void> rt, Int32 accepted, Pointer<Utf8> text);
typedef RuntimeSubmitTextTranslationNative =
    Int32 Function(Pointer<Void> rt, Uint64 serial, Pointer<Utf8> text);
typedef RuntimeStageWidthNative = Uint32 Function(Pointer<Void> rt);
typedef RuntimeStageHeightNative = Uint32 Function(Pointer<Void> rt);
typedef RuntimePixelBufferSizeNative = Uint32 Function(Pointer<Void> rt);
typedef RuntimeAdvanceRenderNative =
    Uint32 Function(
      Pointer<Void> rt,
      Uint32 deltaMs,
      Pointer<Uint8> outPixels,
      Uint32 capacity,
    );
typedef RuntimeIsExitRequestedNative = Int32 Function(Pointer<Void> rt);
typedef RuntimeDestroyNative = Void Function(Pointer<Void> rt);
typedef RuntimeNotifyVideoFinishedNative =
    Void Function(Pointer<Void> rt, Pointer<Utf8> id);
typedef RuntimeNotifySoundFinishedNative =
    Void Function(Pointer<Void> rt, Pointer<Utf8> id);
typedef RuntimeAdvanceWithoutRenderNative =
    Int32 Function(Pointer<Void> rt, Uint32 deltaMs);
typedef RuntimeAdvanceWithoutRender =
    int Function(Pointer<Void> rt, int deltaMs);
typedef RuntimeSetExternalSurfaceNative =
    Int32 Function(
      Pointer<Void> rt,
      Int32 kind,
      Pointer<Void> handle,
      Uint32 width,
      Uint32 height,
    );
typedef RuntimeSetExternalSurface =
    int Function(
      Pointer<Void> rt,
      int kind,
      Pointer<Void> handle,
      int width,
      int height,
    );
typedef RuntimeClearExternalSurfaceNative = Void Function(Pointer<Void> rt);
typedef RuntimeClearExternalSurface = void Function(Pointer<Void> rt);
typedef RuntimeAdvancePresentNative =
    Int32 Function(Pointer<Void> rt, Uint32 deltaMs);
typedef RuntimeAdvancePresent = int Function(Pointer<Void> rt, int deltaMs);
typedef RuntimeSetProfilerEnabledNative =
    Void Function(Pointer<Void> rt, Int32 enabled);
typedef RuntimeSetProfilerEnabled =
    void Function(Pointer<Void> rt, int enabled);
typedef RuntimeSetRuntimeMediaEnabledNative =
    Void Function(Pointer<Void> rt, Int32 enabled);
typedef RuntimeSetRuntimeMediaEnabled =
    void Function(Pointer<Void> rt, int enabled);
typedef RuntimeProfilerSnapshotNative =
    Int32 Function(Pointer<Void> rt, Pointer<Uint8> output, Uint32 capacity);
typedef RuntimeProfilerSnapshot =
    int Function(Pointer<Void> rt, Pointer<Uint8> output, int capacity);

final class _HostEventApi {
  const _HostEventApi({
    required this.handle,
    required this._enable,
    required this._nextEventBytes,
    required this._poll,
    required this._setFontList,
    required this._setWindowState,
    required this._setTextReplacements,
    required this._setTextTranslationEnabled,
    required this._clearState,
  });

  final Pointer<Void> handle;
  final HostEventsEnable _enable;
  final HostEventsNext _nextEventBytes;
  final HostEventsPoll _poll;
  final HostSetFontList _setFontList;
  final HostSetWindowState _setWindowState;
  final HostSetTextReplacements _setTextReplacements;
  final HostSetTextTranslationEnabled _setTextTranslationEnabled;
  final HostClearState _clearState;

  void enable(int enabled) => _enable(handle, enabled);

  int nextEventBytes() => _nextEventBytes(handle);

  int poll(Pointer<Uint8> output, int capacity, Pointer<Uint32> count) =>
      _poll(handle, output, capacity, count);

  int setFontList(int monospace, int vertical, Pointer<Uint8> data, int len) =>
      _setFontList(handle, monospace, vertical, data, len);

  void setWindowState(int flags) => _setWindowState(handle, flags);

  int setTextReplacements(Pointer<Uint8> data, int len) =>
      _setTextReplacements(handle, data, len);

  void setTextTranslationEnabled(int enabled) =>
      _setTextTranslationEnabled(handle, enabled);

  void clearState() => _clearState(handle);
}

// ── CoreBridge — manages the core runtime lifecycle ─────────────

class CoreBridge {
  static const int _hostEventHeaderSize = 24;
  static const int _hostEventBufferBytes = 256 * 1024;
  static CoreBridge? _activeBridge;

  CoreBridge({this.onDialogRequested, bool? engineCursorControlEnabled})
    : _engineCursorControlEnabled =
          engineCursorControlEnabled ?? Platform.isWindows {
    _sharedTextureChannel.setMethodCallHandler(_handleSharedTextureCall);
  }

  final void Function(EngineDialogRequest request)? onDialogRequested;
  bool _initialized = false;
  DynamicLibrary? _lib;
  CoreApiV1? _coreApi;
  Pointer<Void>? _resources;
  Pointer<Void>? _runtime;
  _HostEventApi? _hostEvents;
  RuntimeAdvanceWithoutRender? _advanceWithoutRender;
  bool _advanceWithoutRenderUnavailable = false;
  RuntimeSetExternalSurface? _setExternalSurface;
  RuntimeClearExternalSurface? _clearExternalSurface;
  RuntimeAdvancePresent? _advancePresent;
  RuntimeSetProfilerEnabled? _setProfilerEnabled;
  RuntimeProfilerSnapshot? _profilerSnapshot;
  int? _backendCapabilities;
  bool _backendCapabilitiesUnavailable = false;
  bool _profilerSymbolsUnavailable = false;
  bool _fontOverrideSymbolsUnavailable = false;
  bool _sharedTextureSymbolsUnavailable = false;

  /// 输入门控：喂给 core 前的统一过滤/重映射，默认全放行。
  InputGatePolicy _inputGate = InputGatePolicy.full;
  int? _sharedTextureId;
  int? _sharedTextureKind;
  bool _sharedTextureAttached = false;
  int _sharedTextureWidth = 0;
  int _sharedTextureHeight = 0;
  TextTranslationService? translation;
  int _stageWidth = 1280;
  int _stageHeight = 720;

  static const MethodChannel _sharedTextureChannel = MethodChannel(
    'moe.alphaly.art3m1s/shared_texture',
  );

  /// 紧急回避（[avoid] + keyconfig role15）：非 null 时 UI 层显示全屏覆盖。
  final ValueNotifier<AvoidOverlay?> avoidOverlay = ValueNotifier(null);

  final bool _engineCursorControlEnabled;
  bool _cursorExplicitlyHidden = false;
  int _cursorAutoHideMs = 0;
  Timer? _cursorAutoHideTimer;

  /// 是否隐藏游戏区域的鼠标光标（由 Windows 专用 [mouse] 标签驱动）。
  final ValueNotifier<bool> cursorHidden = ValueNotifier(false);

  /// 应用 [mouse] 的 hide/autohide 参数。
  ///
  /// Artemis 文档明确该标签只适用于 Windows。运行时启动 OS 可以在 macOS/Linux
  /// 上模拟 Windows 脚本分支，但不能因此隐藏真实宿主的系统光标。
  @visibleForTesting
  void applyMouseConfig(Map<String, dynamic> payload) {
    if (!_engineCursorControlEnabled) {
      _resetCursorState();
      return;
    }

    final hideValue = payload['hide'] ?? payload['hidden'];
    final autoHideValue = payload['autohide'];
    final hasHide = hideValue != null;
    final hasAutoHide = autoHideValue != null;
    if (!hasHide && !hasAutoHide) return;

    if (hasHide) {
      _cursorExplicitlyHidden = _asBool(hideValue);
    }
    if (hasAutoHide) {
      _cursorAutoHideMs = (_asInt(autoHideValue) ?? 0)
          .clamp(0, 1 << 31)
          .toInt();
    }

    _cursorAutoHideTimer?.cancel();
    if (_cursorExplicitlyHidden) {
      _setCursorHidden(true);
      return;
    }

    _setCursorHidden(false);
    _armCursorAutoHide();
  }

  /// 鼠标移动后重新显示 autohide 光标，并从头开始计算隐藏时间。
  void notifyMouseActivity() {
    if (!_engineCursorControlEnabled || _cursorExplicitlyHidden) return;
    if (_cursorAutoHideMs <= 0) return;
    _setCursorHidden(false);
    _armCursorAutoHide();
  }

  void _armCursorAutoHide() {
    _cursorAutoHideTimer?.cancel();
    if (_cursorAutoHideMs <= 0 || _cursorExplicitlyHidden) return;
    _cursorAutoHideTimer = Timer(
      Duration(milliseconds: _cursorAutoHideMs),
      () => _setCursorHidden(true),
    );
  }

  void _setCursorHidden(bool hidden) {
    if (cursorHidden.value != hidden) cursorHidden.value = hidden;
  }

  void _resetCursorState() {
    _cursorAutoHideTimer?.cancel();
    _cursorAutoHideTimer = null;
    _cursorExplicitlyHidden = false;
    _cursorAutoHideMs = 0;
    _setCursorHidden(false);
  }

  /// 脚本请求的窗口标题（ui_command caption），壳层可观察后落实到平台窗口。
  final ValueNotifier<String?> windowTitle = ValueNotifier(null);

  /// 窗口状态位（bit0=全屏 bit1=最小化），由壳层随窗口事件更新，供
  /// var system=fullscreen/minimize 同步查询。默认 0（非全屏、非最小化）。
  int _windowStateBits = 0;
  int get windowStateBits => _windowStateBits;
  void setWindowStateBits({bool? fullscreen, bool? minimized}) {
    var bits = _windowStateBits;
    if (fullscreen != null) {
      bits = fullscreen ? (bits | 0x1) : (bits & ~0x1);
    }
    if (minimized != null) {
      bits = minimized ? (bits | 0x2) : (bits & ~0x2);
    }
    _windowStateBits = bits;
    _hostEvents?.setWindowState(bits);
  }

  /// 可枚举字体族（var system=get_font）。Flutter 无系统字体枚举 API，故返回
  /// 随包字体 + 各平台常见 CJK 字体的保守清单；宿主可按需扩充/换成平台通道枚举。
  List<String> enumerateFonts({bool monospace = false, bool vertical = false}) {
    if (monospace) {
      return const ['Menlo', 'Consolas', 'DejaVu Sans Mono', 'Courier New'];
    }
    return const [
      'Source Han Sans',
      'Noto Sans CJK',
      'PingFang SC',
      'Hiragino Sans',
      'Yu Gothic',
      'MS Gothic',
      'Microsoft YaHei',
      'SimSun',
    ];
  }

  late final MediaBridge media = MediaBridge(
    onVideoFinished: notifyVideoFinished,
    onSoundFinished: notifySoundFinished,
  );

  bool get isInitialized => _initialized;
  Pointer<Void>? get runtime => _runtime;
  int get stageWidth => _stageWidth;
  int get stageHeight => _stageHeight;
  int? get sharedTextureId => _sharedTextureId;
  int get sharedTextureWidth => _sharedTextureWidth;
  int get sharedTextureHeight => _sharedTextureHeight;
  bool get hasActiveSharedTexture =>
      _sharedTextureId != null && _sharedTextureAttached;

  Future<int?> enableSharedTexture({
    int? outputWidth,
    int? outputHeight,
  }) async {
    final runtime = _runtime;
    final lib = _lib;
    if (runtime == null || lib == null || _sharedTextureSymbolsUnavailable) {
      return null;
    }
    final width = math.max(outputWidth ?? _stageWidth, _stageWidth);
    final height = math.max(outputHeight ?? _stageHeight, _stageHeight);
    if (_sharedTextureAttached &&
        _sharedTextureId != null &&
        _sharedTextureWidth == width &&
        _sharedTextureHeight == height) {
      return _sharedTextureId;
    }
    final coreApi = _coreApi;
    if (coreApi != null) {
      _setExternalSurface = coreApi.setExternalSurface;
      _clearExternalSurface = coreApi.clearExternalSurface;
      _advancePresent = coreApi.advanceAndPresent;
    } else {
      try {
        _setExternalSurface ??= lib
            .lookupFunction<
              RuntimeSetExternalSurfaceNative,
              RuntimeSetExternalSurface
            >('art3m1s_runtime_set_external_surface');
        _clearExternalSurface ??= lib
            .lookupFunction<
              RuntimeClearExternalSurfaceNative,
              RuntimeClearExternalSurface
            >('art3m1s_runtime_clear_external_surface');
        _advancePresent ??= lib
            .lookupFunction<RuntimeAdvancePresentNative, RuntimeAdvancePresent>(
              'art3m1s_runtime_advance_and_present',
            );
      } catch (error) {
        _sharedTextureSymbolsUnavailable = true;
        Log.info('[CoreBridge] 当前 core 不支持共享纹理，使用 RGBA 回读: $error');
        return null;
      }
    }

    try {
      // Stop Core from presenting into the old object before the native texture
      // host unregisters/releases it during recreation.
      _detachSharedTexture();
      final raw = await _sharedTextureChannel.invokeMapMethod<String, dynamic>(
        'create',
        {'width': width, 'height': height},
      );
      if (raw == null ||
          !_attachSharedTexture(raw, width: width, height: height)) {
        await _sharedTextureChannel.invokeMethod<void>('release');
        _sharedTextureId = null;
        _sharedTextureKind = null;
        return null;
      }
      Log.info(
        '[CoreBridge] 共享纹理已启用: id=$_sharedTextureId '
        '${_sharedTextureWidth}x$_sharedTextureHeight '
        '(stage=${_stageWidth}x$_stageHeight)',
      );
      return _sharedTextureId;
    } catch (error) {
      Log.warn('[CoreBridge] 共享纹理不可用，使用 RGBA 回读: $error');
      _sharedTextureId = null;
      _sharedTextureKind = null;
      unawaited(
        _sharedTextureChannel.invokeMethod<void>('release').catchError((_) {}),
      );
      return null;
    }
  }

  bool _attachSharedTexture(
    Map<dynamic, dynamic> descriptor, {
    int? width,
    int? height,
  }) {
    final runtime = _runtime;
    final setSurface = _setExternalSurface;
    final textureId = (descriptor['textureId'] as num?)?.toInt();
    if (runtime == null || setSurface == null || textureId == null) {
      return false;
    }
    final surfaceWidth = width ?? _sharedTextureWidth;
    final surfaceHeight = height ?? _sharedTextureHeight;
    if (surfaceWidth <= 0 || surfaceHeight <= 0) return false;

    final candidates = <(int?, int?)>[
      (
        (descriptor['kind'] as num?)?.toInt(),
        (descriptor['handle'] as num?)?.toInt(),
      ),
      (
        (descriptor['fallbackKind'] as num?)?.toInt(),
        (descriptor['fallbackHandle'] as num?)?.toInt(),
      ),
    ];
    for (final (kind, handle) in candidates) {
      if (kind == null || handle == null || handle == 0) continue;
      final attached =
          setSurface(
            runtime,
            kind,
            Pointer<Void>.fromAddress(handle),
            surfaceWidth,
            surfaceHeight,
          ) !=
          0;
      if (!attached) continue;
      _sharedTextureId = textureId;
      _sharedTextureKind = kind;
      _sharedTextureAttached = true;
      _sharedTextureWidth = surfaceWidth;
      _sharedTextureHeight = surfaceHeight;
      return true;
    }
    return false;
  }

  Future<void> _handleSharedTextureCall(MethodCall call) async {
    switch (call.method) {
      case 'surfaceCleanup':
        _detachSharedTexture();
      case 'surfaceAvailable':
        final descriptor = call.arguments;
        if (descriptor is Map && !_attachSharedTexture(descriptor)) {
          Log.warn('[CoreBridge] 无法重新绑定 Android 共享纹理 surface');
        }
    }
  }

  void _detachSharedTexture() {
    final runtime = _runtime;
    if (runtime != null && _sharedTextureAttached) {
      _clearExternalSurface?.call(runtime);
    }
    _sharedTextureAttached = false;
  }

  int advanceAndPresent(int deltaMs) {
    final runtime = _runtime;
    final present = _advancePresent;
    if (runtime == null || present == null || !_sharedTextureAttached) {
      return -1;
    }
    final result = present(runtime, deltaMs);
    _drainHostEvents();
    if (result > 0 && (_sharedTextureKind == 2 || _sharedTextureKind == 3)) {
      unawaited(
        _sharedTextureChannel.invokeMethod<void>('frameAvailable').catchError((
          Object error,
        ) {
          Log.warn('[CoreBridge] 共享纹理帧通知失败: $error');
        }),
      );
    } else if (result < 0) {
      Log.warn('[CoreBridge] 共享纹理提交失败，回退到 RGBA 路径');
      _detachSharedTexture();
    }
    return result;
  }

  void _loadLibrary() {
    if (_lib != null) return;
    if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
      return;
    }
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
      final lib = _lib;
      if (lib == null) {
        throw StateError('core dynamic library is unavailable');
      }
      final coreApi = CoreApiV1.tryLoad(lib);
      if (coreApi == null) {
        throw StateError('core 缺少 art3m1s_get_api_v1，拒绝加载旧 ABI');
      }
      _coreApi = coreApi;
      _resources = coreApi.createResources();
      if (_resources == nullptr) {
        _coreApi = null;
        _resources = null;
        throw StateError('core 创建资源句柄失败');
      }
      Log.info('[CoreBridge] 使用版本化 C ABI v1');
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      if (Platform.isMacOS) {
        configureAngle(executableDirectory.path);
      } else if (Platform.isIOS) {
        configureAngle('${executableDirectory.path}/Frameworks');
      }
    } catch (e) {
      Log.error('[CoreBridge] Core 库加载失败: $e');
      _initialized = false;
      return;
    }
    try {
      _registerHostEvents();
      _drainHostEvents();
      _initialized = true;
    } catch (error) {
      Log.error('[CoreBridge] host events v1 初始化失败: $error');
      _initialized = false;
    }
  }

  void _registerHostEvents() {
    if (_lib == null) return;
    _activeBridge = this;
    if (!_tryEnableHostEvents()) {
      throw StateError('core 缺少 host events v1，拒绝使用旧 callback ABI');
    }
  }

  bool _tryEnableHostEvents() {
    final coreApi = _coreApi;
    if (coreApi == null) return false;
    Pointer<Void> handle = nullptr;
    try {
      handle = coreApi.createHostEvents();
      if (handle == nullptr) {
        Log.error('[CoreBridge] 创建 host events 句柄失败');
        return false;
      }
      final api = _HostEventApi(
        handle: handle,
        enable: coreApi.hostEventsEnable,
        nextEventBytes: coreApi.hostEventsNext,
        poll: coreApi.pollEvents,
        setFontList: coreApi.setFontList,
        setWindowState: coreApi.setWindowState,
        setTextReplacements: coreApi.setTextReplacements,
        setTextTranslationEnabled: coreApi.setTextTranslationEnabled,
        clearState: coreApi.clearHostState,
      );
      api.enable(1);
      api.clearState();
      _syncHostState();
      _hostEvents = api;
      Log.info('[CoreBridge] 使用无反向回调 host events 通道');
      return true;
    } catch (error) {
      if (handle != nullptr) {
        try {
          coreApi.destroyHostEvents(handle);
        } catch (_) {}
      }
      Log.error('[CoreBridge] host events v1 启用失败: $error');
      return false;
    }
  }

  void configureTranslation(TextTranslationService? service) {
    final previous = translation;
    translation = service;
    if (previous != null && previous != service) {
      unawaited(previous.dispose());
    }
    _syncTextTranslation();
  }

  void _syncHostState() {
    final api = _hostEvents;
    if (api == null) return;
    _pushFontList(api, monospace: false, vertical: false);
    _pushFontList(api, monospace: true, vertical: false);
    api.setWindowState(_windowStateBits);
    _syncTextTranslation();
  }

  void _pushFontList(
    _HostEventApi api, {
    required bool monospace,
    required bool vertical,
  }) {
    final names = enumerateFonts(monospace: monospace, vertical: vertical);
    final bytes = utf8.encode(names.join('\n'));
    final ptr = bytes.isEmpty ? nullptr : malloc.allocate<Uint8>(bytes.length);
    try {
      if (bytes.isNotEmpty) {
        ptr.asTypedList(bytes.length).setAll(0, bytes);
      }
      api.setFontList(monospace ? 1 : 0, vertical ? 1 : 0, ptr, bytes.length);
    } finally {
      if (ptr != nullptr) malloc.free(ptr);
    }
  }

  void _syncTextTranslation() {
    final api = _hostEvents;
    if (api == null) return;
    final service = translation;
    if (service == null || !service.hostTranslationEnabled) {
      api.setTextTranslationEnabled(0);
      api.setTextReplacements(nullptr, 0);
      return;
    }
    final bytes = utf8.encode(jsonEncode(service.hostReplacementTable));
    final ptr = malloc.allocate<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      if (api.setTextReplacements(ptr, bytes.length) == 0) {
        Log.warn('[CoreBridge] 翻译替换表提交失败');
      }
      api.setTextTranslationEnabled(service.hostOnlineEnabled ? 1 : 0);
    } finally {
      malloc.free(ptr);
    }
  }

  void _drainHostEvents() {
    final api = _hostEvents;
    if (api == null) return;
    var capacity = _hostEventBufferBytes;
    var output = malloc.allocate<Uint8>(capacity);
    final count = calloc<Uint32>();
    try {
      while (true) {
        final nextEvent = api.nextEventBytes();
        if (nextEvent <= 0) break;
        if (nextEvent > capacity) {
          malloc.free(output);
          capacity = nextEvent;
          output = malloc.allocate<Uint8>(capacity);
        }
        final written = api.poll(output, capacity, count);
        if (written <= 0 || count.value == 0) break;
        _handleHostEventBuffer(output, written, count.value);
      }
    } catch (error) {
      Log.error('[CoreBridge] host event 拉取失败: $error');
    } finally {
      malloc.free(output);
      calloc.free(count);
    }
  }

  void _handleHostEventBuffer(
    Pointer<Uint8> output,
    int written,
    int eventCount,
  ) {
    final bytes = output.asTypedList(written);
    final view = ByteData.sublistView(bytes);
    var offset = 0;
    for (var index = 0; index < eventCount; index++) {
      if (offset + _hostEventHeaderSize > written) break;
      final version = view.getUint32(offset, Endian.host);
      final kind = view.getUint32(offset + 4, Endian.host);
      final payloadLength = view.getUint32(offset + 16, Endian.host);
      final aux = view.getUint32(offset + 20, Endian.host);
      offset += _hostEventHeaderSize;
      if (offset + payloadLength > written) break;
      final payload = Uint8List.sublistView(
        bytes,
        offset,
        offset + payloadLength,
      );
      offset += payloadLength;
      if (version != 1) continue;
      switch (kind) {
        case 1:
          _dispatchLog(
            String.fromCharCode(aux),
            utf8.decode(payload, allowMalformed: true),
          );
        case 2:
          _dispatchHostJsonEvent(payload, _dispatchMediaCommand);
        case 3:
          _dispatchHostJsonEvent(payload, _dispatchUiCommand);
      }
    }
  }

  void _dispatchHostJsonEvent(
    Uint8List payload,
    void Function(String kind, String payload) dispatch,
  ) {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map) return;
    final kind = decoded['kind']?.toString();
    if (kind == null) return;
    dispatch(kind, jsonEncode(decoded['payload'] ?? <String, dynamic>{}));
  }

  /// 配置输入门控（每个游戏启动时按资料库条目/补丁设置一次）。
  /// 默认全放行；门控在该 bridge 的 feed 出口统一生效，覆盖播放页、
  /// 触控板模拟与软键盘等全部输入来源。
  void configureInputGate(InputGatePolicy gate) {
    _inputGate = gate;
  }

  void _queueTranslation(int serial, String source, {String? ruby}) {
    final service = translation;
    if (service == null) {
      submitTextTranslation(serial, null);
      return;
    }
    service.enqueue(
      source,
      ruby: ruby,
      onComplete: (translated) {
        if (translation == service) {
          submitTextTranslation(serial, translated);
        }
      },
    );
  }

  void setDebug(bool enabled) {
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.setDebug(enabled ? 1 : 0);
      return;
    }
    if (_lib == null) return;
    final fn = _lib!.lookupFunction<Void Function(Int32), void Function(int)>(
      'art3m1s_set_debug',
    );
    fn(enabled ? 1 : 0);
  }

  void setDamageVisualization(bool enabled) {
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.setDamageVisualization(enabled ? 1 : 0);
      return;
    }
    if (_lib == null) return;
    try {
      final fn = _lib!.lookupFunction<Void Function(Int32), void Function(int)>(
        'art3m1s_set_damage_visualization',
      );
      fn(enabled ? 1 : 0);
    } catch (_) {
      // Older cores do not expose this optional debug visualization control.
    }
  }

  /// 安装运行时覆盖字体（译文缺字时使用，TTF/OTF 字节）。
  /// 返回 false 表示 core 过旧（未导出符号）或字体非法。
  bool setFontOverride(Uint8List bytes) {
    final lib = _lib;
    if (lib == null || _fontOverrideSymbolsUnavailable || bytes.isEmpty) {
      return false;
    }
    try {
      final ptr = malloc.allocate<Uint8>(bytes.length);
      try {
        ptr.asTypedList(bytes.length).setAll(0, bytes);
        final coreApi = _coreApi;
        if (coreApi != null) {
          return coreApi.setFontOverride(ptr, bytes.length) == 1;
        }
        final fn = lib
            .lookupFunction<
              Int32 Function(Pointer<Uint8>, Int32),
              int Function(Pointer<Uint8>, int)
            >('art3m1s_set_font_override');
        return fn(ptr, bytes.length) == 1;
      } finally {
        malloc.free(ptr);
      }
    } catch (error) {
      _fontOverrideSymbolsUnavailable = true;
      Log.info('[CoreBridge] 当前 core 不支持运行时字体覆盖: $error');
      return false;
    }
  }

  /// 清除运行时覆盖字体，恢复游戏脚本字体。
  void clearFontOverride() {
    final lib = _lib;
    if (lib == null || _fontOverrideSymbolsUnavailable) return;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        coreApi.clearFontOverride();
        return;
      }
      final fn = lib.lookupFunction<Void Function(), void Function()>(
        'art3m1s_clear_font_override',
      );
      fn();
    } catch (error) {
      _fontOverrideSymbolsUnavailable = true;
      Log.info('[CoreBridge] 当前 core 不支持运行时字体覆盖: $error');
    }
  }

  /// 设置上报给脚本的机种串覆盖（如 'switch'/'ps4'）；null/空串清除。
  /// 移植版游戏把存档等功能开关在机种判断上时用它伪装。
  void setReportedOs(String? os) {
    final lib = _lib;
    final runtime = _runtime;
    if (lib == null || runtime == null) return;
    try {
      final ptr = (os == null || os.isEmpty)
          ? nullptr
          : os.toNativeUtf8().cast<Utf8>();
      try {
        final coreApi = _coreApi;
        if (coreApi != null) {
          coreApi.setReportedOs(runtime, ptr);
          return;
        }
        final fn = lib
            .lookupFunction<
              Void Function(Pointer<Void>, Pointer<Utf8>),
              void Function(Pointer<Void>, Pointer<Utf8>)
            >('art3m1s_runtime_set_reported_os');
        fn(runtime, ptr);
      } finally {
        if (ptr != nullptr) malloc.free(ptr);
      }
    } catch (error) {
      Log.warn('[CoreBridge] 当前 core 不支持机种上报覆盖: $error');
    }
  }

  bool setProfilerEnabled(bool enabled) {
    final runtime = _runtime;
    final lib = _lib;
    if (runtime == null || lib == null || _profilerSymbolsUnavailable) {
      return false;
    }
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        coreApi.setProfilerEnabled(runtime, enabled ? 1 : 0);
        return true;
      }
      final fn = _setProfilerEnabled ??= lib
          .lookupFunction<
            RuntimeSetProfilerEnabledNative,
            RuntimeSetProfilerEnabled
          >('art3m1s_runtime_set_profiler_enabled');
      fn(runtime, enabled ? 1 : 0);
      return true;
    } catch (error) {
      _profilerSymbolsUnavailable = true;
      Log.info('[CoreBridge] 当前 core 不支持 Profiler: $error');
      return false;
    }
  }

  ProfilerSnapshot? readProfilerSnapshot() {
    final runtime = _runtime;
    final lib = _lib;
    if (runtime == null || lib == null || _profilerSymbolsUnavailable) {
      return null;
    }
    try {
      final coreApi = _coreApi;
      final RuntimeProfilerSnapshot fn;
      if (coreApi != null) {
        fn = coreApi.profilerSnapshot;
      } else {
        fn = _profilerSnapshot ??= lib
            .lookupFunction<
              RuntimeProfilerSnapshotNative,
              RuntimeProfilerSnapshot
            >('art3m1s_runtime_profiler_snapshot');
      }
      final required = fn(runtime, Pointer<Uint8>.fromAddress(0), 0);
      if (required <= 0 || required > 64 * 1024) return null;
      final output = malloc.allocate<Uint8>(required);
      try {
        final written = fn(runtime, output, required);
        if (written <= 0 || written > required) return null;
        final decoded = jsonDecode(utf8.decode(output.asTypedList(written)));
        return decoded is Map<String, dynamic>
            ? ProfilerSnapshot.fromJson(decoded)
            : null;
      } finally {
        malloc.free(output);
      }
    } catch (error) {
      _profilerSymbolsUnavailable = true;
      Log.warn('[CoreBridge] Profiler 快照读取失败: $error');
      return null;
    }
  }

  void configureAngle(String libDir) {
    if (_lib == null) return;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        final ptr = libDir.toNativeUtf8();
        try {
          coreApi.setAnglePath(ptr);
        } finally {
          malloc.free(ptr);
        }
        return;
      }
      final fn = _lib!
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('art3m1s_set_angle_path');
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
      final ptr = dir.toNativeUtf8();
      try {
        final coreApi = _coreApi;
        final resources = _resources;
        final result = coreApi != null && resources != null
            ? coreApi.fsSetSaveDir(resources, ptr)
            : 0;
        if (result == 0) {
          throw StateError('resources_set_save_dir failed');
        }
      } finally {
        malloc.free(ptr);
      }
      // 同步告知 FileProvider 存档基准目录，供写/删/读回退使用
      FileProvider.setSaveDir(dir);
      Log.info('[CoreBridge] 存档目录已设置: $dir');
    } catch (e) {
      Log.error('[CoreBridge] setSaveDir 失败 ($dir): $e');
    }
  }

  void registerFileReader() {
    if (_lib == null) return;
    FileProvider.mountCore(_lib!, coreApi: _coreApi, resources: _resources);
  }

  void createRuntime(int stageW, int stageH, {int backend = 0}) {
    if (_lib == null) return;
    _stageWidth = stageW;
    _stageHeight = stageH;
    _backendCapabilities = null;
    _backendCapabilitiesUnavailable = false;

    final coreApi = _coreApi;
    if (coreApi != null) {
      _runtime = coreApi.createRuntime(stageW, stageH, backend);
    } else {
      final fn = _lib!
          .lookupFunction<
            RuntimeCreateNative,
            Pointer<Void> Function(int, int, int)
          >('art3m1s_runtime_create');
      _runtime = fn(stageW, stageH, backend);
    }
    final runtime = _runtime;
    if (runtime == null || runtime == nullptr) return;
    final resources = _resources;
    if (resources == null || resources == nullptr) {
      throw StateError('runtime 创建时资源句柄不可用');
    }
    if (coreApi != null &&
        coreApi.setRuntimeResources(runtime, resources) == 0) {
      throw StateError('runtime 绑定资源句柄失败');
    }
    if (coreApi?.hasRuntimeMedia ?? false) {
      coreApi!.setRuntimeMediaEnabled(runtime, 1);
      Log.info('[CoreBridge] runtime 视频解码已启用');
    } else {
      try {
        final setRuntimeMedia = _lib!
            .lookupFunction<
              RuntimeSetRuntimeMediaEnabledNative,
              RuntimeSetRuntimeMediaEnabled
            >('art3m1s_runtime_set_runtime_media_enabled_v1');
        setRuntimeMedia(runtime, 1);
        Log.info('[CoreBridge] runtime 视频解码已启用');
      } catch (_) {
        Log.info('[CoreBridge] 当前 core 不支持 runtime 视频解码，保留宿主路径');
      }
    }
  }

  /// Selects an optional E-Mote implementation before project loading.
  /// Older cores do not export this symbol and keep the built-in path.
  bool setEmoteBackend(int backend) {
    if (_runtime == null || _lib == null) return false;
    if (backend == 0) return true;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        return coreApi.setEmoteBackend(_runtime!, backend) != 0;
      }
      final fn = _lib!
          .lookupFunction<
            RuntimeSetEmoteBackendNative,
            int Function(Pointer<Void>, int)
          >('art3m1s_runtime_set_emote_backend');
      return fn(_runtime!, backend) != 0;
    } catch (error) {
      Log.warn('[CoreBridge] E-Mote 后端选择不可用: $error');
      return false;
    }
  }

  bool setRenderQualityPreset(int preset) {
    if (_runtime == null || _lib == null) return false;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        return coreApi.setRenderQualityPreset(_runtime!, preset) != 0;
      }
      final fn = _lib!
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('art3m1s_runtime_set_render_quality_preset');
      return fn(_runtime!, preset) != 0;
    } catch (error) {
      Log.warn('[CoreBridge] 渲染质量设置不可用: $error');
      return false;
    }
  }

  int backendCapabilities() {
    if (_runtime == null || _lib == null || _backendCapabilitiesUnavailable) {
      return 0;
    }
    final cached = _backendCapabilities;
    if (cached != null) return cached;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        return _backendCapabilities = coreApi.backendCapabilities(_runtime!);
      }
      final fn = _lib!
          .lookupFunction<
            RuntimeBackendCapabilitiesNative,
            int Function(Pointer<Void>)
          >('art3m1s_runtime_backend_capabilities');
      return _backendCapabilities = fn(_runtime!);
    } catch (error) {
      _backendCapabilitiesUnavailable = true;
      Log.warn('[CoreBridge] GPU capabilities 查询不可用: $error');
      return 0;
    }
  }

  bool get supportsSpatialUpscaling => backendCapabilities() & (1 << 6) != 0;

  bool configureSpatialUpscale(double renderScale, {double sharpness = 0}) {
    if (_runtime == null || _lib == null) return false;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        return coreApi.configureSpatialUpscale(
              _runtime!,
              renderScale,
              sharpness,
            ) !=
            0;
      }
      final fn = _lib!
          .lookupFunction<
            RuntimeConfigureSpatialUpscaleNative,
            int Function(Pointer<Void>, double, double)
          >('art3m1s_runtime_configure_spatial_upscale');
      return fn(_runtime!, renderScale, sharpness) != 0;
    } catch (error) {
      Log.warn('[CoreBridge] spatial upscale 配置不可用: $error');
      return false;
    }
  }

  bool loadProject(String iniContent, {String platform = 'WINDOWS'}) {
    if (_runtime == null || _lib == null) return false;
    final coreApi = _coreApi;
    final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) fn;
    if (coreApi != null) {
      fn = coreApi.loadProject;
    } else {
      fn = _lib!
          .lookupFunction<
            RuntimeLoadProjectNative,
            int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
          >('art3m1s_runtime_load_project');
    }
    final iniPtr = iniContent.toNativeUtf8();
    final platPtr = platform.trim().toUpperCase().toNativeUtf8();
    try {
      final result = fn(_runtime!, iniPtr, platPtr) == 0;
      if (result) {
        // 加载成功后查询 core 端的实际舞台尺寸
        _updateStageSize();
      }
      _drainHostEvents();
      return result;
    } finally {
      malloc.free(iniPtr);
      malloc.free(platPtr);
    }
  }

  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) {
    if (_runtime == null || _lib == null) return false;
    final coreApi = _coreApi;
    final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Utf8>) fn;
    if (coreApi != null) {
      fn = coreApi.loadProjectBytes;
    } else {
      fn = _lib!
          .lookupFunction<
            RuntimeLoadProjectBytesNative,
            int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Utf8>)
          >('art3m1s_runtime_load_project_bytes');
    }

    final iniPtr = malloc.allocate<Uint8>(iniContent.length);
    final platPtr = platform.trim().toUpperCase().toNativeUtf8();
    try {
      iniPtr.asTypedList(iniContent.length).setAll(0, iniContent);
      final result = fn(_runtime!, iniPtr, iniContent.length, platPtr) == 0;
      if (result) {
        _updateStageSize();
      }
      _drainHostEvents();
      return result;
    } finally {
      malloc.free(iniPtr);
      malloc.free(platPtr);
    }
  }

  /// 导入时先从语言表快速提取 gametitle；不存在时才 headless 运行解释器，
  /// 直到发出第一个 `[caption]`。两条路径都启用环境兼容补丁。
  /// 任何失败（库加载不了、system.ini 读不到、boot 在 caption 前阻塞）返回 null。
  /// 独立于 player 的 CoreBridge：只用 lib + 进程级 FileProvider，不动 _activeBridge。
  Future<String?> probeCaption({
    required String projectPath,
    required bool isPfsArchive,
    String platform = 'WINDOWS',
  }) async {
    Uint8List? iniContent;
    late String charset;
    try {
      if (isPfsArchive) {
        FileProvider.openPfs(projectPath, environmentPatchEnabled: true);
        iniContent = FileProvider.readFile('system.ini');
      } else {
        FileProvider.openDirectory(projectPath, environmentPatchEnabled: true);
        iniContent = FileProvider.readFile('system.ini');
      }
      if (iniContent == null || iniContent.isEmpty) {
        FileProvider.close();
        return null;
      }
      charset = ProjectCharset.detect(iniContent, platform);
      if (isPfsArchive) {
        FileProvider.openPfs(
          projectPath,
          archiveEncoding: charset,
          environmentPatchEnabled: true,
        );
      }
    } catch (e) {
      Log.warn('[CoreBridge] probeCaption 读取 system.ini 失败: $e');
      FileProvider.close();
      return null;
    }

    String? tableCaption;
    try {
      tableCaption = CaptionTableProbe.find(
        paths: FileProvider.listFiles(extension: '.tbl'),
        readFile: FileProvider.readFile,
        charset: charset,
      );
    } catch (e) {
      Log.warn('[CoreBridge] probeCaption 扫描语言表失败，将回退 headless: $e');
    }
    if (tableCaption != null) {
      Log.info('[CoreBridge] 从语言表获取 caption: $tableCaption');
      FileProvider.close();
      return tableCaption;
    }

    try {
      _loadLibrary();
    } catch (e) {
      Log.warn('[CoreBridge] probeCaption 加载库失败: $e');
      FileProvider.close();
      return null;
    }
    final lib = _lib;
    if (lib == null) {
      FileProvider.close();
      return null;
    }

    final coreApi = _coreApi ?? CoreApiV1.tryLoad(lib);
    if (coreApi == null) {
      FileProvider.close();
      return null;
    }
    final ownsResources = _resources == null;
    final resources = _resources ?? coreApi.createResources();
    if (resources == nullptr) {
      FileProvider.close();
      return null;
    }

    // boot 脚本经 core 的原生文件宿主读取资源，须先挂载当前资源根。
    FileProvider.mountCore(lib, coreApi: coreApi, resources: resources);

    final fn = coreApi.probeCaption;

    const cap = 1024;
    final iniPtr = malloc.allocate<Uint8>(iniContent.length);
    final platPtr = platform.trim().toUpperCase().toNativeUtf8();
    final outBuf = malloc.allocate<Uint8>(cap);
    try {
      iniPtr.asTypedList(iniContent.length).setAll(0, iniContent);
      final len = fn(
        resources,
        iniPtr,
        iniContent.length,
        platPtr,
        outBuf,
        cap,
      );
      if (len <= 0) return null;
      return utf8.decode(outBuf.asTypedList(len), allowMalformed: true);
    } catch (e) {
      Log.warn('[CoreBridge] probeCaption 调用失败: $e');
      return null;
    } finally {
      malloc.free(iniPtr);
      malloc.free(platPtr);
      malloc.free(outBuf);
      FileProvider.close();
      if (ownsResources) {
        coreApi.destroyResources(resources);
      }
    }
  }

  void _updateStageSize() {
    if (_runtime == null || _lib == null) return;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        _stageWidth = coreApi.stageWidth(_runtime!);
        _stageHeight = coreApi.stageHeight(_runtime!);
      } else {
        final widthFn = _lib!
            .lookupFunction<
              RuntimeStageWidthNative,
              int Function(Pointer<Void>)
            >('art3m1s_runtime_stage_width');
        final heightFn = _lib!
            .lookupFunction<
              RuntimeStageHeightNative,
              int Function(Pointer<Void>)
            >('art3m1s_runtime_stage_height');
        _stageWidth = widthFn(_runtime!);
        _stageHeight = heightFn(_runtime!);
      }
      Log.info('[CoreBridge] 舞台尺寸已更新: $_stageWidth x $_stageHeight');
    } catch (e) {
      Log.warn('[CoreBridge] 查询舞台尺寸失败: $e');
    }
  }

  void feedMouse(int x, int y) {
    if (_runtime == null || _lib == null) return;
    // 门控：指针位置流（hover/移动）。
    if (!_inputGate.mouseMove) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.feedMouse(_runtime!, x, y);
      return;
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedMouseNative,
          void Function(Pointer<Void>, int, int)
        >('art3m1s_runtime_feed_mouse');
    fn(_runtime!, x, y);
  }

  void feedClick() {
    if (_runtime == null || _lib == null) return;
    if (!_inputGate.mouseButtons) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.feedClick(_runtime!);
      return;
    }
    final fn = _lib!
        .lookupFunction<RuntimeFeedClickNative, void Function(Pointer<Void>)>(
          'art3m1s_runtime_feed_click',
        );
    fn(_runtime!);
  }

  void feedMouseButton(int button, bool pressed) {
    if (_runtime == null || _lib == null) return;
    if (!_inputGate.mouseButtons) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.feedMouseButton(_runtime!, button, pressed ? 1 : 0);
      return;
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedMouseButtonNative,
          void Function(Pointer<Void>, int, int)
        >('art3m1s_runtime_feed_mouse_button');
    fn(_runtime!, button, pressed ? 1 : 0);
  }

  /// 转发真实触摸点给 core（驱动 getTouchCount/Point、flick、多点触控）。
  /// phase：0=down / 1=move / 2=up；id 用 Flutter 的 pointer 唯一标识。
  void feedTouch(int id, int phase, int x, int y) {
    if (_runtime == null || _lib == null) return;
    if (!_inputGate.touch) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.feedTouch(_runtime!, id, phase, x, y);
      return;
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedTouchNative,
          void Function(Pointer<Void>, int, int, int, int)
        >('art3m1s_runtime_feed_touch');
    fn(_runtime!, id, phase, x, y);
  }

  void feedKey(int vk, bool pressed) {
    if (_runtime == null || _lib == null) return;
    // 门控：类别开关 → 黑名单 → 重映射；按下/抬起经同一映射保持一致。
    final mapped = _inputGate.filterKey(vk);
    if (mapped == null) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.feedKey(_runtime!, mapped, pressed ? 1 : 0);
      return;
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedKeyNative,
          void Function(Pointer<Void>, int, int)
        >('art3m1s_runtime_feed_key');
    fn(_runtime!, mapped, pressed ? 1 : 0);
  }

  /// 宿主合成的转发按键（滚轮/手势 → 方向键等）。只受键级黑名单与重映射
  /// 约束，不受键盘类别主开关约束——合成事件由各自的转发开关管。
  void feedForwardedKey(int vk, bool pressed) {
    if (_runtime == null || _lib == null) return;
    final mapped = _inputGate.filterForwardedKey(vk);
    if (mapped == null) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      coreApi.feedKey(_runtime!, mapped, pressed ? 1 : 0);
      return;
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedKeyNative,
          void Function(Pointer<Void>, int, int)
        >('art3m1s_runtime_feed_key');
    fn(_runtime!, mapped, pressed ? 1 : 0);
  }

  bool submitDialog(bool accepted, String text) {
    if (_runtime == null || _lib == null) return false;
    final coreApi = _coreApi;
    if (coreApi != null) {
      final textPtr = text.toNativeUtf8();
      try {
        return coreApi.submitDialog(_runtime!, accepted ? 1 : 0, textPtr) != 0;
      } finally {
        malloc.free(textPtr);
      }
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeSubmitDialogNative,
          int Function(Pointer<Void>, int, Pointer<Utf8>)
        >('art3m1s_runtime_submit_dialog');
    final textPtr = text.toNativeUtf8();
    try {
      return fn(_runtime!, accepted ? 1 : 0, textPtr) != 0;
    } finally {
      malloc.free(textPtr);
    }
  }

  bool submitTextTranslation(int serial, String? text) {
    if (_runtime == null || _lib == null) return false;
    final coreApi = _coreApi;
    if (coreApi != null) {
      final textPtr = text?.toNativeUtf8();
      try {
        return coreApi.submitTextTranslation(
              _runtime!,
              serial,
              textPtr ?? Pointer<Utf8>.fromAddress(0),
            ) !=
            0;
      } finally {
        if (textPtr != null) malloc.free(textPtr);
      }
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeSubmitTextTranslationNative,
          int Function(Pointer<Void>, int, Pointer<Utf8>)
        >('art3m1s_runtime_submit_text_translation');
    final textPtr = text?.toNativeUtf8();
    try {
      return fn(_runtime!, serial, textPtr ?? Pointer<Utf8>.fromAddress(0)) !=
          0;
    } finally {
      if (textPtr != null) malloc.free(textPtr);
    }
  }

  Uint8List? advanceAndRender(int deltaMs) {
    if (_runtime == null || _lib == null) return null;
    final coreApi = _coreApi;
    final int Function(Pointer<Void>, int, Pointer<Uint8>, int) fn;
    if (coreApi != null) {
      fn = coreApi.advanceAndRender;
    } else {
      fn = _lib!
          .lookupFunction<
            RuntimeAdvanceRenderNative,
            int Function(Pointer<Void>, int, Pointer<Uint8>, int)
          >('art3m1s_runtime_advance_and_render');
    }
    final pixelCount = _stageWidth * _stageHeight * 4;
    final out = malloc.allocate<Uint8>(pixelCount);
    try {
      final written = fn(_runtime!, deltaMs, out, pixelCount);
      _drainHostEvents();
      if (written == 0) return null;
      return Uint8List.fromList(out.asTypedList(written));
    } finally {
      malloc.free(out);
    }
  }

  /// 上一帧仍在 Flutter 解码时只推进引擎逻辑，避免 onEnterFrame 驱动的
  /// E-Mote 口型和真实音频时钟因漏 tick 而逐渐错位。
  bool advanceWithoutRender(int deltaMs) {
    if (_runtime == null || _lib == null || _advanceWithoutRenderUnavailable) {
      return false;
    }
    final coreApi = _coreApi;
    if (coreApi != null) {
      final result = coreApi.advanceWithoutRender(_runtime!, deltaMs) != 0;
      _drainHostEvents();
      return result;
    }
    try {
      final fn = _advanceWithoutRender ??= _lib!
          .lookupFunction<
            RuntimeAdvanceWithoutRenderNative,
            RuntimeAdvanceWithoutRender
          >('art3m1s_runtime_advance_without_render');
      final result = fn(_runtime!, deltaMs) != 0;
      _drainHostEvents();
      return result;
    } catch (_) {
      // 旧 core 没有该可选接口时保持原行为，避免每帧重复查找符号。
      _advanceWithoutRenderUnavailable = true;
      return false;
    }
  }

  bool isExitRequested() {
    if (_runtime == null || _lib == null) return false;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        return coreApi.isExitRequested(_runtime!) != 0;
      }
      final fn = _lib!
          .lookupFunction<
            RuntimeIsExitRequestedNative,
            int Function(Pointer<Void>)
          >('art3m1s_runtime_is_exit_requested');
      return fn(_runtime!) != 0;
    } catch (_) {
      return false;
    }
  }

  /// 应用生命周期通知：state 0=退出 / 1=切后台 / 2=回前台。
  /// 驱动 [autosave allow=1]（切后台时自动存档）。core 未导出该符号时静默跳过。
  void notifyLifecycle(int state) {
    if (_runtime == null || _lib == null) return;
    try {
      final coreApi = _coreApi;
      if (coreApi != null) {
        coreApi.notifyLifecycle(_runtime!, state);
        _drainHostEvents();
        return;
      }
      final fn = _lib!
          .lookupFunction<NotifyLifecycleNative, NotifyLifecycleDart>(
            'art3m1s_runtime_notify_lifecycle',
          );
      fn(_runtime!, state);
      _drainHostEvents();
    } catch (e) {
      Log.warn('[CoreBridge] notifyLifecycle 不可用: $e');
    }
  }

  void notifyVideoFinished(String? id) {
    if (_runtime == null || _lib == null) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      final idPtr = id == null
          ? Pointer<Utf8>.fromAddress(0)
          : id.toNativeUtf8();
      try {
        coreApi.notifyVideoFinished(_runtime!, idPtr);
      } finally {
        if (id != null) malloc.free(idPtr);
      }
      return;
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeNotifyVideoFinishedNative,
          void Function(Pointer<Void>, Pointer<Utf8>)
        >('art3m1s_runtime_notify_video_finished');
    final idPtr = id == null ? Pointer<Utf8>.fromAddress(0) : id.toNativeUtf8();
    try {
      fn(_runtime!, idPtr);
    } finally {
      if (id != null) malloc.free(idPtr);
    }
  }

  void notifySoundFinished(String? id) {
    if (_runtime == null || _lib == null) return;
    final coreApi = _coreApi;
    if (coreApi != null) {
      final idPtr = id == null
          ? Pointer<Utf8>.fromAddress(0)
          : id.toNativeUtf8();
      try {
        coreApi.notifySoundFinished(_runtime!, idPtr);
      } finally {
        if (id != null) malloc.free(idPtr);
      }
      return;
    }
    final fn = _lib!
        .lookupFunction<
          RuntimeNotifySoundFinishedNative,
          void Function(Pointer<Void>, Pointer<Utf8>)
        >('art3m1s_runtime_notify_sound_finished');
    final idPtr = id == null ? Pointer<Utf8>.fromAddress(0) : id.toNativeUtf8();
    try {
      fn(_runtime!, idPtr);
    } finally {
      if (id != null) malloc.free(idPtr);
    }
  }

  void shutdown() {
    final hostEvents = _hostEvents;
    hostEvents?.enable(0);
    final hostEventsHandle = hostEvents?.handle;
    if (_activeBridge == this) _activeBridge = null;
    _resetCursorState();
    unawaited(media.dispose());
    final translationService = translation;
    translation = null;
    if (translationService != null) {
      unawaited(translationService.dispose());
    }
    final runtime = _runtime;
    final lib = _lib;
    final coreApi = _coreApi;
    _detachSharedTexture();
    if (_sharedTextureId != null) {
      unawaited(_sharedTextureChannel.invokeMethod<void>('release'));
    }
    _sharedTextureChannel.setMethodCallHandler(null);
    _sharedTextureId = null;
    _sharedTextureKind = null;
    _sharedTextureWidth = 0;
    _sharedTextureHeight = 0;
    _runtime = null;
    _coreApi = null;
    final resources = _resources;
    _resources = null;
    _hostEvents = null;
    _backendCapabilities = null;
    _backendCapabilitiesUnavailable = false;
    _initialized = false;
    _advanceWithoutRender = null;
    _advanceWithoutRenderUnavailable = false;
    _setExternalSurface = null;
    _clearExternalSurface = null;
    _advancePresent = null;
    _setProfilerEnabled = null;
    _profilerSnapshot = null;
    _profilerSymbolsUnavailable = false;
    _fontOverrideSymbolsUnavailable = false;
    _sharedTextureSymbolsUnavailable = false;
    if (runtime != null && lib != null) {
      try {
        Log.info('[CoreBridge] runtime destroy begin');
        if (coreApi != null) {
          coreApi.destroyRuntime(runtime);
        } else {
          final fn = lib
              .lookupFunction<
                RuntimeDestroyNative,
                void Function(Pointer<Void>)
              >('art3m1s_runtime_destroy');
          fn(runtime);
        }
        Log.info('[CoreBridge] runtime destroy end');
      } catch (e) {
        Log.warn('[CoreBridge] runtime destroy failed: $e');
        // dylib may not export art3m1s_runtime_destroy yet
      }
    }
    if (hostEventsHandle != null && coreApi != null) {
      try {
        coreApi.destroyHostEvents(hostEventsHandle);
      } catch (e) {
        Log.warn('[CoreBridge] host event destroy failed: $e');
      }
    }
    FileProvider.close();
    if (resources != null && resources != nullptr) {
      try {
        coreApi?.destroyResources(resources);
      } catch (e) {
        Log.warn('[CoreBridge] resource destroy failed: $e');
      }
    }
    _lib = null;
  }
}
