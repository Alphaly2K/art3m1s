import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../services/logger.dart';
import '../../native_library.dart';
import 'core_katze_api.dart';
import 'katze_translation_api.dart';

typedef _Mount =
    Pointer<KatzeCreateInfo> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _Unmount = Size Function(Pointer<KatzeCreateInfo>);
typedef _Pixels = Size Function(Pointer<KatzeCreateInfo>, Pointer<Uint8>, Size);
typedef _ReadPixels =
    int Function(Pointer<KatzeCreateInfo>, Pointer<Uint8>, int);
typedef _PointerEvent =
    Void Function(Pointer<KatzeCreateInfo>, Int32, Int32, Uint32);
typedef _ButtonEvent =
    Void Function(Pointer<KatzeCreateInfo>, Uint32, Uint32, Uint32);
typedef _InputEvent = void Function(Pointer<KatzeCreateInfo>, int, int, int);
typedef _FocusEvent = Void Function(Pointer<KatzeCreateInfo>, Uint32);
typedef _SetFocus = void Function(Pointer<KatzeCreateInfo>, int);

typedef _PresentFinished = Void Function(Int32);
typedef _PresentReport = Void Function(Int32, Size);
typedef _StepFinished = Void Function(Int32, Uint32);
typedef _StepCallback = Pointer<NativeFunction<_StepFinished>>;
typedef _StepReport = Void Function(Int32, Uint32, Size);
typedef _StepReportCallback = Pointer<NativeFunction<_StepReport>>;

typedef _ScriptMessage = Void Function(Pointer<Uint8>, Size);
typedef _ScriptMessageCallback = Pointer<NativeFunction<_ScriptMessage>>;

typedef _AudioStart =
    Pointer<Void> Function(Uint64, Pointer<NativeFunction<KatzeMixStereo>>);
typedef _AudioStartDart =
    Pointer<Void> Function(int, Pointer<NativeFunction<KatzeMixStereo>>);
typedef _AudioStop = Void Function(Pointer<Void>);

final class _GameHostApiV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int abiVersion;
  @Uint64()
  external int magic;
  @Array(19)
  external Array<Pointer<Void>> functions;
}

typedef _GetGameHostApiNative = Pointer<_GameHostApiV1> Function(Pointer<Size>);

final class _GameHostBindings {
  _GameHostBindings(this.library) : table = _readTable(library);

  final DynamicLibrary library;
  final Pointer<_GameHostApiV1>? table;
  static const _entries = [
    'katze_game_mount',
    'katze_game_unmount',
    'katze_game_set_movie_host',
    'katze_game_set_model_host',
    'katze_game_enable_script_messages',
    'katze_game_drain_script_messages',
    'katze_game_pixels',
    'katze_game_pointer',
    'katze_game_button',
    'katze_game_focus',
    'katze_game_take_window_action',
    'katze_game_step_async',
    'katze_game_step_async_report',
    'katze_game_present_async_report',
    'katze_game_attach_surface',
    'katze_game_present_surface',
    'katze_game_present_surface_async',
    'katze_game_audio_start',
    'katze_game_audio_stop',
  ];

  static Pointer<_GameHostApiV1>? _readTable(DynamicLibrary library) {
    const symbol = 'katze_game_get_api_v1';
    if (!library.providesSymbol(symbol)) return null;
    final size = calloc<Size>();
    try {
      final get = library
          .lookupFunction<_GetGameHostApiNative, _GetGameHostApiNative>(symbol);
      final table = get(size);
      if (table == nullptr || size.value < sizeOf<_GameHostApiV1>()) {
        throw StateError('Katze Host API v1 table is incomplete');
      }
      final api = table.ref;
      if (api.structSize != size.value ||
          api.abiVersion != 1 ||
          api.magic != 0x54534f485a54414b) {
        throw StateError('Katze Host API v1 header is invalid');
      }
      for (var field = 0; field < 14; field++) {
        if (api.functions[field] == nullptr) {
          throw StateError('Katze Host API v1 is missing ${_entries[field]}');
        }
      }
      return table;
    } finally {
      calloc.free(size);
    }
  }

