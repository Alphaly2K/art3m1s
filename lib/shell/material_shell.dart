import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../adaptive/feedback.dart';
import '../controllers/library_actions.dart';
import '../models/game_entry.dart';
import '../providers/library_provider.dart';
import '../screens/about_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/game_grid.dart';

/// Material 壳（Android / Linux）：Material 3，跟随系统亮暗。
/// Linux 上套 yaru 主题贴近 GNOME/Ubuntu 原生观感。
class MaterialShellApp extends StatelessWidget {
  const MaterialShellApp({super.key, this.onEnterBigScreen});

  final Future<bool> Function()? onEnterBigScreen;

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return YaruTheme(
        builder: (context, yaru, child) => MaterialApp(
          title: 'Art3m1s',
          debugShowCheckedModeBanner: false,
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          themeMode: ThemeMode.system,
          home: DebugOverlayHost(
            child: _MaterialLibraryScreen(onEnterBigScreen: onEnterBigScreen),
          ),
        ),
      );
    }
    return MaterialApp(
      title: 'Art3m1s',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: DebugOverlayHost(
        child: Platform.isAndroid
            ? const _MaterialHome()
            : _MaterialLibraryScreen(onEnterBigScreen: onEnterBigScreen),
      ),
    );
  }
}

void _pickGameFolder(BuildContext context, LibraryActions actions) {
  actions.pickDirectory();
}

class _MaterialHome extends ConsumerStatefulWidget {
  const _MaterialHome();

  @override
  ConsumerState<_MaterialHome> createState() => _MaterialHomeState();
}

class _MaterialHomeState extends ConsumerState<_MaterialHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    const titles = ['Art3m1s', '设置', '关于'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab == 0)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '扫描游戏文件夹',
              onPressed: () =>
                  _pickGameFolder(context, LibraryActions(context, ref)),
            ),
        ],
      ),
      body: switch (_tab) {
        0 => const _MaterialLibraryBody(),
        1 => const SettingsScreen(embedded: true),
        _ => const AboutScreen(embedded: true),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '资料库',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: '关于',
          ),
        ],
      ),
    );
  }
}

class _MaterialLibraryBody extends ConsumerWidget {
  const _MaterialLibraryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final actions = LibraryActions(context, ref);
    if (sorted.isEmpty) {
      return LibraryEmptyState(
        action: FilledButton.icon(
          onPressed: () => _pickGameFolder(context, actions),
          icon: const Icon(Icons.add),
          label: const Text('扫描游戏文件夹'),
        ),
      );
    }
    return GameGrid(
      games: sorted,
      onOpen: actions.launch,
      onEdit: actions.editGame,
      onDelete: actions.confirmDelete,
    );
  }
}

class _MaterialLibraryScreen extends ConsumerWidget {
  const _MaterialLibraryScreen({this.onEnterBigScreen});

  final Future<bool> Function()? onEnterBigScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final actions = LibraryActions(context, ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Art3m1s'),
        actions: [
          if (onEnterBigScreen != null)
            IconButton(
              icon: const Icon(Icons.fullscreen_rounded),
              tooltip: '进入大屏模式',
              onPressed: () async {
                final entered = await onEnterBigScreen!();
                if (!context.mounted || entered) return;
                notify(context, '大屏模式需要窗口处于全屏状态');
              },
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '扫描游戏文件夹',
            onPressed: () => _pickGameFolder(context, actions),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: sorted.isEmpty
          ? LibraryEmptyState(
              action: FilledButton.icon(
                onPressed: actions.pickDirectory,
                icon: const Icon(Icons.add),
                label: const Text('添加项目'),
              ),
            )
          : GameGrid(
              games: sorted,
              onOpen: actions.launch,
              onEdit: actions.editGame,
              onDelete: actions.confirmDelete,
            ),
    );
  }
}
