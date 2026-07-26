import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/dialogs.dart';
import '../adaptive/feedback.dart';
import '../models/game_entry.dart';
import '../providers/library_provider.dart';
import '../screens/player_screen.dart';
import '../services/game_importer.dart';
import '../services/logger.dart';

/// 资料库的全部业务流程，三个壳共用；壳只负责入口控件的平台样式。
class LibraryActions {
  final BuildContext context;
  final WidgetRef ref;

  const LibraryActions(this.context, this.ref);

  // ── 添加入口 ──────────────────────────────────────────────

  Future<void> pickDirectory() async {
    final path = await getDirectoryPath(confirmButtonText: '选择此目录');
    if (path == null || !context.mounted) return;

    if (!File('$path${Platform.pathSeparator}system.ini').existsSync()) {
      notify(context, '所选目录中没有 system.ini');
      return;
    }

    final name = path.split(Platform.pathSeparator).last;
    await _editAndAdd(name, path, GameSource.directory);
  }

  Future<void> pickPfs() async {
    String? filePath;
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动平台：通过原生 SAF 选目录，拷贝整个目录（含分卷）到沙箱。
      // 避免 file_selector 在 Android 上返回无法用 dart:io 访问的 content URI。
      if (Platform.isAndroid) {
        final sandboxDir = await GameImporter.pickDirectoryAndCopy();
        if (sandboxDir == null || !context.mounted) return;
        // 在沙箱里找 base .pfs 文件。
        final pfsFile = Directory(sandboxDir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pfs'))
            .where(
              (f) => !RegExp(
                r'\.pfs\.\d{3}$',
                caseSensitive: false,
              ).hasMatch(f.path),
            )
            .firstOrNull;
        if (pfsFile == null) {
          if (context.mounted) notify(context, '所选目录中没有 .pfs 文件');
          return;
        }
        filePath = pfsFile.path;
      } else {
        filePath = await GameImporter.pickPfsFilesAndCopy();
        if (filePath == null) {
          if (context.mounted) notify(context, '请选择 base .pfs 和所有 .pfs.NNN 分卷');
          return;
        }
      }
    } else {
      const typeGroup = XTypeGroup(label: 'PFS 归档', extensions: ['pfs', 'PFS']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      filePath = file?.path;
    }
    if (filePath == null || !context.mounted) return;

    final name = filePath
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');

    await _editAndAdd(name, filePath, GameSource.pfsArchive);
  }

  Future<void> openIosAppFolderManager() async {
    final action = await GameImporter.showIosLibraryManager();
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'scan':
        await scanIosAppFolder();
        break;
      case 'pickPfs':
        await pickPfs();
        break;
    }
  }

  Future<void> scanIosAppFolder() async {
    await GameImporter.prepareIosAppFolders();
    final games = await GameImporter.scanIosAppGamesFolder();
    if (!context.mounted) return;

    if (games.isEmpty) {
      notify(context, '未发现游戏。请在 Files app 中把游戏放入 Art3m1s/Games');
      return;
    }

    if (games.length == 1) {
      await _addDiscoveredGame(games.single);
      return;
    }

    final selected = await showCupertinoModalPopup<DiscoveredGame>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择项目'),
        actions: [
          for (final game in games)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(game),
              child: Text(game.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );

    if (selected != null && context.mounted) {
      await _addDiscoveredGame(selected);
    }
  }

  Future<void> _addDiscoveredGame(DiscoveredGame game) {
    return _editAndAdd(
      game.name,
      game.path,
      game.isPfsArchive ? GameSource.pfsArchive : GameSource.directory,
    );
  }

  Future<void> _editAndAdd(
    String defaultName,
    String path,
    GameSource source,
  ) async {
    final result = await showGameEditDialog(
      context,
      title: '添加项目',
      initialName: defaultName,
    );
    if (result == null || !context.mounted) return;

    await ref.read(libraryProvider.notifier).add(
          GameEntry(
            name: defaultName,
            path: path,
            source: source,
            addedAt: DateTime.now(),
            displayName: result.name.isNotEmpty ? result.name : null,
            coverPath: result.coverPath,
          ),
        );
    Log.info('已添加: ${result.name.isNotEmpty ? result.name : defaultName}');
  }

  // ── 条目操作 ──────────────────────────────────────────────

  Future<void> editGame(GameEntry entry) async {
    final result = await showGameEditDialog(
      context,
      title: '编辑项目',
      initialName: entry.displayNameOrName,
      initialCoverPath: entry.coverPath,
    );
    if (result == null || !context.mounted) return;

    await ref.read(libraryProvider.notifier).update(
          entry.path,
          displayName: result.name.isNotEmpty ? result.name : null,
          coverPath: result.coverPath,
        );
  }

  Future<void> confirmDelete(GameEntry entry) async {
    final confirmed = await showAdaptiveConfirm(
      context,
      title: '移除项目',
      message: '确定从库中移除「${entry.displayNameOrName}」吗？',
      confirmLabel: '移除',
      destructive: true,
    );
    if (confirmed && context.mounted) {
      await ref.read(libraryProvider.notifier).remove(entry.path);
    }
  }

  void launch(GameEntry entry) {
    ref.read(libraryProvider.notifier).markPlayed(entry.path);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => wrapPlayerRoute(
          PlayerScreen(projectPath: entry.path, source: entry.source),
        ),
      ),
    );
  }
}

/// 玩家页面是 Material 组件树（Scaffold/SnackBar/对话框）。
/// 在 MacosApp / CupertinoApp / FluentApp 壳下推入时需自带
/// Theme + ScaffoldMessenger（Material 壳自身已提供）。
Widget wrapPlayerRoute(Widget player) {
  if (!Platform.isMacOS && !Platform.isIOS && !Platform.isWindows) {
    return player;
  }
  return Theme(
    data: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    child: ScaffoldMessenger(child: player),
  );
}
