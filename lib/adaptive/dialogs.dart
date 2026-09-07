import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../models/input_gate.dart';
import '../models/render_backend.dart';

/// 编辑对话框的结果。
class GameEditData {
  final String name;
  final String? coverPath;
  final bool translationEnabled;
  final String translationPatchPath;
  final bool environmentPatchEnabled;
  final bool experimentalElunaEnabled;

  /// 输入门控策略（环境/平台特化的输入过滤），默认全放行。
  final InputGatePolicy inputGate;

  /// 上报机种串覆盖（空串 = 跟随项目平台）。
  final String reportedOs;

  /// system.ini 启动段；按游戏保存。
  final String runtimePlatform;

  const GameEditData({
    required this.name,
    this.coverPath,
    required this.translationEnabled,
    required this.translationPatchPath,
    required this.environmentPatchEnabled,
    required this.experimentalElunaEnabled,
    this.inputGate = InputGatePolicy.full,
    this.reportedOs = '',
    this.runtimePlatform = 'WINDOWS',
  });
}

/// 「机种上报」可选项：键为上报串（空串 = 跟随平台），值为显示名。
const Map<String, String> reportedOsOptions = {
  '': '默认（跟随平台）',
  'windows': 'Windows',
  'iphone': 'iOS',
  'android': 'Android',
  'webassembly': 'WebAssembly',
  'switch': 'Switch',
  'ps4': 'PS4',
};

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

Future<String?> _pickTranslationPatchFile() async {
  const typeGroup = XTypeGroup(
    label: '翻译对照文件',
    extensions: ['json', 'jsonl', 'tsv'],
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
  bool initialTranslationEnabled = false,
  String initialTranslationPatchPath = '',
  bool initialEnvironmentPatchEnabled = false,
  bool initialExperimentalElunaEnabled = false,
  InputGatePolicy initialInputGate = InputGatePolicy.full,
  String initialReportedOs = '',
  String initialRuntimePlatform = 'WINDOWS',
}) {
  if (Platform.isMacOS) {
    return showMacosAlertDialog<GameEditData>(
      context: context,
      builder: (ctx) => _MacosEditDialog(
        title: title,
        initialName: initialName,
        initialCover: initialCoverPath,
        initialTranslationEnabled: initialTranslationEnabled,
        initialTranslationPatchPath: initialTranslationPatchPath,
        initialEnvironmentPatchEnabled: initialEnvironmentPatchEnabled,
        initialExperimentalElunaEnabled: initialExperimentalElunaEnabled,
        initialInputGate: initialInputGate,
        initialReportedOs: initialReportedOs,
        initialRuntimePlatform: initialRuntimePlatform,
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
        initialTranslationEnabled: initialTranslationEnabled,
        initialTranslationPatchPath: initialTranslationPatchPath,
        initialEnvironmentPatchEnabled: initialEnvironmentPatchEnabled,
        initialExperimentalElunaEnabled: initialExperimentalElunaEnabled,
        initialInputGate: initialInputGate,
        initialReportedOs: initialReportedOs,
        initialRuntimePlatform: initialRuntimePlatform,
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
        initialTranslationEnabled: initialTranslationEnabled,
        initialTranslationPatchPath: initialTranslationPatchPath,
        initialEnvironmentPatchEnabled: initialEnvironmentPatchEnabled,
        initialExperimentalElunaEnabled: initialExperimentalElunaEnabled,
        initialInputGate: initialInputGate,
        initialReportedOs: initialReportedOs,
        initialRuntimePlatform: initialRuntimePlatform,
      ),
    );
  }
  return showDialog<GameEditData>(
    context: context,
    builder: (ctx) => _MaterialEditDialog(
      title: title,
      initialName: initialName,
      initialCover: initialCoverPath,
      initialTranslationEnabled: initialTranslationEnabled,
      initialTranslationPatchPath: initialTranslationPatchPath,
      initialEnvironmentPatchEnabled: initialEnvironmentPatchEnabled,
      initialExperimentalElunaEnabled: initialExperimentalElunaEnabled,
      initialInputGate: initialInputGate,
      initialReportedOs: initialReportedOs,
      initialRuntimePlatform: initialRuntimePlatform,
    ),
  );
}