  Pointer<Void> _entry(Pointer<_GameHostApiV1> table, String name) {
    final index = _entries.indexOf(name);
    return index < 0 ? nullptr : table.ref.functions[index];
  }

  bool providesSymbol(String name) {
    final api = table;
    return api == null
        ? library.providesSymbol(name)
        : _entry(api, name) != nullptr;
  }

  Pointer<NativeFunction<T>> lookup<T extends Function>(String name) {
    final api = table;
    if (api == null) return library.lookup<NativeFunction<T>>(name);
    final entry = _entry(api, name);
    if (entry == nullptr) {
      throw ArgumentError('Katze Host does not provide $name');
    }
    return entry.cast<NativeFunction<T>>();
  }
}

/// Mount and own a single native game. Call on the owning Dart isolate.
final class KatzeGameHost {
  KatzeGameHost._(
    this._host,
    this._api,
    this._translation,
    this._mediaLibrary,
    this._releaseModelHost,
    this._scriptListener,
    this._mount,
    this._session,
    this.width,
    this.height,
  ) {
    _time = _buffers<KatzeFrameTime>();
    _flags = _buffers<Uint32>();
  }

  factory KatzeGameHost.open(
    DynamicLibrary library,
    String root, {
    String encoding = '',
    String saveDirectory = '',
    void Function(String)? onScriptMessage,
  }) {
    final api = KatzeApi.load(library);
    final host = _GameHostBindings(library);
    final mount = host.lookup<_Mount>('katze_game_mount').asFunction<_Mount>();
    final context = using(
      (arena) => mount(
        root.toNativeUtf8(allocator: arena),
        encoding.toNativeUtf8(allocator: arena),
        saveDirectory.toNativeUtf8(allocator: arena),
      ),
    );
    if (context == nullptr) throw StateError('Cannot mount Katze game');
    var session = 0;
    DynamicLibrary? media;
    void Function()? models;
    NativeCallable<_ScriptMessage>? scriptListener;
    try {
      media = _attachMovieHost(host, context);
      models = _attachModelHost(host, context, encoding);
      const enableLogs = 'katze_game_enable_script_messages';
      if (onScriptMessage != null &&
          host.providesSymbol(enableLogs) &&
          host.providesSymbol(_drainScriptMessagesSymbol)) {
        final enable = host
            .lookup<Void Function(Pointer<KatzeCreateInfo>)>(enableLogs)
            .asFunction<void Function(Pointer<KatzeCreateInfo>)>();
        scriptListener = NativeCallable<_ScriptMessage>.isolateLocal(
          (Pointer<Uint8> text, int length) =>
              onScriptMessage(utf8.decode(text.asTypedList(length))),
        );
        enable(context);
      }
      session = api.create(context);
      final (width, height) = api.stage(session);
      return KatzeGameHost._(
        host,
        api,
        KatzeTranslationApi.load(library),
        media,
        models,
        scriptListener,
        context,
        session,
        width,
        height,
      );
    } catch (_) {
      scriptListener?.close();
      if (session != 0) api.destroy(session);
      try {
        _releaseMount(host, context);
      } finally {
        media?.close();
        models?.call();
      }
      rethrow;
    }
  }

