import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/feedback.dart';
import '../controllers/library_actions.dart';
import '../models/game_entry.dart';
import '../models/render_backend.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/app_info.dart';
import '../services/logger.dart';
import '../screens/translation_settings_screen.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/game_grid.dart';
import '../widgets/license_data.dart';

/// Windows 壳：fluent_ui（WinUI 风格 NavigationView + Fluent 控件）。
class FluentShellApp extends StatelessWidget {
  const FluentShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Art3m1s',
      debugShowCheckedModeBanner: false,
      theme: FluentThemeData(
        brightness: Brightness.light,
        accentColor: Colors.purple,
      ),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.purple,
      ),
      themeMode: ThemeMode.system,
      // PlayerScreen 及其对话框是 Material 组件，需要这些 delegates。
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: const DebugOverlayHost(child: _FluentHome()),
    );
  }
}

class _FluentHome extends StatefulWidget {
  const _FluentHome();

  @override
  State<_FluentHome> createState() => _FluentHomeState();
}

class _FluentHomeState extends State<_FluentHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      titleBar: const TitleBar(title: Text('Art3m1s')),
      pane: NavigationPane(
        selected: _index,
        onChanged: (i) => setState(() => _index = i),
        displayMode: PaneDisplayMode.auto,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.library),
            title: const Text('资料库'),
            body: const _FluentLibraryPage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('设置'),
            body: const _FluentSettingsPage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.info),
            title: const Text('关于'),
            body: const _FluentAboutPage(),
          ),
        ],
      ),
    );
  }
}

// ── 资料库 ────────────────────────────────────────────────────

class _FluentLibraryPage extends ConsumerWidget {
  const _FluentLibraryPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final actions = LibraryActions(context, ref);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('资料库'),
        commandBar: DropDownButton(
          leading: const Icon(FluentIcons.add),
          title: const Text('添加项目'),
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.folder_open),
              text: const Text('选择文件夹…'),
              onPressed: actions.pickDirectory,
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.archive),
              text: const Text('选择 PFS 归档…'),
              onPressed: actions.pickPfs,
            ),
          ],
        ),
      ),
      content: sorted.isEmpty
          ? LibraryEmptyState(
              action: FilledButton(
                onPressed: actions.pickDirectory,
                child: const Text('添加项目'),
              ),
            )
          : GameGrid(
              games: sorted,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              onOpen: actions.launch,
              onEdit: actions.editGame,
              onDelete: actions.confirmDelete,
            ),
    );
  }
}

// ── 设置 ──────────────────────────────────────────────────────

