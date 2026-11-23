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
    this._modelLibrary,
    this._mount,
    this._session,
    this.width,
    this.height,
  ) {
    _frame = _buffers<Uint8>(width * height * 4);
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
    DynamicLibrary? models;
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
        models?.close();
      }
      rethrow;
    }
  }

  final DynamicLibrary _library;
  final KatzeApi _api;
  final DynamicLibrary? _mediaLibrary;
  final DynamicLibrary? _modelLibrary;
  final Pointer<KatzeCreateInfo> _mount;
  int _session;
  void Function()? _stopAudio;
  final int width;
  final int height;
  final Arena _buffers = Arena();
  late final Pointer<Uint8> _frame;
  late final Pointer<KatzeFrameTime> _time;
  late final Pointer<Uint32> _flags;

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
    _api.reportWindow(_session, fullscreen: fullscreen);
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
    _time.ref
      ..tick += increment
      ..increment = increment
      ..milliseconds = milliseconds;
    return (_api.step(_session, _time, _flags) & 1) == 0;
  }

  Uint8List present() {
    _requireLive();
    _api.present(_session);
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
    _pointer(_mount, x, y, active ? 1 : 0);
  }

  void button(int source, int code, bool down) {
    _requireLive();
    _button(_mount, source, code, down ? 1 : 0);
  }

  void focus(bool focused) {
    _requireLive();
    _focus(_mount, focused ? 1 : 0);
  }

  void close() {
    final session = _session;
    if (session == 0) return;
    stopDeviceAudio();
    _api.destroy(session);
    _session = 0;
    _buffers.releaseAll();
    try {
      _releaseMount(_library, _mount);
    } finally {
      _mediaLibrary?.close();
      _modelLibrary?.close();
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

  static DynamicLibrary? _attachModelHost(
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
    try {
      final provider = core
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>),
            Pointer<Void> Function(Pointer<Utf8>)
          >(getter);
      final attach = library
          .lookupFunction<
            Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Void>),
            int Function(Pointer<KatzeCreateInfo>, Pointer<Void>)
          >(setter);
      final callbacks = using(
        (arena) => provider(encoding.toNativeUtf8(allocator: arena)),
      );
      if (attach(mount, callbacks) != 0) {
        throw StateError('Cannot attach the bundled Katze model host');
      }
      return core;
    } catch (_) {
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
