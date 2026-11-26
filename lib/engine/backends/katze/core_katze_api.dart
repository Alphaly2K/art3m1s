import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class KatzeStage extends Struct {
  @Uint32()
  external int width;

  @Uint32()
  external int height;
}

final class KatzeFrameTime extends Struct {
  @Uint32()
  external int tick;

  @Uint32()
  external int increment;

  @Uint32()
  external int milliseconds;
}

final class _WindowState extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int flags;
  @Array(4)
  external Array<Int32> contentRect;
  @Uint32()
  external int mode;
  @Uint32()
  external int fullscreen;
}

// Constructed by the native host using the matching katze_system2.h.
final class KatzeCreateInfo extends Opaque {}

typedef _GetApi = Int32 Function(Uint32, Uint32, Pointer<Pointer<_Table>>);

final class _TextBytes extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int length;
}

typedef _TextEntry =
    Int32 Function(
      Uint64,
      Pointer<Uint64>,
      Pointer<Uint8>,
      Size,
      Pointer<Size>,
    );
typedef _CompleteText =
    Int32 Function(Uint64, Uint64, Pointer<_TextBytes>, Pointer<Uint32>);

typedef _LastError = Int32 Function(Pointer<Uint8>, Size, Pointer<Size>);
typedef _Create = Int32 Function(Pointer<KatzeCreateInfo>, Pointer<Uint64>);
typedef _Session = Int32 Function(Uint64);
typedef _Stage = Int32 Function(Uint64, Pointer<KatzeStage>);
typedef _ImageCursor = Int32 Function(Uint64, Pointer<Uint32>);
typedef _Step =
    Int32 Function(Uint64, Pointer<KatzeFrameTime>, Pointer<Uint32>);
typedef KatzeMixStereo = Int32 Function(Uint64, Uint32, Pointer<Float>, Size);

final class _Table extends Struct {
  @Uint32()
  external int version;

  @Uint32()
  external int size;

  external Pointer<NativeFunction<_LastError>> lastError;
  external Pointer<NativeFunction<_Create>> create;
  external Pointer<NativeFunction<_Session>> destroy;
  external Pointer<NativeFunction<_Stage>> sessionInfo;
  external Pointer<NativeFunction<_Step>> step;
  external Pointer<NativeFunction<_Session>> present;
  external Pointer<NativeFunction<KatzeMixStereo>> mixStereo;
  external Pointer<
    NativeFunction<Int32 Function(Uint64, Pointer<_WindowState>)>
  >
  setWindowState;
  external Pointer<NativeFunction<_TextEntry>> textEntry;
  external Pointer<NativeFunction<_CompleteText>> completeTextEntry;
  external Pointer<Void> windowPreferences;
  external Pointer<Void> setInputBindings;
  external Pointer<NativeFunction<_ImageCursor>> usesImageCursor;
}

final class KatzeApi {
  KatzeApi._(this._table);

  factory KatzeApi.load(DynamicLibrary library) => using((arena) {
    final lookup = library
        .lookupFunction<
          _GetApi,
          int Function(int, int, Pointer<Pointer<_Table>>)
        >('katze_system2_get_api');
    final out = arena<Pointer<_Table>>();
    final status = lookup(0, sizeOf<_Table>(), out);
    if (status != 0 || out.value == nullptr) {
      throw StateError('Cannot load Katze ABI 0: status $status');
    }
    final table = out.value.ref;
    if (table.version != 0 || table.size != sizeOf<_Table>()) {
      throw StateError('Katze returned an incompatible function table');
    }
    return KatzeApi._(table);
  });

  final _Table _table;

  Pointer<NativeFunction<KatzeMixStereo>> get mixCallback => _table.mixStereo;

  int create(Pointer<KatzeCreateInfo> info) => using((arena) {
    final out = arena<Uint64>();
    final call = _table.create
        .asFunction<int Function(Pointer<KatzeCreateInfo>, Pointer<Uint64>)>();
    _check(call(info, out), 'create');
    return out.value;
  });

