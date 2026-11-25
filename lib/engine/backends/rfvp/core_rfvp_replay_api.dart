part of 'core_rfvp_api.dart';

final class _ReplayBytes extends Struct {
  external Pointer<Uint8> data;
  @Uint64()
  external int length;
}

final class _ReplayOpen extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int nls;
  external _ReplayBytes project;
  external _ReplayBytes saves;
}

final class RfvpReplayRect extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int width;
  @Int32()
  external int height;
}

final class RfvpReplayVertex extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
  @Float()
  external double u;
  @Float()
  external double v;
  @Array(4)
  external Array<Float> rgba;
}

final class RfvpReplayDraw extends Struct {
  @Uint32()
  external int kind;
  @Uint32()
  external int texture;
  @Uint32()
  external int blend;
  @Uint32()
  external int filter;
  @Uint32()
  external int hasClip;
  @Uint32()
  external int effect;
  external RfvpReplayRect source;
  external RfvpReplayRect destination;
  external RfvpReplayRect clip;
  @Array(4)
  external Array<Uint8> rgba;
  @Array(4)
  external Array<RfvpReplayVertex> vertices;
}

final class RfvpReplayHit extends Struct {
  @Uint32()
  external int primId;
  @Uint32()
  external int flags;
  external RfvpReplayRect bounds;
  @Uint32()
  external int order;
}

final class RfvpReplayFrameView extends Struct {
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int drawCount;
  @Uint32()
  external int hitCount;
  @Uint32()
  external int textureCount;
  @Uint32()
  external int reserved;
  external Pointer<RfvpReplayDraw> draws;
  external Pointer<RfvpReplayHit> hits;
}

final class RfvpReplayTexture extends Struct {
  @Uint32()
  external int texture;
  @Uint32()
  external int format;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint64()
  external int generation;
  external _ReplayBytes _pixels;

  /// Read-only bytes borrowed from the frame. Copy to retain them.
  Uint8List get pixels => _pixels.length == 0
      ? Uint8List(0)
      : _pixels.data.asTypedList(_pixels.length).asUnmodifiableView();
}

typedef _ReplayQuery =
    Int32 Function(Uint32, Uint32, Pointer<Pointer<_ReplayApi>>);
typedef _ReplayOpenFn = Int32 Function(Pointer<_ReplayOpen>, Pointer<Uint64>);
typedef _ReplayHandleFn = Int32 Function(Uint64);
typedef _ReplayInputFn = Int32 Function(Uint64, Pointer<_InputEventV1>, Uint32);
typedef _ReplayStepFn = Int32 Function(Uint64, Uint32, Pointer<Uint32>);
typedef _ReplayAcquireFn = Int32 Function(Uint64, Pointer<Uint64>);
typedef _ReplayViewFn = Int32 Function(Uint64, Pointer<RfvpReplayFrameView>);
typedef _ReplayTextureFn =
    Int32 Function(Uint64, Uint32, Pointer<RfvpReplayTexture>);

final class _ReplayApi extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int major;
  @Uint64()
  external int magic;
  external Pointer<NativeFunction<_ReplayOpenFn>> openDirectory;
  external Pointer<NativeFunction<_ReplayHandleFn>> close;
  external Pointer<NativeFunction<_ReplayInputFn>> pushInput;
  external Pointer<NativeFunction<_ReplayStepFn>> step;
  external Pointer<NativeFunction<_ReplayAcquireFn>> acquireFrame;
  external Pointer<NativeFunction<_ReplayViewFn>> frameView;
  external Pointer<NativeFunction<_ReplayTextureFn>> frameTexture;
  external Pointer<NativeFunction<_ReplayHandleFn>> releaseFrame;
}

/// CPU frame interface for a Flutter Host that provides its own renderer.
final class CoreRfvpReplayApi {
  CoreRfvpReplayApi._(this._api);

  final Pointer<_ReplayApi> _api;

  static CoreRfvpReplayApi? tryLoad(DynamicLibrary library) {
    const symbol = 'art3m1s_rfvp_get_api_v2';
    if (!library.providesSymbol(symbol)) return null;
    final query = library
        .lookupFunction<
          _ReplayQuery,
          int Function(int, int, Pointer<Pointer<_ReplayApi>>)
        >(symbol);
    return using((arena) {
      final out = arena<Pointer<_ReplayApi>>();
      final size = sizeOf<_ReplayApi>();
      if (query(2, size, out) != 0 || out.value == nullptr) return null;
      final api = out.value.ref;
      if (api.structSize < size ||
          api.major != 2 ||
          api.magic != 0x325646524d334152) {
        return null;
      }
      return CoreRfvpReplayApi._(out.value);
    });
  }

