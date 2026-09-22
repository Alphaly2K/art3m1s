import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/game_engine.dart';
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

/// 统一的游戏导入:全平台均为「选择目录 → 探测 → 原地入库」,不再复制。
///
/// - 桌面 / iOS:文件系统直接可访问,选目录或扫描 App 文件夹后原地登记。
/// - Android:引导用户授予「所有文件访问」(`MANAGE_EXTERNAL_STORAGE`,
///   API < 30 用 `READ_EXTERNAL_STORAGE`),SAF 选目录后由原生层解析为真实
///   路径,core 经 POSIX 路径直读。不复制、不产生沙箱副本。
///
/// 早期 Android 版本的 SAF 整树复制机制(`.import-incomplete` 批次标记、
/// 拷贝进度、入库即复制)已退役;沙箱内遗留拷贝继续可用,仅保留其删除
/// 逻辑(`deleteManagedImport` 的托管根白名单)。
class GameImporter {
  GameImporter._();

  static const MethodChannel _nativeChannel = MethodChannel(
    'moe.alphaly.art3m1s/native_ptrs',
  );

  /// Android:是否已经拥有读取任意目录所需的存储访问权限。
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _nativeChannel.invokeMethod<bool>('hasAllFilesAccess') ??
          false;
    } on PlatformException catch (e) {
      Log.warn('[GameImporter] hasAllFilesAccess 查询失败: ${e.message}');
      return false;
    }
  }

  /// Android:跳转到系统设置页引导用户授予「所有文件访问」。
  static Future<void> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod<void>('requestAllFilesAccess');
    } on PlatformException catch (e) {
      Log.error('[GameImporter] requestAllFilesAccess 失败: ${e.message}');
    }
  }

  /// Android:调原生目录选择器(SAF),返回所选目录的真实文件系统路径。
  ///
  /// 返回 null 表示用户取消。权限未授予时抛 [GameImportException]
  /// (`needsAllFilesAccess`),由调用方引导授权;URI 无法解析为真实路径时
  /// 抛 `unresolved`,由调用方降级为手动路径输入。
  static Future<String?> pickGameDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
        'pickGameDirectory',
      );
      final status = result?['status'] as String? ?? 'unresolved';
      switch (status) {
        case 'ok':
          final path = result?['path'] as String? ?? '';
          if (path.isEmpty) {
            throw const GameImportException('unresolved');
          }
          return path;
        case 'needsAllFilesAccess':
          throw const GameImportException('needsAllFilesAccess');
        default:
          throw const GameImportException('unresolved');
      }
    } on PlatformException catch (e) {
      if (e.code == 'PICK_CANCELLED') return null;
      Log.error('[GameImporter] pickGameDirectory 失败: ${e.message}');
      throw GameImportException(e.message ?? e.code);
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
  /// `.pfs.NNN` 只是分卷,不会单独成为游戏。返回值按完整路径自然排序,因此同一
  /// 文件夹有多个游戏时,资料库导入顺序稳定且每个条目都绑定具体 PFS 文件。
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

  /// 递归查找已解包工程根目录。
  ///
  /// Artemis 工程以 system.ini 为根标记,RFVP 工程以根目录中的 `.hcb`
  /// 为标记,Siglus 工程以 Scene.pck + Gameexe.dat/ini 为标记；KRKR
  /// 接受 data.xp3、startup.tjs 或根级 XP3；多归档由宿主选择入口。
  /// 某个目录一旦命中标记,就把它当作工程根,不再继续往下找,
  /// 避免把工程内部的资源子目录误当成独立游戏。
  static List<String> discoverUnpackedProjects(String directoryPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) return const [];
    final found = <String>[];
    void visit(Directory dir) {
      var hasSystemIni = false;
      var hasHcb = false;
      var hasDataXp3 = false;
      var hasStartupTjs = false;
      var hasScenePck = false;
      var hasGameexe = false;
      var rootXp3Count = 0;
      final subdirs = <Directory>[];
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is File && _isSystemIniName(_basename(entity.path))) {
            hasSystemIni = true;
          } else if (entity is File && _isHcbName(_basename(entity.path))) {
            hasHcb = true;
          } else if (entity is File && _isDataXp3Name(_basename(entity.path))) {
            hasDataXp3 = true;
          } else if (entity is File &&
              _isStartupTjsName(_basename(entity.path))) {
            hasStartupTjs = true;
          } else if (entity is File && _isXp3Name(_basename(entity.path))) {
            rootXp3Count += 1;
          } else if (entity is File &&
              _isScenePckName(_basename(entity.path))) {
            hasScenePck = true;
          } else if (entity is File && _isGameexeName(_basename(entity.path))) {
            hasGameexe = true;
          } else if (entity is Directory) {
            subdirs.add(entity);
          }
        }
      } on FileSystemException {
        return;
      }
      if (hasSystemIni ||
          hasHcb ||
          hasDataXp3 ||
          hasStartupTjs ||
          (hasScenePck && hasGameexe) ||
          rootXp3Count > 0) {
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

  /// 统一探测入口:返回文件夹中的全部游戏——解包工程目录(system.ini、
  /// `.hcb`、Siglus Scene.pck/Gameexe 或 KRKR XP3/TJS 标记)
  /// 与打包成 PFS 归档的 Artemis 游戏。
  ///
  /// 位于已识别工程目录内部的 `.pfs` 是该工程的资源包,不会被重复登记为
  /// 独立游戏。
  static ({List<String> projects, List<String> pfsArchives}) probeGameFolder(
    String directoryPath,
  ) {
    final projects = discoverUnpackedProjects(directoryPath);
    final pfsArchives = discoverBasePfsFiles(directoryPath)
        .where(
          (file) => !projects.any(
            (project) =>
                isSameLibraryPath(project, file) ||
                normalizeLibraryPath(
                  file,
                ).startsWith('${normalizeLibraryPath(project)}/'),
          ),
        )
        .toList();
    return (projects: projects, pfsArchives: pfsArchives);
  }

  /// 识别已解包目录的引擎。为保持旧资料库行为，优先级固定为
  /// Artemis system.ini > RFVP HCB > Siglus Scene.pck/Gameexe > KRKR XP3/TJS。
  static GameEngineKind detectDirectoryEngine(String directoryPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) return GameEngineKind.art3m1s;
    var hasSystemIni = false;
    var hasHcb = false;
    var hasDataXp3 = false;
    var hasStartupTjs = false;
    var hasScenePck = false;
    var hasGameexe = false;
    var rootXp3Count = 0;
    try {
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = _basename(entity.path);
        if (_isSystemIniName(name)) {
          hasSystemIni = true;
        } else if (_isHcbName(name)) {
          hasHcb = true;
        } else if (_isDataXp3Name(name)) {
          hasDataXp3 = true;
        } else if (_isStartupTjsName(name)) {
          hasStartupTjs = true;
        } else if (_isXp3Name(name)) {
          rootXp3Count += 1;
        } else if (_isScenePckName(name)) {
          hasScenePck = true;
        } else if (_isGameexeName(name)) {
          hasGameexe = true;
        }
      }
    } on FileSystemException {
      return GameEngineKind.art3m1s;
    }
    if (hasSystemIni) return GameEngineKind.art3m1s;
    if (hasHcb) return GameEngineKind.rfvp;
    if (hasScenePck && hasGameexe) return GameEngineKind.siglus;
    if (hasDataXp3 || hasStartupTjs || rootXp3Count > 0) {
      return GameEngineKind.krkr;
    }
    return GameEngineKind.art3m1s;
  }

  /// 资料库路径比较:去掉尾部分隔符,并把 iOS 的 `/private/var` 折成 `/var`。
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

  /// SAF 导入批次遗留目录:`<games>/incoming/<timestamp>/`。
  static Directory? findManagedIncomingBatch(
    String path,
    Iterable<String> roots,
  ) {
    final normalized = normalizeLibraryPath(path);
    for (final root in roots) {
      final prefix = '${normalizeLibraryPath(root)}/incoming/';
      if (!normalized.startsWith(prefix)) continue;
      final rest = normalized.substring(prefix.length);
      if (rest.isEmpty) return null;
      final batchId = rest.split('/').first;
      if (batchId.isEmpty || batchId == '.' || batchId == '..') continue;
      return Directory('$prefix$batchId');
    }
    return null;
  }

  static bool _isUnderNormalized(String path, String parent) {
    return path == parent || path.startsWith('$parent/');
  }

  static bool _batchHasRetainedGames(
    Directory batch,
    String deletingPath,
    Iterable<String> retainedPaths,
  ) {
    final batchPath = normalizeLibraryPath(batch.path);
    final deleting = normalizeLibraryPath(deletingPath);
    return retainedPaths.any((item) {
      final normalized = normalizeLibraryPath(item);
      if (normalized == deleting) return false;
      return _isUnderNormalized(normalized, batchPath);
    });
  }

  /// 删除遗留的 Android 沙箱导入副本;原位导入的用户目录绝不删除。
  static Future<void> removeImportedGameFiles(
    String path, {
    Iterable<String> retainedPaths = const [],
  }) async {
    if (!Platform.isAndroid) return;
    final roots = await _androidManagedGameRoots();
    deleteManagedImport(path, roots, retainedPaths: retainedPaths);
  }

  static Future<List<String>> _androidManagedGameRoots() async {
    final roots = <String>{};
    final support = await getApplicationSupportDirectory();
    roots.add('${support.path}${Platform.pathSeparator}games');
    final documents = await getApplicationDocumentsDirectory();
    roots.add('${documents.path}${Platform.pathSeparator}games');
    return roots.map(normalizeLibraryPath).toList(growable: false);
  }

  /// 删除位于托管根目录下的遗留导入路径。
  ///
  /// SAF 一次导入对应 `incoming/<timestamp>/` 整个批次。资料库里该批次
  /// 没有其他条目时,删除整个导入目录,而不是只删 `.pfs`。同一批次还有
  /// 其他资料库条目时,只删当前游戏自己的文件。
  static void deleteManagedImport(
    String path,
    Iterable<String> roots, {
    Iterable<String> retainedPaths = const [],
  }) {
    if (!isManagedImportPath(path, roots)) return;
    final batch = findManagedIncomingBatch(path, roots);
    if (batch != null && !_batchHasRetainedGames(batch, path, retainedPaths)) {
      if (batch.existsSync()) batch.deleteSync(recursive: true);
      _pruneEmptyParents(batch.path, roots);
      return;
    }
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

  /// 跨平台 basename(避免 `package:path` 依赖)。
  static String _basename(String path) {
    // 同时处理 / 和 \(兼容不同来源的路径)
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

  static bool _isHcbName(String name) {
    return name.toLowerCase().endsWith('.hcb');
  }

  static bool _isDataXp3Name(String name) => name.toLowerCase() == 'data.xp3';

  static bool _isStartupTjsName(String name) =>
      name.toLowerCase() == 'startup.tjs';

  static bool _isXp3Name(String name) => name.toLowerCase().endsWith('.xp3');

  static bool _isScenePckName(String name) => name.toLowerCase() == 'scene.pck';

  static bool _isGameexeName(String name) =>
      name.toLowerCase() == 'gameexe.dat' ||
      name.toLowerCase() == 'gameexe.ini';
}
