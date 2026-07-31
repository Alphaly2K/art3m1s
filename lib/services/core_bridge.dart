import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/logger.dart';
import 'caption_table_probe.dart';
import 'file_provider.dart';
import 'media_bridge.dart';
import 'project_charset.dart';
import 'text_translation_service.dart';

typedef LogCallbackNative =
    Int32 Function(Pointer<Int8> level, Pointer<Int8> msg);
typedef RegisterLogCallbackNative =
    Void Function(Pointer<NativeFunction<LogCallbackNative>>);
typedef MediaCommandCallbackNative =
    Void Function(Pointer<Int8> kind, Pointer<Int8> payloadJson);
typedef RegisterMediaCommandCallbackNative =
    Void Function(Pointer<NativeFunction<MediaCommandCallbackNative>>);
typedef UiCommandCallbackNative =
    Void Function(Pointer<Int8> kind, Pointer<Int8> payloadJson);
typedef RegisterUiCommandCallbackNative =
    Void Function(Pointer<NativeFunction<UiCommandCallbackNative>>);
typedef TextInjectCallbackNative =
    Int32 Function(Pointer<Int8> text, Pointer<Uint8> output, Int32 capacity);
typedef RegisterTextInjectCallbackNative =
    Void Function(Pointer<NativeFunction<TextInjectCallbackNative>>);

// var system=get_font：core 传入 monospace/vertical 偏好，宿主把换行分隔的字体名
// 写入 buf（≤cap 字节），返回写入字节数；容量不足或无字体返回 0。
typedef FontQueryCallbackNative =
    Int32 Function(
      Int32 monospace,
      Int32 vertical,
      Pointer<Uint8> buf,
      Int32 cap,
    );
typedef RegisterFontQueryNative =
    Void Function(Pointer<NativeFunction<FontQueryCallbackNative>>);

// var system=fullscreen/minimize：宿主返回位标志 bit0=全屏 bit1=最小化。
typedef WindowStateCallbackNative = Int32 Function();
typedef RegisterWindowStateNative =
    Void Function(Pointer<NativeFunction<WindowStateCallbackNative>>);

// 生命周期通知：state 0=退出 / 1=切后台 / 2=回前台（驱动 [autosave allow=1]）。
typedef NotifyLifecycleNative = Void Function(Pointer<Void> rt, Int32 state);
typedef NotifyLifecycleDart = void Function(Pointer<Void> rt, int state);

int _fontQueryCallback(
  int monospace,
  int vertical,
  Pointer<Uint8> buf,
  int cap,
) {
  try {
    final names =
        CoreBridge._activeBridge?.enumerateFonts(
          monospace: monospace != 0,
          vertical: vertical != 0,
        ) ??
        const <String>[];
    if (names.isEmpty || cap <= 0) return 0;
    final bytes = utf8.encode(names.join('\n'));
    if (bytes.length > cap) return 0;
    buf.asTypedList(cap).setRange(0, bytes.length, bytes);
    return bytes.length;
  } catch (e) {
    Log.error('[CoreBridge] 字体枚举失败: $e');
    return 0;
  }
}

int _windowStateCallback() {
  return CoreBridge._activeBridge?.windowStateBits ?? 0;
}

