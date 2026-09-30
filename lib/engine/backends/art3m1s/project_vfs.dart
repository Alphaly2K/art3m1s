import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../services/logger.dart';
import 'pfs_bridge.dart';
import 'project_charset.dart';

/// 解析结果：资源来自某个散装文件，或某个 PFS 归档条目。
final class VfsEntry {
  VfsEntry.file(File this.file) : archive = null, entryPath = null, size = 0;

  VfsEntry.archive({
    required Pointer<Void> this.archive,
    required String this.entryPath,
    required this.size,
  }) : file = null;

  final File? file;
  final Pointer<Void>? archive;
  final String? entryPath;
  final int size;
}

/// 一层只读资源视图。查找用归一化键（`/` 分隔、小写），读取用原始相对路径：
/// 归档和大小写敏感文件系统都按原始路径命中。
abstract interface class VfsLayer {
  VfsEntry? lookup(String key, String path);

  /// 参与 [ProjectVfs.listFiles] 的归一化键。sidecar 层不参与列表。
  Iterable<String> get indexedPaths;

  void close();
}

/// 散装目录层。
///
/// * 解包工程用 [DirectoryVfsLayer.indexed]：打开时建一次索引，会话内视为只读。
/// * 归档工程的同级散装文件用 [DirectoryVfsLayer.live]：逐次探测，命中即覆盖
///   归档条目（与 core 的 sidecar 语义一致），但不参与 `listFiles`。
final class DirectoryVfsLayer implements VfsLayer {
  factory DirectoryVfsLayer.indexed(String root) {
    final result = _indexDirectory(root);
    return DirectoryVfsLayer._(root, result.files, result.failed);
  }

  factory DirectoryVfsLayer.live(String root) =>
      DirectoryVfsLayer._(root, null, true);

  DirectoryVfsLayer._(this._root, this._snapshot, this._liveFallback);

  final String _root;
  final Map<String, File>? _snapshot;
  final bool _liveFallback;

  static ({Map<String, File> files, bool failed}) _indexDirectory(String root) {
    final index = <String, File>{};
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
        index[relative.toLowerCase()] = File(entity.path);
      }
    } catch (error) {
      Log.warn('[ProjectVfs] 目录索引建立失败，回退逐路径探测: $error');
      return (files: index, failed: true);
    }
    return (files: index, failed: false);
  }

  @override
  VfsEntry? lookup(String key, String path) {
    final snapshot = _snapshot;
    if (snapshot != null && !_liveFallback) {
      final file = snapshot[key];
      return file == null ? null : VfsEntry.file(file);
    }
    final file = File(
      '$_root${Platform.pathSeparator}'
      '${path.replaceAll('/', Platform.pathSeparator)}',
    );
    return file.existsSync() ? VfsEntry.file(file) : null;
  }

  @override
  Iterable<String> get indexedPaths => _snapshot?.keys ?? const <String>[];

  @override
  void close() {}
}

/// 单个 PFS 归档（基础卷或分卷各占一层）。
final class PfsVfsLayer implements VfsLayer {
  PfsVfsLayer._(this.path, this._archive, this._entries);

  static final PfsBridge _bridge = PfsBridge();

  final String path;
  final Pointer<Void> _archive;
  final Map<String, ({String entryPath, int size})> _entries;

  /// 打不开时返回 null：调用方把它当作缺失层而不是致命错误。
  static PfsVfsLayer? open(String path, {required String charset}) {
    _bridge.initialize();
    final requested = ProjectCharset.normalize(charset);
    final requestedHandle = _bridge.openWithEncoding(path, requested);
    if (requestedHandle == nullptr) {
      Log.warn('[ProjectVfs] 归档打开失败: $path');
      return null;
    }
    var handle = requestedHandle;
    var entries = _readEntries(handle);
    if (requested != 'UTF-8') {
      final utf8Handle = _bridge.openWithEncoding(path, 'UTF-8');
      if (utf8Handle != nullptr) {
        final utf8Entries = _readEntries(utf8Handle);
        if (_preferUtf8(entries, utf8Entries)) {
          _bridge.close(requestedHandle);
          handle = utf8Handle;
          entries = utf8Entries;
        } else {
          _bridge.close(utf8Handle);
        }
      }
    }
    return PfsVfsLayer._(path, handle, entries);
  }