  final _GameHostBindings _host;
  final KatzeApi _api;
  final KatzeTranslationApi? _translation;
  final DynamicLibrary? _mediaLibrary;
  final void Function()? _releaseModelHost;
  final NativeCallable<_ScriptMessage>? _scriptListener;
  static const _drainScriptMessagesSymbol = 'katze_game_drain_script_messages';
  final Pointer<KatzeCreateInfo> _mount;
  int _session;
  void Function()? _stopAudio;
  final int width;
  final int height;
  final Arena _buffers = Arena();
  late final Pointer<Uint8> _frame = _buffers<Uint8>(width * height * 4);
  late final Pointer<KatzeFrameTime> _time;
  late final Pointer<Uint32> _flags;
  late final Pointer<Uint32> _imageCursor = _buffers<Uint32>();
  NativeCallable<_PresentFinished>? _presentListener;
  NativeCallable<_PresentReport>? _presentReportListener;
  Completer<bool>? _presentCompletion;
  NativeCallable<_StepFinished>? _stepListener;
  NativeCallable<_StepReport>? _stepReportListener;
  static const _diagnosticCapacity = 4096;
  late final _diagnostic = _buffers<Uint8>(_diagnosticCapacity);
  late final _hasStepReport = _host.providesSymbol(
    'katze_game_step_async_report',
  );
  Completer<bool>? _stepCompletion;
  final _pendingInput = <void Function()>[];

  late final _ReadPixels _pixels = _host
      .lookup<_Pixels>('katze_game_pixels')
      .asFunction<_ReadPixels>();
  late final _InputEvent _pointer = _host
      .lookup<_PointerEvent>('katze_game_pointer')
      .asFunction<_InputEvent>();
  late final _InputEvent _button = _host
      .lookup<_ButtonEvent>('katze_game_button')
      .asFunction<_InputEvent>();
  late final _SetFocus _focus = _host
      .lookup<_FocusEvent>('katze_game_focus')
      .asFunction<_SetFocus>();

  late final _windowAction = _host
      .lookup<Uint32 Function(Pointer<KatzeCreateInfo>)>(
        'katze_game_take_window_action',
      )
      .asFunction<int Function(Pointer<KatzeCreateInfo>)>();

  int takeWindowAction() {
    _requireLive();
    return _windowAction(_mount);
  }

  late final _drainScriptMessages = _host
      .lookup<Void Function(Pointer<KatzeCreateInfo>, _ScriptMessageCallback)>(
        _drainScriptMessagesSymbol,
      )
      .asFunction<
        void Function(Pointer<KatzeCreateInfo>, _ScriptMessageCallback)
      >();

  void _reportScriptMessages() {
    final listener = _scriptListener;
    if (listener != null) {
      _drainScriptMessages(_mount, listener.nativeFunction);
    }
  }

  void reportWindow({bool? fullscreen}) {
    _requireLive();
    _sendInput(() => _api.reportWindow(_session, fullscreen: fullscreen));
  }

  (int, String)? textEntry() {
    _requireLive();
    return _api.textEntry(_session);
  }

  bool completeTextEntry(int id, String? text) {
    _requireLive();
    return _api.completeTextEntry(_session, id, text);
  }

  bool get usesImageCursor => _api.usesImageCursor(_session, _imageCursor);

  bool configureTranslation(
    Map<String, String> entries, {
    required bool online,
  }) => _translation?.configure(_session, entries, online: online) ?? false;

  void drainTranslationRequests(void Function(int, String) request) =>
      _translation?.drain(_session, request);

  void completeTranslation(int id, String? text) =>
      _translation?.complete(_session, id, text);

  bool step({required int increment, required int milliseconds}) {
    _requireLive();
    _requireIdle();
    _time.ref
      ..tick += increment
      ..increment = increment
      ..milliseconds = milliseconds;
    try {
      return (_api.step(_session, _time, _flags) & 1) == 0;
    } finally {
      _reportScriptMessages();
    }
  }

  late final _enqueueStep = _host
      .lookup<Int32 Function(Uint64, Uint32, Uint32, _StepCallback)>(
        'katze_game_step_async',
      )
      .asFunction<int Function(int, int, int, _StepCallback)>();

  late final _enqueueStepReport = _host
      .lookup<
        Int32 Function(
          Uint64,
          Uint32,
          Uint32,
          Pointer<Uint8>,
          Size,
          _StepReportCallback,
        )
      >('katze_game_step_async_report')
      .asFunction<
        int Function(int, int, int, Pointer<Uint8>, int, _StepReportCallback)
      >();

