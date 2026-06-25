import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_entry.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/game_importer.dart';
import '../services/logger.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  OverlayEntry? _debugEntry;

  @override
  void initState() {
    super.initState();
    Log.bind(_onToggle);
  }

  void _onToggle() {
    if (Log.overlayVisible) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_debugEntry != null) return;
    final overlay = Overlay.of(context);
    _debugEntry = OverlayEntry(builder: (_) => const DebugOverlay());
    overlay.insert(_debugEntry!);
  }

  void _hideOverlay() {
    _debugEntry?.remove();
    _debugEntry = null;
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debug = ref.watch(settingsProvider.select((s) => s.debugMode));
    if (debug && _debugEntry == null) {
      Log.overlayVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
    } else if (!debug && _debugEntry != null) {
      Log.overlayVisible = false;
      _hideOverlay();
    }
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Art3m1s'),
        actions: [
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
      body: sorted.isEmpty ? _buildEmpty() : _buildGrid(sorted),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProject,
        icon: const Icon(Icons.add),
        label: const Text('添加项目'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videogame_asset_outlined, size: 80,
              color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('库中暂无项目', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('点击下方按钮添加游戏',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
                  )),
        ],
      ),
    );
  }

  Widget _buildGrid(List<GameEntry> games) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: games.length,
        itemBuilder: (_, index) => GameCard(
          entry: games[index],
          onTap: () => _launch(games[index]),
          onEdit: () => _editGame(games[index]),
          onDelete: () => _confirmDelete(games[index]),
        ),
      ),
    );
  }

  void _addProject() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('添加项目',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('选择文件夹'),
                subtitle: const Text('已解包的工程目录（含 system.ini）'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickDirectory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive),
                title: const Text('选择 PFS 归档'),
                subtitle: const Text('直接读取，不写入磁盘'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickPfs();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDirectory() async {
    final path = await getDirectoryPath(confirmButtonText: '选择此目录');
    if (path == null || !mounted) return;

    if (!File('$path${Platform.pathSeparator}system.ini').existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选目录中没有 system.ini')),
        );
      }
      return;
    }

    final name = path.split(Platform.pathSeparator).last;
    _editAndAdd(name, path, GameSource.directory);
  }

  Future<void> _pickPfs() async {
    String? filePath;
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动平台：通过原生 SAF 选目录，拷贝整个目录（含分卷）到沙箱。
      // 避免 file_selector 在 Android 上返回无法用 dart:io 访问的 content URI。
      if (Platform.isAndroid) {
        final sandboxDir = await GameImporter.pickDirectoryAndCopy();
        if (sandboxDir == null || !mounted) return;
        // 在沙箱里找 base .pfs 文件。
        final pfsFile = Directory(sandboxDir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pfs'))
            .where((f) => !RegExp(r'\.pfs\.\d{3}$', caseSensitive: false).hasMatch(f.path))
            .firstOrNull;
        if (pfsFile == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('所选目录中没有 .pfs 文件')),
            );
          }
          return;
        }
        filePath = pfsFile.path;
      } else {
        // iOS：flutter_file_dialog 给的路径可用，但分卷可能在别的目录。
        // 先回退到目录选择。
        final dirPath = await getDirectoryPath(confirmButtonText: '选择 PFS 所在目录');
        if (dirPath == null || !mounted) return;
        final pfsFile = Directory(dirPath)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pfs'))
            .where((f) => !RegExp(r'\.pfs\.\d{3}$', caseSensitive: false).hasMatch(f.path))
            .firstOrNull;
        if (pfsFile == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('所选目录中没有 .pfs 文件')),
            );
          }
          return;
        }
        filePath = pfsFile.path;
      }
    } else {
      const typeGroup = XTypeGroup(label: 'PFS 归档', extensions: ['pfs', 'PFS']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      filePath = file?.path;
    }
    if (filePath == null || !mounted) return;

    final name = filePath
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.pfs$', caseSensitive: false), '');

    _editAndAdd(name, filePath, GameSource.pfsArchive);
  }

  void _editAndAdd(String defaultName, String path, GameSource source) {
    _showEditDialog(
      title: '添加项目',
      initialName: defaultName,
      onSave: (name, coverPath) {
        ref.read(libraryProvider.notifier).add(GameEntry(
          name: defaultName,
          path: path,
          source: source,
          addedAt: DateTime.now(),
          displayName: name.isNotEmpty ? name : null,
          coverPath: coverPath,
        ));
        Log.info('已添加: ${name.isNotEmpty ? name : defaultName}');
      },
    );
  }

  void _editGame(GameEntry entry) {
    _showEditDialog(
      title: '编辑项目',
      initialName: entry.displayNameOrName,
      initialCover: entry.coverPath,
      onSave: (name, coverPath) {
        ref.read(libraryProvider.notifier).update(
          entry.path,
          displayName: name.isNotEmpty ? name : null,
          coverPath: coverPath,
        );
      },
    );
  }

  void _showEditDialog({
    required String title,
    required String initialName,
    String? initialCover,
    required void Function(String name, String? coverPath) onSave,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _EditDialog(
        title: title,
        initialName: initialName,
        initialCover: initialCover ?? '',
        onSave: onSave,
      ),
    );
  }

  void _launch(GameEntry entry) {
    ref.read(libraryProvider.notifier).markPlayed(entry.path);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          projectPath: entry.path,
          source: entry.source,
        ),
      ),
    );
  }

  void _confirmDelete(GameEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除项目'),
        content: Text('确定从库中移除「${entry.displayNameOrName}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              ref.read(libraryProvider.notifier).remove(entry.path);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }
}

class GameCard extends StatelessWidget {
  final GameEntry entry;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const GameCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: _buildCover(context)),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.displayNameOrName, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          entry.source == GameSource.pfsArchive
                              ? Icons.archive : Icons.folder_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.source == GameSource.pfsArchive ? 'PFS' : '目录',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: onEdit,
                          child: Icon(Icons.edit, size: 14,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onDelete,
                          child: Icon(Icons.close, size: 16,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    if (entry.coverPath != null && File(entry.coverPath!).existsSync()) {
      return Image.file(File(entry.coverPath!), fit: BoxFit.cover);
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          entry.source == GameSource.pfsArchive ? Icons.archive : Icons.folder_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _EditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialCover;
  final void Function(String name, String? coverPath) onSave;

  const _EditDialog({
    required this.title,
    required this.initialName,
    required this.initialCover,
    required this.onSave,
  });

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _nameCtrl;
  String? _coverPath;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _coverPath = widget.initialCover.isNotEmpty ? widget.initialCover : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '游戏名称', hintText: '输入自定义名称'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_coverPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(_coverPath!), width: 64, height: 64, fit: BoxFit.cover),
                )
              else
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, size: 32),
                ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _pickCover,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(_coverPath != null ? '更换' : '选择封面'),
              ),
              if (_coverPath != null)
                TextButton(
                  onPressed: () => setState(() => _coverPath = null),
                  child: const Text('清除'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_nameCtrl.text.trim(), _coverPath);
            Navigator.of(context).pop();
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _pickCover() async {
    const typeGroup = XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'bmp']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      setState(() => _coverPath = file.path);
    }
  }
}
