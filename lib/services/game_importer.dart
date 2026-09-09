import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

class GameImportException implements Exception {
  const GameImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DiscoveredGame {
  const DiscoveredGame({
    required this.name,
    required this.path,
    required this.source,
  });

  final String name;
  final String path;
  final String source;

  bool get isPfsArchive => source == 'pfsArchive';

  factory DiscoveredGame.fromMap(Map<dynamic, dynamic> map) => DiscoveredGame(
    name: map['name'] as String? ?? '',
    path: map['path'] as String? ?? '',
    source: map['source'] as String? ?? '',
  );
}

class GameImportProgress {
  const GameImportProgress({
    required this.filesCopied,
    required this.bytesCopied,
    this.currentName = '',
  });

  final int filesCopied;
  final int bytesCopied;
  final String currentName;

  factory GameImportProgress.fromMap(Map<dynamic, dynamic> map) {
    return GameImportProgress(
      filesCopied: (map['files'] as num?)?.toInt() ?? 0,
      bytesCopied: (map['bytes'] as num?)?.toInt() ?? 0,
      currentName: map['current']?.toString() ?? '',
    );
  }

  String get message {
    final size = _formatBytes(bytesCopied);
    final copied = '已复制 $filesCopied 个文件 · $size';
    return currentName.isEmpty ? copied : '$copied\n$currentName';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 游戏数据沙箱导入。
///
/// Android/iOS 对文件系统有严格限制：
/// - Android：native 代码无法稳定访问外部存储（Scoped Storage / SAF）
/// - iOS：沙箱外的路径在下次启动后可能失效
///
/// 解决方案：把游戏目录 / PFS 分卷整组复制到应用沙箱内，
/// native 代码直接通过 `File::open` 读取。
class GameImporter {
  GameImporter._();

  /// 桌面平台不需要沙箱导入（native 可直接访问文件系统）。
  static bool get needsSandbox => Platform.isAndroid || Platform.isIOS;

  static const MethodChannel _nativeChannel = MethodChannel(
    'moe.alphaly.art3m1s/native_ptrs',
  );
  static final StreamController<GameImportProgress> _progress =
      StreamController<GameImportProgress>.broadcast();
  static bool _nativeHandlerInstalled = false;

  static void _ensureNativeHandler() {
    if (_nativeHandlerInstalled) return;
    _nativeHandlerInstalled = true;
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'importProgress' && call.arguments is Map) {
        _progress.add(
          GameImportProgress.fromMap(call.arguments as Map<dynamic, dynamic>),
        );
      }
    });
  }

  /// Android 专用：调原生 SAF 目录选择器，把整个目录拷贝到沙箱，
  /// 返回沙箱目录路径（`<filesDir>/games/incoming/<timestamp>/`）。
  /// 该目录下包含所有原始文件（含 .pfs 和 .pfs.NNN 分卷）。
  static Future<String?> pickDirectoryAndCopy({
    ValueChanged<GameImportProgress>? onProgress,
  }) async {
    if (!Platform.isAndroid) return null;
    _ensureNativeHandler();
    final subscription = onProgress == null
        ? null
        : _progress.stream.listen(onProgress);
    try {
      return await _nativeChannel.invokeMethod<String>('pickDirectoryAndCopy');
    } on PlatformException catch (e) {
      if (e.code == 'PICK_CANCELLED') return null;
      Log.error('[GameImporter] pickDirectoryAndCopy 失败: ${e.message}');
      throw GameImportException(e.message ?? e.code);
    } finally {
      await subscription?.cancel();
    }
  }

