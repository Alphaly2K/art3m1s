import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class _Bytes extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int length;
}

final class _Replacement extends Struct {
  external _Bytes source;
  external _Bytes translation;
}

typedef _Configure =
    Int32 Function(Uint64, Uint32, Pointer<_Replacement>, Size);
typedef _Poll =
    Int32 Function(
      Uint64,
      Pointer<Uint64>,
      Pointer<Uint8>,
      Size,
      Pointer<Size>,
    );
typedef _Complete = Int32 Function(Uint64, Uint64, Pointer<_Bytes>);

final class _Table extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int size;
  external Pointer<NativeFunction<_Configure>> configure;
  external Pointer<NativeFunction<_Poll>> poll;
  external Pointer<NativeFunction<_Complete>> complete;
}

typedef _GetApi = Pointer<_Table> Function();

final class NativeTextTranslation {
  NativeTextTranslation._(_Table table)
    : _configure = table.configure.asFunction(),
      _poll = table.poll.asFunction(),
      _complete = table.complete.asFunction();

  final int Function(int, int, Pointer<_Replacement>, int) _configure;
  final int Function(int, Pointer<Uint64>, Pointer<Uint8>, int, Pointer<Size>)
  _poll;
  final int Function(int, int, Pointer<_Bytes>) _complete;
  static const _maxTextBytes = 16 * 1024;

  static NativeTextTranslation? load(DynamicLibrary library, String symbol) {
    if (!library.providesSymbol(symbol)) return null;
    final pointer = library.lookupFunction<_GetApi, _GetApi>(symbol)();
    if (pointer == nullptr) return null;
    final table = pointer.ref;
    if (table.version != 1 ||
        table.size < sizeOf<_Table>() ||
        table.configure == nullptr ||
        table.poll == nullptr ||
        table.complete == nullptr) {
      return null;
    }
    return NativeTextTranslation._(table);
  }

  bool configure(
    int session,
    Map<String, String> replacements, {
    required bool online,
  }) {
    return using((arena) {
      const maxEntries = 262144;
      final entries = arena<_Replacement>(
        replacements.length.clamp(0, maxEntries),
      );
      var count = 0;
      var total = 0;
      for (final entry in replacements.entries) {
        final source = utf8.encode(entry.key);
        final target = utf8.encode(entry.value);
        if (source.length > _maxTextBytes || target.length > _maxTextBytes) {
          continue;
        }
        total += source.length + target.length;
        if (count == maxEntries || total > 64 * 1024 * 1024) break;
        final pair = entries[count++];
        _write(pair.source, source, arena);
        _write(pair.translation, target, arena);
      }
      return _configure(session, online ? 1 : 0, entries, count) == 0;
    });
  }

  void drain(int session, void Function(int, String) request) {
    using((arena) {
      final id = arena<Uint64>();
      final length = arena<Size>();
      final bytes = arena<Uint8>(_maxTextBytes);
      for (var i = 0; i < 16; ++i) {
        if (_poll(session, id, bytes, _maxTextBytes, length) != 0) break;
        request(id.value, utf8.decode(bytes.asTypedList(length.value)));
      }
    });
  }

  void complete(int session, int id, String? text) {
    using((arena) {
      final bytes = text == null ? null : utf8.encode(text);
      if (bytes == null || bytes.length > _maxTextBytes) {
        _complete(session, id, nullptr);
        return;
      }
      final value = arena<_Bytes>();
      _write(value.ref, bytes, arena);
      _complete(session, id, value);
    });
  }

  static void _write(_Bytes destination, List<int> bytes, Arena arena) {
    destination.data = arena<Uint8>(bytes.length);
    destination.length = bytes.length;
    destination.data.asTypedList(bytes.length).setAll(0, bytes);
  }
}
