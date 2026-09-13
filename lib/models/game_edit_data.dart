import 'input_gate.dart';

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

/// 「添加/编辑项目」对话框的提交结果。
class GameEditData {
  final String name;
  final String? coverPath;
  final bool translationEnabled;
  final String translationPatchPath;
  final bool environmentPatchEnabled;
  final bool experimentalElunaEnabled;

  /// 输入门控策略（环境/平台特化的输入过滤），默认全放行。
  final InputGatePolicy inputGate;

  /// 用户选择的覆盖字体文件（托管绝对路径）；空串表示使用游戏脚本字体。
  final String fontOverrideFilePath;

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
    this.fontOverrideFilePath = '',
    this.reportedOs = '',
    this.runtimePlatform = 'WINDOWS',
  });
}
