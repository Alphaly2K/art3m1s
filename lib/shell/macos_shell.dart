import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoPageRoute, DefaultCupertinoLocalizations;
import 'package:flutter/material.dart'
    show DefaultMaterialLocalizations, ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../adaptive/context_menu.dart';
import '../adaptive/feedback.dart';
import '../controllers/library_actions.dart';
import '../models/game_entry.dart';
import '../models/render_backend.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/app_info.dart';
import '../screens/licenses_macos.dart';
import '../screens/translation_settings_screen.dart';
import 'macos_menu_bar.dart';
import '../services/logger.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/game_grid.dart';
import '../widgets/inset_scrollbar.dart';
import '../widgets/macos_circle_button.dart';

/// macOS 壳：MacosApp + 侧栏（资料库 / 设置 / 关于）。
class MacosShellApp extends StatelessWidget {
  const MacosShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'Art3m1s',
      debugShowCheckedModeBanner: false,
      // 钉死强调色为标准蓝，避免随系统强调色漂移。
      //
      // 关键修复：macos_ui 默认把 iconTheme.color 设成了**强调色(蓝)**，导致所有未
      // 显式着色的 MacosIcon 都是蓝的——深色下蓝图标压深底/蓝底(如 MacosIconButton
      // 默认蓝底)对比极差甚至隐形。这里全局覆盖为随亮暗的中性前景色，一次修好返回钮/
      // 复制钮/侧栏等所有图标。
      theme: MacosThemeData.light(accentColor: AccentColor.blue).copyWith(
        iconTheme: const MacosIconThemeData(color: Color(0xFF1D1D1F), size: 20),
      ),
      darkTheme: MacosThemeData.dark(accentColor: AccentColor.blue).copyWith(
        iconTheme: const MacosIconThemeData(color: Color(0xFFE4E4E7), size: 20),
      ),
      themeMode: ThemeMode.system,
      // PlayerScreen 及其对话框是 Material 组件，需要这些 delegates。
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: const _MacosHome(),
    );
  }
}

class _MacosHome extends StatefulWidget {
  const _MacosHome();

  @override
  State<_MacosHome> createState() => _MacosHomeState();
}

class _MacosHomeState extends State<_MacosHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MacosMenuBar(
      onOpenSettings: () => setState(() => _index = 1),
      onOpenAbout: () => setState(() => _index = 2),
      child: DebugOverlayHost(
        child: MacosWindow(
          sidebarState: NSVisualEffectViewState.active,
          sidebar: Sidebar(
            minWidth: 190,
            builder: (context, scrollController) => SidebarItems(
              currentIndex: _index,
              scrollController: scrollController,
              onChanged: (i) => setState(() => _index = i),
              itemSize: SidebarItemSize.large,
              // macos_ui 默认选中色带 0.75 透明度且随窗口主/非主状态切换，
              // textLuminance 的黑白判定会与实际视觉亮度脱节，文字间歇性
              // 撞色不可读。固定为不透明系统蓝 → 文字恒为白色。
              selectedColor: const MacosColor.fromRGBO(22, 105, 229, 1.0),
              items: const [
                SidebarItem(
                  leading: MacosIcon(CupertinoIcons.square_grid_2x2),
                  label: Text('资料库'),
                ),
                SidebarItem(
                  leading: MacosIcon(CupertinoIcons.gear),
                  label: Text('设置'),
                ),
                SidebarItem(
                  leading: MacosIcon(CupertinoIcons.info_circle),
                  label: Text('关于'),
                ),
              ],
            ),
            bottom: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Art3m1s ${AppInfo.version}',
                style: const TextStyle(
                  fontSize: 11,
                  color: MacosColors.systemGrayColor,
                ),
              ),
            ),
          ),
          child: switch (_index) {
            0 => const _MacosLibraryPage(),
            1 => const _MacosSettingsPage(),
            _ => const _MacosAboutPage(),
          },
        ),
      ),
    );
  }
}

// ── 资料库 ────────────────────────────────────────────────────