  /// 与 core 的选择规则一致：UTF-8 解出的名字不同且没有替换字符时才改用它，
  /// 否则保留请求字符集，避免 Shift_JIS 名字被解坏。
  static bool _preferUtf8(
    Map<String, ({String entryPath, int size})> requested,
    Map<String, ({String entryPath, int size})> utf8,
  ) {
    final requestedNames = requested.values
        .map((entry) => entry.entryPath)
        .toSet();
    final utf8Names = utf8.values.map((entry) => entry.entryPath).toSet();
    if (requestedNames.length == utf8Names.length &&
        requestedNames.containsAll(utf8Names)) {
      return false;
    }
    return utf8Names.every((name) => !name.contains('\uFFFD'));
  }

  static Map<String, ({String entryPath, int size})> _readEntries(
    Pointer<Void> archive,
  ) {
    final entries = <String, ({String entryPath, int size})>{};
    final count = _bridge.entryCount(archive);
    for (var index = 0; index < count; index++) {
      final entryPath = _bridge.entryPath(archive, index);
      if (entryPath == null) continue;
      final size =
          _bridge.entrySize(archive, index) ??
          _bridge.fileSize(archive, entryPath);
      // 0 字节/读不到大小的条目按历史行为视为缺失。
      if (size <= 0) continue;
      final key = _normalizeKey(entryPath);
      if (key == null) continue;
      entries.putIfAbsent(key, () => (entryPath: entryPath, size: size));
    }
    return entries;
  }

  @override
  VfsEntry? lookup(String key, String path) {
    final entry = _entries[key];
    if (entry == null) return null;
    return VfsEntry.archive(
      archive: _archive,
      entryPath: entry.entryPath,
      size: entry.size,
    );
  }

  @override
  Iterable<String> get indexedPaths => _entries.keys;

  @override
  void close() {
    _bridge.close(_archive);
  }
}

/// Artemis 项目 VFS。
///
/// 查找优先级（高 → 低）：
///   1. 解包目录（散装补丁文件，含归档工程的 sidecar 文件）
///   2. 大 id 分卷（`root.pfs.006` → `root.pfs.002`）
///   3. 小 id 分卷与基础卷（`root.pfs.000` → `root.pfs`）
///
/// 存档与运行期 override 由调用方置于本 VFS 之前。core 侧挂载 PFS 时用同一套
/// 优先级：归档父目录是 sidecar 覆盖层，归档之间后挂载者胜出。
final class ProjectVfs {
  ProjectVfs._(this._layers, this._directoryRoot, this._archiveBasePath);

  final List<VfsLayer> _layers;
  final String? _directoryRoot;
  final String? _archiveBasePath;

  /// 传给 core `resources_mount_pfs` 的入口归档；无归档层时为 null。
  String? get archiveBasePath => _archiveBasePath;

  /// 挂载失败时回退 `resources_mount_directory` 用的目录。
  String? get directoryRoot => _directoryRoot;

  bool get hasArchiveLayers => _archiveBasePath != null;

  /// 打开解包工程：散装文件优先，其次按 id 从大到小叠加同级归档。
  static ProjectVfs openDirectory(
    String root, {
    String charset = 'Shift_JIS',
    bool includeInnerArchives = true,
    bool indexDirectory = true,
  }) {
    final layers = <VfsLayer>[
      indexDirectory
          ? DirectoryVfsLayer.indexed(root)
          : DirectoryVfsLayer.live(root),
    ];
    String? archiveBase;
    if (includeInnerArchives) {
      final candidates = listArchiveCandidatesIn(root);
      final opened = <String>[];
      for (final candidate in candidates.reversed) {
        final layer = PfsVfsLayer.open(candidate, charset: charset);
        if (layer == null) continue;
        layers.add(layer);
        opened.add(candidate);
      }
      // core 需要一个能打开的入口归档；没有归档层时保持目录模式。
      if (opened.isNotEmpty) {
        final base = archiveBaseFor(candidates);
        archiveBase = base != null && opened.contains(base)
            ? base
            : opened.last;
      }
    }
    return ProjectVfs._(layers, root, archiveBase);
  }

