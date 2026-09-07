import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:macos_ui/macos_ui.dart';

import '../models/input_gate.dart';
import '../models/render_backend.dart';
import '../widgets/inset_scrollbar.dart';
import 'miuix_chrome.dart';

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
  } else if (usesMiuixChrome(context)) {
    return showMiuixConfirm(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
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
    return showMacosSheet<GameEditData>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        final width = size.width < 640
            ? (size.width - 48).clamp(360.0, 520.0)
            : 520.0;
        final height = (size.height - 80).clamp(420.0, 640.0);
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 28),
            child: SizedBox(
              width: width,
              height: height,
              child: MacosSheet(
                insetPadding: EdgeInsets.zero,
                child: _MacosEditDialog(
                  title: title,
                  initialName: initialName,
                  initialCover: initialCoverPath,
                  initialTranslationEnabled: initialTranslationEnabled,
                  initialTranslationPatchPath: initialTranslationPatchPath,
                  initialEnvironmentPatchEnabled:
                      initialEnvironmentPatchEnabled,
                  initialExperimentalElunaEnabled:
                      initialExperimentalElunaEnabled,
                  initialInputGate: initialInputGate,
                  initialReportedOs: initialReportedOs,
                  initialRuntimePlatform: initialRuntimePlatform,
                ),
              ),
            ),
          ),
        );
      },
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
  if (usesMiuixChrome(context)) {
    return showMiuixGameEditDialog(
      context,
      title: title,
      initialName: initialName,
      initialCoverPath: initialCoverPath,
      initialTranslationEnabled: initialTranslationEnabled,
      initialTranslationPatchPath: initialTranslationPatchPath,
      initialEnvironmentPatchEnabled: initialEnvironmentPatchEnabled,
      initialExperimentalElunaEnabled: initialExperimentalElunaEnabled,
      initialInputGate: initialInputGate,
      initialReportedOs: initialReportedOs,
      initialRuntimePlatform: initialRuntimePlatform,
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
  final ScrollController _scroll = ScrollController();
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

  GameEditData _result() {
    return GameEditData(
      name: _name.text.trim(),
      coverPath: _cover,
      translationEnabled: _translationEnabled,
      translationPatchPath: _translationPatchPath,
      environmentPatchEnabled: _environmentPatchEnabled,
      experimentalElunaEnabled: _experimentalElunaEnabled,
      inputGate: _inputGate,
      reportedOs: _reportedOs,
      runtimePlatform: _runtimePlatform,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.title2.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: InsetScrollbar(
            controller: _scroll,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                _MacosFormSection(
                  title: '基本',
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: _CoverTitleBlock(
                        coverPath: _cover,
                        onTapCover: () async {
                          final path = await _pickCoverFile();
                          if (path != null) setState(() => _cover = path);
                        },
                        titleField: MacosTextField(
                          controller: _name,
                          placeholder: '游戏名称',
                          autofocus: true,
                        ),
                        actions: [
                          PushButton(
                            controlSize: ControlSize.small,
                            secondary: true,
                            onPressed: () async {
                              final path = await _pickCoverFile();
                              if (path != null) setState(() => _cover = path);
                            },
                            child: Text(_cover != null ? '更换封面' : '选择封面'),
                          ),
                          if (_cover != null)
                            PushButton(
                              controlSize: ControlSize.small,
                              secondary: true,
                              onPressed: () => setState(() => _cover = null),
                              child: const Text('清除'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                _MacosFormSection(
                  title: '翻译',
                  children: [
                    _MacosFormRow(
                      label: '启用文本翻译',
                      control: MacosSwitch(
                        value: _translationEnabled,
                        onChanged: (value) =>
                            setState(() => _translationEnabled = value),
                      ),
                    ),
                    if (_translationEnabled)
                      _MacosFormRow(
                        label: '对照文件',
                        caption: _translationPatchPath.isEmpty
                            ? '未选择对照文件'
                            : _translationPatchPath,
                        control: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_translationPatchPath.isNotEmpty) ...[
                              PushButton(
                                controlSize: ControlSize.small,
                                secondary: true,
                                onPressed: () =>
                                    setState(() => _translationPatchPath = ''),
                                child: const Text('清除'),
                              ),
                              const SizedBox(width: 6),
                            ],
                            PushButton(
                              controlSize: ControlSize.small,
                              secondary: true,
                              onPressed: () async {
                                final path = await _pickTranslationPatchFile();
                                if (path != null) {
                                  setState(() => _translationPatchPath = path);
                                }
                              },
                              child: const Text('选择'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                _MacosFormSection(
                  title: '兼容',
                  children: [
                    _MacosFormRow(
                      label: '环境兼容补丁',
                      caption: '按项目补丁调整运行环境',
                      control: MacosSwitch(
                        value: _environmentPatchEnabled,
                        onChanged: (value) =>
                            setState(() => _environmentPatchEnabled = value),
                      ),
                    ),
                    _MacosFormRow(
                      label: '启动 OS',
                      caption: '写入 system.ini 的启动段',
                      control: _MacosPopupWrap(
                        child: MacosPopupButton<String>(
                          value: runtimePlatforms.contains(_runtimePlatform)
                              ? _runtimePlatform
                              : 'WINDOWS',
                          items: [
                            for (final platform in runtimePlatforms)
                              MacosPopupMenuItem(
                                value: platform,
                                child: Text(platform),
                              ),
                          ],
                          onChanged: (platform) {
                            if (platform != null) {
                              setState(() => _runtimePlatform = platform);
                            }
                          },
                        ),
                      ),
                    ),
                    _MacosFormRow(
                      label: '输入方式',
                      caption: _inputGate.knownProfile == null
                          ? '自定义规则（来自补丁）'
                          : '触屏移植会关掉键盘默认键',
                      control: _MacosPopupWrap(
                        child: MacosPopupButton<InputGateProfile>(
                          value: _inputGate.knownProfile,
                          hint: const Text('自定义'),
                          items: [
                            for (final profile in InputGateProfile.values)
                              MacosPopupMenuItem(
                                value: profile,
                                child: Text(profile.label),
                              ),
                          ],
                          onChanged: _selectInputGateProfile,
                        ),
                      ),
                    ),
                    _MacosFormRow(
                      label: '机种上报',
                      caption: '脚本读取到的平台标识',
                      control: _MacosPopupWrap(
                        child: MacosPopupButton<String>(
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
                      ),
                    ),
                  ],
                ),
                _MacosFormSection(
                  title: '实验',
                  children: [
                    _MacosFormRow(
                      label: 'Eluna E-Mote',
                      caption: '实验性立绘后端，可能不稳定',
                      control: MacosSwitch(
                        value: _experimentalElunaEnabled,
                        onChanged: (value) =>
                            setState(() => _experimentalElunaEnabled = value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: dark ? const Color(0x26FFFFFF) : const Color(0x1A000000),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              const Spacer(),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 10),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.of(context).pop(_result()),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacosFormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _MacosFormSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
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
                      margin: const EdgeInsets.symmetric(horizontal: 14),
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

class _MacosFormRow extends StatelessWidget {
  final String label;
  final String? caption;
  final Widget control;

  const _MacosFormRow({
    required this.label,
    this.caption,
    required this.control,
  });

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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption1.copyWith(
                      color: MacosColors.systemGrayColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            fit: FlexFit.loose,
            child: Align(alignment: Alignment.centerRight, child: control),
          ),
        ],
      ),
    );
  }
}

class _MacosPopupWrap extends StatelessWidget {
  final Widget child;

  const _MacosPopupWrap({required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 188),
      child: child,
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
          _CoverTitleBlock(
            coverPath: _cover,
            thumbSize: 48,
            onTapCover: () async {
              final path = await _pickCoverFile();
              if (path != null) setState(() => _cover = path);
            },
            titleField: CupertinoTextField(
              controller: _name,
              placeholder: '游戏名称',
              autofocus: true,
            ),
            actions: [
              CupertinoButton(
                sizeStyle: CupertinoButtonSize.small,
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final path = await _pickCoverFile();
                  if (path != null) setState(() => _cover = path);
                },
                child: Text(_cover != null ? '更换封面' : '选择封面'),
              ),
              if (_cover != null)
                CupertinoButton(
                  sizeStyle: CupertinoButtonSize.small,
                  padding: EdgeInsets.zero,
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
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CoverTitleBlock(
                coverPath: _cover,
                thumbSize: 56,
                onTapCover: () async {
                  final path = await _pickCoverFile();
                  if (path != null) setState(() => _cover = path);
                },
                titleField: TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '游戏名称',
                    hintText: '输入自定义名称',
                  ),
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () async {
                      final path = await _pickCoverFile();
                      if (path != null) setState(() => _cover = path);
                    },
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(_cover != null ? '更换封面' : '选择封面'),
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
                onChanged: (value) =>
                    setState(() => _translationEnabled = value),
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
                      DropdownMenuItem(
                        value: profile,
                        child: Text(profile.label),
                      ),
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
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
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
        ),
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

class _CoverTitleBlock extends StatelessWidget {
  const _CoverTitleBlock({
    required this.coverPath,
    required this.titleField,
    required this.actions,
    this.onTapCover,
    this.thumbSize = 52,
  });

  final String? coverPath;
  final Widget titleField;
  final List<Widget> actions;
  final VoidCallback? onTapCover;
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onTapCover,
          child: _CoverThumb(path: coverPath, size: thumbSize),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleField,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: actions),
              ],
            ],
          ),
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
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverTitleBlock(
                coverPath: _cover,
                thumbSize: 52,
                onTapCover: () async {
                  final path = await _pickCoverFile();
                  if (path != null) setState(() => _cover = path);
                },
                titleField: fluent.InfoLabel(
                  label: '游戏名称',
                  child: fluent.TextBox(
                    controller: _name,
                    placeholder: '输入自定义名称',
                    autofocus: true,
                  ),
                ),
                actions: [
                  fluent.Button(
                    onPressed: () async {
                      final path = await _pickCoverFile();
                      if (path != null) setState(() => _cover = path);
                    },
                    child: Text(_cover != null ? '更换封面' : '选择封面'),
                  ),
                  if (_cover != null)
                    fluent.Button(
                      onPressed: () => setState(() => _cover = null),
                      child: const Text('清除'),
                    ),
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
                        onPressed: () =>
                            setState(() => _translationPatchPath = ''),
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
                        fluent.ComboBoxItem(
                          value: platform,
                          child: Text(platform),
                        ),
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
        ),
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

Future<GameEditData?> showMiuixGameEditDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  String? initialCoverPath,
  required bool initialTranslationEnabled,
  required String initialTranslationPatchPath,
  required bool initialEnvironmentPatchEnabled,
  required bool initialExperimentalElunaEnabled,
  required InputGatePolicy initialInputGate,
  required String initialReportedOs,
  required String initialRuntimePlatform,
}) {
  return showMiuixHostedOverlay<GameEditData>(
    context: context,
    overlay: (context, show, dismiss, finish) {
      return MiuixOverlayDialog(
        show: show,
        title: title,
        renderInRootScaffold: false,
        onDismissRequest: dismiss,
        onDismissFinished: finish,
        content: _MiuixEditForm(
          initialName: initialName,
          initialCover: initialCoverPath,
          initialTranslationEnabled: initialTranslationEnabled,
          initialTranslationPatchPath: initialTranslationPatchPath,
          initialEnvironmentPatchEnabled: initialEnvironmentPatchEnabled,
          initialExperimentalElunaEnabled: initialExperimentalElunaEnabled,
          initialInputGate: initialInputGate,
          initialReportedOs: initialReportedOs,
          initialRuntimePlatform: initialRuntimePlatform,
          onCancel: () => dismiss(),
          onSave: (data) => dismiss(data),
        ),
      );
    },
  );
}

class _MiuixEditForm extends StatefulWidget {
  const _MiuixEditForm({
    required this.initialName,
    required this.initialCover,
    required this.initialTranslationEnabled,
    required this.initialTranslationPatchPath,
    required this.initialEnvironmentPatchEnabled,
    required this.initialExperimentalElunaEnabled,
    required this.initialInputGate,
    required this.initialReportedOs,
    required this.initialRuntimePlatform,
    required this.onCancel,
    required this.onSave,
  });

  final String initialName;
  final String? initialCover;
  final bool initialTranslationEnabled;
  final String initialTranslationPatchPath;
  final bool initialEnvironmentPatchEnabled;
  final bool initialExperimentalElunaEnabled;
  final InputGatePolicy initialInputGate;
  final String initialReportedOs;
  final String initialRuntimePlatform;
  final VoidCallback onCancel;
  final ValueChanged<GameEditData> onSave;

  @override
  State<_MiuixEditForm> createState() => _MiuixEditFormState();
}

class _MiuixEditFormState extends State<_MiuixEditForm> {
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

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _selectInputGateProfile(InputGateProfile? profile) {
    if (profile == null) return;
    setState(
      () => _inputGate = switch (profile) {
        InputGateProfile.full => InputGatePolicy.full,
        InputGateProfile.touchOnly => InputGatePolicy.touchOnly,
      },
    );
  }

  GameEditData _data() {
    return GameEditData(
      name: _name.text.trim(),
      coverPath: _cover,
      translationEnabled: _translationEnabled,
      translationPatchPath: _translationPatchPath,
      environmentPatchEnabled: _environmentPatchEnabled,
      experimentalElunaEnabled: _experimentalElunaEnabled,
      inputGate: _inputGate,
      reportedOs: _reportedOs,
      runtimePlatform: _runtimePlatform,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final reportedKeys = reportedOsOptions.keys.toList();
    final runtimeIndex = runtimePlatforms.contains(_runtimePlatform)
        ? runtimePlatforms.indexOf(_runtimePlatform)
        : 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiuixBasicComponent(
                    startAction: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () async {
                          final path = await _pickCoverFile();
                          if (path != null) setState(() => _cover = path);
                        },
                        child: _CoverThumb(path: _cover, size: 48),
                      ),
                    ),
                    content: [
                      MiuixTextField(
                        controller: _name,
                        label: '游戏名称',
                        useLabelAsPlaceholder: true,
                        singleLine: true,
                        autofocus: true,
                      ),
                    ],
                    endActions: [
                      MiuixTextButton(
                        _cover == null ? '选择封面' : '更换',
                        onPressed: () async {
                          final path = await _pickCoverFile();
                          if (path != null) setState(() => _cover = path);
                        },
                      ),
                      if (_cover != null)
                        MiuixTextButton(
                          '清除',
                          onPressed: () => setState(() => _cover = null),
                        ),
                    ],
                  ),
                  MiuixSwitchPreference(
                    title: '启用文本翻译',
                    value: _translationEnabled,
                    onChanged: (value) =>
                        setState(() => _translationEnabled = value),
                  ),
                  if (_translationEnabled)
                    MiuixBasicComponent(
                      title: '对照文件',
                      summary: _translationPatchPath.isEmpty
                          ? '未选择对照文件'
                          : _translationPatchPath,
                      endActions: [
                        MiuixTextButton(
                          '选择',
                          onPressed: () async {
                            final path = await _pickTranslationPatchFile();
                            if (path != null) {
                              setState(() => _translationPatchPath = path);
                            }
                          },
                        ),
                        if (_translationPatchPath.isNotEmpty)
                          MiuixTextButton(
                            '清除',
                            onPressed: () =>
                                setState(() => _translationPatchPath = ''),
                          ),
                      ],
                    ),
                  MiuixSwitchPreference(
                    title: '环境兼容补丁',
                    value: _environmentPatchEnabled,
                    onChanged: (value) =>
                        setState(() => _environmentPatchEnabled = value),
                  ),
                  MiuixSwitchPreference(
                    title: '实验性 Eluna E-Mote',
                    value: _experimentalElunaEnabled,
                    onChanged: (value) =>
                        setState(() => _experimentalElunaEnabled = value),
                  ),
                  MiuixOverlayDropdownPreference(
                    title: '输入方式',
                    summary: _inputGate.knownProfile == null
                        ? '自定义规则（来自补丁）'
                        : null,
                    items: [
                      for (final profile in InputGateProfile.values)
                        profile.label,
                    ],
                    selectedIndex: _inputGate.knownProfile?.index ?? 0,
                    renderInRootScaffold: false,
                    onSelectedIndexChange: (index) {
                      _selectInputGateProfile(InputGateProfile.values[index]);
                    },
                  ),
                  MiuixOverlayDropdownPreference(
                    title: '机种上报',
                    items: [
                      for (final label in reportedOsOptions.values) label,
                    ],
                    selectedIndex: reportedKeys
                        .indexOf(_reportedOs)
                        .clamp(0, reportedKeys.length - 1),
                    renderInRootScaffold: false,
                    onSelectedIndexChange: (index) {
                      setState(() => _reportedOs = reportedKeys[index]);
                    },
                  ),
                  MiuixOverlayDropdownPreference(
                    title: '启动 OS',
                    items: runtimePlatforms,
                    selectedIndex: runtimeIndex,
                    renderInRootScaffold: false,
                    onSelectedIndexChange: (index) {
                      setState(
                        () => _runtimePlatform = runtimePlatforms[index],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MiuixTextButton('取消', onPressed: widget.onCancel),
              const SizedBox(width: 12),
              MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: () => widget.onSave(_data()),
                child: MiuixText('保存', style: theme.textStyles.button),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
