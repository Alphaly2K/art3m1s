import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/logger.dart';
import 'pfs_bridge.dart';

typedef FileReaderNative = Int32 Function(
  Pointer<Utf8> path, Pointer<Uint8> buf, Int32 bufSize, Int64 offset,
);
typedef RegisterFileReaderNative = Void Function(
  Pointer<NativeFunction<FileReaderNative>>,
);

class FileProvider {
  static final PfsBridge _pfs = PfsBridge();
  static final List<Pointer<Void>> _archives = [];
  static String? _directory;

  static void openPfs(String archivePath) {
    close();
    _pfs.initialize();

    final dir = File(archivePath).parent;
    // Collect BOTH .pfs and .pfs.NNN files.
    // .pfs          → game data or split-volume base
    // .pfs.NNN      → either a split volume (handled by MultiFileReader)
    //                 OR a standalone patch (translation/mod). We open it
    //                 standalone — if it has a valid PFS header it joins
    //                 the override chain; if it's raw split data it fails
    //                 harmlessly.
    final candidates = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final lower = f.path.toLowerCase();
          return lower.endsWith('.pfs') ||
              RegExp(r'\.pfs\.\d{3}$').hasMatch(lower);
        })
        .map((f) => f.path)
        .toList()
      ..sort();

    for (final path in candidates) {
      final h = _pfs.open(path);
      if (h != nullptr) _archives.add(h);
    }
  }

  static void openDirectory(String root) {
    close();
    _directory = root;
  }

  static void close() {
    for (final h in _archives) {
      _pfs.close(h);
    }
    _archives.clear();
    _directory = null;
  }

  static Uint8List? readFile(String path) => _lookup(path);

  static Uint8List? _lookup(String path) {
    for (final h in _archives.reversed) {
      final size = _pfs.fileSize(h, path);
      if (size > 0) {
        final buf = malloc.allocate<Uint8>(size);
        try {
          final read = _pfs.read(h, path, 0, buf, size);
          if (read > 0) return Uint8List.fromList(buf.asTypedList(read));
        } finally {
          malloc.free(buf);
        }
      }
    }
    if (_directory != null) {
      final file = File('$_directory${Platform.pathSeparator}$path');
      if (file.existsSync()) return file.readAsBytesSync();
    }
    return null;
  }

  static int _callback(Pointer<Utf8> pathPtr, Pointer<Uint8> buf, int bufSize, int offset) {
    final path = pathPtr.toDartString();
    if (buf == nullptr || bufSize <= 0) {
      final sz = _querySize(path);
      if (sz <= 0) Log.debug('MISS: $path');
      return sz;
    }
    final result = _readData(path, buf, bufSize, offset);
    if (result <= 0) Log.debug('MISS: $path read');
    return result;
  }

  static int _querySize(String path) {
    for (final h in _archives.reversed) {
      final sz = _pfs.fileSize(h, path);
      if (sz > 0) return sz;
    }
    if (_directory != null) {
      final file = File('$_directory${Platform.pathSeparator}$path');
      if (file.existsSync()) return file.lengthSync();
    }
    return -1;
  }

  static int _readData(String path, Pointer<Uint8> buf, int bufSize, int offset) {
    for (final h in _archives.reversed) {
      final sz = _pfs.fileSize(h, path);
      if (sz > 0) return _pfs.read(h, path, offset, buf, bufSize);
    }
    if (_directory != null) {
      try {
        if (offset == -1) {
          final file = File('$_directory${Platform.pathSeparator}$path');
          return file.existsSync() ? file.lengthSync() : -1;
        }
        final raf = File('$_directory${Platform.pathSeparator}$path').openSync(mode: FileMode.read);
        try {
          raf.setPositionSync(offset);
          final remaining = raf.lengthSync() - offset;
          final toRead = bufSize < remaining ? bufSize : remaining;
          final data = raf.readSync(toRead);
          for (var i = 0; i < data.length; i++) { buf[i] = data[i]; }
          return data.length;
        } finally {
          raf.closeSync();
        }
      } catch (_) {
        return -1;
      }
    }
    return -1;
  }

  static void register(DynamicLibrary lib) {
    final registerFn = lib.lookupFunction<RegisterFileReaderNative,
        void Function(Pointer<NativeFunction<FileReaderNative>>)>(
      'art3m1s_register_file_reader',
    );
    final nativeCallable = NativeCallable<FileReaderNative>.isolateLocal(
      _callback, exceptionalReturn: -1,
    );
    registerFn(nativeCallable.nativeFunction);
  }
}