// ── macOS ──────────────────────────────────────────────────────

class _MacosEditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? initialCover;
  final bool initialTranslationEnabled;
  final String initialTranslationPatchPath;
  final bool initialEnvironmentPatchEnabled;
  final bool initialExperimentalElunaEnabled;
  final InputGatePolicy initialInputGate;
  final String initialReportedOs;
  final String initialRuntimePlatform;

  const _MacosEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
    required this.initialTranslationEnabled,
    required this.initialTranslationPatchPath,
    required this.initialEnvironmentPatchEnabled,
    required this.initialExperimentalElunaEnabled,
    this.initialInputGate = InputGatePolicy.full,
    this.initialReportedOs = '',
    this.initialRuntimePlatform = 'WINDOWS',
  });

  @override
  State<_MacosEditDialog> createState() => _MacosEditDialogState();
}

class _MacosEditDialogState extends State<_MacosEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _cover;
  late bool _translationEnabled;
  late String _translationPatchPath;
  late bool _environmentPatchEnabled;
  late bool _experimentalElunaEnabled;
  late InputGatePolicy _inputGate;
  late String _reportedOs;
  late String _runtimePlatform;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
    _translationEnabled = widget.initialTranslationEnabled;
    _translationPatchPath = widget.initialTranslationPatchPath;
    _environmentPatchEnabled = widget.initialEnvironmentPatchEnabled;
    _experimentalElunaEnabled = widget.initialExperimentalElunaEnabled;
    _inputGate = widget.initialInputGate;
    _reportedOs = widget.initialReportedOs;
    _runtimePlatform = widget.initialRuntimePlatform;
  }

  /// 输入方式 profile 选择：只认预置 profile；补丁带来的自定义规则（knownProfile
  /// 为 null）在用户显式改选前保持不变。
  void _selectInputGateProfile(InputGateProfile? profile) {
    if (profile == null) return;
    setState(
      () => _inputGate = switch (profile) {
        InputGateProfile.full => InputGatePolicy.full,
        InputGateProfile.touchOnly => InputGatePolicy.touchOnly,
      },
    );
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
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('启用文本翻译')),
              MacosSwitch(
                value: _translationEnabled,
                onChanged: (value) =>
                    setState(() => _translationEnabled = value),
              ),
            ],
          ),
          if (_translationEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _translationPatchPath.isEmpty
                        ? '未选择对照文件'
                        : _translationPatchPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_translationPatchPath.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () => setState(() => _translationPatchPath = ''),
                    child: const Text('清除'),
                  ),
                ],
                const SizedBox(width: 6),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: () async {
                    final path = await _pickTranslationPatchFile();
                    if (path != null) {
                      setState(() => _translationPatchPath = path);
                    }
                  },
                  child: const Text('选择对照文件'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('环境兼容补丁')),
              MacosSwitch(
                value: _environmentPatchEnabled,
                onChanged: (value) =>
                    setState(() => _environmentPatchEnabled = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('启动 OS')),
              MacosPopupButton<String>(
                value: runtimePlatforms.contains(_runtimePlatform)
                    ? _runtimePlatform
                    : 'WINDOWS',
                items: [
                  for (final platform in runtimePlatforms)
                    MacosPopupMenuItem(value: platform, child: Text(platform)),
                ],
                onChanged: (platform) {
                  if (platform != null) {
                    setState(() => _runtimePlatform = platform);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('实验性 Eluna E-Mote')),
              MacosSwitch(
                value: _experimentalElunaEnabled,
                onChanged: (value) =>
                    setState(() => _experimentalElunaEnabled = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('输入方式')),
              MacosPopupButton<InputGateProfile>(
                value: _inputGate.knownProfile ?? InputGateProfile.full,
                items: [
                  for (final profile in InputGateProfile.values)
                    MacosPopupMenuItem(
                      value: profile,
                      child: Text(profile.label),
                    ),
                ],
                onChanged: _selectInputGateProfile,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('机种上报')),
              MacosPopupButton<String>(
                value: _reportedOs,
                items: [
                  for (final entry in reportedOsOptions.entries)
                    MacosPopupMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (os) {
                  if (os == null) return;
                  setState(() => _reportedOs = os);
                },
              ),
            ],
          ),
        ],
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.of(context).pop(
          GameEditData(
            name: _name.text.trim(),
            coverPath: _cover,
            translationEnabled: _translationEnabled,
            translationPatchPath: _translationPatchPath,
            environmentPatchEnabled: _environmentPatchEnabled,
            experimentalElunaEnabled: _experimentalElunaEnabled,
            inputGate: _inputGate,
            reportedOs: _reportedOs,
            runtimePlatform: _runtimePlatform,
          ),
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
  final bool initialTranslationEnabled;
  final String initialTranslationPatchPath;
  final bool initialEnvironmentPatchEnabled;
  final bool initialExperimentalElunaEnabled;
  final InputGatePolicy initialInputGate;
  final String initialReportedOs;
  final String initialRuntimePlatform;

  const _CupertinoEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
    required this.initialTranslationEnabled,
    required this.initialTranslationPatchPath,
    required this.initialEnvironmentPatchEnabled,
    required this.initialExperimentalElunaEnabled,
    this.initialInputGate = InputGatePolicy.full,
    this.initialReportedOs = '',
    this.initialRuntimePlatform = 'WINDOWS',
  });

  @override
  State<_CupertinoEditDialog> createState() => _CupertinoEditDialogState();
}

