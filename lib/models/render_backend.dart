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
    list.add(const BackendOption(3, 'Metal'));
    list.add(const BackendOption(0, 'CGL'));
  }
  if (Platform.isIOS) {
    list.add(const BackendOption(3, 'Metal'));
  }
  if (Platform.isLinux) {
    list.add(const BackendOption(2, 'Vulkan'));
  }
  if (Platform.isWindows) {
    list.add(const BackendOption(2, 'Vulkan'));
    list.add(const BackendOption(4, 'D3D11'));
  }
  list.add(const BackendOption(1, 'GL'));
  return list;
}

String backendName(int v) {
  return switch (v) {
    0 => 'CGL (macOS Core OpenGL)',
    1 => 'ANGLE / OpenGL ES',
    2 => 'ANGLE / Vulkan',
    3 => 'ANGLE / Metal',
    4 => 'ANGLE / D3D11',
    _ => '未知',
  };
}

/// system.ini 启动段的候选值。
const runtimePlatforms = ['WINDOWS', 'ANDROID', 'IOS', 'WASM'];
