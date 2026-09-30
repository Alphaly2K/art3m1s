import 'dart:typed_data';

import 'project_vfs.dart';

/// Per-runtime media/asset reader that outlives `FileProvider.detachCoreMount`.
///
/// Resident multi-game sessions drop the process-global FileProvider index on
/// purpose. Media still needs to read the current project's directory or its
/// standalone PFS patch volumes, including UTF-8 names inside a Shift_JIS game.
///
/// 与 FileProvider 共用同一套 VFS 优先级（解包目录 > 大 id 分卷 > 小 id 分卷），
/// 常驻会话切换后媒体读取与引擎读取不会分叉。
class ProjectAssetStore {
  ProjectAssetStore();

  ProjectVfs? _vfs;

  void close() {
    _vfs?.close();
    _vfs = null;
  }

  /// 打开工程资源视图。解包目录用逐路径探测，避免为媒体建整棵索引。
  void openProject(
    String path, {
    required bool isArchive,
    String charset = 'Shift_JIS',
  }) {
    close();
    _vfs = isArchive
        ? ProjectVfs.openArchive(path, charset: charset)
        : ProjectVfs.openDirectory(
            path,
            charset: charset,
            indexDirectory: false,
          );
  }

  void openDirectory(String root) => openProject(root, isArchive: false);

  void openArchives(String archivePath, {String charset = 'UTF-8'}) =>
      openProject(archivePath, isArchive: true, charset: charset);

  Uint8List? read(String path) => _vfs?.readFile(path);
}