int _logCallback(Pointer<Int8> levelPtr, Pointer<Int8> msgPtr) {
  final level = levelPtr.cast<Utf8>().toDartString();
  final msg = msgPtr.cast<Utf8>().toDartString();
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

void _uiCommandCallback(Pointer<Int8> kindPtr, Pointer<Int8> payloadPtr) {
  try {
    final kind = kindPtr.cast<Utf8>().toDartString();
    final rawPayload = payloadPtr.cast<Utf8>().toDartString();
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
  } catch (e) {
    Log.error('[CoreBridge] UI 命令解析失败: $e');
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

int _textInjectCallback(
  Pointer<Int8> textPtr,
  Pointer<Uint8> output,
  int capacity,
) {
  try {
    final source = textPtr.cast<Utf8>().toDartString();
    return CoreBridge._activeBridge?.translation?.inject(
          source,
          output,
          capacity,
        ) ??
        -1;
  } catch (error) {
    Log.error('[Translation] 注入回调失败: $error');
    return -1;
  }
}

class EngineDialogRequest {
  const EngineDialogRequest({
    required this.title,
    required this.message,
    required this.hasCancel,
    required this.hasTextField,
    required this.textFieldSize,
    required this.initialText,
  });

  factory EngineDialogRequest.fromJson(Map<String, dynamic> json) {
    return EngineDialogRequest(
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      hasCancel: json['hasCancel'] == true,
      hasTextField: json['textfield'] == true,
      textFieldSize: switch (json['textfieldSize']) {
        final num value when value > 0 => value.toInt(),
        _ => null,
      },
      initialText: json['initialText']?.toString() ?? '',
    );
  }

  final String title;
  final String message;
  final bool hasCancel;
  final bool hasTextField;
  final int? textFieldSize;
  final String initialText;
}

/// 紧急回避覆盖状态（[avoid] 触发）。`file` 为覆盖图资源名（null 表示纯黑遮罩）。
class AvoidOverlay {
  const AvoidOverlay({this.file});
  final String? file;
}

// ── Core FFI type definitions ───────────────────────────────────

typedef RuntimeCreateNative =
    Pointer<Void> Function(Uint32 w, Uint32 h, Int32 backend);
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
typedef RuntimeUploadVideoLayerFrameNative =
    Int32 Function(
      Pointer<Void> rt,
      Pointer<Utf8> id,
      Uint32 width,
      Uint32 height,
      Pointer<Uint8> rgba,
      IntPtr rgbaLen,
    );
typedef RuntimeUploadVideoLayerFrame =
    int Function(Pointer<Void>, Pointer<Utf8>, int, int, Pointer<Uint8>, int);
typedef RuntimeAdvanceWithoutRenderNative =
    Int32 Function(Pointer<Void> rt, Uint32 deltaMs);
typedef RuntimeAdvanceWithoutRender =
    int Function(Pointer<Void> rt, int deltaMs);

// ── CoreBridge — manages the core runtime lifecycle ─────────────

class CoreBridge {
  static NativeCallable<LogCallbackNative>? _sharedLogCallable;
  static NativeCallable<MediaCommandCallbackNative>? _sharedMediaCallable;
  static NativeCallable<UiCommandCallbackNative>? _sharedUiCallable;
  static NativeCallable<TextInjectCallbackNative>? _sharedTextInjectCallable;
  static NativeCallable<FontQueryCallbackNative>? _sharedFontQueryCallable;
  static NativeCallable<WindowStateCallbackNative>? _sharedWindowStateCallable;
  static CoreBridge? _activeBridge;

  CoreBridge({this.onDialogRequested, bool? engineCursorControlEnabled})
    : _engineCursorControlEnabled =
          engineCursorControlEnabled ?? Platform.isWindows;

  final void Function(EngineDialogRequest request)? onDialogRequested;
  bool _initialized = false;
  DynamicLibrary? _lib;
  Pointer<Void>? _runtime;
  RuntimeUploadVideoLayerFrame? _uploadVideoLayerFrame;
  RuntimeAdvanceWithoutRender? _advanceWithoutRender;
  bool _advanceWithoutRenderUnavailable = false;
  TextTranslationService? translation;
  final Map<String, Pointer<Utf8>> _videoLayerIds = {};
  int _stageWidth = 1280;
  int _stageHeight = 720;

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
    uploadVideoLayerFrame: _uploadLayerVideoFrame,
  );

  bool get isInitialized => _initialized;
  Pointer<Void>? get runtime => _runtime;
  int get stageWidth => _stageWidth;
  int get stageHeight => _stageHeight;

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
      if (Platform.isMacOS) {
        configureAngle(File(Platform.resolvedExecutable).parent.path);
      }
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
    final registerFn = _lib!
        .lookupFunction<
          RegisterLogCallbackNative,
          void Function(Pointer<NativeFunction<LogCallbackNative>>)
        >('art3m1s_register_log_callback');
    _sharedLogCallable ??= NativeCallable<LogCallbackNative>.isolateLocal(
      _logCallback,
      exceptionalReturn: -1,
    );
    registerFn(_sharedLogCallable!.nativeFunction);

    final registerMediaFn = _lib!
        .lookupFunction<
          RegisterMediaCommandCallbackNative,
          void Function(Pointer<NativeFunction<MediaCommandCallbackNative>>)
        >('art3m1s_register_media_command_callback');
    _sharedMediaCallable ??=
        NativeCallable<MediaCommandCallbackNative>.isolateLocal(
          _mediaCommandCallback,
        );
    _activeBridge = this;
    registerMediaFn(_sharedMediaCallable!.nativeFunction);

    final registerUiFn = _lib!
        .lookupFunction<
          RegisterUiCommandCallbackNative,
          void Function(Pointer<NativeFunction<UiCommandCallbackNative>>)
        >('art3m1s_register_ui_command_callback');
    _sharedUiCallable ??= NativeCallable<UiCommandCallbackNative>.isolateLocal(
      _uiCommandCallback,
    );
    registerUiFn(_sharedUiCallable!.nativeFunction);

    final registerTextInjectFn = _lib!
        .lookupFunction<
          RegisterTextInjectCallbackNative,
          void Function(Pointer<NativeFunction<TextInjectCallbackNative>>)
        >('art3m1s_register_text_inject_callback');
    _sharedTextInjectCallable ??=
        NativeCallable<TextInjectCallbackNative>.isolateLocal(
          _textInjectCallback,
          exceptionalReturn: -1,
        );
    registerTextInjectFn(_sharedTextInjectCallable!.nativeFunction);

    // 字体枚举与窗口状态查询是可选回调：老版本 core 可能未导出，查不到就跳过（不崩）。
    try {
      final registerFontFn = _lib!
          .lookupFunction<
            RegisterFontQueryNative,
            void Function(Pointer<NativeFunction<FontQueryCallbackNative>>)
          >('art3m1s_register_font_query');
      _sharedFontQueryCallable ??=
          NativeCallable<FontQueryCallbackNative>.isolateLocal(
            _fontQueryCallback,
            exceptionalReturn: 0,
          );
      registerFontFn(_sharedFontQueryCallable!.nativeFunction);
    } catch (e) {
      Log.warn('[CoreBridge] 字体枚举回调不可用（core 未导出）: $e');
    }

    try {
      final registerWindowFn = _lib!
          .lookupFunction<
            RegisterWindowStateNative,
            void Function(Pointer<NativeFunction<WindowStateCallbackNative>>)
          >('art3m1s_register_window_state_query');
      _sharedWindowStateCallable ??=
          NativeCallable<WindowStateCallbackNative>.isolateLocal(
            _windowStateCallback,
            exceptionalReturn: 0,
          );
      registerWindowFn(_sharedWindowStateCallable!.nativeFunction);
    } catch (e) {
      Log.warn('[CoreBridge] 窗口状态回调不可用（core 未导出）: $e');
    }
  }

  void configureTranslation(TextTranslationService? service) {
    final previous = translation;
    translation = service;
    if (previous != null && previous != service) {
      unawaited(previous.dispose());
    }
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
    if (_lib == null) return;
    final fn = _lib!.lookupFunction<Void Function(Int32), void Function(int)>(
      'art3m1s_set_debug',
    );
    fn(enabled ? 1 : 0);
  }

  void configureAngle(String libDir) {
    if (_lib == null) return;
    try {
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
      final fn = _lib!
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('art3m1s_set_save_dir');
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

    final fn = _lib!
        .lookupFunction<
          RuntimeCreateNative,
          Pointer<Void> Function(int, int, int)
        >('art3m1s_runtime_create');
    _runtime = fn(stageW, stageH, backend);
  }

  bool loadProject(String iniContent, {String platform = 'WINDOWS'}) {
    if (_runtime == null || _lib == null) return false;
    final fn = _lib!
        .lookupFunction<
          RuntimeLoadProjectNative,
          int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
        >('art3m1s_runtime_load_project');
    final iniPtr = iniContent.toNativeUtf8();
    final platPtr = platform.trim().toUpperCase().toNativeUtf8();
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

  bool loadProjectBytes(Uint8List iniContent, {String platform = 'WINDOWS'}) {
    if (_runtime == null || _lib == null) return false;
    final fn = _lib!
        .lookupFunction<
          RuntimeLoadProjectBytesNative,
          int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Utf8>)
        >('art3m1s_runtime_load_project_bytes');

    final iniPtr = malloc.allocate<Uint8>(iniContent.length);
    final platPtr = platform.trim().toUpperCase().toNativeUtf8();
    try {
      iniPtr.asTypedList(iniContent.length).setAll(0, iniContent);
      final result = fn(_runtime!, iniPtr, iniContent.length, platPtr) == 0;
      if (result) {
        _updateStageSize();
      }
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

    // boot 脚本经 core 的 request_file 回调到 FileProvider，须先注册文件读回调。
    FileProvider.register(lib);

    final fn = lib
        .lookupFunction<
          ProbeCaptionNative,
          int Function(Pointer<Uint8>, int, Pointer<Utf8>, Pointer<Uint8>, int)
        >('art3m1s_probe_caption');

    const cap = 1024;
    final iniPtr = malloc.allocate<Uint8>(iniContent.length);
    final platPtr = platform.trim().toUpperCase().toNativeUtf8();
    final outBuf = malloc.allocate<Uint8>(cap);
    try {
      iniPtr.asTypedList(iniContent.length).setAll(0, iniContent);
      final len = fn(iniPtr, iniContent.length, platPtr, outBuf, cap);
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
    }
  }

  void _updateStageSize() {
    if (_runtime == null || _lib == null) return;
    try {
      final widthFn = _lib!
          .lookupFunction<RuntimeStageWidthNative, int Function(Pointer<Void>)>(
            'art3m1s_runtime_stage_width',
          );
      final heightFn = _lib!
          .lookupFunction<
            RuntimeStageHeightNative,
            int Function(Pointer<Void>)
          >('art3m1s_runtime_stage_height');
      _stageWidth = widthFn(_runtime!);
      _stageHeight = heightFn(_runtime!);
      Log.info('[CoreBridge] 舞台尺寸已更新: $_stageWidth x $_stageHeight');
    } catch (e) {
      Log.warn('[CoreBridge] 查询舞台尺寸失败: $e');
    }
  }

  void feedMouse(int x, int y) {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedMouseNative,
          void Function(Pointer<Void>, int, int)
        >('art3m1s_runtime_feed_mouse');
    fn(_runtime!, x, y);
  }

  void feedClick() {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!
        .lookupFunction<RuntimeFeedClickNative, void Function(Pointer<Void>)>(
          'art3m1s_runtime_feed_click',
        );
    fn(_runtime!);
  }

  void feedMouseButton(int button, bool pressed) {
    if (_runtime == null || _lib == null) return;
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
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedTouchNative,
          void Function(Pointer<Void>, int, int, int, int)
        >('art3m1s_runtime_feed_touch');
    fn(_runtime!, id, phase, x, y);
  }

  void feedKey(int vk, bool pressed) {
    if (_runtime == null || _lib == null) return;
    final fn = _lib!
        .lookupFunction<
          RuntimeFeedKeyNative,
          void Function(Pointer<Void>, int, int)
        >('art3m1s_runtime_feed_key');
    fn(_runtime!, vk, pressed ? 1 : 0);
  }

  bool submitDialog(bool accepted, String text) {
    if (_runtime == null || _lib == null) return false;
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
    media.pumpLayerVideoFrames();
    final fn = _lib!
        .lookupFunction<
          RuntimeAdvanceRenderNative,
          int Function(Pointer<Void>, int, Pointer<Uint8>, int)
        >('art3m1s_runtime_advance_and_render');
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

  /// 上一帧仍在 Flutter 解码时只推进引擎逻辑，避免 onEnterFrame 驱动的
  /// E-Mote 口型和真实音频时钟因漏 tick 而逐渐错位。
  bool advanceWithoutRender(int deltaMs) {
    if (_runtime == null || _lib == null || _advanceWithoutRenderUnavailable) {
      return false;
    }
    media.pumpLayerVideoFrames();
    try {
      final fn = _advanceWithoutRender ??= _lib!
          .lookupFunction<
            RuntimeAdvanceWithoutRenderNative,
            RuntimeAdvanceWithoutRender
          >('art3m1s_runtime_advance_without_render');
      return fn(_runtime!, deltaMs) != 0;
    } catch (_) {
      // 旧 core 没有该可选接口时保持原行为，避免每帧重复查找符号。
      _advanceWithoutRenderUnavailable = true;
      return false;
    }
  }

  bool _uploadLayerVideoFrame(
    String id,
    int width,
    int height,
    Pointer<Uint8> rgba,
    int rgbaLen,
  ) {
    final runtime = _runtime;
    final lib = _lib;
    if (runtime == null || lib == null) return false;
    final fn = _uploadVideoLayerFrame ??= lib
        .lookupFunction<
          RuntimeUploadVideoLayerFrameNative,
          RuntimeUploadVideoLayerFrame
        >('art3m1s_runtime_upload_video_layer_frame');
    final idPtr = _videoLayerIds.putIfAbsent(id, id.toNativeUtf8);
    return fn(runtime, idPtr, width, height, rgba, rgbaLen) != 0;
  }

  bool isExitRequested() {
    if (_runtime == null || _lib == null) return false;
    try {
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
      final fn = _lib!
          .lookupFunction<NotifyLifecycleNative, NotifyLifecycleDart>(
            'art3m1s_runtime_notify_lifecycle',
          );
      fn(_runtime!, state);
    } catch (e) {
      Log.warn('[CoreBridge] notifyLifecycle 不可用: $e');
    }
  }

  void notifyVideoFinished(String? id) {
    if (_runtime == null || _lib == null) return;
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
    _runtime = null;
    _initialized = false;
    _uploadVideoLayerFrame = null;
    _advanceWithoutRender = null;
    _advanceWithoutRenderUnavailable = false;
    for (final id in _videoLayerIds.values) {
      malloc.free(id);
    }
    _videoLayerIds.clear();

    if (runtime != null && lib != null) {
      try {
        Log.info('[CoreBridge] runtime destroy begin');
        final fn = lib
            .lookupFunction<RuntimeDestroyNative, void Function(Pointer<Void>)>(
              'art3m1s_runtime_destroy',
            );
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
