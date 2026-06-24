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

typedef FileWriterNative = Int32 Function(
  Pointer<Utf8> path, Pointer<Uint8> buf, Int32 len,
);
typedef RegisterFileWriterNative = Void Function(
  Pointer<NativeFunction<FileWriterNative>>,
);

typedef FileDeleteNative = Int32 Function(Pointer<Utf8> path);
typedef RegisterFileDeleteNative = Void Function(
  Pointer<NativeFunction<FileDeleteNative>>,
);

class FileProvider {
  static final PfsBridge _pfs = PfsBridge();
  static final List<Pointer<Void>> _archives = [];
  static NativeCallable<FileReaderNative>? _readerCallable;
  static NativeCallable<FileWriterNative>? _writerCallable;
  static NativeCallable<FileDeleteNative>? _deleteCallable;
  static String? _directory;

  /// 存档读写基准目录（应用沙箱内）。core 通过回调传相对路径（如
  /// `savedata/save0001.dat`），一律拼到此目录下落盘/读取（方案 A1 +
  /// 存档统一放沙箱目录）。
  static String? _saveDir;

  static void setSaveDir(String dir) {
    _saveDir = dir;
  }

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
    _saveDir = null;
  }

  static Uint8List? readFile(String path) => _lookup(path);

  static Uint8List? _lookup(String path) {
    final saveFile = _saveFile(path);
    if (saveFile != null && saveFile.existsSync()) {
      return saveFile.readAsBytesSync();
    }
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
    final saveFile = _saveFile(path);
    if (saveFile != null && saveFile.existsSync()) {
      return saveFile.lengthSync();
    }
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
    final saveFile = _saveFile(path);
    if (saveFile != null) {
      final r = _readFromFile(saveFile, buf, bufSize, offset);
      if (r >= 0) return r;
    }
    for (final h in _archives.reversed) {
      final sz = _pfs.fileSize(h, path);
      if (sz > 0) return _pfs.read(h, path, offset, buf, bufSize);
    }
    if (_directory != null) {
      final r = _readFromFile(
        File('$_directory${Platform.pathSeparator}$path'), buf, bufSize, offset);
      if (r >= 0) return r;
    }
    return -1;
  }

  static int _readFromFile(File file, Pointer<Uint8> buf, int bufSize, int offset) {
    try {
      if (offset == -1) {
        return file.existsSync() ? file.lengthSync() : -1;
      }
      if (!file.existsSync()) return -1;
      final raf = file.openSync(mode: FileMode.read);
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

  /// 把 core 传来的脚本相对路径解析为沙箱内的存档文件。
  static File? _saveFile(String path) {
    if (_saveDir == null) return null;
    final rel = _normalizeRelativePath(path);
    if (rel == null) {
      Log.warn('[FileProvider] 非法存档路径: $path');
      return null;
    }
    return File('$_saveDir${Platform.pathSeparator}'
        '${rel.replaceAll('/', Platform.pathSeparator)}');
  }

  static String? _normalizeRelativePath(String path) {
    final parts = <String>[];
    for (final raw in path.trim().replaceAll('\\', '/').split('/')) {
      final part = raw.trim();
      if (part.isEmpty || part == '.') continue;
      if (part == '..' || part.contains(':')) return null;
      parts.add(part);
    }
    return parts.isEmpty ? null : parts.join('/');
  }

  static int _writeCallback(Pointer<Utf8> pathPtr, Pointer<Uint8> buf, int len) {
    try {
      final path = pathPtr.toDartString();
      final file = _saveFile(path);
      if (file == null) {
        Log.warn('[FileProvider] writer: saveDir 未设置, 丢弃 $path');
        return -1;
      }
      file.parent.createSync(recursive: true);
      final data = len > 0 ? buf.asTypedList(len) : Uint8List(0);
      file.writeAsBytesSync(data, flush: true);
      return len;
    } catch (e) {
      Log.error('[FileProvider] writer 失败: $e');
      return -1;
    }
  }

  static int _deleteCallback(Pointer<Utf8> pathPtr) {
    try {
      final path = pathPtr.toDartString();
      final file = _saveFile(path);
      if (file == null) return -1;
      if (file.existsSync()) file.deleteSync();
      return 0;
    } catch (e) {
      Log.error('[FileProvider] delete 失败: $e');
      return -1;
    }
  }

  static void register(DynamicLibrary lib) {
    final registerFn = lib.lookupFunction<RegisterFileReaderNative,
        void Function(Pointer<NativeFunction<FileReaderNative>>)>(
      'art3m1s_register_file_reader',
    );
    _readerCallable ??= NativeCallable<FileReaderNative>.isolateLocal(
      _callback, exceptionalReturn: -1,
    );
    registerFn(_readerCallable!.nativeFunction);

    // 写文件回调（存档落盘）
    final registerWriter = lib.lookupFunction<RegisterFileWriterNative,
        void Function(Pointer<NativeFunction<FileWriterNative>>)>(
      'art3m1s_register_file_writer',
    );
    _writerCallable ??= NativeCallable<FileWriterNative>.isolateLocal(
      _writeCallback, exceptionalReturn: -1,
    );
    registerWriter(_writerCallable!.nativeFunction);

    // 删除文件回调（删档）
    final registerDelete = lib.lookupFunction<RegisterFileDeleteNative,
        void Function(Pointer<NativeFunction<FileDeleteNative>>)>(
      'art3m1s_register_file_delete',
    );
    _deleteCallable ??= NativeCallable<FileDeleteNative>.isolateLocal(
      _deleteCallback, exceptionalReturn: -1,
    );
    registerDelete(_deleteCallable!.nativeFunction);
  }
}
