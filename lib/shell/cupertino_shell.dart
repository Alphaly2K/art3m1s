import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/cupertino_chrome.dart';
import '../adaptive/feedback.dart';
import '../controllers/library_actions.dart';
import '../models/game_entry.dart';
import '../models/render_backend.dart';
import '../models/render_output.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/app_info.dart';
import '../screens/licenses_cupertino.dart';
import '../screens/translation_settings_screen.dart';
import '../services/logger.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/game_grid.dart';
import '../widgets/render_resolution_dialog.dart';

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
      home: const DebugOverlayHost(child: _CupertinoHome()),
    );
  }
}

class _CupertinoHome extends StatelessWidget {
  const _CupertinoHome();

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        height: 56,
        iconSize: 25,
        items: const [
          BottomNavigationBarItem(
            icon: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(CupertinoIcons.square_grid_2x2),
            ),
            label: '资料库',
          ),
          BottomNavigationBarItem(
            icon: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(CupertinoIcons.settings),
            ),
            label: '设置',
          ),
          BottomNavigationBarItem(
            icon: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(CupertinoIcons.info),
            ),
            label: '关于',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) => switch (index) {
            0 => const _CupertinoLibraryScreen(),
            1 => const _CupertinoSettingsScreen(),
            _ => const _CupertinoAboutScreen(),
          },
        );
      },
    );
  }
}

class _CupertinoLibraryScreen extends ConsumerWidget {
  const _CupertinoLibraryScreen();

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
              onPressed: actions.scanIosAppFolder,
              child: const Icon(CupertinoIcons.search),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: sorted.isEmpty
            ? LibraryEmptyState(
                action: CupertinoButton.filled(
                  onPressed: actions.scanIosAppFolder,
                  child: const Text('扫描游戏'),
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
            CupertinoSymmetricListSection(
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
                if (supportsSpatialUpscalingSettings(settings.backend))
                  CupertinoListTile.notched(
                    title: const Text('超分输出'),
                    subtitle: Text(
                      renderOutputDescription(
                        settings.renderOutputMode,
                        customWidth: settings.customRenderWidth,
                        customHeight: settings.customRenderHeight,
                      ),
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      final v = await _pickOption<RenderOutputMode>(
                        context,
                        title: '超分输出',
                        options: [
                          for (final mode in RenderOutputMode.values)
                            (mode, mode.label),
                        ],
                      );
                      if (v != null) notifier.setRenderOutputMode(v);
                    },
                  ),
                if (supportsSpatialUpscalingSettings(settings.backend) &&
                    settings.renderOutputMode == RenderOutputMode.custom)
                  CupertinoListTile.notched(
                    title: const Text('自定义分辨率'),
                    subtitle: const Text('保持游戏宽高比'),
                    additionalInfo: Text(
                      '${settings.customRenderWidth}×${settings.customRenderHeight}',
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      final size = await showRenderResolutionDialog(
                        context,
                        width: settings.customRenderWidth,
                        height: settings.customRenderHeight,
                      );
                      if (size != null) {
                        notifier.setCustomRenderSize(size.width, size.height);
                      }
                    },
                  ),
              ],
            ),
            CupertinoSymmetricListSection(
              header: const Text('运行时'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('文本翻译'),
                  additionalInfo: Text(settings.translation.mode.label),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const TranslationSettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            CupertinoSymmetricListSection(
              header: const Text('控制'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('触摸板鼠标'),
                  subtitle: const Text('使用相对移动与鼠标点击操作游戏'),
                  trailing: CupertinoSwitch(
                    value: settings.mobileTouchpadEnabled,
                    onChanged: notifier.setMobileTouchpadEnabled,
                  ),
                ),
              ],
            ),
            CupertinoSymmetricListSection(
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
                  title: const Text('脏区着色'),
                  subtitle: const Text('标记实际重绘区域'),
                  trailing: CupertinoSwitch(
                    value: settings.damageVisualization,
                    onChanged: settings.debugMode
                        ? notifier.setDamageVisualization
                        : null,
                  ),
                ),
                CupertinoListTile.notched(
                  title: const Text('Profiler 浮层'),
                  subtitle: const Text('显示分阶段耗时与内存统计'),
                  trailing: CupertinoSwitch(
                    value: settings.profilerOverlay,
                    onChanged: settings.debugMode
                        ? notifier.setProfilerOverlay
                        : null,
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
            CupertinoSymmetricListSection(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  const _AppBadge(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Art3m1s',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Artemis 视觉小说引擎前端\n版本 ${AppInfo.displayVersion} · MPL-2.0',
                          style: const TextStyle(
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
            CupertinoSymmetricListSection(
              header: const Text('仓库'),
              children: [
                _CopyTile(title: 'Flutter App', value: _appRepository),
                _CopyTile(title: 'Rust Core', value: _coreRepository),
              ],
            ),
            CupertinoSymmetricListSection(
              header: const Text('许可证'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('第三方许可证'),
                  subtitle: const Text('查看 Flutter 与依赖包许可证'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const CupertinoLicensesPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            CupertinoSymmetricListSection(
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
                    'mlua/Lua 5.1 · glow · ANGLE (Metal)',
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        AppInfo.logoAsset,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
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
