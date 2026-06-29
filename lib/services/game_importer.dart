import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

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

  /// Android 专用：调原生 SAF 目录选择器，把整个目录拷贝到沙箱，
  /// 返回沙箱目录路径（`<filesDir>/games/incoming/<timestamp>/`）。
  /// 该目录下包含所有原始文件（含 .pfs 和 .pfs.NNN 分卷）。
  static Future<String?> pickDirectoryAndCopy() async {
    if (!Platform.isAndroid) return null;
    try {
      const channel = MethodChannel('moe.alphaly.art3m1s/native_ptrs');
      return await channel.invokeMethod<String>('pickDirectoryAndCopy');
    } on PlatformException catch (e) {
      if (e.code == 'PICK_CANCELLED') return null;
      Log.error('[GameImporter] pickDirectoryAndCopy 失败: ${e.message}');
      return null;
    }
  }

  /// iOS 专用：原生 UIDocumentPicker + security-scoped URL，把用户选中的
  /// base `.pfs` 和 `.pfs.NNN` 分卷直接复制进 app sandbox。
  static Future<String?> pickPfsFilesAndCopy() async {
    if (!Platform.isIOS) return null;
    try {
      const channel = MethodChannel('moe.alphaly.art3m1s/native_ptrs');
      return await channel.invokeMethod<String>('pickPfsFilesAndCopy');
    } on PlatformException catch (e) {
      if (e.code == 'PICK_CANCELLED') return null;
      Log.error('[GameImporter] pickPfsFilesAndCopy 失败: ${e.message}');
      return null;
    }
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

  /// 删除沙箱里的游戏副本（从库中移除项目时调用）。
  static Future<void> removeFromSandbox(String originalPath) async {
    final appSupport = await getApplicationSupportDirectory();
    final gamesDir = Directory(
      '${appSupport.path}${Platform.pathSeparator}games',
    );
    if (!gamesDir.existsSync()) return;

    final isFile = _isFileLikePath(originalPath);
    final gameId = _computeGameId(originalPath, isFile);
    final targetDir = Directory(
      '${gamesDir.path}${Platform.pathSeparator}$gameId',
    );
    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
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
}
