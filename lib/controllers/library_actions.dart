import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/dialogs.dart';
import '../adaptive/feedback.dart';
import '../models/game_entry.dart';
import '../models/input_gate.dart';
import '../navigation/player_page_route.dart';
import '../providers/library_provider.dart';
import '../services/core_bridge.dart';
import '../screens/player_screen.dart';
import '../services/app_data_paths.dart';
import '../services/game_importer.dart';
import '../services/logger.dart';
import '../services/game_manifest.dart';
import '../services/vndb_service.dart';

/// 资料库的全部业务流程，三个壳共用；壳只负责入口控件的平台样式。
class LibraryActions {
  final BuildContext context;
  final WidgetRef ref;

  const LibraryActions(this.context, this.ref);

  // ── 添加入口 ──────────────────────────────────────────────

  Future<void> pickDirectory() async {
    List<String> projects;
    try {
      if (Platform.isAndroid) {
        // Android 不能用 dart:io 直接读 SAF 目录，先拷进沙箱再识别 system.ini。
        final imported = await _importAndroidDirectory(
          GameImporter.discoverUnpackedProjects,
        );
        if (imported == null || !context.mounted) return;
        projects = imported;
      } else {
        final path = await getDirectoryPath(confirmButtonText: '选择此目录');
        if (path == null || !context.mounted) return;
        projects = GameImporter.discoverUnpackedProjects(path);
      }
    } on GameImportException catch (error) {
      if (context.mounted) notify(context, error.message);
      return;
    }
    if (!context.mounted) return;
    if (projects.isEmpty) {
      notify(context, '所选目录中没有 system.ini');
      return;
    }
    if (projects.length == 1) {
      final path = projects.single;
      await _editAndAdd(
        _directoryDisplayName(path),
        path,
        GameSource.directory,
      );
      return;
    }
    await _addDiscoveredGamesAutomatically([
      for (final path in projects)
        DiscoveredGame(
          name: _directoryDisplayName(path),
          path: path,
          source: GameSource.directory.name,
        ),
    ]);
  }

