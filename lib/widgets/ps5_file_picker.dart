import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adaptive/ps5_chrome.dart';
import '../controllers/ps5_input.dart';

enum Ps5FilePickerMode { directory, file }

class Ps5FilePickerOptions {
  const Ps5FilePickerOptions({
    required this.mode,
    required this.title,
    this.initialDirectory,
    this.allowedExtensions = const {},
    this.confirmLabel,
  });

  final Ps5FilePickerMode mode;
  final String title;
  final String? initialDirectory;
  final Set<String> allowedExtensions;
  final String? confirmLabel;
}

Future<String?> showPs5FilePicker(
  BuildContext context, {
  required Ps5FilePickerMode mode,
  required String title,
  String? initialDirectory,
  Set<String> allowedExtensions = const {},
  String? confirmLabel,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '关闭文件浏览器',
    barrierColor: const Color(0xB8000000),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Ps5FilePickerDialog(
        options: Ps5FilePickerOptions(
          mode: mode,
          title: title,
          initialDirectory: initialDirectory,
          allowedExtensions: allowedExtensions
              .map((extension) => extension.toLowerCase())
              .toSet(),
          confirmLabel: confirmLabel,
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.975, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class Ps5FilePickerDialog extends StatefulWidget {
  const Ps5FilePickerDialog({super.key, required this.options});

  final Ps5FilePickerOptions options;

  @override
  State<Ps5FilePickerDialog> createState() => _Ps5FilePickerDialogState();
}

class _Ps5FilePickerDialogState extends State<Ps5FilePickerDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'PS5 file picker');
  final ScrollController _scrollController = ScrollController();
  late final List<Directory> _roots;
  List<_FileEntry> _entries = const [];
  String _currentPath = '';
  String? _selectedPath;
  String? _error;
  bool _busy = true;
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    _roots = _pickableRoots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _open(_initialPath());
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _initialPath() {
    final configured = widget.options.initialDirectory?.trim();
    if (configured != null && configured.isNotEmpty) {
      final type = FileSystemEntity.typeSync(configured, followLinks: false);
      if (type == FileSystemEntityType.directory) return configured;
      if (type == FileSystemEntityType.file) {
        return File(configured).parent.path;
      }
    }
    if (_roots.isNotEmpty) return _roots.first.path;
    return Directory.current.path;
  }

  Future<void> _open(String path) async {
    final directory = Directory(path);
    setState(() {
      _busy = true;
      _error = null;
      _selectedPath = null;
    });
    try {
      final entities = await directory.list(followLinks: false).toList();
      final entries = <_FileEntry>[];
      for (final entity in entities) {
        final basename = _basename(entity.path);
        if (!_showHidden && basename.startsWith('.')) continue;
        final isDirectory = entity is Directory;
        if (!isDirectory &&
            widget.options.mode == Ps5FilePickerMode.file &&
            !_matchesExtension(basename)) {
          continue;
        }
        entries.add(
          _FileEntry(
            name: basename,
            path: entity.path,
            isDirectory: isDirectory,
          ),
        );
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _currentPath = directory.path;
        _entries = entries;
        _busy = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '无法读取此文件夹：${error.message}';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '无法读取此文件夹：$error';
        _busy = false;
      });
    }
    _focusNode.requestFocus();
  }

  bool _matchesExtension(String name) {
    if (widget.options.allowedExtensions.isEmpty) return true;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return false;
    return widget.options.allowedExtensions.contains(
      name.substring(dot + 1).toLowerCase(),
    );
  }

  List<Directory> _pickableRoots() {
    final roots = <Directory>[];
    void add(String? path) {
      if (path == null || path.trim().isEmpty) return;
      final directory = Directory(path);
      if (!directory.existsSync()) return;
      if (roots.any(
        (root) => root.path.toLowerCase() == directory.path.toLowerCase(),
      )) {
        return;
      }
      roots.add(directory);
    }

    if (Platform.isWindows) {
      for (var code = 'A'.codeUnitAt(0); code <= 'Z'.codeUnitAt(0); code++) {
        final path = '${String.fromCharCode(code)}:\\';
        if (Directory(path).existsSync()) add(path);
      }
      add(Platform.environment['USERPROFILE']);
    } else {
      add(Platform.environment['HOME']);
      add('/Volumes');
      add('/');
    }
    return roots;
  }

  Future<void> _activate(_FileEntry entry) async {
    if (entry.isDirectory) {
      await _open(entry.path);
      return;
    }
    setState(() => _selectedPath = entry.path);
    _accept(entry.path);
  }

  void _accept([String? path]) {
    final selected =
        path ??
        _selectedPath ??
        (widget.options.mode == Ps5FilePickerMode.directory
            ? _currentPath
            : null);
    if (selected == null) return;
    if (widget.options.mode == Ps5FilePickerMode.file &&
        FileSystemEntity.isDirectorySync(selected)) {
      return;
    }
    Navigator.of(context).pop(selected);
  }

  void _goUp() {
    final parent = Directory(_currentPath).parent;
    if (parent.path != _currentPath) {
      _open(parent.path);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final action = ps5InputAction(event.logicalKey);
    if (action == Ps5InputAction.back) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      _goUp();
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.accept) {
      if (_selectedPath != null ||
          widget.options.mode == Ps5FilePickerMode.directory) {
        _accept();
      }
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.down) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.up) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.previous) {
      _moveSelection(-5);
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.next) {
      _moveSelection(5);
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.left) {
      _goUp();
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.right) {
      final selected = _selectedPath;
      if (selected != null) {
        final entry = _entries
            .where((item) => item.path == selected)
            .firstOrNull;
        if (entry != null) _activate(entry);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSelection(int delta) {
    if (_entries.isEmpty) return;
    final current = _entries.indexWhere((entry) => entry.path == _selectedPath);
    final next = current < 0
        ? (delta > 0 ? 0 : _entries.length - 1)
        : (current + delta).clamp(0, _entries.length - 1);
    setState(() => _selectedPath = _entries[next].path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = (next * 59.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool get _canAccept {
    if (widget.options.mode == Ps5FilePickerMode.directory) return true;
    return _selectedPath != null && FileSystemEntity.isFileSync(_selectedPath!);
  }

  String get _acceptLabel =>
      widget.options.confirmLabel ??
      (widget.options.mode == Ps5FilePickerMode.directory ? '选择当前文件夹' : '选择文件');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 72).clamp(760.0, 1280.0);
    final height = (size.height - 72).clamp(540.0, 820.0);
    return Center(
      child: SizedBox(
        key: const ValueKey('ps5-file-picker'),
        width: width,
        height: height,
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Ps5Panel(
            opaque: true,
            child: Column(
              children: [
                _PickerHeader(
                  title: widget.options.title,
                  currentPath: _currentPath,
                  onClose: () => Navigator.of(context).pop(),
                ),
                const Divider(height: 1, color: Ps5Colors.line),
                Expanded(
                  child: Row(
                    children: [
                      _PickerRoots(
                        roots: _roots,
                        currentPath: _currentPath,
                        onOpen: _open,
                      ),
                      const VerticalDivider(width: 1, color: Ps5Colors.line),
                      Expanded(
                        child: Column(
                          children: [
                            _PickerToolbar(
                              currentPath: _currentPath,
                              showHidden: _showHidden,
                              onUp: _currentPath == '/' ? null : () => _goUp(),
                              onHome: _roots.isEmpty
                                  ? null
                                  : () => _open(_roots.first.path),
                              onToggleHidden: () {
                                setState(() => _showHidden = !_showHidden);
                                _open(_currentPath);
                              },
                              onOpenPath: _open,
                            ),
                            Expanded(child: _buildEntries()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Ps5Colors.line),
                _PickerFooter(
                  selection: _selectedPath,
                  selectionIsDirectory:
                      _selectedPath != null &&
                      FileSystemEntity.isDirectorySync(_selectedPath!),
                  acceptLabel: _acceptLabel,
                  canAccept: _canAccept,
                  onCancel: () => Navigator.of(context).pop(),
                  onAccept: _accept,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntries() {
    if (_busy) {
      return const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Ps5Colors.accent,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Ps5Colors.danger, fontSize: 14),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Text(
          '此文件夹为空',
          style: TextStyle(color: Ps5Colors.textMuted, fontSize: 14),
        ),
      );
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _FileRow(
            entry: entry,
            selected: entry.path == _selectedPath,
            onTap: () => setState(() => _selectedPath = entry.path),
            onActivate: () => _activate(entry),
          );
        },
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({
    required this.title,
    required this.currentPath,
    required this.onClose,
  });

  final String title;
  final String currentPath;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Ps5IconButton(
              icon: Icons.close_rounded,
              tooltip: '关闭',
              onPressed: onClose,
              size: 40,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Ps5Colors.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Ps5Colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRoots extends StatelessWidget {
  const _PickerRoots({
    required this.roots,
    required this.currentPath,
    required this.onOpen,
  });

  final List<Directory> roots;
  final String currentPath;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Text(
              '位置',
              style: TextStyle(
                color: Ps5Colors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          for (final root in roots)
            _RootTile(
              directory: root,
              selected: _sameOrInside(currentPath, root.path),
              onTap: () => onOpen(root.path),
            ),
        ],
      ),
    );
  }

  bool _sameOrInside(String path, String root) {
    final normalizedPath = path.replaceAll('\\', '/').toLowerCase();
    final normalizedRoot = root.replaceAll('\\', '/').toLowerCase();
    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith(
          normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/',
        );
  }
}

class _RootTile extends StatelessWidget {
  const _RootTile({
    required this.directory,
    required this.selected,
    required this.onTap,
  });

  final Directory directory;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _rootDisplayName(directory.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? Ps5Colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          hoverColor: Ps5Colors.panelHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            child: Row(
              children: [
                Icon(
                  _rootIcon(directory.path),
                  color: selected ? Ps5Colors.accent : Ps5Colors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Ps5Colors.accent : Ps5Colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerToolbar extends StatelessWidget {
  const _PickerToolbar({
    required this.currentPath,
    required this.showHidden,
    required this.onUp,
    required this.onHome,
    required this.onToggleHidden,
    required this.onOpenPath,
  });

  final String currentPath;
  final bool showHidden;
  final VoidCallback? onUp;
  final VoidCallback? onHome;
  final VoidCallback onToggleHidden;
  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Ps5IconButton(
              icon: Icons.arrow_upward_rounded,
              tooltip: '上一级',
              onPressed: onUp,
              size: 38,
            ),
            Ps5IconButton(
              icon: Icons.home_rounded,
              tooltip: '主目录',
              onPressed: onHome,
              size: 38,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Breadcrumbs(path: currentPath, onOpen: onOpenPath),
            ),
            Ps5IconButton(
              icon: showHidden
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              tooltip: showHidden ? '隐藏隐藏文件' : '显示隐藏文件',
              selected: showHidden,
              onPressed: onToggleHidden,
              size: 38,
            ),
          ],
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onOpen});

  final String path;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final crumbs = _breadcrumbs(path);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: Ps5Colors.textMuted,
                ),
              ),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              child: InkWell(
                onTap: () => onOpen(crumbs[i].path),
                borderRadius: BorderRadius.circular(5),
                hoverColor: Ps5Colors.accentSoft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  child: Text(
                    crumbs[i].label,
                    style: const TextStyle(
                      color: Ps5Colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onActivate,
  });

  final _FileEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? Ps5Colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onActivate,
          borderRadius: BorderRadius.circular(7),
          hoverColor: Ps5Colors.panelHover,
          child: SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                children: [
                  Icon(
                    entry.isDirectory
                        ? Icons.folder_rounded
                        : _fileIcon(entry.name),
                    color: selected
                        ? Ps5Colors.accent
                        : entry.isDirectory
                        ? const Color(0xFFFFCE5A)
                        : Ps5Colors.textMuted,
                    size: 25,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Ps5Colors.accent : Ps5Colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (entry.isDirectory)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Ps5Colors.textMuted,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerFooter extends StatelessWidget {
  const _PickerFooter({
    required this.selection,
    required this.selectionIsDirectory,
    required this.acceptLabel,
    required this.canAccept,
    required this.onCancel,
    required this.onAccept,
  });

  final String? selection;
  final bool selectionIsDirectory;
  final String acceptLabel;
  final bool canAccept;
  final VoidCallback onCancel;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selection == null
                    ? '选择一个项目'
                    : '${selectionIsDirectory ? '文件夹' : '文件'}  $selection',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Ps5Colors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            Ps5Button(onPressed: onCancel, child: const Text('取消')),
            const SizedBox(width: 10),
            Ps5Button(
              primary: true,
              icon: Icons.check_rounded,
              onPressed: canAccept ? onAccept : null,
              child: Text(acceptLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileEntry {
  const _FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
}

class _Breadcrumb {
  const _Breadcrumb(this.label, this.path);

  final String label;
  final String path;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final slash = trimmed.lastIndexOf('/');
  return slash < 0 ? trimmed : trimmed.substring(slash + 1);
}

String _rootDisplayName(String path) {
  if (path == '/') return '根目录';
  if (Platform.isWindows && RegExp(r'^[A-Za-z]:\\?$').hasMatch(path)) {
    return path.substring(0, 2);
  }
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null &&
      path.replaceAll('\\', '/') == home.replaceAll('\\', '/')) {
    return '主目录';
  }
  final name = _basename(path);
  if (name == 'Volumes') return '磁盘';
  return name.isEmpty ? path : name;
}

IconData _rootIcon(String path) {
  if (path == '/') return Icons.storage_rounded;
  if (path == '/Volumes') return Icons.storage_rounded;
  if (Platform.isWindows && RegExp(r'^[A-Za-z]:\\?$').hasMatch(path)) {
    return Icons.storage_rounded;
  }
  return Icons.home_rounded;
}

IconData _fileIcon(String name) {
  final extension = name.contains('.')
      ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
      : '';
  return switch (extension) {
    'png' || 'jpg' || 'jpeg' || 'bmp' || 'webp' || 'gif' => Icons.image_rounded,
    'json' || 'jsonl' || 'tsv' || 'csv' || 'txt' => Icons.description_rounded,
    'ttf' || 'otf' => Icons.font_download_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

List<_Breadcrumb> _breadcrumbs(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (Platform.isWindows && RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    final result = <_Breadcrumb>[];
    var current = '';
    var first = true;
    for (final part in parts) {
      current = first ? '$part\\' : '$current$part\\';
      result.add(_Breadcrumb(part, current));
      first = false;
    }
    return result;
  }
  final result = <_Breadcrumb>[const _Breadcrumb('/', '/')];
  var current = '';
  for (final part in normalized.split('/').where((part) => part.isNotEmpty)) {
    current = '$current/$part';
    result.add(_Breadcrumb(part, current));
  }
  return result;
}
