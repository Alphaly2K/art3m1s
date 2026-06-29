import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef PfsOpenNative = Pointer<Void> Function(Pointer<Utf8> path);
typedef PfsFileSizeNative = Int32 Function(
    Pointer<Void> archive, Pointer<Utf8> path);
typedef PfsEntryCountNative = Int32 Function(Pointer<Void> archive);
typedef PfsEntryPathNative = Int32 Function(
    Pointer<Void> archive, Int32 index, Pointer<Utf8> buf, Int32 bufSize);
typedef PfsReadNative = Int32 Function(
  Pointer<Void> archive,
  Pointer<Utf8> path,
  Uint64 offset,
  Pointer<Uint8> buf,
  Uint32 bufSize,
);
typedef PfsCloseNative = Void Function(Pointer<Void> archive);
typedef PfsUnpackNative = Int32 Function(
    Pointer<Utf8> archivePath, Pointer<Utf8> outputDir);

class PfsBridge {
  static PfsBridge? _instance;
  DynamicLibrary? _lib;
  bool _loaded = false;

  factory PfsBridge() {
    _instance ??= PfsBridge._();
    return _instance!;
  }

  PfsBridge._();

  bool get isLoaded => _loaded;

  void initialize() {
    if (_loaded) return;
    _lib = _loadLibrary();
    _loaded = true;
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    final name = Platform.isMacOS
        ? 'libpfs_upk.dylib'
        : Platform.isLinux || Platform.isAndroid
            ? 'libpfs_upk.so'
            : 'pfs_upk.dll';
    return DynamicLibrary.open(name);
  }

  DynamicLibrary get lib {
    if (_lib == null) initialize();
    return _lib!;
  }

  Pointer<Void> open(String archivePath) {
    final fn = lib.lookupFunction<PfsOpenNative,
        Pointer<Void> Function(Pointer<Utf8>)>('pfs_open');
    final pathPtr = archivePath.toNativeUtf8();
    try {
      return fn(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  int fileSize(Pointer<Void> archive, String path) {
    final fn = lib.lookupFunction<PfsFileSizeNative,
        int Function(Pointer<Void>, Pointer<Utf8>)>('pfs_file_size');
    final pathPtr = path.toNativeUtf8();
    try {
      return fn(archive, pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  int entryCount(Pointer<Void> archive) {
    final fn = lib.lookupFunction<PfsEntryCountNative,
        int Function(Pointer<Void>)>('pfs_entry_count');
    return fn(archive);
  }

  String? entryPath(Pointer<Void> archive, int index) {
    final fn = lib.lookupFunction<PfsEntryPathNative,
        int Function(Pointer<Void>, int, Pointer<Utf8>, int)>('pfs_entry_path');
    const bufSize = 4096;
    final buf = malloc.allocate<Utf8>(bufSize);
    try {
      final written = fn(archive, index, buf, bufSize);
      if (written < 0) return null;
      return buf.toDartString();
    } finally {
      malloc.free(buf);
    }
  }

  int read(Pointer<Void> archive, String path, int offset, Pointer<Uint8> buf, int bufSize) {
    final fn = lib.lookupFunction<PfsReadNative,
        int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Uint8>, int)>(
      'pfs_read',
    );
    final pathPtr = path.toNativeUtf8();
    try {
      return fn(archive, pathPtr, offset, buf, bufSize);
    } finally {
      malloc.free(pathPtr);
    }
  }

  void close(Pointer<Void> archive) {
    final fn = lib.lookupFunction<PfsCloseNative,
        void Function(Pointer<Void>)>('pfs_close');
    fn(archive);
  }

  /// Legacy: bulk unpack to disk.
  String? unpack(String archivePath, String outputDir) {
    final fn = lib.lookupFunction<PfsUnpackNative,
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('pfs_unpack');

    final archiveUtf8 = archivePath.toNativeUtf8();
    final outputUtf8 = outputDir.toNativeUtf8();

    try {
      final result = fn(archiveUtf8, outputUtf8);
      if (result == 0) return null;
      return 'unpack failed (code: $result)';
    } finally {
      malloc.free(archiveUtf8);
      malloc.free(outputUtf8);
    }
  }
}