  Future<void> pickPfs() async {
    var filePaths = <String>[];
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动平台：通过原生选择器复制数据，再让每个 base PFS 独立成为项目。
      // 避免 file_selector 在 Android 上返回无法用 dart:io 访问的 content URI。
      if (Platform.isAndroid) {
        try {
          final imported = await _importAndroidDirectory(
            GameImporter.discoverBasePfsFiles,
          );
          if (imported == null || !context.mounted) return;
          filePaths = imported;
        } on GameImportException catch (error) {
          if (context.mounted) notify(context, error.message);
          return;
        }
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

  Future<List<String>?> _importAndroidDirectory(
    List<String> Function(String path) discover,
  ) async {
    BlockingProgressController? progress;
    try {
      final sandboxDir = await GameImporter.pickDirectoryAndCopy(
        onProgress: (value) {
          if (!context.mounted) return;
          progress ??= showBlockingProgress(
            context,
            title: '正在导入游戏',
            message: value.message,
          );
          progress?.update(value.message);
        },
      );
      if (sandboxDir == null || !context.mounted) return null;
      progress ??= showBlockingProgress(
        context,
        title: '正在导入游戏',
        message: '正在识别游戏文件…',
      );
      progress?.update('正在识别游戏文件…');
      await Future<void>.delayed(Duration.zero);
      return discover(sandboxDir);
    } finally {
      progress?.close();
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
    final pending = <DiscoveredGame>[];
    for (final game in games) {
      if (_isAlreadyInLibrary(game.path)) continue;
      if (GameImporter.libraryContainsPath(
        pending.map((item) => item.path),
        game.path,
      )) {
        continue;
      }
      pending.add(game);
    }
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
    final manifest = await GameManifest.loadForProject(game.path, source);
    final metadata = await _resolveGameMetadata(
      game.name,
      game.path,
      source,
      gameId,
      manifest,
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
            translationEnabled: manifest?.translationEnabled ?? false,
            translationPatchPath: manifest?.translationPatchPath ?? '',
            environmentPatchEnabled: manifest?.environmentPatchEnabled ?? false,
            experimentalElunaEnabled:
                manifest?.experimentalElunaEnabled ?? false,
            inputGate: manifest?.inputGate ?? InputGatePolicy.full,
            vndbId: metadata.vndbId ?? '',
            fontOverridePath: manifest?.fontOverride ?? '',
            reportedOs: manifest?.reportedOs ?? '',
            runtimePlatform:
                manifest?.runtimePlatform ??
                GameManifest.defaultRuntimePlatform,
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
    if (_isAlreadyInLibrary(path)) {
      if (context.mounted) notify(context, '该游戏已在资料库中');
      return;
    }
    final gameId = _gameIdForPath(path);
    notify(context, '正在读取游戏信息；VNDB 不可用时将离线继续…');
    final manifest = await GameManifest.loadForProject(path, source);
    final metadata = await _resolveGameMetadata(
      defaultName,
      path,
      source,
      gameId,
      manifest,
    );
    if (metadata == null || !context.mounted) return;

    final result = await showGameEditDialog(
      context,
      title: '添加项目',
      initialName: metadata.name,
      initialCoverPath: metadata.coverPath,
      initialTranslationEnabled: manifest?.translationEnabled ?? false,
      initialTranslationPatchPath: manifest?.translationPatchPath ?? '',
      initialEnvironmentPatchEnabled:
          manifest?.environmentPatchEnabled ?? false,
      initialExperimentalElunaEnabled:
          manifest?.experimentalElunaEnabled ?? false,
      initialInputGate: manifest?.inputGate ?? InputGatePolicy.full,
      initialRuntimePlatform:
          manifest?.runtimePlatform ?? GameManifest.defaultRuntimePlatform,
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
            experimentalElunaEnabled: result.experimentalElunaEnabled,
            inputGate: result.inputGate,
            vndbId: metadata.vndbId ?? '',
            fontOverridePath: manifest?.fontOverride ?? '',
            reportedOs: result.reportedOs.isNotEmpty
                ? result.reportedOs
                : manifest?.reportedOs ?? '',
            runtimePlatform: result.runtimePlatform,
          ),
        );
    Log.info('已添加: ${result.name.isNotEmpty ? result.name : defaultName}');
  }

  Future<_ResolvedGameMetadata?> _resolveGameMetadata(
    String defaultName,
    String path,
    GameSource source,
    String gameId,
    GameManifest? manifest,
  ) async {
    // 清单携带 vndbId 时精确查询；否则从语言表提取 gametitle，找不到时再
    // headless 运行到 caption。目录名常是罗马音缩写，会命中错误 VN；
    // 整个过程均为 best-effort。
    VndbGameInfo? info;
    if (manifest?.vndbId case final vndbId?) {
      info = await VndbService.lookupById(vndbId);
      if (!context.mounted) return null;
    }
    if (info == null) {
      final caption = await CoreBridge().probeCaption(
        projectPath: path,
        isPfsArchive: source == GameSource.pfsArchive,
        platform:
            manifest?.runtimePlatform ?? GameManifest.defaultRuntimePlatform,
      );
      if (!context.mounted) return null;
      // caption 常是「脏」的（含汉化译名/版本号/补丁公告），lookupGame 会切段滤垃圾。
      final rawTitle = (caption != null && caption.trim().isNotEmpty)
          ? caption
          : defaultName;
      info = await VndbService.lookupGame(rawTitle);
      if (!context.mounted) return null;
    }
    if (info == null) {
      return _ResolvedGameMetadata(
        manifest?.name ?? defaultName,
        null,
        manifest?.vndbId,
      );
    }

    String? coverPath;
    if (info.imageUrl case final imageUrl?) {
      coverPath = await VndbService.downloadCover(imageUrl, gameId);
      if (!context.mounted) return null;
    }
    return _ResolvedGameMetadata(info.title, coverPath, manifest?.vndbId);
  }

  String _pfsDisplayName(String path) => path
      .split(Platform.pathSeparator)
      .last
      .replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');

  String _directoryDisplayName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.isEmpty ? path : name;
  }

  String _gameIdForPath(String path) {
    final library = ref.read(libraryProvider);
    for (final game in library) {
      if (GameImporter.isSameLibraryPath(game.path, path)) return game.id;
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
    final configured = await GameManifest.loadEntrySettings(entry);
    if (!context.mounted) return;
    final result = await showGameEditDialog(
      context,
      title: '编辑项目',
      initialName: configured.displayNameOrName,
      initialCoverPath: configured.coverPath,
      initialTranslationEnabled: configured.translationEnabled,
      initialTranslationPatchPath: configured.translationPatchPath,
      initialEnvironmentPatchEnabled: configured.environmentPatchEnabled,
      initialExperimentalElunaEnabled: configured.experimentalElunaEnabled,
      initialInputGate: configured.inputGate,
      initialReportedOs: configured.reportedOs,
      initialRuntimePlatform: configured.runtimePlatform,
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
          experimentalElunaEnabled: result.experimentalElunaEnabled,
          inputGate: result.inputGate,
          reportedOs: result.reportedOs,
          runtimePlatform: result.runtimePlatform,
        );
  }

  bool _isAlreadyInLibrary(String path) {
    return GameImporter.libraryContainsPath(
      ref.read(libraryProvider).map((entry) => entry.path),
      path,
    );
  }

  Future<void> confirmDelete(GameEntry entry) async {
    final message = Platform.isAndroid
        ? '确定从库中移除「${entry.displayNameOrName}」并删除应用内已导入的游戏文件吗？'
        : '确定从库中移除「${entry.displayNameOrName}」吗？';
    final confirmed = await showAdaptiveConfirm(
      context,
      title: '移除项目',
      message: message,
      confirmLabel: '移除',
      destructive: true,
    );
    if (confirmed && context.mounted) {
      await ref.read(libraryProvider.notifier).remove(entry.path);
    }
  }

  void launch(GameEntry entry) {
    unawaited(_launch(entry));
  }

  Future<void> _launch(GameEntry entry) async {
    // Manifest 是每个游戏的权威配置源；每次创建宿主前重新读取，外部编辑
    // 或跨启动修改都能立即生效，不再依赖 GameEntry 的旧缓存。
    final configured = await GameManifest.loadEntrySettings(entry);
    if (!context.mounted) return;
    await ref.read(libraryProvider.notifier).markPlayed(configured.path);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      PlayerPageRoute<void>(
        builder: (_) => wrapPlayerRoute(
          PlayerScreen(
            gameId: configured.id,
            projectPath: configured.path,
            source: configured.source,
            translationEnabled: configured.translationEnabled,
            translationPatchPath: configured.translationPatchPath,
            environmentPatchEnabled: configured.environmentPatchEnabled,
            experimentalElunaEnabled: configured.experimentalElunaEnabled,
            inputGate: configured.inputGate,
            fontOverridePath: configured.fontOverridePath,
            reportedOs: configured.reportedOs,
            runtimePlatform: configured.runtimePlatform,
            manifestPath: configured.manifestPath,
          ),
        ),
      ),
    );
  }
}

class _ResolvedGameMetadata {
  const _ResolvedGameMetadata(this.name, this.coverPath, [this.vndbId]);

  final String name;
  final String? coverPath;
  final String? vndbId;
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
