import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/feedback.dart';
import '../controllers/library_actions.dart';
import '../models/game_entry.dart';
import '../models/render_backend.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/licenses_cupertino.dart';
import '../services/logger.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/game_grid.dart';

/// iOS 壳：CupertinoApp，导航栏 + ActionSheet + 分组设置页。
class CupertinoShellApp extends StatelessWidget {
  const CupertinoShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Art3m1s',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: const DebugOverlayHost(child: _CupertinoLibraryScreen()),
    );
  }
}

class _CupertinoLibraryScreen extends ConsumerWidget {
  const _CupertinoLibraryScreen();

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final actions = LibraryActions(context, ref);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('添加项目'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              actions.openIosAppFolderManager();
            },
            child: const Text('App 文件夹（Files app）'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              actions.pickDirectory();
            },
            child: const Text('选择文件夹'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              actions.pickPfs();
            },
            child: const Text('选择 PFS 归档'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final actions = LibraryActions(context, ref);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('资料库'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              sizeStyle: CupertinoButtonSize.small,
              onPressed: () => _showAddSheet(context, ref),
              child: const Icon(CupertinoIcons.add),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              sizeStyle: CupertinoButtonSize.small,
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const _CupertinoSettingsScreen(),
                  ),
                );
              },
              child: const Icon(CupertinoIcons.gear),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: sorted.isEmpty
            ? LibraryEmptyState(
                action: CupertinoButton.filled(
                  onPressed: () => _showAddSheet(context, ref),
                  child: const Text('添加项目'),
                ),
              )
            : GameGrid(
                games: sorted,
                onOpen: actions.launch,
                onEdit: actions.editGame,
                onDelete: actions.confirmDelete,
              ),
      ),
    );
  }
}

// ── 设置 ──────────────────────────────────────────────────────

class _CupertinoSettingsScreen extends ConsumerWidget {
  const _CupertinoSettingsScreen();

  Future<T?> _pickOption<T>(
    BuildContext context, {
    required String title,
    required List<(T, String)> options,
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final (value, label) in options)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(value),
              child: Text(label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final backends = availableBackends();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('设置')),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('渲染'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('图形后端'),
                  subtitle: Text(backendName(settings.backend)),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () async {
                    final v = await _pickOption<int>(
                      context,
                      title: '图形后端',
                      options: [for (final b in backends) (b.value, b.label)],
                    );
                    if (v != null) notifier.setBackend(v);
                  },
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('运行时'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('启动 OS'),
                  subtitle: const Text('选择 system.ini 使用的启动段'),
                  additionalInfo: Text(settings.runtimePlatform),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () async {
                    final v = await _pickOption<String>(
                      context,
                      title: '启动 OS',
                      options: [for (final p in runtimePlatforms) (p, p)],
                    );
                    if (v != null) notifier.setRuntimePlatform(v);
                  },
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('调试'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('调试模式'),
                  subtitle: const Text('记录详细日志'),
                  trailing: CupertinoSwitch(
                    value: settings.debugMode,
                    onChanged: notifier.setDebugMode,
                  ),
                ),
                CupertinoListTile.notched(
                  title: const Text('调试面板'),
                  subtitle: const Text('显示浮动监控面板'),
                  trailing: CupertinoSwitch(
                    value: settings.debugOverlay,
                    onChanged: notifier.setDebugOverlay,
                  ),
                ),
                CupertinoListTile.notched(
                  title: const Text('导出日志文件'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () async {
                    final file = await Log.exportToFile();
                    if (context.mounted) {
                      notify(context, '已导出: ${file.path}');
                    }
                  },
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('显示'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('显示帧率'),
                  trailing: CupertinoSwitch(
                    value: settings.showFps,
                    onChanged: notifier.setShowFps,
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('信息'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('关于 Art3m1s'),
                  subtitle: const Text('许可证、依赖与仓库地址'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const _CupertinoAboutScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 关于 ──────────────────────────────────────────────────────

class _CupertinoAboutScreen extends StatelessWidget {
  const _CupertinoAboutScreen();

  static const _appRepository = 'https://github.com/Alphaly2K/art3m1s';
  static const _coreRepository = 'https://github.com/Alphaly2K/art3m1s-core';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('关于')),
      child: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  _AppBadge(),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Art3m1s',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Artemis 视觉小说引擎前端\n版本 1.0.0+1 · AGPL-3.0',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('仓库'),
              children: [
                _CopyTile(title: 'Flutter App', value: _appRepository),
                _CopyTile(title: 'Rust Core', value: _coreRepository),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('许可证'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('第三方许可证'),
                  subtitle: const Text('查看 Flutter 与依赖包许可证'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const CupertinoLicensesPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('主要依赖'),
              children: const [
                CupertinoListTile.notched(
                  title: Text('Flutter'),
                  subtitle: Text(
                    'flutter_riverpod · path_provider · ffi · file_selector · '
                    'audioplayers · media_kit',
                  ),
                ),
                CupertinoListTile.notched(
                  title: Text('Rust / Native'),
                  subtitle: Text(
                    'art3m1s-core · asb-interpreter · pfs-upk-rust · '
                    'mlua/Lua 5.1 · glow · MetalANGLE',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBadge extends StatelessWidget {
  const _AppBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CupertinoColors.systemPurple,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'A3',
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CopyTile extends StatelessWidget {
  final String title;
  final String value;

  const _CopyTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile.notched(
      title: Text(title),
      subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(CupertinoIcons.doc_on_doc, size: 18),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) notify(context, '已复制');
      },
    );
  }
}
