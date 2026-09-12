import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../services/logger.dart';
import 'pfs_bridge.dart';
import 'core_api.dart';
import 'environment_patch.dart';

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
  static CoreApiV1? _coreApi;
  static Pointer<Void>? _resources;
  static bool _ownsResources = false;
  static String? _archivePath;
  static String _archiveEncoding = 'Shift_JIS';
  static String? _directory;
  static bool _environmentPatchEnabled = false;
  static final Map<String, Uint8List> _environmentPatchCache = {};
  // 启动时一次性建立的资源索引：脚本会成批探测多种后缀/路径变体（每个候选
  // 一次 FFI 回调），有索引后存在性与大小查询都是纯内存查表，不再产生
  // 逐路径的系统调用。键为统一小写的 `/` 分隔相对路径（两侧的归档/文件系统
  // 查找历史上都是大小写不敏感的）。
  static final Map<String, _IndexedResource> _resourceIndex = {};

  /// 存档读写基准目录（应用沙箱内）。core 通过回调传相对路径（如
  /// `savedata/save0001.dat`），一律拼到此目录下落盘/读取（方案 A1 +
  /// 存档统一放沙箱目录）。
  static String? _saveDir;

  /// 目录模式的活路径回退：仅当资源索引为空（建立失败）时逐路径探测。
  static bool get _directoryFallbackActive =>
      _directory != null && _resourceIndex.isEmpty;

  static void setSaveDir(String dir) {
    _saveDir = dir;
    final api = _coreApi;
    final resources = _resources;
    if (api != null && resources != null) {
      final ptr = dir.toNativeUtf8();
      try {
        api.fsSetSaveDir(resources, ptr);
      } finally {
        malloc.free(ptr);
      }
    }
  }

  static void openPfs(
    String archivePath, {
    String archiveEncoding = 'Shift_JIS',
    bool environmentPatchEnabled = false,
  }) {
    close();
    _archivePath = archivePath;
    _archiveEncoding = archiveEncoding;
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
    _buildPfsResourceIndex();
  }

  static void openDirectory(
    String root, {
    bool environmentPatchEnabled = false,
  }) {
    close();
    _archivePath = null;
    _directory = root;
    _environmentPatchEnabled = environmentPatchEnabled;
    _buildDirectoryResourceIndex(root);
  }

  /// PFS 模式：枚举所有已开归档的条目建索引。反向遍历 + `putIfAbsent`，
  /// 与查询时"后开归档（补丁卷）优先、同归档内同名取先"的历史语义一致。
  /// 条目大小优先用 O(1) 的 `entrySize` 直读；旧库未导出该符号时回退到
  /// 按路径的 `fileSize` 查询（旧库上较慢，仅作兼容）。
  static void _buildPfsResourceIndex() {
    for (final archive in _archives.reversed) {
      final count = _pfs.entryCount(archive);
      for (var index = 0; index < count; index++) {
        final entryPath = _pfs.entryPath(archive, index);
        if (entryPath == null) continue;
        final size =
            _pfs.entrySize(archive, index) ?? _pfs.fileSize(archive, entryPath);
        // 0 字节/读不到大小的条目按历史行为视为缺失。
        if (size <= 0) continue;
        final key = entryPath.replaceAll('\\', '/').toLowerCase();
        _resourceIndex.putIfAbsent(
          key,
          () => _IndexedResource(pfs: _PfsResource(archive, entryPath, size)),
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

  /// 索引键：统一 `/` 分隔 + 小写。PFS 与目录两侧的历史查找行为都是
  /// 大小写不敏感的（pf8/引擎归档查找、大小写不敏感文件系统）。
  static String _indexKey(String path) {
    return path.replaceAll('\\', '/').toLowerCase();
  }

  static void close() {
    final api = _coreApi;
    final resources = _resources;
    if (api != null && resources != null && resources != nullptr) {
      api.fsClear(resources);
      if (_ownsResources) {
        api.destroyResources(resources);
      }
    }
    _coreApi = null;
    _resources = null;
    _ownsResources = false;
    for (final h in _archives) {
      _pfs.close(h);
    }
    _archives.clear();
    _archivePath = null;
    _directory = null;
    _saveDir = null;
    _environmentPatchEnabled = false;
    _environmentPatchCache.clear();
    _resourceIndex.clear();
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
    if (_archivePath != null) {
      final sidecar = _readArchiveSidecar(path);
      if (sidecar != null) return sidecar;
    }
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

  /// PFS 归档旁的散装资源。部分游戏把视频等大文件放在归档同目录，且这些
  /// 文件应覆盖归档内同名条目；路径仍限制在归档父目录内。
  static Uint8List? _readArchiveSidecar(String path) {
    final archivePath = _archivePath;
    if (archivePath == null) return null;
    final relative = _normalizeRelativePath(path);
    if (relative == null) return null;
    final root = File(archivePath).parent;
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}',
    );
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  /// 索引未建成时的目录活读回退。
  static Uint8List? _readDirectoryFileLive(String path) {
    final root = _directory;
    if (root == null || !_directoryFallbackActive) return null;
    final file = File('$root${Platform.pathSeparator}$path');
    return file.existsSync() ? file.readAsBytesSync() : null;
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

  static Map<String, Uint8List> _coreOverrides() {
    if (!_environmentPatchEnabled) return const {};
    final overrides = EnvironmentPatch.virtualFiles();
    final original = _lookupResource('system/first.iet');
    if (original != null) {
      final transformed = EnvironmentPatch.transform(
        'system/first.iet',
        original,
      );
      if (!identical(transformed, original)) {
        overrides['system/first.iet'] = transformed;
      }
    }
    return overrides;
  }

  static void mountCore(
    DynamicLibrary lib, {
    CoreApiV1? coreApi,
    Pointer<Void>? resources,
  }) {
    final api = coreApi ?? CoreApiV1.tryLoad(lib);
    if (api == null) {
      throw StateError('core 缺少 art3m1s_get_api_v1，拒绝使用旧文件 ABI');
    }
    final ownsResources = resources == null;
    final resourceHandle = resources ?? api.createResources();
    if (resourceHandle == nullptr) {
      throw StateError('core 创建资源句柄失败');
    }
    api.fsClear(resourceHandle);
    if (_directory case final root?) {
      final path = root.toNativeUtf8();
      try {
        if (api.fsMountDirectory(resourceHandle, path) == 0) {
          throw StateError('mount directory failed: $root');
        }
      } finally {
        malloc.free(path);
      }
    } else if (_archivePath case final archive?) {
      final path = archive.toNativeUtf8();
      final encoding = _archiveEncoding.toNativeUtf8();
      try {
        if (api.fsMountPfs(resourceHandle, path, encoding) == 0) {
          throw StateError('mount PFS failed: $archive');
        }
      } finally {
        malloc.free(path);
        malloc.free(encoding);
      }
    } else {
      throw StateError('FileProvider has no mounted resource root');
    }
    api.fsClearOverrides(resourceHandle);
    for (final entry in _coreOverrides().entries) {
      final path = entry.key.toNativeUtf8();
      final data = entry.value;
      final bytes = malloc.allocate<Uint8>(data.length);
      try {
        bytes.asTypedList(data.length).setAll(0, data);
        if (api.fsSetOverride(resourceHandle, path, bytes, data.length) == 0) {
          throw StateError('set core override failed: ${entry.key}');
        }
      } finally {
        malloc.free(path);
        malloc.free(bytes);
      }
    }
    if (_saveDir case final saveDir?) {
      final path = saveDir.toNativeUtf8();
      try {
        if (api.fsSetSaveDir(resourceHandle, path) == 0) {
          throw StateError('set core save directory failed: $saveDir');
        }
      } finally {
        malloc.free(path);
      }
    }
    _coreApi = api;
    _resources = resourceHandle;
    _ownsResources = ownsResources;
  }
}
