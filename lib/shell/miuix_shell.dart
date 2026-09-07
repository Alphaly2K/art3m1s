import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/feedback.dart';
import '../adaptive/miuix_chrome.dart';
import '../controllers/library_actions.dart';
import '../models/game_entry.dart';
import '../models/host_ui_theme.dart';
import '../models/render_backend.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/translation_settings_screen.dart';
import '../services/app_info.dart';
import '../services/logger.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/game_grid.dart';

/// Android Miuix 壳：用 flutter_miuix 的主题与组件替换 Material 资料库/设置。
class MiuixShellApp extends StatelessWidget {
  const MiuixShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MiuixSystemTheme(
      child: Builder(
        builder: (context) {
          final theme = MiuixTheme.of(context);
          return MaterialApp(
            title: 'Art3m1s',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: theme.colors.primary,
                brightness: theme.brightness,
              ),
              brightness: theme.brightness,
            ),
            home: const DebugOverlayHost(child: _MiuixLibraryScreen()),
          );
        },
      ),
    );
  }
}

class _MiuixLibraryScreen extends ConsumerWidget {
  const _MiuixLibraryScreen();

  Future<void> _showAddSheet(
    BuildContext context,
    LibraryActions actions,
  ) async {
    final choice = await showMiuixSheet<int>(
      context: context,
      title: '添加项目',
      content: (context, dismiss) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          child: MiuixCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixBasicComponent(
                  title: '选择文件夹',
                  summary: '已解包的工程目录（含 system.ini）',
                  startAction: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: miuixNamedIcon('folder'),
                  ),
                  onClick: () => dismiss(0),
                ),
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 16),
                  child: MiuixHorizontalDivider(),
                ),
                MiuixBasicComponent(
                  title: '选择 PFS 归档',
                  summary: '直接读取，不写入磁盘',
                  startAction: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: miuixNamedIcon('addFolder'),
                  ),
                  onClick: () => dismiss(1),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || choice == null) return;
    if (choice == 0) {
      await actions.pickDirectory();
    } else if (choice == 1) {
      await actions.pickPfs();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final actions = LibraryActions(context, ref);

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: 'Art3m1s',
        largeTitle: '资料库',
        blurred: true,
        actions: [
          miuixBarAction(
            icon: 'add',
            onPressed: () => _showAddSheet(context, actions),
          ),
          miuixBarAction(
            icon: 'settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MiuixSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      content: (padding) {
        if (sorted.isEmpty) {
          return Padding(
            padding: padding,
            child: LibraryEmptyState(
              action: MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: () => _showAddSheet(context, actions),
                child: const MiuixText('添加项目'),
              ),
            ),
          );
        }
        return GameGrid(
          games: sorted,
          padding: padding + const EdgeInsets.fromLTRB(12, 8, 12, 20),
          onOpen: actions.launch,
          onEdit: actions.editGame,
          onDelete: actions.confirmDelete,
        );
      },
    );
  }
}