  /// iOS 专用：原生 UIDocumentPicker + security-scoped URL，把用户选中的
  /// base `.pfs` 和各自的 `.pfs.NNN` 分卷按游戏分组复制进 app sandbox。
  ///
  /// 新版原生端返回路径数组；这里仍接受旧版的单个字符串，允许 Dart 与原生壳
  /// 在升级期间短暂错配。
  static Future<List<String>?> pickPfsFilesAndCopy() async {
    if (!Platform.isIOS) return null;
    try {
      final raw = await _nativeChannel.invokeMethod<dynamic>(
        'pickPfsFilesAndCopy',
      );
      if (raw is String) {
        return raw.isEmpty ? const [] : [raw];
      }
      if (raw is List) {
        return raw
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
      }
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'PICK_CANCELLED') return null;
      Log.error('[GameImporter] pickPfsFilesAndCopy 失败: ${e.message}');
      return null;
    }
  }

  /// iOS 专用：打开一个原生管理面板。
  ///
  /// 返回值：
  /// - `scan`: 扫描 Files app 可见的 Art3m1s/Games
  /// - `pickPfs`: 打开系统 PFS 文件选择器
  /// - null: 用户关闭
  static Future<String?> showIosLibraryManager() async {
    if (!Platform.isIOS) return null;
    try {
      return await _nativeChannel.invokeMethod<String>('showIosLibraryManager');
    } on PlatformException catch (e) {
      Log.error('[GameImporter] showIosLibraryManager 失败: ${e.message}');
      return null;
    }
  }

  static Future<String?> prepareIosAppFolders() async {
    if (!Platform.isIOS) return null;
    try {
      return await _nativeChannel.invokeMethod<String>('prepareIosAppFolders');
    } on PlatformException catch (e) {
      Log.error('[GameImporter] prepareIosAppFolders 失败: ${e.message}');
      return null;
    }
  }

  static Future<List<DiscoveredGame>> scanIosAppGamesFolder() async {
    if (!Platform.isIOS) return const [];
    try {
      final raw = await _nativeChannel.invokeMethod<List<dynamic>>(
        'scanIosAppGamesFolder',
      );
      return (raw ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(DiscoveredGame.fromMap)
          .where((game) => game.path.isNotEmpty)
          .toList();
    } on PlatformException catch (e) {
      Log.error('[GameImporter] scanIosAppGamesFolder 失败: ${e.message}');
      return const [];
    }
  }

  /// 递归枚举目录中的 base `.pfs` 文件。
  ///
  /// `.pfs.NNN` 只是分卷，不会单独成为游戏。返回值按完整路径自然排序，因此同一
  /// 文件夹有多个游戏时，资料库导入顺序稳定且每个条目都绑定具体 PFS 文件。
  static List<String> discoverBasePfsFiles(String directoryPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) return const [];
    final paths = directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) => file.path)
        .where(_isBasePfsPath)
        .toList();
    paths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return paths;
  }

  /// 递归查找含 `system.ini` 的已解包工程根目录。
  ///
  /// 某个目录一旦含有 system.ini，就把它当作工程根，不再继续往下找，
  /// 避免把工程内部的资源子目录误当成独立游戏。
  static List<String> discoverUnpackedProjects(String directoryPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) return const [];
    final found = <String>[];
    void visit(Directory dir) {
      FileSystemEntity? ini;
      final subdirs = <Directory>[];
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is File && _isSystemIniName(_basename(entity.path))) {
            ini = entity;
          } else if (entity is Directory) {
            subdirs.add(entity);
          }
        }
      } on FileSystemException {
        return;
      }
      if (ini != null) {
        found.add(dir.path);
        return;
      }
      for (final subdir in subdirs) {
        visit(subdir);
      }
    }

    visit(directory);
    found.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return found;
  }

  /// 把 `sourcePath` 对应的游戏数据复制到沙箱。
  ///
  /// - `sourcePath` 是 `.pfs` 文件（自动连带 `.pfs.NNN` 分卷）或目录。
  /// - 返回沙箱内的目标路径（目录或 base .pfs 文件）。
  /// - 如果已导入过（同名 + 同大小），直接返回已有路径，不重复复制。
  static Future<String> importToSandbox(String sourcePath) async {
    final appSupport = await getApplicationSupportDirectory();
    final gamesPrefix =
        '${appSupport.path}${Platform.pathSeparator}games${Platform.pathSeparator}';

    // 已在沙箱内（例如刚通过 pickDirectoryAndCopy 拷贝的）→ 直接返回。
    if (sourcePath.startsWith(gamesPrefix)) {
      return sourcePath;
    }
    if (Platform.isIOS && await _isInIosVisibleGamesFolder(sourcePath)) {
      return sourcePath;
    }

    final gamesDir = Directory(
      '${appSupport.path}${Platform.pathSeparator}games',
    );
    if (!gamesDir.existsSync()) gamesDir.createSync(recursive: true);

    final isFile = _isFileLikePath(sourcePath);
    final gameId = _computeGameId(sourcePath, isFile);
    final targetDir = Directory(
      '${gamesDir.path}${Platform.pathSeparator}$gameId',
    );

    // 已导入且大小一致 → 直接复用。
    if (targetDir.existsSync() && _isComplete(sourcePath, isFile, targetDir)) {
      return _resolvePath(sourcePath, isFile, targetDir);
    }

    // 否则清理旧副本后重新复制。
    if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
    targetDir.createSync(recursive: true);

    if (isFile) {
      await _copyPfsWithVolumes(File(sourcePath), targetDir);
    } else {
      await _copyDirectory(Directory(sourcePath), targetDir);
    }

    return _resolvePath(sourcePath, isFile, targetDir);
  }

  /// 资料库路径比较：去掉尾部分隔符，并把 iOS 的 `/private/var` 折成 `/var`。
  static String normalizeLibraryPath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.startsWith('/private/var/') ||
        normalized.startsWith('/private/tmp/')) {
      normalized = normalized.substring('/private'.length);
    }
    return normalized;
  }

  static bool isSameLibraryPath(String a, String b) =>
      normalizeLibraryPath(a) == normalizeLibraryPath(b);

  static bool libraryContainsPath(Iterable<String> existing, String path) {
    return existing.any((item) => isSameLibraryPath(item, path));
  }

  static bool isManagedImportPath(String path, Iterable<String> roots) {
    final normalized = normalizeLibraryPath(path);
    if (normalized.isEmpty) return false;
    for (final root in roots) {
      final prefix = normalizeLibraryPath(root);
      if (prefix.isEmpty) continue;
      if (normalized == prefix) return false;
      if (normalized.startsWith('$prefix/')) return true;
    }
    return false;
  }

  /// 删除 Android 导入到应用存储的游戏文件。iOS 的 Files 可见目录不删。
  static Future<void> removeImportedGameFiles(String path) async {
    if (!Platform.isAndroid) return;
    final roots = await _androidManagedGameRoots();
    try {
      if (File(path).existsSync() || Directory(path).existsSync()) {
        final appSupport = await getApplicationSupportDirectory();
        final gameId = _computeGameId(path, _isFileLikePath(path));
        final legacy = Directory(
          '${appSupport.path}${Platform.pathSeparator}games${Platform.pathSeparator}$gameId',
        );
        if (legacy.existsSync() &&
            !isSameLibraryPath(legacy.path, path) &&
            isManagedImportPath(legacy.path, roots)) {
          legacy.deleteSync(recursive: true);
        }
      }
    } catch (e) {
      Log.warn('[GameImporter] 遗留沙箱副本清理失败: $e');
    }
    deleteManagedImport(path, roots);
  }

  /// 兼容旧调用：仅 Android 会删除导入副本。
  static Future<void> removeFromSandbox(String originalPath) {
    return removeImportedGameFiles(originalPath);
  }

  static Future<List<String>> _androidManagedGameRoots() async {
    final roots = <String>{};
    final support = await getApplicationSupportDirectory();
    roots.add('${support.path}${Platform.pathSeparator}games');
    final documents = await getApplicationDocumentsDirectory();
    roots.add('${documents.path}${Platform.pathSeparator}games');
    return roots.map(normalizeLibraryPath).toList(growable: false);
  }

  /// 删除位于托管根目录下的导入路径，并收掉空的 timestamp 父目录。
  static void deleteManagedImport(String path, Iterable<String> roots) {
    if (!isManagedImportPath(path, roots)) return;
    final directory = Directory(path);
    final file = File(path);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    } else if (file.existsSync()) {
      _deleteImportedFile(file);
    }
    _pruneEmptyParents(path, roots);
  }

  static void _deleteImportedFile(File base) {
    final parent = base.parent;
    final name = _basename(base.path);
    if (_isBasePfsName(name) && parent.existsSync()) {
      final baseNameNoExt = name.replaceAll(
        RegExp(r'\.pfs$', caseSensitive: false),
        '',
      );
      final volumePattern = RegExp(
        '^${RegExp.escape(baseNameNoExt)}\\.pfs\\.\\d{3}\$',
        caseSensitive: false,
      );
      for (final vol in parent.listSync().whereType<File>()) {
        if (volumePattern.hasMatch(_basename(vol.path))) {
          vol.deleteSync();
        }
      }
    }
    if (base.existsSync()) base.deleteSync();
  }

  static void _pruneEmptyParents(String path, Iterable<String> roots) {
    final rootSet = roots.map(normalizeLibraryPath).toSet();
    var current = Directory(normalizeLibraryPath(path));
    if (!current.existsSync()) current = current.parent;
    while (true) {
      final normalized = normalizeLibraryPath(current.path);
      if (rootSet.contains(normalized)) return;
      if (!rootSet.any((root) => normalized.startsWith('$root/'))) return;
      if (!current.existsSync()) {
        current = current.parent;
        continue;
      }
      if (current.listSync(followLinks: false).isNotEmpty) return;
      current.deleteSync();
      current = current.parent;
    }
  }

  /// 用文件名 + 大小生成稳定 ID（FNV-1a 64-bit）。
  static String _computeGameId(String path, bool isFile) {
    final name = _basename(
      path,
    ).replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');
    int size;
    if (isFile) {
      size = File(path).lengthSync();
    } else if (Directory(path).existsSync()) {
      size = Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .fold<int>(0, (sum, f) => sum + f.lengthSync());
    } else {
      throw FileSystemException('路径既不是文件也不是目录', path);
    }
    return _computeGameIdFromNameAndSize(name, size);
  }

  /// 复制 PFS 文件 + 所有分卷 (.pfs.000, .pfs.001, ...)。
  static Future<void> _copyPfsWithVolumes(
    File basePfs,
    Directory target,
  ) async {
    final parent = basePfs.parent;
    final baseNameNoExt = _basename(
      basePfs.path,
    ).replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');

    // 1) 复制 base .pfs
    final dest = File(
      '${target.path}${Platform.pathSeparator}${_basename(basePfs.path)}',
    );
    await _copyFile(basePfs, dest);

    // 2) 扫父目录，找同名 .pfs.NNN 分卷。
    if (parent.existsSync()) {
      final volumePattern = RegExp(
        '^${RegExp.escape(baseNameNoExt)}\\.pfs\\.\\d{3}\$',
        caseSensitive: false,
      );
      final volumes =
          parent
              .listSync()
              .whereType<File>()
              .where((f) => volumePattern.hasMatch(_basename(f.path)))
              .toList()
            ..sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));

      for (final vol in volumes) {
        final vDest = File(
          '${target.path}${Platform.pathSeparator}${_basename(vol.path)}',
        );
        await _copyFile(vol, vDest);
      }
    }
  }

  /// 递归复制目录。
  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    if (!dst.existsSync()) dst.createSync(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = _basename(entity.path);
      if (entity is File) {
        await _copyFile(
          entity,
          File('${dst.path}${Platform.pathSeparator}$name'),
        );
      } else if (entity is Directory) {
        await _copyDirectory(
          entity,
          Directory('${dst.path}${Platform.pathSeparator}$name'),
        );
      }
    }
  }

  static Future<void> _copyFile(File src, File dst) async {
    await src.copy(dst.path);
  }

  /// 检查沙箱副本是否完整。
  static bool _isComplete(
    String sourcePath,
    bool isFile,
    Directory sandboxDir,
  ) {
    if (isFile) {
      final source = File(sourcePath);
      final baseInSandbox = File(
        '${sandboxDir.path}${Platform.pathSeparator}${_basename(sourcePath)}',
      );
      if (!baseInSandbox.existsSync()) return false;
      if (baseInSandbox.lengthSync() != source.lengthSync()) return false;
      // 检查分卷。
      final parent = source.parent;
      if (!parent.existsSync()) return true;
      final baseNameNoExt = _basename(
        sourcePath,
      ).replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');
      final volumePattern = RegExp(
        '^${RegExp.escape(baseNameNoExt)}\\.pfs\\.\\d{3}\$',
        caseSensitive: false,
      );
      for (final vol in parent.listSync().whereType<File>().where(
        (f) => volumePattern.hasMatch(_basename(f.path)),
      )) {
        final vInSandbox = File(
          '${sandboxDir.path}${Platform.pathSeparator}${_basename(vol.path)}',
        );
        if (!vInSandbox.existsSync()) return false;
        if (vInSandbox.lengthSync() != vol.lengthSync()) return false;
      }
      return true;
    } else {
      final srcFiles = Directory(
        sourcePath,
      ).listSync(recursive: true).whereType<File>().length;
      final dstFiles = sandboxDir
          .listSync(recursive: true)
          .whereType<File>()
          .length;
      return srcFiles == dstFiles && dstFiles > 0;
    }
  }

  /// 解析最终路径：base .pfs 文件或目录。
  static String _resolvePath(
    String sourcePath,
    bool isFile,
    Directory sandboxDir,
  ) {
    if (isFile) {
      return '${sandboxDir.path}${Platform.pathSeparator}${_basename(sourcePath)}';
    }
    return sandboxDir.path;
  }

  /// 跨平台 basename（避免 `package:path` 依赖）。
  static String _basename(String path) {
    // 同时处理 / 和 \（兼容不同来源的路径）
    final idx = path.lastIndexOf(RegExp('[/\\\\]'));
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  static bool _isBasePfsPath(String path) {
    return _isBasePfsName(_basename(path));
  }

  static bool _isBasePfsName(String name) {
    name = name.toLowerCase();
    return name.endsWith('.pfs') && !RegExp(r'\.pfs\.\d{3}$').hasMatch(name);
  }

  static bool _isSystemIniName(String name) {
    return name.toLowerCase() == 'system.ini';
  }

  static bool _isFileLikePath(String path) {
    if (File(path).existsSync()) return true;
    return _isBasePfsPath(path);
  }

  static String _computeGameIdFromNameAndSize(String name, int size) {
    name = name.replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');
    int hash = 0xcbf29ce484222325;
    for (final code in '$name:$size'.codeUnits) {
      hash ^= code;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return '${name}_${hash.toRadixString(16)}';
  }

  static Future<bool> _isInIosVisibleGamesFolder(String sourcePath) async {
    final documents = await getApplicationDocumentsDirectory();
    final visibleGamesPrefix =
        '${documents.path}${Platform.pathSeparator}Art3m1s${Platform.pathSeparator}Games${Platform.pathSeparator}';
    return sourcePath.startsWith(visibleGamesPrefix);
  }
}
