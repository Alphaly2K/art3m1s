import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/dialogs.dart';
import '../adaptive/feedback.dart';
import '../models/game_entry.dart';
import '../navigation/player_page_route.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/core_bridge.dart';
import '../screens/player_screen.dart';
import '../services/app_data_paths.dart';
import '../services/game_importer.dart';
import '../services/logger.dart';
import '../services/vndb_service.dart';

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
    var filePaths = <String>[];
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动平台：通过原生选择器复制数据，再让每个 base PFS 独立成为项目。
      // 避免 file_selector 在 Android 上返回无法用 dart:io 访问的 content URI。
      if (Platform.isAndroid) {
        final sandboxDir = await GameImporter.pickDirectoryAndCopy();
        if (sandboxDir == null || !context.mounted) return;
        filePaths = GameImporter.discoverBasePfsFiles(sandboxDir);
      } else {
        final picked = await GameImporter.pickPfsFilesAndCopy();
        if (picked == null) {
          if (context.mounted) notify(context, '请选择 base .pfs 和所有 .pfs.NNN 分卷');
          return;
        }
        filePaths = picked;
      }
    } else {
      const typeGroup = XTypeGroup(label: 'PFS 归档', extensions: ['pfs', 'PFS']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) filePaths = [file.path];
    }
    if (!context.mounted) return;
    if (filePaths.isEmpty) {
      notify(context, '所选位置中没有 base .pfs 文件');
      return;
    }

    final games = filePaths
        .map(
          (path) => DiscoveredGame(
            name: _pfsDisplayName(path),
            path: path,
            source: GameSource.pfsArchive.name,
          ),
        )
        .toList(growable: false);

    if (games.length == 1) {
      await _addDiscoveredGame(games.single);
    } else {
      await _addDiscoveredGamesAutomatically(games);
    }
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

    await _addDiscoveredGamesAutomatically(games);
  }

  Future<void> _addDiscoveredGame(DiscoveredGame game) {
    return _editAndAdd(
      game.name,
      game.path,
      game.isPfsArchive ? GameSource.pfsArchive : GameSource.directory,
    );
  }

  Future<void> _addDiscoveredGamesAutomatically(
    List<DiscoveredGame> games,
  ) async {
    final existingPaths = ref
        .read(libraryProvider)
        .map((entry) => entry.path)
        .toSet();
    final pending = games
        .where((game) => !existingPaths.contains(game.path))
        .toList(growable: false);
    if (pending.isEmpty) {
      if (context.mounted) notify(context, '扫描到的游戏都已在资料库中');
      return;
    }

    var added = 0;
    for (var index = 0; index < pending.length; index++) {
      if (!context.mounted) return;
      final game = pending[index];
      notify(context, '正在添加 ${index + 1}/${pending.length}：${game.name}');
      if (await _addDiscoveredGameAutomatically(game)) added++;
    }
    if (context.mounted) {
      notify(context, '已添加 $added 个游戏');
    }
  }

  Future<bool> _addDiscoveredGameAutomatically(DiscoveredGame game) async {
    final source = game.isPfsArchive
        ? GameSource.pfsArchive
        : GameSource.directory;
    final gameId = _gameIdForPath(game.path);
    final metadata = await _resolveGameMetadata(
      game.name,
      game.path,
      source,
      gameId,
    );
    if (metadata == null || !context.mounted) return false;

    await ref
        .read(libraryProvider.notifier)
        .add(
          GameEntry(
            id: gameId,
            name: game.name,
            path: game.path,
            source: source,
            addedAt: DateTime.now(),
            displayName: metadata.name == game.name ? null : metadata.name,
            coverPath: metadata.coverPath,
          ),
        );
    Log.info('已自动添加: ${metadata.name}');
    return true;
  }

  Future<void> _editAndAdd(
    String defaultName,
    String path,
    GameSource source,
  ) async {
    final gameId = _gameIdForPath(path);
    notify(context, '正在获取游戏信息…');
    final metadata = await _resolveGameMetadata(
      defaultName,
      path,
      source,
      gameId,
    );
    if (metadata == null || !context.mounted) return;

    final result = await showGameEditDialog(
      context,
      title: '添加项目',
      initialName: metadata.name,
      initialCoverPath: metadata.coverPath,
    );
    if (result == null || !context.mounted) return;
    final coverPath = await AppDataPaths.importCover(result.coverPath, gameId);
    if (!context.mounted) return;

    await ref
        .read(libraryProvider.notifier)
        .add(
          GameEntry(
            id: gameId,
            name: defaultName,
            path: path,
            source: source,
            addedAt: DateTime.now(),
            displayName: result.name.isNotEmpty ? result.name : null,
            coverPath: coverPath,
            translationEnabled: result.translationEnabled,
            translationPatchPath: result.translationPatchPath,
            environmentPatchEnabled: result.environmentPatchEnabled,
          ),
        );
    Log.info('已添加: ${result.name.isNotEmpty ? result.name : defaultName}');
  }

  Future<_ResolvedGameMetadata?> _resolveGameMetadata(
    String defaultName,
    String path,
    GameSource source,
    String gameId,
  ) async {
    // 优先从语言表提取 gametitle，找不到时再 headless 运行到 caption。
    // 目录名常是罗马音缩写，会命中错误 VN；整个过程均为 best-effort。
    final caption = await CoreBridge().probeCaption(
      projectPath: path,
      isPfsArchive: source == GameSource.pfsArchive,
      platform: ref.read(settingsProvider).runtimePlatform,
    );
    if (!context.mounted) return null;
    // caption 常是「脏」的（含汉化译名/版本号/补丁公告），lookupGame 会切段滤垃圾。
    final rawTitle = (caption != null && caption.trim().isNotEmpty)
        ? caption
        : defaultName;
    final info = await VndbService.lookupGame(rawTitle);
    if (!context.mounted) return null;
    if (info == null) return _ResolvedGameMetadata(defaultName, null);

    String? coverPath;
    if (info.imageUrl case final imageUrl?) {
      coverPath = await VndbService.downloadCover(imageUrl, gameId);
      if (!context.mounted) return null;
    }
    return _ResolvedGameMetadata(info.title, coverPath);
  }

  String _pfsDisplayName(String path) => path
      .split(Platform.pathSeparator)
      .last
      .replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');

  String _gameIdForPath(String path) {
    final library = ref.read(libraryProvider);
    for (final game in library) {
      if (game.path == path) return game.id;
    }
    final existing = library.map((game) => game.id).toSet();
    final random = Random.secure();
    while (true) {
      final id = List.generate(
        8,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      if (!existing.contains(id)) return id;
    }
  }

  // ── 条目操作 ──────────────────────────────────────────────

  Future<void> editGame(GameEntry entry) async {
    final result = await showGameEditDialog(
      context,
      title: '编辑项目',
      initialName: entry.displayNameOrName,
      initialCoverPath: entry.coverPath,
      initialTranslationEnabled: entry.translationEnabled,
      initialTranslationPatchPath: entry.translationPatchPath,
      initialEnvironmentPatchEnabled: entry.environmentPatchEnabled,
    );
    if (result == null || !context.mounted) return;
    final coverPath = await AppDataPaths.importCover(
      result.coverPath,
      entry.id,
    );
    if (!context.mounted) return;

    await ref
        .read(libraryProvider.notifier)
        .update(
          entry.path,
          displayName: result.name.isNotEmpty ? result.name : null,
          coverPath: coverPath,
          translationEnabled: result.translationEnabled,
          translationPatchPath: result.translationPatchPath,
          environmentPatchEnabled: result.environmentPatchEnabled,
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
      PlayerPageRoute<void>(
        builder: (_) => wrapPlayerRoute(
          PlayerScreen(
            gameId: entry.id,
            projectPath: entry.path,
            source: entry.source,
            translationEnabled: entry.translationEnabled,
            translationPatchPath: entry.translationPatchPath,
            environmentPatchEnabled: entry.environmentPatchEnabled,
          ),
        ),
      ),
    );
  }
}

class _ResolvedGameMetadata {
  const _ResolvedGameMetadata(this.name, this.coverPath);

  final String name;
  final String? coverPath;
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
