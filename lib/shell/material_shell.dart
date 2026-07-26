import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../controllers/library_actions.dart';
import '../models/game_entry.dart';
import '../providers/library_provider.dart';
import '../screens/settings_screen.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/game_grid.dart';

/// Material 壳（Android / Linux）：Material 3，跟随系统亮暗。
/// Linux 上套 yaru 主题贴近 GNOME/Ubuntu 原生观感。
class MaterialShellApp extends StatelessWidget {
  const MaterialShellApp({super.key});

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
          home: const DebugOverlayHost(child: _MaterialLibraryScreen()),
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
      home: const DebugOverlayHost(child: _MaterialLibraryScreen()),
    );
  }
}

class _MaterialLibraryScreen extends ConsumerWidget {
  const _MaterialLibraryScreen();

  void _showAddMenuMobile(BuildContext context, LibraryActions actions) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('选择文件夹'),
              subtitle: const Text('已解包的工程目录（含 system.ini）'),
              onTap: () {
                Navigator.of(ctx).pop();
                actions.pickDirectory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive),
              title: const Text('选择 PFS 归档'),
              subtitle: const Text('直接读取，不写入磁盘'),
              onTap: () {
                Navigator.of(ctx).pop();
                actions.pickPfs();
              },
            ),
            const SizedBox(height: 8),
          ],
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
    final mobile = Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Art3m1s'),
        actions: [
          if (mobile)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '添加项目',
              onPressed: () => _showAddMenuMobile(context, actions),
            )
          else
            PopupMenuButton<int>(
              icon: const Icon(Icons.add),
              tooltip: '添加项目',
              onSelected: (v) {
                if (v == 0) actions.pickDirectory();
                if (v == 1) actions.pickPfs();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 0,
                  child: ListTile(
                    leading: Icon(Icons.folder_open),
                    title: Text('选择文件夹…'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 1,
                  child: ListTile(
                    leading: Icon(Icons.archive),
                    title: Text('选择 PFS 归档…'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: sorted.isEmpty
          ? LibraryEmptyState(
              action: FilledButton.icon(
                onPressed: () => mobile
                    ? _showAddMenuMobile(context, actions)
                    : actions.pickDirectory(),
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
