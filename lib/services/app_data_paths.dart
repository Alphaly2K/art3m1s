import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 统一管理应用产生的数据目录。
///
/// 存档、翻译缓存和封面都从同一个根目录派生，避免各模块分别调用
/// path_provider 或手写平台路径后落入不同位置。
class AppDataPaths {
  AppDataPaths._();

  static Future<Directory>? _initialization;

  static Future<Directory> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  static Future<Directory> savesDirectory() async {
    final root = await ensureInitialized();
    return _ensureChild(root, Platform.isIOS ? 'Saves' : 'saves');
  }

  static Future<Directory> translationsDirectory() async {
    return _ensureChild(await ensureInitialized(), 'translations');
  }

  static Future<Directory> coversDirectory() async {
    return _ensureChild(await ensureInitialized(), 'covers');
  }

  /// 把用户选择的封面复制进统一目录；复制失败时保留原路径。
  static Future<String?> importCover(String? sourcePath, String gameId) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return sourcePath;
    final source = File(sourcePath);
    final covers = await coversDirectory();
    final safeId = _safeFileName(gameId);
    final extension = _imageExtension(source.path);
    final destination = File(
      '${covers.path}${Platform.pathSeparator}$safeId$extension',
    );

    if (_samePath(source.path, destination.path)) return destination.path;
    if (!await source.exists()) {
      return await _findManagedCover(covers, safeId) ?? sourcePath;
    }

    try {
      await source.copy(destination.path);
      return destination.path;
    } catch (_) {
      return sourcePath;
    }
  }

  static Future<Directory> _initialize() async {
    final root = await _resolveRoot();
    await root.create(recursive: true);
    await _migrateLegacyLayout(root);
    await savesDirectoryWithoutInitialization(root).create(recursive: true);
    await Directory(
      '${root.path}${Platform.pathSeparator}translations',
    ).create(recursive: true);
    await Directory(
      '${root.path}${Platform.pathSeparator}covers',
    ).create(recursive: true);
    return root;
  }

  static Future<Directory> _resolveRoot() async {
    if (Platform.isIOS) {
      final documents = await getApplicationDocumentsDirectory();
      return Directory('${documents.path}${Platform.pathSeparator}Art3m1s');
    }
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) return external;
    }
    return getApplicationSupportDirectory();
  }

  static Future<void> _migrateLegacyLayout(Directory root) async {
    final marker = File(
      '${root.path}${Platform.pathSeparator}.storage-layout-v2',
    );
    if (await marker.exists()) return;

    final sources = <Directory>[];
    try {
      sources.add(await getApplicationSupportDirectory());
    } catch (_) {}

    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null) {
      sources.add(Directory('$home/Library/Application Support/art3m1s'));
    } else if (Platform.isLinux && home != null) {
      sources.add(Directory('$home/.local/share/art3m1s'));
    } else if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'];
      if (appData != null) sources.add(Directory('$appData\\art3m1s'));
    }

    final saveName = Platform.isIOS ? 'Saves' : 'saves';
    for (final source in sources) {
      if (_samePath(source.path, root.path) || !await source.exists()) continue;
      await _mergeKnownDirectory(source, 'saves', root, saveName);
      await _mergeKnownDirectory(source, 'Saves', root, saveName);
      await _mergeKnownDirectory(source, 'translations', root, 'translations');
      await _mergeKnownDirectory(source, 'covers', root, 'covers');
    }

    try {
      await marker.writeAsString('2\n', flush: true);
    } catch (_) {}
  }

  static Future<void> _mergeKnownDirectory(
    Directory sourceRoot,
    String sourceName,
    Directory destinationRoot,
    String destinationName,
  ) async {
    final source = Directory(
      '${sourceRoot.path}${Platform.pathSeparator}$sourceName',
    );
    if (!await source.exists()) return;
    final destination = Directory(
      '${destinationRoot.path}${Platform.pathSeparator}$destinationName',
    );
    await _copyDirectoryMissing(source, destination);
  }

  static Future<void> _copyDirectoryMissing(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = _basename(entity.path);
      final targetPath = '${destination.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        await _copyDirectoryMissing(entity, Directory(targetPath));
      } else if (entity is File) {
        await _copyFileIfMissing(entity, File(targetPath));
      }
    }
  }

  static Future<void> _copyFileIfMissing(File source, File destination) async {
    try {
      if (!await source.exists() || await destination.exists()) return;
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
    } catch (_) {}
  }

  static Directory savesDirectoryWithoutInitialization(Directory root) {
    return Directory(
      '${root.path}${Platform.pathSeparator}'
      '${Platform.isIOS ? 'Saves' : 'saves'}',
    );
  }

  static Future<Directory> _ensureChild(Directory root, String name) async {
    final directory = Directory('${root.path}${Platform.pathSeparator}$name');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<String?> _findManagedCover(
    Directory covers,
    String safeId,
  ) async {
    if (!await covers.exists()) return null;
    await for (final entity in covers.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      final dot = name.lastIndexOf('.');
      final stem = dot < 0 ? name : name.substring(0, dot);
      if (stem == safeId) return entity.path;
    }
    return null;
  }

  static String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  static String _imageExtension(String path) {
    final name = _basename(path);
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final extension = name.substring(dot).toLowerCase();
    const supported = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'};
    return supported.contains(extension) ? extension : '.jpg';
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  static bool _samePath(String left, String right) {
    String normalize(String value) {
      var normalized = value.replaceAll('\\', '/');
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return Platform.isWindows ? normalized.toLowerCase() : normalized;
    }

    return normalize(left) == normalize(right);
  }
}
