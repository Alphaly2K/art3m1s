import 'dart:io';

import 'package:flutter/material.dart';

import '../models/game_edit_data.dart';
import '../models/game_engine.dart';
import '../models/input_gate.dart';
import '../models/render_backend.dart';
import '../screens/translation_font_picker.dart';
import '../services/app_info.dart';
import '../widgets/ps5_file_picker.dart';
import 'ps5_chrome.dart';

Future<GameEditData?> showPs5GameEditDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  required GameEngineKind engine,
  String? initialCoverPath,
  bool initialTranslationEnabled = false,
  String initialTranslationPatchPath = '',
  bool initialEnvironmentPatchEnabled = false,
  bool initialExperimentalElunaEnabled = false,
  InputGatePolicy initialInputGate = InputGatePolicy.full,
  String initialFontOverrideFilePath = '',
  String initialReportedOs = '',
  String initialRuntimePlatform = 'WINDOWS',
}) {
  return showGeneralDialog<GameEditData>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '关闭项目设置',
    barrierColor: const Color(0xC9000000),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Ps5GameEditDialog(
        title: title,
        initialName: initialName,
        engine: engine,
        initialCoverPath: initialCoverPath,
        initialTranslationEnabled: initialTranslationEnabled,
        initialTranslationPatchPath: initialTranslationPatchPath,
        initialEnvironmentPatchEnabled: initialEnvironmentPatchEnabled,
        initialExperimentalElunaEnabled: initialExperimentalElunaEnabled,
        initialInputGate: initialInputGate,
        initialFontOverrideFilePath: initialFontOverrideFilePath,
        initialReportedOs: initialReportedOs,
        initialRuntimePlatform: initialRuntimePlatform,
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

String _runtimePlatformCaption(String platform) => switch (platform) {
  'WINDOWS' => '使用 Windows 平台代码路径',
  'ANDROID' => '模拟 Android 启动环境',
  'IOS' => '模拟 iOS 启动环境',
  'WASM' => '模拟 WebAssembly 启动环境',
  _ => platform,
};

class Ps5GameEditDialog extends StatefulWidget {
  const Ps5GameEditDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.engine,
    this.initialCoverPath,
    required this.initialTranslationEnabled,
    required this.initialTranslationPatchPath,
    required this.initialEnvironmentPatchEnabled,
    required this.initialExperimentalElunaEnabled,
    required this.initialInputGate,
    this.initialFontOverrideFilePath = '',
    required this.initialReportedOs,
    required this.initialRuntimePlatform,
  });

  final String title;
  final String initialName;
  final GameEngineKind engine;
  final String? initialCoverPath;
  final bool initialTranslationEnabled;
  final String initialTranslationPatchPath;
  final bool initialEnvironmentPatchEnabled;
  final bool initialExperimentalElunaEnabled;
  final InputGatePolicy initialInputGate;
  final String initialFontOverrideFilePath;
  final String initialReportedOs;
  final String initialRuntimePlatform;

  @override
  State<Ps5GameEditDialog> createState() => _Ps5GameEditDialogState();
}

