import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../native_library.dart';
import 'core_katze_api.dart';

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

typedef _AudioStart =
    Pointer<Void> Function(Uint64, Pointer<NativeFunction<KatzeMixStereo>>);
typedef _AudioStartDart =
    Pointer<Void> Function(int, Pointer<NativeFunction<KatzeMixStereo>>);
typedef _AudioStop = Void Function(Pointer<Void>);

/// Mount and own a single native game. Call on the owning Dart isolate.
final class KatzeGameHost {
  KatzeGameHost._(
    this._library,
    this._api,
    this._mediaLibrary,
    this._releaseModelHost,
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
  }) {
    final api = KatzeApi.load(library);
    final mount = library.lookupFunction<_Mount, _Mount>('katze_game_mount');
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
    try {
      media = _attachMovieHost(library, context);
      models = _attachModelHost(library, context, encoding);
      session = api.create(context);
      final (width, height) = api.stage(session);
      return KatzeGameHost._(
        library,
        api,
        media,
        models,
        context,
        session,
        width,
        height,
      );
    } catch (_) {
      if (session != 0) api.destroy(session);
      try {
        _releaseMount(library, context);
      } finally {
        media?.close();
        models?.call();
      }
      rethrow;
    }
  }

  final DynamicLibrary _library;
  final KatzeApi _api;
  final DynamicLibrary? _mediaLibrary;
  final void Function()? _releaseModelHost;
  final Pointer<KatzeCreateInfo> _mount;
  int _session;
  void Function()? _stopAudio;
  final int width;
  final int height;
  final Arena _buffers = Arena();
  late final Pointer<Uint8> _frame = _buffers<Uint8>(width * height * 4);
  late final Pointer<KatzeFrameTime> _time;
  late final Pointer<Uint32> _flags;
  NativeCallable<_PresentFinished>? _presentListener;
  NativeCallable<_PresentReport>? _presentReportListener;
  Completer<bool>? _presentCompletion;
  NativeCallable<_StepFinished>? _stepListener;
  NativeCallable<_StepReport>? _stepReportListener;
  static const _diagnosticCapacity = 4096;
  late final _diagnostic = _buffers<Uint8>(_diagnosticCapacity);
  late final _hasStepReport = _library.providesSymbol(
    'katze_game_step_async_report',
  );
  Completer<bool>? _stepCompletion;
  final _pendingInput = <void Function()>[];

  late final _ReadPixels _pixels = _library
      .lookupFunction<_Pixels, _ReadPixels>('katze_game_pixels');
  late final _InputEvent _pointer = _library
      .lookupFunction<_PointerEvent, _InputEvent>('katze_game_pointer');
  late final _InputEvent _button = _library
      .lookupFunction<_ButtonEvent, _InputEvent>('katze_game_button');
  late final _SetFocus _focus = _library.lookupFunction<_FocusEvent, _SetFocus>(
    'katze_game_focus',
  );

  late final _windowAction = _library
      .lookupFunction<
        Uint32 Function(Pointer<KatzeCreateInfo>),
        int Function(Pointer<KatzeCreateInfo>)
      >('katze_game_take_window_action');

  int takeWindowAction() {
    _requireLive();
    return _windowAction(_mount);
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

  bool step({required int increment, required int milliseconds}) {
    _requireLive();
    _requireIdle();
    _time.ref
      ..tick += increment
      ..increment = increment
      ..milliseconds = milliseconds;
    return (_api.step(_session, _time, _flags) & 1) == 0;
  }

  late final _enqueueStep = _library
      .lookupFunction<
        Int32 Function(Uint64, Uint32, Uint32, _StepCallback),
        int Function(int, int, int, _StepCallback)
      >('katze_game_step_async');

  late final _enqueueStepReport = _library
      .lookupFunction<
        Int32 Function(
          Uint64,
          Uint32,
          Uint32,
          Pointer<Uint8>,
          Size,
          _StepReportCallback,
        ),
        int Function(int, int, int, Pointer<Uint8>, int, _StepReportCallback)
      >('katze_game_step_async_report');

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
      _library.providesSymbol('katze_game_step_async') &&
      _library.providesSymbol('katze_game_present_async_report');

  bool get supportsSharedTexture =>
      Platform.isMacOS &&
      _library.providesSymbol('katze_game_attach_surface') &&
      _library.providesSymbol('katze_game_present_surface') &&
      _library.providesSymbol('katze_game_step_async');

  late final _attachSurface = _library
      .lookupFunction<
        Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Void>, Uint32, Uint32),
        int Function(Pointer<KatzeCreateInfo>, Pointer<Void>, int, int)
      >('katze_game_attach_surface');
  late final _presentSurface = _library
      .lookupFunction<
        Int32 Function(Pointer<KatzeCreateInfo>, Uint64),
        int Function(Pointer<KatzeCreateInfo>, int)
      >('katze_game_present_surface');

  late final _presentSurfaceAsync = _library
      .lookupFunction<
        Int32 Function(
          Pointer<KatzeCreateInfo>,
          Uint64,
          Pointer<NativeFunction<_PresentFinished>>,
        ),
        int Function(
          Pointer<KatzeCreateInfo>,
          int,
          Pointer<NativeFunction<_PresentFinished>>,
        )
      >('katze_game_present_surface_async');

  late final _presentPixelsAsync = _library
      .lookupFunction<
        Int32 Function(
          Uint64,
          Pointer<Uint8>,
          Size,
          Pointer<NativeFunction<_PresentReport>>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<NativeFunction<_PresentReport>>,
        )
      >('katze_game_present_async_report');

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
    if (!_library.providesSymbol('katze_game_present_surface_async')) {
      return _presentSurface(_mount, _session) == 0;
    }
    final listener = _presentListener ??=
        NativeCallable<_PresentFinished>.listener(_finishAsyncPresent);
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
      final start = _library.lookupFunction<_AudioStart, _AudioStartDart>(
        'katze_game_audio_start',
      );
      final stop = _library
          .lookupFunction<_AudioStop, void Function(Pointer<Void>)>(
            'katze_game_audio_stop',
          );
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
    } finally {
      _session = 0;
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
        _releaseMount(_library, _mount);
      } finally {
        _mediaLibrary?.close();
        _releaseModelHost?.call();
      }
    }
  }

  static DynamicLibrary? _attachMovieHost(
    DynamicLibrary library,
    Pointer<KatzeCreateInfo> mount,
  ) {
    const setter = 'katze_game_set_movie_host';
    if (Platform.environment['KATZE_FFMPEG_MOVIES'] == '1' ||
        !library.providesSymbol(setter)) {
      return null;
    }
    final media = openKatzeMediaLibrary();
    if (media == null) return null;
    const getter = 'art3m1s_katze_movie_host_v0';
    if (!media.providesSymbol(getter)) {
      media.close();
      return null;
    }
    try {
      final callbacks = media
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            getter,
          )();
      final attach = library
          .lookupFunction<
            Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Void>),
            int Function(Pointer<KatzeCreateInfo>, Pointer<Void>)
          >(setter);
      if (attach(mount, callbacks) != 0) {
        throw StateError('Cannot attach the bundled Katze movie host');
      }
      return media;
    } catch (_) {
      media.close();
      rethrow;
    }
  }

  static void Function()? _attachModelHost(
    DynamicLibrary library,
    Pointer<KatzeCreateInfo> mount,
    String encoding,
  ) {
    const setter = 'katze_game_set_model_host';
    if (!library.providesSymbol(setter)) return null;
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
      final attach = library
          .lookupFunction<
            Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Void>),
            int Function(Pointer<KatzeCreateInfo>, Pointer<Void>)
          >(setter);
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
    DynamicLibrary library,
    Pointer<KatzeCreateInfo> mount,
  ) {
    final unmount = library
        .lookupFunction<_Unmount, int Function(Pointer<KatzeCreateInfo>)>(
          'katze_game_unmount',
        );
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
