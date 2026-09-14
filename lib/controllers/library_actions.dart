import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/dialogs.dart';
import '../adaptive/feedback.dart';
import '../adaptive/ps5_chrome.dart';
import 'ps5_game_sessions.dart';
import '../engine/engine_runtime_factory.dart';
import '../models/game_engine.dart';
import '../models/game_entry.dart';
import '../models/input_gate.dart';
import '../navigation/player_page_route.dart';
import '../providers/library_provider.dart';
import '../screens/player_screen.dart';
import '../services/app_data_paths.dart';
import '../services/game_importer.dart';
import '../services/logger.dart';
import '../services/game_manifest.dart';
import '../services/vndb_service.dart';
import '../widgets/ps5_file_picker.dart';

/// 资料库的全部业务流程，三个壳共用；壳只负责入口控件的平台样式。
class LibraryActions {
  final BuildContext context;
  final WidgetRef ref;

  const LibraryActions(this.context, this.ref);

  // ── 添加入口 ──────────────────────────────────────────────

  /// 统一的导入流程:选择目录 → 探测 → 原地入库,全平台一致、不复制。
  /// Android 走原生 SAF 选择器并解析真实路径(需要「所有文件访问」授权);
  /// PS5 桌面壳走内置大屏文件浏览器,其它桌面壳沿用系统目录选择器;
  /// iOS 用 `scanIosAppFolder` 扫描 App 文件夹。
  ///
  /// 探测同时覆盖两类游戏:解包工程目录(system.ini → Artemis,
  /// `.hcb` → RFVP)和打包成 PFS 归档的 Artemis 游戏(没有外露 system.ini,
  /// 以 base `.pfs` 文件为标记)。位于已识别工程目录内部的 .pfs 是该工程的
  /// 资源包,不重复登记为独立游戏。
  Future<void> pickDirectory() async {
    final path = await _pickImportDirectory();
    if (path == null || !context.mounted) return;
    final probe = GameImporter.probeGameFolder(path);
    if (probe.projects.isEmpty && probe.pfsArchives.isEmpty) {
      notify(context, '所选目录中没有可识别的游戏项目');
      return;
    }
    final games = [
      for (final path in probe.projects)
        DiscoveredGame(
          name: _directoryDisplayName(path),
          path: path,
          source: GameSource.directory.name,
        ),
      for (final path in probe.pfsArchives)
        DiscoveredGame(
          name: _pfsDisplayName(path),
          path: path,
          source: GameSource.pfsArchive.name,
        ),
    ];
    if (games.length == 1) {
      await _addDiscoveredGame(games.single);
      return;
    }
    await _addDiscoveredGamesAutomatically(games);
  }

  /// 选一个导入目录。Android 上授权缺失时引导用户开启「所有文件访问」,
  /// URI 无法解析为真实路径时降级为手动输入;用户取消返回 null。
  Future<String?> _pickImportDirectory() async {
    if (!Platform.isAndroid) {
      if (usesPs5Chrome(context)) {
        return showPs5FilePicker(
          context,
          mode: Ps5FilePickerMode.directory,
          title: '选择游戏文件夹',
        );
      }
      return getDirectoryPath(confirmButtonText: '选择此目录');
    }
    try {
      return await GameImporter.pickGameDirectory();
    } on GameImportException catch (error) {
      if (!context.mounted) return null;
      if (error.message == 'needsAllFilesAccess') {
        await _promptAllFilesAccess();
        return null;
      }
      if (error.message == 'unresolved') {
        notify(context, '无法解析所选目录的路径,请手动输入目录');
        return _promptManualDirectoryPath();
      }
      notify(context, error.message);
      return null;
    }
  }

  Future<void> _promptAllFilesAccess() async {
    final confirmed = await showAdaptiveConfirm(
      context,
      title: '需要存储访问权限',
      message:
          '为了直接读取游戏目录而不复制文件,需要在系统设置中允许'
          '「所有文件访问」。授权后请重新选择游戏目录。',
      confirmLabel: '去授权',
    );
    if (confirmed) {
      await GameImporter.requestAllFilesAccess();
    }
  }

  Future<String?> _promptManualDirectoryPath() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        // 库页面可能运行在非 Material 壳下,自带浅色主题与文本方向。
        return Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          child: AlertDialog(
            title: const Text('输入游戏目录路径'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如 /sdcard/Games/某游戏',
              ),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
    if (path == null || path.isEmpty) return null;
    if (!Directory(path).existsSync()) {
      if (context.mounted) notify(context, '目录不存在: $path');
      return null;
    }
    return path;
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

  Future<bool> _addDiscoveredGame(DiscoveredGame game) {
    return _editAndAdd(
      game.name,
      game.path,
      game.isPfsArchive ? GameSource.pfsArchive : GameSource.directory,
    );
  }

  Future<int> _addDiscoveredGamesAutomatically(
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
      return 0;
    }

    var added = 0;
    for (var index = 0; index < pending.length; index++) {
      if (!context.mounted) return added;
      final game = pending[index];
      notify(context, '正在添加 ${index + 1}/${pending.length}：${game.name}');
      if (await _addDiscoveredGameAutomatically(game)) added++;
    }
    if (context.mounted) {
      notify(context, '已添加 $added 个游戏');
    }
    return added;
  }