class _FluentSettingsPage extends ConsumerWidget {
  const _FluentSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final backends = availableBackends();
    final backendValues = backends.map((b) => b.value).toSet();

    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('设置')),
      children: [
        _FluentSection(
          title: '渲染',
          children: [
            _FluentSettingRow(
              label: '图形后端',
              caption: backendName(settings.backend),
              control: ComboBox<int>(
                value: backendValues.contains(settings.backend)
                    ? settings.backend
                    : backends.first.value,
                items: [
                  for (final b in backends)
                    ComboBoxItem(value: b.value, child: Text(b.label)),
                ],
                onChanged: (v) {
                  if (v != null) notifier.setBackend(v);
                },
              ),
            ),
          ],
        ),
        _FluentSection(
          title: '运行时',
          children: [
            _FluentSettingRow(
              label: '启动 OS',
              caption: '选择 system.ini 使用的启动段',
              control: ComboBox<String>(
                value: settings.runtimePlatform,
                items: [
                  for (final p in runtimePlatforms)
                    ComboBoxItem(value: p, child: Text(p)),
                ],
                onChanged: (v) {
                  if (v != null) notifier.setRuntimePlatform(v);
                },
              ),
            ),
            _FluentSettingRow(
              label: '文本翻译',
              caption: settings.translation.mode.label,
              control: Button(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) =>
                          const TranslationSettingsScreen(),
                    ),
                  );
                },
                child: const Text('配置'),
              ),
            ),
          ],
        ),
        _FluentSection(
          title: '调试',
          children: [
            _FluentSettingRow(
              label: '调试模式',
              caption: '记录详细日志',
              control: ToggleSwitch(
                checked: settings.debugMode,
                onChanged: notifier.setDebugMode,
              ),
            ),
            _FluentSettingRow(
              label: '脏区着色',
              caption: '标记实际重绘区域',
              control: ToggleSwitch(
                checked: settings.damageVisualization,
                onChanged: settings.debugMode
                    ? notifier.setDamageVisualization
                    : null,
              ),
            ),
            _FluentSettingRow(
              label: 'Profiler 浮层',
              caption: '显示分阶段耗时与内存统计',
              control: ToggleSwitch(
                checked: settings.profilerOverlay,
                onChanged: settings.debugMode
                    ? notifier.setProfilerOverlay
                    : null,
              ),
            ),
            _FluentSettingRow(
              label: '调试面板',
              caption: '显示浮动监控面板',
              control: ToggleSwitch(
                checked: settings.debugOverlay,
                onChanged: notifier.setDebugOverlay,
              ),
            ),
            _FluentSettingRow(
              label: '日志',
              caption: '导出当前会话日志到文件',
              control: Button(
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
        _FluentSection(
          title: '显示',
          children: [
            _FluentSettingRow(
              label: '显示帧率',
              control: ToggleSwitch(
                checked: settings.showFps,
                onChanged: notifier.setShowFps,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FluentSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FluentSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(title, style: theme.typography.bodyStrong),
          ),
          Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(),
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

class _FluentSettingRow extends StatelessWidget {
  final String label;
  final String? caption;
  final Widget control;

  const _FluentSettingRow({
    required this.label,
    this.caption,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
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

class _FluentAboutPage extends StatelessWidget {
  const _FluentAboutPage();

  static const _appRepository = 'https://github.com/Alphaly2K/art3m1s';
  static const _coreRepository = 'https://github.com/Alphaly2K/art3m1s-core';

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('关于')),
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
                Text('Art3m1s', style: theme.typography.subtitle),
                Text(
                  'Artemis 视觉小说引擎前端 · 版本 ${AppInfo.displayVersion} · AGPL-3.0',
                  style: theme.typography.caption?.copyWith(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _FluentSection(
          title: '仓库',
          children: [
            _FluentRepoRow(label: 'Flutter App', url: _appRepository),
            _FluentRepoRow(label: 'Rust Core', url: _coreRepository),
          ],
        ),
        _FluentSection(
          title: '许可证',
          children: [
            _FluentSettingRow(
              label: '第三方许可证',
              caption: '查看 Flutter 与依赖包许可证',
              control: Button(
                onPressed: () {
                  Navigator.of(context).push(
                    FluentPageRoute<void>(
                      builder: (_) => const _FluentLicensesPage(),
                    ),
                  );
                },
                child: const Text('查看'),
              ),
            ),
          ],
        ),
        _FluentSection(
          title: '主要依赖',
          children: const [
            _FluentSettingRow(
              label: 'Flutter',
              caption:
                  'flutter_riverpod · path_provider · shared_preferences · ffi · '
                  'file_selector · audioplayers · media_kit · fluent_ui',
              control: SizedBox.shrink(),
            ),
            _FluentSettingRow(
              label: 'Rust / Native',
              caption:
                  'art3m1s-core · asb-interpreter · pfs-upk-rust · mlua/Lua 5.1 · '
                  'glow · image · encoding_rs · jis0208 · ANGLE',
              control: SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
  }
}

class _FluentRepoRow extends StatelessWidget {
  final String label;
  final String url;

  const _FluentRepoRow({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return _FluentSettingRow(
      label: label,
      caption: url,
      control: IconButton(
        icon: const Icon(FluentIcons.copy, size: 16),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) notify(context, '已复制');
        },
      ),
    );
  }
}

// ── 第三方许可证 ──────────────────────────────────────────────

class _FluentLicensesPage extends StatefulWidget {
  const _FluentLicensesPage();

  @override
  State<_FluentLicensesPage> createState() => _FluentLicensesPageState();
}

class _FluentLicensesPageState extends State<_FluentLicensesPage> {
  late final Future<List<PackageLicenses>> _licenses = collectLicenses();

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      titleBar: TitleBar(
        title: const Text('第三方许可证'),
        onBackRequested: () => Navigator.of(context).pop(),
      ),
      content: FutureBuilder<List<PackageLicenses>>(
        future: _licenses,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: ProgressRing());
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: data.length,
            itemBuilder: (context, index) {
              final item = data[index];
              return ListTile.selectable(
                title: Text(item.package),
                subtitle: Text('${item.licenses.length} 条许可证'),
                trailing: const Icon(FluentIcons.chevron_right, size: 12),
                onPressed: () {
                  Navigator.of(context).push(
                    FluentPageRoute<void>(
                      builder: (_) => _FluentLicenseDetailPage(item: item),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _FluentLicenseDetailPage extends StatelessWidget {
  final PackageLicenses item;

  const _FluentLicenseDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return NavigationView(
      titleBar: TitleBar(
        title: Text(item.package),
        onBackRequested: () => Navigator.of(context).pop(),
      ),
      content: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        itemCount: item.licenses.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: SelectableText(
            licenseText(item.licenses[index]),
            style: theme.typography.body?.copyWith(height: 1.45),
          ),
        ),
      ),
    );
  }
}