class _MacosLibraryPage extends ConsumerWidget {
  const _MacosLibraryPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) {
            final actions = LibraryActions(context, ref);
            return Stack(
              children: [
                Positioned.fill(
                  child: sorted.isEmpty
                      ? LibraryEmptyState(
                          action: PushButton(
                            controlSize: ControlSize.large,
                            onPressed: actions.pickDirectory,
                            child: const Text('添加项目'),
                          ),
                        )
                      : InsetScrollbar(
                          controller: scrollController,
                          child: GameGrid(
                            games: sorted,
                            controller: scrollController,
                            // 顶部让位给浮动页头。
                            padding: const EdgeInsets.fromLTRB(20, 76, 20, 20),
                            onOpen: actions.launch,
                            onEdit: actions.editGame,
                            onDelete: actions.confirmDelete,
                          ),
                        ),
                ),
                // 页头与网格内容左右缘对齐（均为 20）。
                Positioned(
                  top: 14,
                  left: 20,
                  right: 20,
                  child: _GlassHeader(
                    title: '资料库',
                    trailing: MacosCircleButton(
                      icon: CupertinoIcons.add,
                      tooltip: '添加项目',
                      onTapWithPosition: (position) {
                        showAdaptiveContextMenu(context, position, [
                          ContextMenuAction(
                            label: '选择文件夹…',
                            icon: CupertinoIcons.folder,
                            onSelected: actions.pickDirectory,
                          ),
                          ContextMenuAction(
                            label: '选择 PFS 归档…',
                            icon: CupertinoIcons.archivebox,
                            onSelected: actions.pickPfs,
                          ),
                        ]);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── 设置 ──────────────────────────────────────────────────────

class _MacosSettingsPage extends ConsumerWidget {
  const _MacosSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final backends = availableBackends();
    final backendValues = backends.map((b) => b.value).toSet();

    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) => _HeaderedPage(
            header: const _GlassHeader(title: '设置'),
            scrollController: scrollController,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Section(
                    title: '渲染',
                    children: [
                      _SettingRow(
                        label: '图形后端',
                        caption: backendName(settings.backend),
                        control: MacosPopupButton<int>(
                          value: backendValues.contains(settings.backend)
                              ? settings.backend
                              : backends.first.value,
                          items: [
                            for (final b in backends)
                              MacosPopupMenuItem(
                                value: b.value,
                                child: Text(b.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) notifier.setBackend(v);
                          },
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: '运行时',
                    children: [
                      _SettingRow(
                        label: '启动 OS',
                        caption: '选择 system.ini 使用的启动段',
                        control: MacosPopupButton<String>(
                          value: settings.runtimePlatform,
                          items: [
                            for (final p in runtimePlatforms)
                              MacosPopupMenuItem(value: p, child: Text(p)),
                          ],
                          onChanged: (v) {
                            if (v != null) notifier.setRuntimePlatform(v);
                          },
                        ),
                      ),
                      _SettingRow(
                        label: '文本翻译',
                        caption: settings.translation.mode.label,
                        control: PushButton(
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: () {
                            // 与「第三方许可证」一致用 CupertinoPageRoute，带滑入动画
                            //（原 PageRouteBuilder 未给 transitionsBuilder，无动画）。
                            Navigator.of(context).push(
                              CupertinoPageRoute<void>(
                                builder: (_) =>
                                    const TranslationSettingsScreen(),
                              ),
                            );
                          },
                          child: const Text('配置'),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: '调试',
                    children: [
                      _SettingRow(
                        label: '调试模式',
                        caption: '记录详细日志',
                        control: MacosSwitch(
                          value: settings.debugMode,
                          onChanged: notifier.setDebugMode,
                        ),
                      ),
                      _SettingRow(
                        label: '调试面板',
                        caption: '显示浮动监控面板',
                        control: MacosSwitch(
                          value: settings.debugOverlay,
                          onChanged: notifier.setDebugOverlay,
                        ),
                      ),
                      _SettingRow(
                        label: '日志',
                        caption: '导出当前会话日志到文件',
                        control: PushButton(
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: () async {
                            final file = await Log.exportToFile();
                            if (context.mounted) {
                              notify(context, '已导出: ${file.path}');
                            }
                          },
                          child: const Text('导出日志文件'),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: '显示',
                    children: [
                      _SettingRow(
                        label: '显示帧率',
                        control: MacosSwitch(
                          value: settings.showFps,
                          onChanged: notifier.setShowFps,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// macOS 系统设置风格的分组卡片。
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              title,
              style: theme.typography.subheadline.copyWith(
                fontWeight: FontWeight.w600,
                color: MacosColors.systemGrayColor,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0x1AFFFFFF) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: dark ? const Color(0x26FFFFFF) : const Color(0x1A000000),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 14),
                      color: dark
                          ? const Color(0x26FFFFFF)
                          : const Color(0x1A000000),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String? caption;
  final Widget control;

  const _SettingRow({required this.label, this.caption, required this.control});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.typography.body),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: theme.typography.caption1.copyWith(
                      color: MacosColors.systemGrayColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

// ── 关于 ──────────────────────────────────────────────────────

class _MacosAboutPage extends StatelessWidget {
  const _MacosAboutPage();

  static const _appRepository = 'https://github.com/Alphaly2K/art3m1s';
  static const _coreRepository = 'https://github.com/Alphaly2K/art3m1s-core';

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) => _HeaderedPage(
            header: const _GlassHeader(title: '关于'),
            scrollController: scrollController,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Art3m1s', style: theme.typography.title1),
                          Text(
                            'Artemis 视觉小说引擎前端 · 版本 ${AppInfo.displayVersion} · AGPL-3.0',
                            style: theme.typography.caption1.copyWith(
                              color: MacosColors.systemGrayColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Section(
                    title: '仓库',
                    children: [
                      _RepoRow(label: 'Flutter App', url: _appRepository),
                      _RepoRow(label: 'Rust Core', url: _coreRepository),
                    ],
                  ),
                  _Section(
                    title: '许可证',
                    children: [
                      _SettingRow(
                        label: '第三方许可证',
                        caption: '查看 Flutter 与依赖包许可证',
                        control: PushButton(
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute<void>(
                                builder: (_) => const MacosLicensesPage(),
                              ),
                            );
                          },
                          child: const Text('查看'),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: '主要依赖',
                    children: [
                      _SettingRow(
                        label: 'Flutter',
                        caption:
                            'flutter_riverpod · path_provider · shared_preferences · ffi · '
                            'file_selector · audioplayers · media_kit · macos_ui',
                        control: const SizedBox.shrink(),
                      ),
                      _SettingRow(
                        label: 'Rust / Native',
                        caption:
                            'art3m1s-core · asb-interpreter · pfs-upk-rust · mlua/Lua 5.1 · '
                            'glow · image · encoding_rs · jis0208 · MetalANGLE',
                        control: const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RepoRow extends StatelessWidget {
  final String label;
  final String url;

  const _RepoRow({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final dark = MacosTheme.of(context).brightness == Brightness.dark;
    return _SettingRow(
      label: label,
      caption: url,
      // MacosIconButton 默认蓝底（activeBlue），在深色页面上是个突兀的蓝方块且图标
      // 对比不足。改透明底 + 显式自适应图标色，作纯图标复制按钮。
      control: MacosIconButton(
        backgroundColor: MacosColors.transparent,
        icon: MacosIcon(
          CupertinoIcons.doc_on_doc,
          size: 16,
          color: dark ? const Color(0xFFE4E4E7) : const Color(0xFF1D1D1F),
        ),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) notify(context, '已复制');
        },
      ),
    );
  }
}

/// Finder 风格页头：纯文字大标题 + 可选尾部控件。
class _GlassHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _GlassHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    // 固定行高：无论有无尾部控件（30px 圆钮），标题垂直位置保持一致。
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Text(
            title,
            style: theme.typography.title2.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 页头 + 内缩滚动条的标准页面骨架（设置/关于等非网格页共用）。
class _HeaderedPage extends StatelessWidget {
  final Widget header;
  final ScrollController scrollController;
  final Widget child;

  const _HeaderedPage({
    required this.header,
    required this.scrollController,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: header,
        ),
        Expanded(
          child: InsetScrollbar(
            controller: scrollController,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