  Future<bool> _addDiscoveredGameAutomatically(DiscoveredGame game) async {
    final source = game.isPfsArchive
        ? GameSource.pfsArchive
        : GameSource.directory;
    final gameId = _gameIdForPath(game.path);
    final manifest = await GameManifest.loadForProject(game.path, source);
    final engine = _resolveProjectEngine(manifest, game.path, source);
    final metadata = await _resolveGameMetadata(
      game.name,
      game.path,
      source,
      gameId,
      manifest,
      engine,
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
            engine: engine,
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

  Future<bool> _editAndAdd(
    String defaultName,
    String path,
    GameSource source,
  ) async {
    if (_isAlreadyInLibrary(path)) {
      if (context.mounted) notify(context, '该游戏已在资料库中');
      return false;
    }
    final gameId = _gameIdForPath(path);
    notify(context, '正在读取游戏信息；VNDB 不可用时将离线继续…');
    final manifest = await GameManifest.loadForProject(path, source);
    final engine = _resolveProjectEngine(manifest, path, source);
    final metadata = await _resolveGameMetadata(
      defaultName,
      path,
      source,
      gameId,
      manifest,
      engine,
    );
    if (metadata == null || !context.mounted) return false;

    final result = await showGameEditDialog(
      context,
      title: '添加项目',
      engine: engine,
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
    if (result == null || !context.mounted) return false;
    final coverPath = await AppDataPaths.importCover(result.coverPath, gameId);
    if (!context.mounted) return false;

    await ref
        .read(libraryProvider.notifier)
        .add(
          GameEntry(
            id: gameId,
            name: defaultName,
            path: path,
            source: source,
            engine: engine,
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
            fontOverrideFilePath: result.fontOverrideFilePath,
            reportedOs: result.reportedOs.isNotEmpty
                ? result.reportedOs
                : manifest?.reportedOs ?? '',
            runtimePlatform: result.runtimePlatform,
          ),
        );
    Log.info('已添加: ${result.name.isNotEmpty ? result.name : defaultName}');
    return true;
  }

  Future<_ResolvedGameMetadata?> _resolveGameMetadata(
    String defaultName,
    String path,
    GameSource source,
    String gameId,
    GameManifest? manifest,
    GameEngineKind engine,
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
      final caption = await EngineRuntimeFactory.probeCaption(
        engine: engine,
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

  /// 引擎识别优先级:manifest 显式声明 > 目录标记探测 > PFS 归档。
  /// PFS 是 Artemis 专属格式(`GameEngineKind.supportsPfsArchives`),
  /// 没有 manifest 声明时一律按 Artemis 处理。
  GameEngineKind _resolveProjectEngine(
    GameManifest? manifest,
    String path,
    GameSource source,
  ) {
    final manifestEngine = manifest?.engine;
    if (manifestEngine != null) return manifestEngine;
    if (source == GameSource.directory) {
      return GameImporter.detectDirectoryEngine(path);
    }
    return GameEngineKind.art3m1s;
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
      engine: configured.engine,
      initialName: configured.displayNameOrName,
      initialCoverPath: configured.coverPath,
      initialTranslationEnabled: configured.translationEnabled,
      initialTranslationPatchPath: configured.translationPatchPath,
      initialEnvironmentPatchEnabled: configured.environmentPatchEnabled,
      initialExperimentalElunaEnabled: configured.experimentalElunaEnabled,
      initialInputGate: configured.inputGate,
      initialFontOverrideFilePath: configured.fontOverrideFilePath,
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
          fontOverrideFilePath: result.fontOverrideFilePath,
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
    // 原位导入的目录是用户文件,移除库条目不删除;只有早期 Android
    // 沙箱内的遗留导入副本会随条目一起清理(见 LibraryNotifier.remove)。
    final message =
        '确定从库中移除「${entry.displayNameOrName}」吗？'
        '游戏目录本身不会被删除。';
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
    final ps5BigScreen = usesPs5Chrome(context);
    // Manifest 是每个游戏的权威配置源；每次创建宿主前重新读取，外部编辑
    // 或跨启动修改都能立即生效，不再依赖 GameEntry 的旧缓存。
    final configured = await GameManifest.loadEntrySettings(entry);
    if (!context.mounted) return;
    await ref.read(libraryProvider.notifier).markPlayed(configured.path);
    if (!context.mounted) return;
    final sessionHost = Ps5GameSessionScope.maybeOf(context);
    if (sessionHost != null && configured.engine != GameEngineKind.krkr) {
      sessionHost.activate(configured);
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      PlayerPageRoute<void>(
        builder: (_) => wrapPlayerRoute(
          PlayerScreen(
            gameId: configured.id,
            projectPath: configured.path,
            source: configured.source,
            engine: configured.engine,
            translationEnabled: configured.translationEnabled,
            translationPatchPath: configured.translationPatchPath,
            environmentPatchEnabled: configured.environmentPatchEnabled,
            experimentalElunaEnabled: configured.experimentalElunaEnabled,
            ps5BigScreen: ps5BigScreen,
            addedAt: configured.addedAt,
            lastPlayedAt: configured.lastPlayedAt,
            screenshotPath: configured.screenshotPath,
            inputGate: configured.inputGate,
            fontOverridePath: configured.fontOverridePath,
            fontOverrideFilePath: configured.fontOverrideFilePath,
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
