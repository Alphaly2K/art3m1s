import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/logger.dart';
import 'environment_patch.dart';
import 'pfs_bridge.dart';

typedef FileReaderNative =
    Int32 Function(
      Pointer<Utf8> path,
      Pointer<Uint8> buf,
      Int32 bufSize,
      Int64 offset,
    );
typedef RegisterFileReaderNative =
    Void Function(Pointer<NativeFunction<FileReaderNative>>);

typedef FileWriterNative =
    Int32 Function(Pointer<Utf8> path, Pointer<Uint8> buf, Int32 len);
typedef RegisterFileWriterNative =
    Void Function(Pointer<NativeFunction<FileWriterNative>>);

typedef FileDeleteNative = Int32 Function(Pointer<Utf8> path);
typedef RegisterFileDeleteNative =
    Void Function(Pointer<NativeFunction<FileDeleteNative>>);

final class _PfsResource {
  const _PfsResource(this.archive, this.entryPath, this.size);

  final Pointer<Void> archive;

  /// 归档内的原始条目路径（读取时用它，而不是查询串）。
  final String entryPath;
  final int size;
}

/// 资源索引条目：PFS 条目或目录文件，二选一。
final class _IndexedResource {
  const _IndexedResource({this.pfs, this.file});

  final _PfsResource? pfs;
  final File? file;
}

class FileProvider {
  static final PfsBridge _pfs = PfsBridge();
  static final List<Pointer<Void>> _archives = [];
  static NativeCallable<FileReaderNative>? _readerCallable;
  static NativeCallable<FileWriterNative>? _writerCallable;
  static NativeCallable<FileDeleteNative>? _deleteCallable;
  static String? _directory;
  static bool _environmentPatchEnabled = false;
  static final Map<String, Uint8List> _environmentPatchCache = {};
  // 启动时一次性建立的资源索引：脚本会成批探测多种后缀/路径变体（每个候选
  // 一次 FFI 回调），有索引后存在性与大小查询都是纯内存查表，不再产生
  // 逐路径的系统调用。键为规范化相对路径；目录模式（文件系统大小写不敏感）
  // 键为小写，PFS 模式保持条目原始大小写。
  static final Map<String, _IndexedResource> _resourceIndex = {};
  static bool _resourceIndexCaseInsensitive = false;

  /// 存档读写基准目录（应用沙箱内）。core 通过回调传相对路径（如
  /// `savedata/save0001.dat`），一律拼到此目录下落盘/读取（方案 A1 +
  /// 存档统一放沙箱目录）。
  static String? _saveDir;

  /// 目录模式的活路径回退：仅当资源索引为空（建立失败）时逐路径探测。
  static bool get _directoryFallbackActive =>
      _directory != null && _resourceIndex.isEmpty;

  static void setSaveDir(String dir) {
    _saveDir = dir;
  }

