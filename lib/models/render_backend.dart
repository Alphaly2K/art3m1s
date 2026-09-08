import 'dart:io' show Platform;

/// 一个可选的图形后端（传给 core 的整数值 + 显示名）。
class BackendOption {
  final int value;
  final String label;

  const BackendOption(this.value, this.label);
}

/// 当前平台可用的后端列表（第一项为推荐值）。
List<BackendOption> availableBackends() {
  final list = <BackendOption>[];
  if (Platform.isMacOS) {
    list.add(const BackendOption(3, 'Metal（原生）'));
    list.add(const BackendOption(6, 'ANGLE / Metal（参考）'));
    list.add(const BackendOption(5, 'OpenGL / CGL（参考）'));
  }
  if (Platform.isIOS) {
    list.add(const BackendOption(3, 'Metal（原生）'));
    list.add(const BackendOption(6, 'ANGLE / Metal（参考）'));
  }
  if (Platform.isAndroid) {
    list.add(const BackendOption(2, 'Vulkan（原生）'));
  }
  if (Platform.isLinux) {
    list.add(const BackendOption(2, 'Vulkan'));
  }
  if (Platform.isWindows) {
    list.add(const BackendOption(2, 'Vulkan'));
    list.add(const BackendOption(4, 'D3D11'));
  }
  list.add(BackendOption(1, Platform.isAndroid ? 'OpenGL ES（参考）' : 'GL'));
  return list;
}

String backendName(int v) {
  return switch (v) {
    0 => Platform.isIOS || Platform.isMacOS ? 'Metal（原生，平台默认）' : '平台默认',
    1 => Platform.isAndroid ? 'OpenGL ES（参考）' : 'ANGLE / OpenGL ES',
    2 => Platform.isAndroid ? 'Vulkan（原生）' : 'ANGLE / Vulkan',
    3 => Platform.isIOS || Platform.isMacOS ? 'Metal（原生）' : 'ANGLE / Metal',
    4 => 'ANGLE / D3D11',
    5 => 'OpenGL / CGL（参考）',
    6 => 'ANGLE / Metal（参考）',
    _ => '未知',
  };
}

/// system.ini 启动段的候选值。
const runtimePlatforms = ['WINDOWS', 'ANDROID', 'IOS', 'WASM'];