class MiuixSettingsScreen extends ConsumerWidget {
  const MiuixSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final backends = availableBackends();
    final selectedBackend = backends.indexWhere(
      (option) => option.value == settings.backend,
    );

    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '设置',
        navigationIcon: miuixBarAction(
          icon: 'back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      content: (padding) {
        return ListView(
          padding: padding.add(const EdgeInsets.fromLTRB(12, 0, 12, 32)),
          children: [
            MiuixSettingsGroup(
              title: '外观',
              children: [
                for (final theme in HostUiTheme.values)
                  MiuixRadioButtonPreference(
                    title: theme.label,
                    summary: theme == HostUiTheme.material
                        ? 'Android 默认 Material 3'
                        : 'HyperOS 风格组件',
                    selected: settings.hostUiTheme == theme,
                    onClick: () => notifier.setHostUiTheme(theme),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            MiuixSettingsGroup(
              title: '渲染',
              children: [
                MiuixOverlayDropdownPreference(
                  title: '图形后端',
                  summary: backendName(settings.backend),
                  items: [for (final option in backends) option.label],
                  selectedIndex: selectedBackend < 0 ? 0 : selectedBackend,
                  onSelectedIndexChange: (index) {
                    notifier.setBackend(backends[index].value);
                  },
                ),
                MiuixArrowPreference(
                  title: '文本翻译',
                  summary: settings.translation.mode.label,
                  startAction: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: miuixNamedIcon('translate'),
                  ),
                  onClick: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TranslationSettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            MiuixSettingsGroup(
              title: '控制',
              children: [
                MiuixSwitchPreference(
                  title: '触摸板鼠标',
                  summary: '使用相对移动与鼠标点击操作游戏',
                  value: settings.mobileTouchpadEnabled,
                  onChanged: notifier.setMobileTouchpadEnabled,
                ),
              ],
            ),
            const SizedBox(height: 8),
            MiuixSettingsGroup(
              title: '调试',
              children: [
                MiuixSwitchPreference(
                  title: '调试模式',
                  summary: '记录详细日志',
                  value: settings.debugMode,
                  onChanged: notifier.setDebugMode,
                ),
                MiuixSwitchPreference(
                  title: '脏区着色',
                  summary: '标记实际重绘区域',
                  value: settings.damageVisualization,
                  enabled: settings.debugMode,
                  onChanged: notifier.setDamageVisualization,
                ),
                MiuixSwitchPreference(
                  title: 'Profiler 浮层',
                  summary: '显示分阶段耗时与内存统计',
                  value: settings.profilerOverlay,
                  enabled: settings.debugMode,
                  onChanged: notifier.setProfilerOverlay,
                ),
                MiuixSwitchPreference(
                  title: '调试面板',
                  summary: '显示浮动监控面板',
                  value: settings.debugOverlay,
                  onChanged: notifier.setDebugOverlay,
                ),
                MiuixArrowPreference(
                  title: '导出日志文件',
                  startAction: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: miuixNamedIcon('copy'),
                  ),
                  onClick: () async {
                    final file = await Log.exportToFile();
                    if (context.mounted) {
                      notify(context, '已导出: ${file.path}');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            MiuixSettingsGroup(
              title: '显示',
              children: [
                MiuixSwitchPreference(
                  title: '显示帧率',
                  value: settings.showFps,
                  onChanged: notifier.setShowFps,
                ),
              ],
            ),
            const SizedBox(height: 8),
            MiuixSettingsGroup(
              title: '信息',
              children: [
                MiuixArrowPreference(
                  title: '关于 Art3m1s',
                  summary: '许可证、依赖与仓库地址',
                  startAction: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: miuixNamedIcon('info'),
                  ),
                  onClick: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MiuixAboutScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class MiuixAboutScreen extends StatelessWidget {
  const MiuixAboutScreen({super.key});

  static const _appRepository = 'https://github.com/Alphaly2K/art3m1s';
  static const _coreRepository = 'https://github.com/Alphaly2K/art3m1s-core';

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '关于',
        navigationIcon: miuixBarAction(
          icon: 'back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      content: (padding) {
        return ListView(
          padding: padding.add(const EdgeInsets.fromLTRB(12, 0, 12, 32)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      AppInfo.logoAsset,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MiuixText('Art3m1s', style: theme.textStyles.title2),
                        const SizedBox(height: 4),
                        MiuixText(
                          'Artemis 视觉小说引擎前端',
                          style: theme.textStyles.body2,
                          color: theme.colors.onSurfaceVariantSummary,
                        ),
                        const SizedBox(height: 2),
                        MiuixText(
                          '版本 ${AppInfo.displayVersion}',
                          style: theme.textStyles.body2,
                          color: theme.colors.onSurfaceVariantSummary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            MiuixSettingsGroup(
              title: '许可证',
              children: [
                const MiuixBasicComponent(
                  title: 'Art3m1s',
                  summary: 'Mozilla Public License 2.0',
                ),
                MiuixArrowPreference(
                  title: '第三方许可证',
                  summary: '查看 Flutter 与依赖包许可证',
                  onClick: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'Art3m1s',
                      applicationVersion: AppInfo.displayVersion,
                      applicationLegalese: 'MPL-2.0',
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            MiuixSettingsGroup(
              title: '仓库',
              children: [
                _CopyPreference(title: 'Flutter App', value: _appRepository),
                _CopyPreference(title: 'Rust Core', value: _coreRepository),
              ],
            ),
            const SizedBox(height: 8),
            const MiuixSettingsGroup(
              title: 'Flutter 依赖',
              children: [
                MiuixBasicComponent(
                  title: 'flutter_miuix / flutter_riverpod / yaru',
                  summary:
                      'macos_ui · fluent_ui · media_kit · shared_preferences',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const MiuixSettingsGroup(
              title: 'Rust / Native',
              children: [
                MiuixBasicComponent(
                  title: 'art3m1s-core / asb-interpreter',
                  summary: 'pfs-upk-rust · mlua · ANGLE',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CopyPreference extends StatelessWidget {
  const _CopyPreference({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MiuixArrowPreference(
      title: title,
      summary: value,
      onClick: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) notify(context, '已复制');
      },
    );
  }
}