  RfvpReplaySession openDirectory(
    String root, {
    String? saveRoot,
    int nls = art3m1sRfvpNlsShiftJis,
  }) => using((arena) {
    final info = arena<_ReplayOpen>();
    final project = root.toNativeUtf8(allocator: arena);
    final saves = saveRoot?.toNativeUtf8(allocator: arena);
    info.ref
      ..structSize = sizeOf<_ReplayOpen>()
      ..nls = nls;
    info.ref.project
      ..data = project.cast()
      ..length = project.length;
    if (saves != null) {
      info.ref.saves
        ..data = saves.cast()
        ..length = saves.length;
    }
    final out = arena<Uint64>();
    final status =
        _api.ref.openDirectory
            .asFunction<int Function(Pointer<_ReplayOpen>, Pointer<Uint64>)>()(
          info,
          out,
        );
    _checkReplayStatus('openDirectory', status);
    return RfvpReplaySession._(_api, out.value);
  });
}

final class RfvpReplaySession {
  RfvpReplaySession._(this._api, this._session);

  final Pointer<_ReplayApi> _api;
  int _session;

  void pushInput(List<RfvpCoreInputEvent> events) {
    if (events.isEmpty) return;
    using((arena) {
      final native = arena<_InputEventV1>(events.length);
      _writeInputEvents(native, events);
      final status =
          _api.ref.pushInput
              .asFunction<int Function(int, Pointer<_InputEventV1>, int)>()(
            _session,
            native,
            events.length,
          );
      _checkReplayStatus('pushInput', status);
    });
  }

  /// Advances by the Host's elapsed time and returns whether the game exited.
  bool step(int deltaMs) => using((arena) {
    final flags = arena<Uint32>();
    final status =
        _api.ref.step.asFunction<int Function(int, int, Pointer<Uint32>)>()(
          _session,
          deltaMs,
          flags,
        );
    _checkReplayStatus('step', status);
    return flags.value & 1 != 0;
  });

  RfvpReplayFrame? acquireFrame() => using((arena) {
    final lease = arena<Uint64>();
    final status = _api.ref.acquireFrame
        .asFunction<int Function(int, Pointer<Uint64>)>()(_session, lease);
    if (status == art3m1sRfvpStatusNoFrame) return null;
    _checkReplayStatus('acquireFrame', status);
    return RfvpReplayFrame._(_api, lease.value);
  });

  void close() {
    if (_session == 0) return;
    _checkReplayStatus(
      'close',
      _api.ref.close.asFunction<int Function(int)>()(_session),
    );
    _session = 0;
  }
}

/// An immutable frame lease. Close it after the renderer finishes reading it.
final class RfvpReplayFrame {
  RfvpReplayFrame._(this._api, this._lease);

  final Pointer<_ReplayApi> _api;
  int _lease;
  int _activeReads = 0;

  /// Use the read-only structs and pointers during the synchronous [read] call.
  T withView<T>(T Function(RfvpReplayFrameView) read) => _borrow((arena) {
    final view = arena<RfvpReplayFrameView>();
    final status =
        _api.ref.frameView
            .asFunction<int Function(int, Pointer<RfvpReplayFrameView>)>()(
          _lease,
          view,
        );
    _checkReplayStatus('frameView', status);
    return read(view.ref);
  });

  /// Use the texture record and bytes during the synchronous [read] call.
  T withTexture<T>(int index, T Function(RfvpReplayTexture) read) => _borrow((
    arena,
  ) {
    final texture = arena<RfvpReplayTexture>();
    final status =
        _api.ref.frameTexture
            .asFunction<int Function(int, int, Pointer<RfvpReplayTexture>)>()(
          _lease,
          index,
          texture,
        );
    _checkReplayStatus('frameTexture', status);
    return read(texture.ref);
  });

  T _borrow<T>(T Function(Arena) read) {
    _activeReads++;
    try {
      return using(read);
    } finally {
      _activeReads--;
    }
  }

  void close() {
    if (_lease == 0) return;
    if (_activeReads != 0) throw StateError('RFVP frame is being read');
    _checkReplayStatus(
      'releaseFrame',
      _api.ref.releaseFrame.asFunction<int Function(int)>()(_lease),
    );
    _lease = 0;
  }
}

void _checkReplayStatus(String operation, int status) {
  if (status != art3m1sRfvpStatusOk) {
    throw RfvpReplayException(operation, status);
  }
}

final class RfvpReplayException implements Exception {
  const RfvpReplayException(this.operation, this.status);

  final String operation;
  final int status;

  @override
  String toString() => 'RFVP v2 $operation failed with status $status';
}