class _CupertinoEditDialogState extends State<_CupertinoEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _cover;
  late bool _translationEnabled;
  late String _translationPatchPath;
  late bool _environmentPatchEnabled;
  late bool _experimentalElunaEnabled;
  late InputGatePolicy _inputGate;
  late String _reportedOs;
  late String _runtimePlatform;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
    _translationEnabled = widget.initialTranslationEnabled;
    _translationPatchPath = widget.initialTranslationPatchPath;
    _environmentPatchEnabled = widget.initialEnvironmentPatchEnabled;
    _experimentalElunaEnabled = widget.initialExperimentalElunaEnabled;
    _inputGate = widget.initialInputGate;
    _reportedOs = widget.initialReportedOs;
    _runtimePlatform = widget.initialRuntimePlatform;
  }

  /// 输入方式 profile 选择：只认预置 profile；补丁带来的自定义规则（knownProfile
  /// 为 null）在用户显式改选前保持不变。
  void _selectInputGateProfile(InputGateProfile? profile) {
    if (profile == null) return;
    setState(
      () => _inputGate = switch (profile) {
        InputGateProfile.full => InputGatePolicy.full,
        InputGateProfile.touchOnly => InputGatePolicy.touchOnly,
      },
    );
  }

  Future<String?> _pickReportedOs() {
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('机种上报'),
        actions: [
          for (final entry in reportedOsOptions.entries)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(entry.key),
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<String?> _pickRuntimePlatform() {
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('启动 OS'),
        actions: [
          for (final platform in runtimePlatforms)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(platform),
              child: Text(platform),
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
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(child: Text('启用文本翻译')),
              CupertinoSwitch(
                value: _translationEnabled,
                onChanged: (value) =>
                    setState(() => _translationEnabled = value),
              ),
            ],
          ),
          if (_translationEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _translationPatchPath.isEmpty
                        ? '未选择对照文件'
                        : _translationPatchPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                CupertinoButton(
                  sizeStyle: CupertinoButtonSize.small,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  onPressed: () async {
                    final path = await _pickTranslationPatchFile();
                    if (path != null) {
                      setState(() => _translationPatchPath = path);
                    }
                  },
                  child: const Text('选择'),
                ),
                if (_translationPatchPath.isNotEmpty)
                  CupertinoButton(
                    sizeStyle: CupertinoButtonSize.small,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    onPressed: () => setState(() => _translationPatchPath = ''),
                    child: const Text('清除'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('环境兼容补丁')),
              CupertinoSwitch(
                value: _environmentPatchEnabled,
                onChanged: (value) =>
                    setState(() => _environmentPatchEnabled = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('启动 OS')),
              CupertinoButton(
                sizeStyle: CupertinoButtonSize.small,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onPressed: () async {
                  final platform = await _pickRuntimePlatform();
                  if (platform != null) {
                    setState(() => _runtimePlatform = platform);
                  }
                },
                child: Text(_runtimePlatform),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('实验性 Eluna E-Mote')),
              CupertinoSwitch(
                value: _experimentalElunaEnabled,
                onChanged: (value) =>
                    setState(() => _experimentalElunaEnabled = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('输入方式')),
              CupertinoSlidingSegmentedControl<InputGateProfile>(
                groupValue: _inputGate.knownProfile,
                children: {
                  for (final profile in InputGateProfile.values)
                    profile: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(profile.label),
                    ),
                },
                onValueChanged: _selectInputGateProfile,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('机种上报')),
              CupertinoButton(
                sizeStyle: CupertinoButtonSize.small,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onPressed: () async {
                  final os = await _pickReportedOs();
                  if (os != null) setState(() => _reportedOs = os);
                },
                child: Text(reportedOsOptions[_reportedOs] ?? _reportedOs),
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
            GameEditData(
              name: _name.text.trim(),
              coverPath: _cover,
              translationEnabled: _translationEnabled,
              translationPatchPath: _translationPatchPath,
              environmentPatchEnabled: _environmentPatchEnabled,
              experimentalElunaEnabled: _experimentalElunaEnabled,
              inputGate: _inputGate,
              reportedOs: _reportedOs,
              runtimePlatform: _runtimePlatform,
            ),
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
  final bool initialTranslationEnabled;
  final String initialTranslationPatchPath;
  final bool initialEnvironmentPatchEnabled;
  final bool initialExperimentalElunaEnabled;
  final InputGatePolicy initialInputGate;
  final String initialReportedOs;
  final String initialRuntimePlatform;

  const _MaterialEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
    required this.initialTranslationEnabled,
    required this.initialTranslationPatchPath,
    required this.initialEnvironmentPatchEnabled,
    required this.initialExperimentalElunaEnabled,
    this.initialInputGate = InputGatePolicy.full,
    this.initialReportedOs = '',
    this.initialRuntimePlatform = 'WINDOWS',
  });

  @override
  State<_MaterialEditDialog> createState() => _MaterialEditDialogState();
}

class _MaterialEditDialogState extends State<_MaterialEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _cover;
  late bool _translationEnabled;
  late String _translationPatchPath;
  late bool _environmentPatchEnabled;
  late bool _experimentalElunaEnabled;
  late InputGatePolicy _inputGate;
  late String _reportedOs;
  late String _runtimePlatform;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
    _translationEnabled = widget.initialTranslationEnabled;
    _translationPatchPath = widget.initialTranslationPatchPath;
    _environmentPatchEnabled = widget.initialEnvironmentPatchEnabled;
    _experimentalElunaEnabled = widget.initialExperimentalElunaEnabled;
    _inputGate = widget.initialInputGate;
    _reportedOs = widget.initialReportedOs;
    _runtimePlatform = widget.initialRuntimePlatform;
  }

  /// 输入方式 profile 选择：只认预置 profile；补丁带来的自定义规则（knownProfile
  /// 为 null）在用户显式改选前保持不变。
  void _selectInputGateProfile(InputGateProfile? profile) {
    if (profile == null) return;
    setState(
      () => _inputGate = switch (profile) {
        InputGateProfile.full => InputGatePolicy.full,
        InputGateProfile.touchOnly => InputGatePolicy.touchOnly,
      },
    );
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用文本翻译'),
            value: _translationEnabled,
            onChanged: (value) => setState(() => _translationEnabled = value),
          ),
          if (_translationEnabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _translationPatchPath.isEmpty
                    ? '未选择对照文件'
                    : _translationPatchPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_translationPatchPath.isNotEmpty)
                    IconButton(
                      tooltip: '清除',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          setState(() => _translationPatchPath = ''),
                    ),
                  IconButton(
                    tooltip: '选择对照文件',
                    icon: const Icon(Icons.folder_open),
                    onPressed: () async {
                      final path = await _pickTranslationPatchFile();
                      if (path != null) {
                        setState(() => _translationPatchPath = path);
                      }
                    },
                  ),
                ],
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('环境兼容补丁'),
            value: _environmentPatchEnabled,
            onChanged: (value) =>
                setState(() => _environmentPatchEnabled = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('实验性 Eluna E-Mote'),
            value: _experimentalElunaEnabled,
            onChanged: (value) =>
                setState(() => _experimentalElunaEnabled = value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('输入方式'),
            subtitle: _inputGate.knownProfile == null
                ? const Text('自定义规则（来自补丁）')
                : null,
            trailing: DropdownButton<InputGateProfile>(
              value: _inputGate.knownProfile,
              hint: const Text('自定义'),
              items: [
                for (final profile in InputGateProfile.values)
                  DropdownMenuItem(value: profile, child: Text(profile.label)),
              ],
              onChanged: _selectInputGateProfile,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('机种上报'),
            trailing: DropdownButton<String>(
              value: _reportedOs,
              items: [
                for (final entry in reportedOsOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (os) {
                if (os != null) setState(() => _reportedOs = os);
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启动 OS'),
            trailing: DropdownButton<String>(
              value: runtimePlatforms.contains(_runtimePlatform)
                  ? _runtimePlatform
                  : 'WINDOWS',
              items: [
                for (final platform in runtimePlatforms)
                  DropdownMenuItem(value: platform, child: Text(platform)),
              ],
              onChanged: (platform) {
                if (platform != null) {
                  setState(() => _runtimePlatform = platform);
                }
              },
            ),
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
            GameEditData(
              name: _name.text.trim(),
              coverPath: _cover,
              translationEnabled: _translationEnabled,
              translationPatchPath: _translationPatchPath,
              environmentPatchEnabled: _environmentPatchEnabled,
              experimentalElunaEnabled: _experimentalElunaEnabled,
              inputGate: _inputGate,
              reportedOs: _reportedOs,
              runtimePlatform: _runtimePlatform,
            ),
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
  final bool initialTranslationEnabled;
  final String initialTranslationPatchPath;
  final bool initialEnvironmentPatchEnabled;
  final bool initialExperimentalElunaEnabled;
  final InputGatePolicy initialInputGate;
  final String initialReportedOs;
  final String initialRuntimePlatform;

  const _FluentEditDialog({
    required this.title,
    required this.initialName,
    this.initialCover,
    required this.initialTranslationEnabled,
    required this.initialTranslationPatchPath,
    required this.initialEnvironmentPatchEnabled,
    required this.initialExperimentalElunaEnabled,
    this.initialInputGate = InputGatePolicy.full,
    this.initialReportedOs = '',
    this.initialRuntimePlatform = 'WINDOWS',
  });

  @override
  State<_FluentEditDialog> createState() => _FluentEditDialogState();
}

class _FluentEditDialogState extends State<_FluentEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _cover;
  late bool _translationEnabled;
  late String _translationPatchPath;
  late bool _environmentPatchEnabled;
  late bool _experimentalElunaEnabled;
  late InputGatePolicy _inputGate;
  late String _reportedOs;
  late String _runtimePlatform;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
    _translationEnabled = widget.initialTranslationEnabled;
    _translationPatchPath = widget.initialTranslationPatchPath;
    _environmentPatchEnabled = widget.initialEnvironmentPatchEnabled;
    _experimentalElunaEnabled = widget.initialExperimentalElunaEnabled;
    _inputGate = widget.initialInputGate;
    _reportedOs = widget.initialReportedOs;
    _runtimePlatform = widget.initialRuntimePlatform;
  }

  /// 输入方式 profile 选择：只认预置 profile；补丁带来的自定义规则（knownProfile
  /// 为 null）在用户显式改选前保持不变。
  void _selectInputGateProfile(InputGateProfile? profile) {
    if (profile == null) return;
    setState(
      () => _inputGate = switch (profile) {
        InputGateProfile.full => InputGatePolicy.full,
        InputGateProfile.touchOnly => InputGatePolicy.touchOnly,
      },
    );
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
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('启用文本翻译')),
              fluent.ToggleSwitch(
                checked: _translationEnabled,
                onChanged: (value) =>
                    setState(() => _translationEnabled = value),
              ),
            ],
          ),
          if (_translationEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _translationPatchPath.isEmpty
                        ? '未选择对照文件'
                        : _translationPatchPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_translationPatchPath.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  fluent.Button(
                    onPressed: () => setState(() => _translationPatchPath = ''),
                    child: const Text('清除'),
                  ),
                ],
                const SizedBox(width: 6),
                fluent.Button(
                  onPressed: () async {
                    final path = await _pickTranslationPatchFile();
                    if (path != null) {
                      setState(() => _translationPatchPath = path);
                    }
                  },
                  child: const Text('选择对照文件'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('环境兼容补丁')),
              fluent.ToggleSwitch(
                checked: _environmentPatchEnabled,
                onChanged: (value) =>
                    setState(() => _environmentPatchEnabled = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('启动 OS')),
              fluent.ComboBox<String>(
                value: runtimePlatforms.contains(_runtimePlatform)
                    ? _runtimePlatform
                    : 'WINDOWS',
                items: [
                  for (final platform in runtimePlatforms)
                    fluent.ComboBoxItem(value: platform, child: Text(platform)),
                ],
                onChanged: (platform) {
                  if (platform != null) {
                    setState(() => _runtimePlatform = platform);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('实验性 Eluna E-Mote')),
              fluent.ToggleSwitch(
                checked: _experimentalElunaEnabled,
                onChanged: (value) =>
                    setState(() => _experimentalElunaEnabled = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('输入方式')),
              fluent.ComboBox<InputGateProfile>(
                value: _inputGate.knownProfile,
                placeholder: const Text('自定义（补丁）'),
                items: [
                  for (final profile in InputGateProfile.values)
                    fluent.ComboBoxItem(
                      value: profile,
                      child: Text(profile.label),
                    ),
                ],
                onChanged: _selectInputGateProfile,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('机种上报')),
              fluent.ComboBox<String>(
                value: _reportedOs,
                items: [
                  for (final entry in reportedOsOptions.entries)
                    fluent.ComboBoxItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (os) {
                  if (os != null) setState(() => _reportedOs = os);
                },
              ),
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
            GameEditData(
              name: _name.text.trim(),
              coverPath: _cover,
              translationEnabled: _translationEnabled,
              translationPatchPath: _translationPatchPath,
              environmentPatchEnabled: _environmentPatchEnabled,
              experimentalElunaEnabled: _experimentalElunaEnabled,
              inputGate: _inputGate,
              reportedOs: _reportedOs,
              runtimePlatform: _runtimePlatform,
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
