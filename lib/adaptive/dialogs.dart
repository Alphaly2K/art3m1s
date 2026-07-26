import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// 编辑对话框的结果。
class GameEditData {
  final String name;
  final String? coverPath;

  const GameEditData({required this.name, this.coverPath});
}

/// 平台自适应的确认框。返回 true 表示用户确认。
Future<bool> showAdaptiveConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  bool? result;
  if (Platform.isMacOS) {
    result = await showMacosAlertDialog<bool>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.exclamationmark_circle,
          size: 56,
          color: MacosColors.systemOrangeColor,
        ),
        title: Text(title),
        message: Text(message, textAlign: TextAlign.center),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
      ),
    );
  } else if (Platform.isWindows) {
    result = await fluent.showDialog<bool>(
      context: context,
      builder: (ctx) => fluent.ContentDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            style: destructive
                ? fluent.ButtonStyle(
                    backgroundColor: fluent.WidgetStatePropertyAll(
                      fluent.Colors.red,
                    ),
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  } else if (Platform.isIOS) {
    result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  } else {
    result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
  return result ?? false;
}

Future<String?> _pickCoverFile() async {
  const typeGroup = XTypeGroup(
    label: '图片',
    extensions: ['png', 'jpg', 'jpeg', 'bmp'],
  );
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  return file?.path;
}

/// 平台自适应的「添加/编辑项目」对话框：名称 + 可选封面。
Future<GameEditData?> showGameEditDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  String? initialCoverPath,
}) {
  if (Platform.isMacOS) {
    return showMacosAlertDialog<GameEditData>(
      context: context,
      builder: (ctx) => _MacosEditDialog(
        title: title,
        initialName: initialName,
        initialCover: initialCoverPath,
      ),
    );
  }
  if (Platform.isWindows) {
    return fluent.showDialog<GameEditData>(
      context: context,
      builder: (ctx) => _FluentEditDialog(
        title: title,
        initialName: initialName,
        initialCover: initialCoverPath,
      ),
    );
  }
  if (Platform.isIOS) {
    return showCupertinoDialog<GameEditData>(
      context: context,
      builder: (ctx) => _CupertinoEditDialog(
        title: title,
        initialName: initialName,
        initialCover: initialCoverPath,
      ),
    );
  }
  return showDialog<GameEditData>(
    context: context,
    builder: (ctx) => _MaterialEditDialog(
      title: title,
      initialName: initialName,
      initialCover: initialCoverPath,
    ),
  );
}

// ── macOS ──────────────────────────────────────────────────────

class _MacosEditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? initialCover;

  const _MacosEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
  });

  @override
  State<_MacosEditDialog> createState() => _MacosEditDialogState();
}

class _MacosEditDialogState extends State<_MacosEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  String? _cover;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MacosAlertDialog(
      appIcon: const MacosIcon(
        CupertinoIcons.game_controller,
        size: 56,
        color: MacosColors.systemPurpleColor,
      ),
      title: Text(widget.title),
      message: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MacosTextField(
            controller: _name,
            placeholder: '游戏名称',
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CoverThumb(path: _cover, size: 44),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () async {
                  final path = await _pickCoverFile();
                  if (path != null) setState(() => _cover = path);
                },
                child: Text(_cover != null ? '更换封面' : '选择封面'),
              ),
              if (_cover != null) ...[
                const SizedBox(width: 6),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: () => setState(() => _cover = null),
                  child: const Text('清除'),
                ),
              ],
            ],
          ),
        ],
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.of(context).pop(
          GameEditData(name: _name.text.trim(), coverPath: _cover),
        ),
        child: const Text('保存'),
      ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    );
  }
}

// ── iOS ────────────────────────────────────────────────────────

class _CupertinoEditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? initialCover;

  const _CupertinoEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
  });

  @override
  State<_CupertinoEditDialog> createState() => _CupertinoEditDialogState();
}

class _CupertinoEditDialogState extends State<_CupertinoEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  String? _cover;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _name,
            placeholder: '游戏名称',
            autofocus: true,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CoverThumb(path: _cover, size: 40),
              CupertinoButton(
                sizeStyle: CupertinoButtonSize.small,
                onPressed: () async {
                  final path = await _pickCoverFile();
                  if (path != null) setState(() => _cover = path);
                },
                child: Text(_cover != null ? '更换封面' : '选择封面'),
              ),
              if (_cover != null)
                CupertinoButton(
                  sizeStyle: CupertinoButtonSize.small,
                  onPressed: () => setState(() => _cover = null),
                  child: const Text('清除'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(
            GameEditData(name: _name.text.trim(), coverPath: _cover),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// ── Material ───────────────────────────────────────────────────

class _MaterialEditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? initialCover;

  const _MaterialEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
  });

  @override
  State<_MaterialEditDialog> createState() => _MaterialEditDialogState();
}

class _MaterialEditDialogState extends State<_MaterialEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  String? _cover;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
  }

  @override
  void dispose() {
    _name.dispose();
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
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '游戏名称',
              hintText: '输入自定义名称',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CoverThumb(path: _cover, size: 56),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () async {
                  final path = await _pickCoverFile();
                  if (path != null) setState(() => _cover = path);
                },
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(_cover != null ? '更换' : '选择封面'),
              ),
              if (_cover != null)
                TextButton(
                  onPressed: () => setState(() => _cover = null),
                  child: const Text('清除'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            GameEditData(name: _name.text.trim(), coverPath: _cover),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final String? path;
  final double size;

  const _CoverThumb({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (path != null && File(path!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path!),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        CupertinoIcons.photo,
        size: size * 0.45,
        color: dark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
      ),
    );
  }
}


// ── Windows (Fluent) ───────────────────────────────────────────

class _FluentEditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? initialCover;

  const _FluentEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
  });

  @override
  State<_FluentEditDialog> createState() => _FluentEditDialogState();
}

class _FluentEditDialogState extends State<_FluentEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  String? _cover;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return fluent.ContentDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fluent.InfoLabel(
            label: '游戏名称',
            child: fluent.TextBox(
              controller: _name,
              placeholder: '输入自定义名称',
              autofocus: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CoverThumb(path: _cover, size: 48),
              const SizedBox(width: 10),
              fluent.Button(
                onPressed: () async {
                  final path = await _pickCoverFile();
                  if (path != null) setState(() => _cover = path);
                },
                child: Text(_cover != null ? '更换封面' : '选择封面'),
              ),
              if (_cover != null) ...[
                const SizedBox(width: 6),
                fluent.Button(
                  onPressed: () => setState(() => _cover = null),
                  child: const Text('清除'),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        fluent.Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        fluent.FilledButton(
          onPressed: () => Navigator.of(context).pop(
            GameEditData(name: _name.text.trim(), coverPath: _cover),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