class _Ps5GameEditDialogState extends State<Ps5GameEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _coverPath;
  late bool _translationEnabled;
  late String _translationPatchPath;
  late bool _environmentPatchEnabled;
  late bool _experimentalElunaEnabled;
  late InputGatePolicy _inputGate;
  late String _fontOverrideFilePath;
  late String _reportedOs;
  late String _runtimePlatform;

  @override
  void initState() {
    super.initState();
    _coverPath = widget.initialCoverPath;
    _translationEnabled = widget.initialTranslationEnabled;
    _translationPatchPath = widget.initialTranslationPatchPath;
    _environmentPatchEnabled = widget.initialEnvironmentPatchEnabled;
    _experimentalElunaEnabled = widget.initialExperimentalElunaEnabled;
    _inputGate = widget.initialInputGate;
    _fontOverrideFilePath = widget.initialFontOverrideFilePath;
    _reportedOs = widget.initialReportedOs;
    _runtimePlatform = widget.initialRuntimePlatform;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _chooseCover() async {
    final path = await showPs5FilePicker(
      context,
      mode: Ps5FilePickerMode.file,
      title: '选择封面图片',
      initialDirectory: _coverPath == null
          ? null
          : File(_coverPath!).parent.path,
      allowedExtensions: const {'png', 'jpg', 'jpeg', 'bmp', 'webp'},
    );
    if (path != null && mounted) {
      setState(() => _coverPath = path);
    }
  }

  Future<void> _chooseTranslationPatch() async {
    final path = await showPs5FilePicker(
      context,
      mode: Ps5FilePickerMode.file,
      title: '选择翻译对照文件',
      initialDirectory: _translationPatchPath.isEmpty
          ? null
          : File(_translationPatchPath).parent.path,
      allowedExtensions: const {'json', 'jsonl', 'tsv'},
    );
    if (path != null && mounted) {
      setState(() => _translationPatchPath = path);
    }
  }

  Future<void> _chooseFontOverride() async {
    final path = await pickOverrideFont(context);
    if (path != null && mounted) {
      setState(() => _fontOverrideFilePath = path);
    }
  }

  Future<void> _pickRuntimePlatform() async {
    final selected = await showPs5OptionPicker<String>(
      context,
      title: '启动 OS',
      selected: runtimePlatforms.contains(_runtimePlatform)
          ? _runtimePlatform
          : 'WINDOWS',
      options: [
        for (final platform in runtimePlatforms)
          (
            value: platform,
            label: platform,
            caption: _runtimePlatformCaption(platform),
          ),
      ],
    );
    if (selected != null && mounted) {
      setState(() => _runtimePlatform = selected);
    }
  }

  Future<void> _pickInputGate() async {
    final selected = await showPs5OptionPicker<InputGateProfile>(
      context,
      title: '输入方式',
      selected: _inputGate.knownProfile ?? InputGateProfile.full,
      options: [
        for (final profile in InputGateProfile.values)
          (
            value: profile,
            label: profile.label,
            caption: profile == InputGateProfile.full
                ? '键盘、鼠标、触摸与滚轮全部放行'
                : '关闭真实键盘输入，保留鼠标与触摸',
          ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(
      () => _inputGate = switch (selected) {
        InputGateProfile.full => InputGatePolicy.full,
        InputGateProfile.touchOnly => InputGatePolicy.touchOnly,
      },
    );
  }

  Future<void> _pickReportedOs() async {
    final selected = await showPs5OptionPicker<String>(
      context,
      title: '机种上报',
      selected: reportedOsOptions.containsKey(_reportedOs) ? _reportedOs : '',
      options: [
        for (final entry in reportedOsOptions.entries)
          (
            value: entry.key,
            label: entry.value,
            caption: entry.key.isEmpty ? '使用项目本身的默认机种' : '向脚本上报 ${entry.value}',
          ),
      ],
    );
    if (selected != null && mounted) {
      setState(() => _reportedOs = selected);
    }
  }

  void _submit() {
    Navigator.of(context).pop(
      GameEditData(
        name: _name.text.trim(),
        coverPath: _coverPath,
        translationEnabled: _translationEnabled,
        translationPatchPath: _translationPatchPath,
        environmentPatchEnabled: _environmentPatchEnabled,
        experimentalElunaEnabled: _experimentalElunaEnabled,
        inputGate: _inputGate,
        fontOverrideFilePath: _fontOverrideFilePath,
        reportedOs: _reportedOs,
        runtimePlatform: _runtimePlatform,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.engine.supportedGameSettings;
    final showTranslation = fields.contains(
      GameSettingField.translationEnabled,
    );
    final showEnvironmentPatch = fields.contains(
      GameSettingField.environmentPatch,
    );
    final showRuntimePlatform = fields.contains(
      GameSettingField.runtimePlatform,
    );
    final showInputGate = fields.contains(GameSettingField.inputGate);
    final showFontOverride = fields.contains(GameSettingField.fontOverride);
    final showReportedOs = fields.contains(GameSettingField.reportedOs);
    final showExperimental = fields.contains(
      GameSettingField.experimentalEluna,
    );
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 72).clamp(760.0, 1040.0);
    final height = (size.height - 64).clamp(560.0, 760.0);

    return Center(
      child: SizedBox(
        key: const ValueKey('ps5-game-edit-dialog'),
        width: width,
        height: height,
        child: Ps5Panel(
          opaque: true,
          child: Column(
            children: [
              SizedBox(
                height: 76,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Ps5IconButton(
                        icon: Icons.close_rounded,
                        tooltip: '关闭',
                        autofocus: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Ps5Colors.text,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _EngineBadge(engine: widget.engine),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Ps5Colors.line),
              Expanded(
                child: Row(
                  children: [
                    _CoverSidebar(
                      name: _name.text,
                      coverPath: _coverPath,
                      onChoose: _chooseCover,
                      onClear: _coverPath == null
                          ? null
                          : () => setState(() => _coverPath = null),
                    ),
                    const VerticalDivider(width: 1, color: Ps5Colors.line),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(26, 22, 26, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Ps5Field(
                                controller: _name,
                                label: '显示名称',
                                hintText: '输入项目名称',
                                onChanged: (_) => setState(() {}),
                              ),
                              if (showTranslation) ...[
                                const SizedBox(height: 24),
                                Ps5Section(
                                  title: '文本翻译',
                                  children: [
                                    Ps5SettingRow(
                                      label: '启用翻译',
                                      caption: '在游戏运行时应用翻译服务或对照文件',
                                      control: Ps5Switch(
                                        value: _translationEnabled,
                                        onChanged: (value) => setState(
                                          () => _translationEnabled = value,
                                        ),
                                      ),
                                    ),
                                    if (_translationEnabled)
                                      Ps5SettingRow(
                                        label: '对照文件',
                                        caption: _translationPatchPath.isEmpty
                                            ? '未选择 JSON / JSONL / TSV'
                                            : _translationPatchPath,
                                        control: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_translationPatchPath
                                                .isNotEmpty)
                                              Ps5IconButton(
                                                icon: Icons
                                                    .delete_outline_rounded,
                                                tooltip: '清除对照文件',
                                                destructive: true,
                                                onPressed: () => setState(
                                                  () => _translationPatchPath =
                                                      '',
                                                ),
                                                size: 38,
                                              ),
                                            const SizedBox(width: 6),
                                            Ps5Button(
                                              icon: Icons.folder_open_rounded,
                                              onPressed:
                                                  _chooseTranslationPatch,
                                              child: const Text('浏览'),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              if (showFontOverride) ...[
                                const SizedBox(height: 24),
                                Ps5Section(
                                  title: '字体',
                                  children: [
                                    Ps5SettingRow(
                                      label: '覆盖字体',
                                      caption: _fontOverrideFilePath.isEmpty
                                          ? '使用游戏脚本字体'
                                          : overrideFontDisplayName(
                                              _fontOverrideFilePath,
                                            ),
                                      control: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_fontOverrideFilePath.isNotEmpty)
                                            Ps5IconButton(
                                              icon: Icons
                                                  .delete_outline_rounded,
                                              tooltip: '清除字体',
                                              destructive: true,
                                              onPressed: () => setState(
                                                () => _fontOverrideFilePath =
                                                    '',
                                              ),
                                              size: 38,
                                            ),
                                          const SizedBox(width: 6),
                                          Ps5Button(
                                            icon: Icons
                                                .font_download_rounded,
                                            onPressed: _chooseFontOverride,
                                            child: const Text('浏览'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (showEnvironmentPatch ||
                                  showRuntimePlatform ||
                                  showInputGate ||
                                  showReportedOs ||
                                  showExperimental) ...[
                                const SizedBox(height: 24),
                                Ps5Section(
                                  title: '兼容与运行',
                                  children: [
                                    if (showEnvironmentPatch)
                                      Ps5SettingRow(
                                        label: '环境兼容补丁',
                                        caption: '按项目补丁调整运行环境',
                                        control: Ps5Switch(
                                          value: _environmentPatchEnabled,
                                          onChanged: (value) => setState(
                                            () => _environmentPatchEnabled =
                                                value,
                                          ),
                                        ),
                                      ),
                                    if (showRuntimePlatform)
                                      Ps5SettingRow(
                                        label: '启动 OS',
                                        caption: '写入 system.ini 的启动段',
                                        control: Ps5Button(
                                          icon: Icons.memory_rounded,
                                          onPressed: _pickRuntimePlatform,
                                          child: Text(_runtimePlatform),
                                        ),
                                      ),
                                    if (showInputGate)
                                      Ps5SettingRow(
                                        label: '输入方式',
                                        caption: _inputGate.knownProfile == null
                                            ? '自定义规则（来自补丁）'
                                            : '决定键盘与触摸输入是否放行',
                                        control: Ps5Button(
                                          icon: Icons.gamepad_rounded,
                                          onPressed: _pickInputGate,
                                          child: Text(
                                            _inputGate.knownProfile?.label ??
                                                '自定义',
                                          ),
                                        ),
                                      ),
                                    if (showReportedOs)
                                      Ps5SettingRow(
                                        label: '机种上报',
                                        caption: '脚本读取到的平台标识',
                                        control: Ps5Button(
                                          icon: Icons.devices_rounded,
                                          onPressed: _pickReportedOs,
                                          child: Text(
                                            reportedOsOptions[_reportedOs] ??
                                                reportedOsOptions['']!,
                                          ),
                                        ),
                                      ),
                                    if (showExperimental)
                                      Ps5SettingRow(
                                        label: '实验性 Eluna E-Mote',
                                        caption: '启用 Artemis 实验运行时能力',
                                        control: Ps5Switch(
                                          value: _experimentalElunaEnabled,
                                          onChanged: (value) => setState(
                                            () => _experimentalElunaEnabled =
                                                value,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Ps5Colors.line),
              SizedBox(
                height: 76,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '设置会写入项目清单，之后可随时修改。',
                          style: TextStyle(
                            color: Ps5Colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Ps5Button(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 10),
                      Ps5Button(
                        primary: true,
                        icon: Icons.check_rounded,
                        onPressed: _submit,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverSidebar extends StatelessWidget {
  const _CoverSidebar({
    required this.name,
    required this.coverPath,
    required this.onChoose,
    required this.onClear,
  });

  final String name;
  final String? coverPath;
  final VoidCallback onChoose;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 286,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: coverPath != null && File(coverPath!).existsSync()
                      ? Image.file(
                          File(coverPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Ps5Colors.backgroundRaised,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                AppInfo.logoAsset,
                                width: 82,
                                height: 82,
                                fit: BoxFit.cover,
                              ),
                              const SizedBox(height: 18),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Text(
                                  name.isEmpty ? '未命名项目' : name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Ps5Colors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Ps5Button(
                    icon: Icons.image_search_rounded,
                    onPressed: onChoose,
                    child: Text(coverPath == null ? '选择封面' : '更换封面'),
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 8),
                  Ps5IconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: '清除封面',
                    destructive: true,
                    onPressed: onClear,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineBadge extends StatelessWidget {
  const _EngineBadge({required this.engine});

  final GameEngineKind engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Ps5Colors.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x553CE7FF)),
      ),
      child: Text(
        engine.label,
        style: const TextStyle(
          color: Ps5Colors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
