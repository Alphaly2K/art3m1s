import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ps5_input.dart';
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
    final width = (size.width - 72).clamp(620.0, 720.0);
    final height = (size.height - 64).clamp(560.0, 760.0);

    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            ps5InputAction(event.logicalKey) == Ps5InputAction.back) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: SizedBox(
          key: const ValueKey('ps5-game-edit-dialog'),
          width: width,
          height: height,
          child: Ps5MenuPanel(
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
                        Text(
                          widget.engine.label,
                          style: const TextStyle(
                            color: Ps5Colors.menuMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0x32FFFFFF)),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 120,
                                child: AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child:
                                        _coverPath != null &&
                                            File(_coverPath!).existsSync()
                                        ? Image.file(
                                            File(_coverPath!),
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                          )
                                        : const DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: Color(0x66101620),
                                            ),
                                            child: Center(
                                              child: Image(
                                                image: AssetImage(
                                                  AppInfo.logoAsset,
                                                ),
                                                width: 48,
                                                height: 48,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 22),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Ps5Field(
                                      controller: _name,
                                      label: '显示名称',
                                      hintText: '输入项目名称',
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      children: [
                                        Ps5Button(
                                          icon: Icons.image_search_rounded,
                                          onPressed: _chooseCover,
                                          child: Text(
                                            _coverPath == null
                                                ? '选择封面'
                                                : '更换封面',
                                          ),
                                        ),
                                        if (_coverPath != null)
                                          Ps5Button(
                                            icon: Icons.delete_outline_rounded,
                                            destructive: true,
                                            onPressed: () => setState(
                                              () => _coverPath = null,
                                            ),
                                            child: const Text('清除封面'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (showTranslation) ...[
                            const SizedBox(height: 24),
                            Ps5Section(
                              title: '文本翻译',
                              children: [
                                Ps5SettingRow(
                                  compact: true,
                                  label: '启用翻译',
                                  caption: '在游戏运行时应用翻译服务或对照文件',
                                  control: Ps5Switch(
                                    value: _translationEnabled,
                                    onChanged: (value) => setState(
                                      () => _translationEnabled = value,
                                    ),
                                  ),
                                  onPressed: () => setState(
                                    () => _translationEnabled =
                                        !_translationEnabled,
                                  ),
                                ),
                                if (_translationEnabled)
                                  Ps5SettingRow(
                                    compact: true,
                                    label: '对照文件',
                                    caption: _translationPatchPath.isEmpty
                                        ? '未选择 JSON / JSONL / TSV'
                                        : _translationPatchPath,
                                    trailing: '浏览',
                                    control: _translationPatchPath.isNotEmpty
                                        ? Ps5IconButton(
                                            icon: Icons.delete_outline_rounded,
                                            tooltip: '清除对照文件',
                                            destructive: true,
                                            onPressed: () => setState(
                                              () => _translationPatchPath = '',
                                            ),
                                            size: 38,
                                          )
                                        : null,
                                    onPressed: _chooseTranslationPatch,
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
                                  compact: true,
                                  label: '覆盖字体',
                                  caption: _fontOverrideFilePath.isEmpty
                                      ? '使用游戏脚本字体'
                                      : overrideFontDisplayName(
                                          _fontOverrideFilePath,
                                        ),
                                  trailing: '浏览',
                                  control: _fontOverrideFilePath.isNotEmpty
                                      ? Ps5IconButton(
                                          icon: Icons.delete_outline_rounded,
                                          tooltip: '清除字体',
                                          destructive: true,
                                          onPressed: () => setState(
                                            () => _fontOverrideFilePath = '',
                                          ),
                                          size: 38,
                                        )
                                      : null,
                                  onPressed: _chooseFontOverride,
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
                                    compact: true,
                                    label: '环境兼容补丁',
                                    caption: '按项目补丁调整运行环境',
                                    control: Ps5Switch(
                                      value: _environmentPatchEnabled,
                                      onChanged: (value) => setState(
                                        () => _environmentPatchEnabled = value,
                                      ),
                                    ),
                                    onPressed: () => setState(
                                      () => _environmentPatchEnabled =
                                          !_environmentPatchEnabled,
                                    ),
                                  ),
                                if (showRuntimePlatform)
                                  Ps5SettingRow(
                                    compact: true,
                                    label: '启动 OS',
                                    caption: '写入 system.ini 的启动段',
                                    trailing: _runtimePlatform,
                                    onPressed: _pickRuntimePlatform,
                                  ),
                                if (showInputGate)
                                  Ps5SettingRow(
                                    compact: true,
                                    label: '输入方式',
                                    caption: _inputGate.knownProfile == null
                                        ? '自定义规则（来自补丁）'
                                        : '决定键盘与触摸输入是否放行',
                                    trailing:
                                        _inputGate.knownProfile?.label ?? '自定义',
                                    onPressed: _pickInputGate,
                                  ),
                                if (showReportedOs)
                                  Ps5SettingRow(
                                    compact: true,
                                    label: '机种上报',
                                    caption: '脚本读取到的平台标识',
                                    trailing:
                                        reportedOsOptions[_reportedOs] ??
                                        reportedOsOptions['']!,
                                    onPressed: _pickReportedOs,
                                  ),
                                if (showExperimental)
                                  Ps5SettingRow(
                                    compact: true,
                                    label: '实验性 Eluna E-Mote',
                                    caption: '启用 Artemis 实验运行时能力',
                                    control: Ps5Switch(
                                      value: _experimentalElunaEnabled,
                                      onChanged: (value) => setState(
                                        () => _experimentalElunaEnabled = value,
                                      ),
                                    ),
                                    onPressed: () => setState(
                                      () => _experimentalElunaEnabled =
                                          !_experimentalElunaEnabled,
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
                const Divider(height: 1, color: Color(0x32FFFFFF)),
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
      ),
    );
  }
}