  void destroy(int session) => _check(
    _table.destroy.asFunction<int Function(int)>()(session),
    'destroy',
  );

  (int, int) stage(int session) => using((arena) {
    final out = arena<KatzeStage>();
    final call = _table.sessionInfo
        .asFunction<int Function(int, Pointer<KatzeStage>)>();
    _check(call(session, out), 'session_info');
    return (out.ref.width, out.ref.height);
  });

  int step(int session, Pointer<KatzeFrameTime> time, Pointer<Uint32> flags) {
    final call = _table.step
        .asFunction<
          int Function(int, Pointer<KatzeFrameTime>, Pointer<Uint32>)
        >();
    _check(call(session, time, flags), 'step');
    return flags.value;
  }

  void present(int session) => _check(
    _table.present.asFunction<int Function(int)>()(session),
    'present',
  );

  void mixStereo(
    int session,
    int sampleRate,
    Pointer<Float> output,
    int frames,
  ) {
    final call = _table.mixStereo
        .asFunction<int Function(int, int, Pointer<Float>, int)>();
    _check(call(session, sampleRate, output, frames), 'mix_stereo');
  }

  bool usesImageCursor(int session, Pointer<Uint32> enabled) {
    final call = _table.usesImageCursor
        .asFunction<int Function(int, Pointer<Uint32>)>();
    _check(call(session, enabled), 'uses_image_cursor');
    return enabled.value != 0;
  }

  void reportWindow(int session, {bool? fullscreen}) => using((arena) {
    final state = arena<_WindowState>();
    state.ref
      ..size = sizeOf<_WindowState>()
      ..flags = fullscreen == null ? 2 : 6
      ..mode = 1
      ..fullscreen = fullscreen == true ? 1 : 0;
    final call = _table.setWindowState
        .asFunction<int Function(int, Pointer<_WindowState>)>();
    _check(call(session, state), 'set_window_state');
  });

  (int, String)? textEntry(int session) => using((arena) {
    final id = arena<Uint64>();
    final size = arena<Size>();
    final read = _table.textEntry
        .asFunction<
          int Function(int, Pointer<Uint64>, Pointer<Uint8>, int, Pointer<Size>)
        >();
    Pointer<Uint8> buffer = nullptr;
    var capacity = 0;
    var result = read(session, id, buffer, capacity, size);
    while (result == -4 && size.value > capacity) {
      capacity = size.value;
      buffer = arena<Uint8>(capacity);
      result = read(session, id, buffer, capacity, size);
    }
    _check(result, 'text_entry');
    if (id.value == 0) return null;
    return (
      id.value,
      size.value == 0 ? '' : utf8.decode(buffer.asTypedList(size.value)),
    );
  });

  bool completeTextEntry(int session, int id, String? text) => using((arena) {
    final accepted = arena<Uint32>();
    Pointer<_TextBytes> input = nullptr;
    if (text != null) {
      final bytes = utf8.encode(text);
      input = arena<_TextBytes>();
      if (bytes.isNotEmpty) {
        input.ref.data = arena<Uint8>(bytes.length);
        input.ref.data.asTypedList(bytes.length).setAll(0, bytes);
      }
      input.ref.length = bytes.length;
    }
    final complete = _table.completeTextEntry
        .asFunction<
          int Function(int, int, Pointer<_TextBytes>, Pointer<Uint32>)
        >();
    _check(complete(session, id, input, accepted), 'complete_text_entry');
    return accepted.value != 0;
  });

  void _check(int status, String operation) {
    if (status == 0) return;
    final detail = using((arena) {
      final lastError = _table.lastError
          .asFunction<int Function(Pointer<Uint8>, int, Pointer<Size>)>();
      final size = arena<Size>();
      lastError(nullptr, 0, size);
      if (size.value == 0) return '';
      final buffer = arena<Uint8>(size.value);
      return lastError(buffer, size.value, size) == 0
          ? utf8.decode(buffer.asTypedList(size.value), allowMalformed: true)
          : '';
    });
    throw StateError('Katze $operation failed ($status): $detail');
  }
}