  Future<bool> stepAsync(int milliseconds) async {
    _requireLive();
    _requireIdle();
    final tick = ++_time.ref.tick;
    final int status;
    if (_hasStepReport) {
      final listener = _stepReportListener ??=
          NativeCallable<_StepReport>.listener(
            (int status, int flags, int written) =>
                _finishAsyncStep(status, flags, written),
          );
      status = _enqueueStepReport(
        _session,
        tick,
        milliseconds,
        _diagnostic,
        _diagnosticCapacity,
        listener.nativeFunction,
      );
    } else {
      final listener = _stepListener ??= NativeCallable<_StepFinished>.listener(
        (int status, int flags) => _finishAsyncStep(status, flags),
      );
      status = _enqueueStep(
        _session,
        tick,
        milliseconds,
        listener.nativeFunction,
      );
    }
    if (status != 0) {
      throw StateError('Katze could not queue frame: $status');
    }
    final completion = _stepCompletion = Completer<bool>();
    return completion.future;
  }

  void _finishAsyncStep(int status, int flags, [int written = 0]) {
    final completion = _stepCompletion;
    if (completion == null) return;
    _stepCompletion = null;
    try {
      _reportScriptMessages();
      if (status != 0) {
        final detail = written == 0
            ? 'status $status'
            : utf8.decode(_diagnostic.asTypedList(written));
        throw StateError('Katze step failed: $detail');
      }
      _flushInput();
      completion.complete((flags & 1) == 0);
    } catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      _pendingInput.clear();
    }
  }

  Future<void> waitForFrame() async {
    final pending = _stepCompletion ?? _presentCompletion;
    if (pending != null) {
      await pending.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
    }
  }

  // Mount callbacks can still be using host state until the worker replies.
  bool get _framePending =>
      _stepCompletion != null || _presentCompletion != null;

  void _requireIdle() {
    if (_framePending) throw StateError('Katze frame is pending');
  }

  void _flushInput() {
    try {
      for (final event in _pendingInput) {
        event();
      }
    } finally {
      _pendingInput.clear();
    }
  }

  void _sendInput(void Function() event) {
    if (!_framePending) {
      event();
    } else {
      _pendingInput.add(event);
    }
  }

  late final bool supportsAsyncPixels =
      _host.providesSymbol('katze_game_step_async') &&
      _host.providesSymbol('katze_game_present_async_report');

  bool get supportsSharedTexture =>
      Platform.isMacOS &&
      _host.providesSymbol('katze_game_attach_surface') &&
      _host.providesSymbol('katze_game_present_surface') &&
      _host.providesSymbol('katze_game_step_async');

  late final _attachSurface = _host
      .lookup<
        Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Void>, Uint32, Uint32)
      >('katze_game_attach_surface')
      .asFunction<
        int Function(Pointer<KatzeCreateInfo>, Pointer<Void>, int, int)
      >();
  late final _presentSurface = _host
      .lookup<Int32 Function(Pointer<KatzeCreateInfo>, Uint64)>(
        'katze_game_present_surface',
      )
      .asFunction<int Function(Pointer<KatzeCreateInfo>, int)>();

  late final _presentSurfaceAsync = _host
      .lookup<
        Int32 Function(
          Pointer<KatzeCreateInfo>,
          Uint64,
          Pointer<NativeFunction<_PresentFinished>>,
        )
      >('katze_game_present_surface_async')
      .asFunction<
        int Function(
          Pointer<KatzeCreateInfo>,
          int,
          Pointer<NativeFunction<_PresentFinished>>,
        )
      >();

  late final _presentPixelsAsync = _host
      .lookup<
        Int32 Function(
          Uint64,
          Pointer<Uint8>,
          Size,
          Pointer<NativeFunction<_PresentReport>>,
        )
      >('katze_game_present_async_report')
      .asFunction<
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<NativeFunction<_PresentReport>>,
        )
      >();

  bool attachSurface(int address, int width, int height) {
    _requireLive();
    _requireIdle();
    return _attachSurface(
          _mount,
          Pointer<Void>.fromAddress(address),
          width,
          height,
        ) ==
        0;
  }

  void detachSurface() {
    _requireLive();
    _requireIdle();
    _attachSurface(_mount, nullptr, 0, 0);
  }

  Future<bool> presentSurface() async {
    _requireLive();
    _requireIdle();
    if (!_host.providesSymbol('katze_game_present_surface_async')) {
      return _presentSurface(_mount, _session) == 0;
    }
    final listener = _presentListener ??=
        NativeCallable<_PresentFinished>.listener(
          (int status) => _finishAsyncPresent(status),
        );
    if (_presentSurfaceAsync(_mount, _session, listener.nativeFunction) != 0) {
      return false;
    }
    return (_presentCompletion = Completer<bool>()).future;
  }

  Future<Uint8List?> presentPixelsAsync() async {
    _requireLive();
    _requireIdle();
    final listener = _presentReportListener ??=
        NativeCallable<_PresentReport>.listener((int status, int written) {
          final detail = written == 0
              ? 'status $status'
              : utf8.decode(_diagnostic.asTypedList(written));
          _finishAsyncPresent(status, detail);
        });
    final accepted = _presentPixelsAsync(
      _session,
      _diagnostic,
      _diagnosticCapacity,
      listener.nativeFunction,
    );
    if (accepted != 0) {
      throw StateError('Katze could not queue presentation: $accepted');
    }
    final presented = await (_presentCompletion = Completer<bool>()).future;
    return presented && _session != 0 ? _copyPixels() : null;
  }

  void _finishAsyncPresent(int status, [String? diagnostic]) {
    final completion = _presentCompletion;
    _presentCompletion = null;
    if (completion == null) return;
    try {
      if (status != 0 && diagnostic != null) {
        throw StateError('Katze presentation failed: $diagnostic');
      }
      _flushInput();
      completion.complete(status == 0);
    } catch (error, stack) {
      _pendingInput.clear();
      completion.completeError(error, stack);
    }
  }

  Uint8List present() {
    _requireLive();
    _requireIdle();
    _api.present(_session);
    return _copyPixels();
  }

  Uint8List _copyPixels() {
    final count = width * height * 4;
    if (_pixels(_mount, _frame, count) != count) {
      throw StateError('Katze host did not supply a complete frame');
    }
    return Uint8List.fromList(_frame.asTypedList(count));
  }

  void mixStereo(int sampleRate, Pointer<Float> output, int frames) {
    _requireLive();
    if (_stopAudio != null) {
      throw StateError('Audio device is consuming this session');
    }
    _api.mixStereo(_session, sampleRate, output, frames);
  }

  bool startDeviceAudio() {
    _requireLive();
    if (_stopAudio != null) return true;
    try {
      final start = _host
          .lookup<_AudioStart>('katze_game_audio_start')
          .asFunction<_AudioStartDart>();
      final stop = _host
          .lookup<_AudioStop>('katze_game_audio_stop')
          .asFunction<void Function(Pointer<Void>)>();
      final output = start(_session, _api.mixCallback);
      if (output == nullptr) return false;
      _stopAudio = () => stop(output);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  void stopDeviceAudio() {
    _stopAudio?.call();
    _stopAudio = null;
  }

  void pointer(int x, int y, {bool active = true}) {
    _requireLive();
    _sendInput(() => _pointer(_mount, x, y, active ? 1 : 0));
  }

  void button(int source, int code, bool down) {
    _requireLive();
    _sendInput(() => _button(_mount, source, code, down ? 1 : 0));
  }

  void focus(bool focused) {
    _requireLive();
    _sendInput(() => _focus(_mount, focused ? 1 : 0));
  }

  void close() {
    final session = _session;
    if (session == 0) return;
    stopDeviceAudio();
    try {
      _api.destroy(session);
      _reportScriptMessages();
    } finally {
      _session = 0;
      _scriptListener?.close();
      _presentListener?.close();
      _presentReportListener?.close();
      _presentCompletion?.complete(false);
      _presentCompletion = null;
      _stepListener?.close();
      _stepReportListener?.close();
      _stepCompletion?.complete(false);
      _stepCompletion = null;
      _pendingInput.clear();
      _buffers.releaseAll();
      try {
        _releaseMount(_host, _mount);
      } finally {
        _mediaLibrary?.close();
        _releaseModelHost?.call();
      }
    }
  }

  static DynamicLibrary? _attachMovieHost(
    _GameHostBindings host,
    Pointer<KatzeCreateInfo> mount,
  ) {
    const setter = 'katze_game_set_movie_host';
    if (Platform.environment['KATZE_FFMPEG_MOVIES'] == '1' ||
        !host.providesSymbol(setter)) {
      return null;
    }
    DynamicLibrary? media;
    try {
      media = openKatzeMediaLibrary();
      if (media == null) return null;
      const getter = 'art3m1s_katze_movie_host_v0';
      if (!media.providesSymbol(getter)) {
        media.close();
        return null;
      }
      final callbacks = media
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            getter,
          )();
      final attach = host
          .lookup<Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Void>)>(
            setter,
          )
          .asFunction<int Function(Pointer<KatzeCreateInfo>, Pointer<Void>)>();
      if (attach(mount, callbacks) != 0) {
        throw StateError('Cannot attach the bundled Katze movie host');
      }
      return media;
    } catch (error) {
      media?.close();
      Log.warn('[Katze] Using the built-in movie decoder: $error');
      return null;
    }
  }

  static void Function()? _attachModelHost(
    _GameHostBindings host,
    Pointer<KatzeCreateInfo> mount,
    String encoding,
  ) {
    const setter = 'katze_game_set_model_host';
    if (!host.providesSymbol(setter)) return null;
    final DynamicLibrary core;
    try {
      core = openEngineCoreLibrary();
    } on StateError {
      return null;
    }
    const getter = 'art3m1s_katze_model_host_v0';
    if (!core.providesSymbol(getter)) {
      core.close();
      return null;
    }
    void Function(Pointer<Void>)? destroy;
    var callbacks = nullptr.cast<Void>();
    try {
      final provider = core
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>),
            Pointer<Void> Function(Pointer<Utf8>)
          >(getter);
      const destroySymbol = 'art3m1s_katze_model_host_destroy_v0';
      if (core.providesSymbol(destroySymbol)) {
        destroy = core
            .lookupFunction<
              Void Function(Pointer<Void>),
              void Function(Pointer<Void>)
            >(destroySymbol);
      }
      final attach = host
          .lookup<Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Void>)>(
            setter,
          )
          .asFunction<int Function(Pointer<KatzeCreateInfo>, Pointer<Void>)>();
      callbacks = using(
        (arena) => provider(encoding.toNativeUtf8(allocator: arena)),
      );
      if (attach(mount, callbacks) != 0) {
        throw StateError('Cannot attach the bundled Katze model host');
      }
      return () {
        destroy?.call(callbacks);
        core.close();
      };
    } catch (_) {
      if (callbacks != nullptr) destroy?.call(callbacks);
      core.close();
      rethrow;
    }
  }

  static void _releaseMount(
    _GameHostBindings host,
    Pointer<KatzeCreateInfo> mount,
  ) {
    final unmount = host
        .lookup<_Unmount>('katze_game_unmount')
        .asFunction<int Function(Pointer<KatzeCreateInfo>)>();
    final remaining = unmount(mount);
    if (remaining != 0) {
      throw StateError(
        'Katze released the session with $remaining open resources',
      );
    }
  }

  void _requireLive() {
    if (_session == 0) throw StateError('Katze game is closed');
  }
}