  static void openPfs(
    String archivePath, {
    String archiveEncoding = 'Shift_JIS',
    bool environmentPatchEnabled = false,
  }) {
    close();
    _environmentPatchEnabled = environmentPatchEnabled;
    _pfs.initialize();

    final dir = File(archivePath).parent;
    // Collect BOTH .pfs and .pfs.NNN files.
    // .pfs          → game data or split-volume base
    // .pfs.NNN      → either a split volume (handled by MultiFileReader)
    //                 OR a standalone patch (translation/mod). We open it
    //                 standalone — if it has a valid PFS header it joins
    //                 the override chain; if it's raw split data it fails
    //                 harmlessly.
    final candidates =
        dir
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
      final h = _pfs.openWithEncoding(path, archiveEncoding);
      if (h != nullptr) _archives.add(h);
    }
    _resourceIndexCaseInsensitive = false;
    _buildPfsResourceIndex();
  }

  static void openDirectory(
    String root, {
    bool environmentPatchEnabled = false,
  }) {
    close();
    _directory = root;
    _environmentPatchEnabled = environmentPatchEnabled;
    _resourceIndexCaseInsensitive = true;
    _buildDirectoryResourceIndex(root);
  }

  /// PFS 模式：枚举所有已开归档的条目建索引。后打开的归档（补丁卷）覆盖
  /// 先打开的，与查询时 `_archives.reversed` 的优先序一致。
  static void _buildPfsResourceIndex() {
    for (final archive in _archives) {
      final count = _pfs.entryCount(archive);
      for (var index = 0; index < count; index++) {
        final entryPath = _pfs.entryPath(archive, index);
        if (entryPath == null) continue;
        final size = _pfs.fileSize(archive, entryPath);
        // 0 字节/读不到大小的条目按历史行为视为缺失。
        if (size <= 0) continue;
        final key = entryPath.replaceAll('\\', '/');
        _resourceIndex[key] = _IndexedResource(
          pfs: _PfsResource(archive, entryPath, size),
        );
      }
    }
  }

  /// 目录模式：递归遍历一次建索引。文件系统大小写不敏感，键统一小写。
  static void _buildDirectoryResourceIndex(String root) {
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    try {
      for (final entity in Directory(
        root,
      ).listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.startsWith(prefix)) continue;
        final relative = entity.path
            .substring(prefix.length)
            .replaceAll(Platform.pathSeparator, '/');
        _resourceIndex[relative.toLowerCase()] = _IndexedResource(
          file: File(entity.path),
        );
      }
    } catch (e) {
      Log.warn('[FileProvider] 目录索引建立失败，回退逐路径探测: $e');
      _resourceIndex.clear();
    }
  }

  static String _indexKey(String path) {
    final normalized = path.replaceAll('\\', '/');
    return _resourceIndexCaseInsensitive ? normalized.toLowerCase() : normalized;
  }

  static void close() {
    for (final h in _archives) {
      _pfs.close(h);
    }
    _archives.clear();
    _directory = null;
    _saveDir = null;
    _environmentPatchEnabled = false;
    _environmentPatchCache.clear();
    _resourceIndex.clear();
    _resourceIndexCaseInsensitive = false;
  }

  static Uint8List? readFile(String path) => _lookup(path);

  static List<String> listFiles({String? extension}) {
    final suffix = extension?.toLowerCase();
    final paths = <String, String>{};
    for (final key in _resourceIndex.keys) {
      if (suffix != null && !key.toLowerCase().endsWith(suffix)) continue;
      paths[key.toLowerCase()] = key;
    }
    return paths.values.toList();
  }

  static Uint8List? _lookup(String path) {
    final saveFile = _saveFile(path);
    if (saveFile != null && saveFile.existsSync()) {
      return saveFile.readAsBytesSync();
    }
    final patched = _patchedResource(path);
    if (patched != null) return patched;
    return _lookupResource(path);
  }

  static Uint8List? _lookupResource(String path) {
    final indexed = _resourceIndex[_indexKey(path)];
    if (indexed == null) return _readDirectoryFileLive(path);
    if (indexed.pfs case final resource?) {
      final buf = malloc.allocate<Uint8>(resource.size);
      try {
        final read = _pfs.read(
          resource.archive,
          resource.entryPath,
          0,
          buf,
          resource.size,
        );
        if (read > 0) return Uint8List.fromList(buf.asTypedList(read));
      } finally {
        malloc.free(buf);
      }
      return null;
    }
    final file = indexed.file!;
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  /// 索引未建成时的目录活读回退。
  static Uint8List? _readDirectoryFileLive(String path) {
    final root = _directory;
    if (root == null || !_directoryFallbackActive) return null;
    final file = File('$root${Platform.pathSeparator}$path');
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  static int _callback(
    Pointer<Utf8> pathPtr,
    Pointer<Uint8> buf,
    int bufSize,
    int offset,
  ) {
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
    final patched = _patchedResource(path);
    if (patched != null) return patched.length;
    final indexed = _resourceIndex[_indexKey(path)];
    if (indexed != null) {
      if (indexed.pfs != null) return indexed.pfs!.size;
      final file = indexed.file!;
      return file.existsSync() ? file.lengthSync() : -1;
    }
    if (_directoryFallbackActive) {
      final file = File('$_directory${Platform.pathSeparator}$path');
      if (file.existsSync()) return file.lengthSync();
    }
    return -1;
  }

  static int _readData(
    String path,
    Pointer<Uint8> buf,
    int bufSize,
    int offset,
  ) {
    final saveFile = _saveFile(path);
    if (saveFile != null) {
      final r = _readFromFile(saveFile, buf, bufSize, offset);
      if (r >= 0) return r;
    }
    final patched = _patchedResource(path);
    if (patched != null) {
      return _readFromBytes(patched, buf, bufSize, offset);
    }
    final indexed = _resourceIndex[_indexKey(path)];
    if (indexed != null) {
      if (indexed.pfs case final resource?) {
        return _pfs.read(resource.archive, resource.entryPath, offset, buf, bufSize);
      }
      return _readFromFile(indexed.file!, buf, bufSize, offset);
    }
    if (_directoryFallbackActive) {
      return _readFromFile(
        File('$_directory${Platform.pathSeparator}$path'),
        buf,
        bufSize,
        offset,
      );
    }
    return -1;
  }

  static Uint8List? _patchedResource(String path) {
    if (!_environmentPatchEnabled) return null;

    final normalized = EnvironmentPatch.normalizePath(path);
    if (normalized.isEmpty) return null;
    final cached = _environmentPatchCache[normalized];
    if (cached != null) return cached;

    final virtual = EnvironmentPatch.virtualFile(normalized);
    if (virtual != null) {
      _environmentPatchCache[normalized] = virtual;
      Log.info('[EnvironmentPatch] 覆盖资源: $normalized');
      return virtual;
    }
    if (!EnvironmentPatch.canTransform(normalized)) return null;

    final original = _lookupResource(path);
    if (original == null) return null;
    final transformed = EnvironmentPatch.transform(normalized, original);
    _environmentPatchCache[normalized] = transformed;
    if (!identical(transformed, original)) {
      Log.info('[EnvironmentPatch] 修补启动脚本: $normalized');
    }
    return transformed;
  }

  static int _readFromBytes(
    Uint8List data,
    Pointer<Uint8> buf,
    int bufSize,
    int offset,
  ) {
    if (offset == -1) return data.length;
    if (offset < 0 || offset >= data.length) {
      return offset == data.length ? 0 : -1;
    }
    final count = bufSize < data.length - offset
        ? bufSize
        : data.length - offset;
    buf.asTypedList(count).setRange(0, count, data, offset);
    return count;
  }

  static int _readFromFile(
    File file,
    Pointer<Uint8> buf,
    int bufSize,
    int offset,
  ) {
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
        buf.asTypedList(data.length).setRange(0, data.length, data);
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
    return File(
      '$_saveDir${Platform.pathSeparator}'
      '${rel.replaceAll('/', Platform.pathSeparator)}',
    );
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

  static int _writeCallback(
    Pointer<Utf8> pathPtr,
    Pointer<Uint8> buf,
    int len,
  ) {
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
    final registerFn = lib
        .lookupFunction<
          RegisterFileReaderNative,
          void Function(Pointer<NativeFunction<FileReaderNative>>)
        >('art3m1s_register_file_reader');
    _readerCallable ??= NativeCallable<FileReaderNative>.isolateLocal(
      _callback,
      exceptionalReturn: -1,
    );
    registerFn(_readerCallable!.nativeFunction);

    // 写文件回调（存档落盘）
    final registerWriter = lib
        .lookupFunction<
          RegisterFileWriterNative,
          void Function(Pointer<NativeFunction<FileWriterNative>>)
        >('art3m1s_register_file_writer');
    _writerCallable ??= NativeCallable<FileWriterNative>.isolateLocal(
      _writeCallback,
      exceptionalReturn: -1,
    );
    registerWriter(_writerCallable!.nativeFunction);

    // 删除文件回调（删档）
    final registerDelete = lib
        .lookupFunction<
          RegisterFileDeleteNative,
          void Function(Pointer<NativeFunction<FileDeleteNative>>)
        >('art3m1s_register_file_delete');
    _deleteCallable ??= NativeCallable<FileDeleteNative>.isolateLocal(
      _deleteCallback,
      exceptionalReturn: -1,
    );
    registerDelete(_deleteCallable!.nativeFunction);
  }
}