  /// 打开归档工程：同级散装文件优先，其次按 id 从大到小叠加归档。
  static ProjectVfs openArchive(
    String archivePath, {
    String charset = 'Shift_JIS',
  }) {
    final parent = File(archivePath).parent.path;
    final layers = <VfsLayer>[DirectoryVfsLayer.live(parent)];
    final candidates = listArchiveCandidatesIn(parent);
    for (final candidate in candidates.reversed) {
      final layer = PfsVfsLayer.open(candidate, charset: charset);
      if (layer != null) layers.add(layer);
    }
    return ProjectVfs._(
      layers,
      parent,
      layers.length > 1 ? archiveBaseFor(candidates) ?? archivePath : null,
    );
  }

  /// 枚举归档所在目录里的 `.pfs` 与 `.pfs.NNN` 候选（升序，AppleDouble 除外）。
  static List<String> listArchiveCandidatesIn(String directoryPath) {
    final candidates = <String>[];
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) return candidates;
    try {
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.split(RegExp(r'[/\\]')).last;
        if (name.startsWith('._')) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.pfs') ||
            RegExp(r'\.pfs\.\d{3}$').hasMatch(lower)) {
          candidates.add(entity.path);
        }
      }
    } on FileSystemException catch (error) {
      Log.warn('[ProjectVfs] 归档候选枚举失败: $error');
    }
    candidates.sort();
    return candidates;
  }

  /// 基础卷优先作为入口；只有分卷时退回最小 id。
  static String? archiveBaseFor(List<String> candidates) {
    for (final candidate in candidates) {
      if (candidate.toLowerCase().endsWith('.pfs')) return candidate;
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  /// 按优先级查找并读取。路径不合法或未命中都返回 null。
  Uint8List? readFile(String path) {
    final normalized = normalizeRelativePath(path);
    if (normalized == null) return null;
    final key = normalized.toLowerCase();
    for (final layer in _layers) {
      final entry = layer.lookup(key, normalized);
      if (entry == null) continue;
      final bytes = _read(entry);
      if (bytes != null) return bytes;
    }
    return null;
  }

  /// 索引中可见的路径（去重后按层优先级合并）。
  List<String> listFiles({String? extension}) {
    final suffix = extension?.toLowerCase();
    final paths = <String, String>{};
    for (final layer in _layers) {
      for (final key in layer.indexedPaths) {
        if (suffix != null && !key.endsWith(suffix)) continue;
        paths.putIfAbsent(key, () => key);
      }
    }
    return paths.values.toList();
  }

  void close() {
    for (final layer in _layers) {
      layer.close();
    }
    _layers.clear();
  }

  static Uint8List? _read(VfsEntry entry) {
    final file = entry.file;
    if (file != null) {
      return file.existsSync() ? file.readAsBytesSync() : null;
    }
    final archive = entry.archive;
    final entryPath = entry.entryPath;
    if (archive == null || entryPath == null || entry.size <= 0) return null;
    final buffer = malloc.allocate<Uint8>(entry.size);
    try {
      final read = PfsVfsLayer._bridge.read(
        archive,
        entryPath,
        0,
        buffer,
        entry.size,
      );
      if (read <= 0) return null;
      return Uint8List.fromList(buffer.asTypedList(read));
    } finally {
      malloc.free(buffer);
    }
  }

  /// 把任意脚本路径归一化成 `a/b/c`；含 `..` 或盘符的路径视为非法。
  static String? normalizeRelativePath(String path) {
    final parts = <String>[];
    for (final raw in path.trim().replaceAll('\\', '/').split('/')) {
      final part = raw.trim();
      if (part.isEmpty || part == '.') continue;
      if (part == '..' || part.contains(':')) return null;
      parts.add(part);
    }
    return parts.isEmpty ? null : parts.join('/');
  }
}

String? _normalizeKey(String path) =>
    ProjectVfs.normalizeRelativePath(path)?.toLowerCase();
