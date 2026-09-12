import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos/ns_window_button_type.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import 'services/app_info.dart';
import 'services/app_data_paths.dart';
import 'services/logger.dart';
import 'services/storage_service.dart';
import 'services/startup_diagnostics.dart';
import 'models/host_ui_theme.dart';
import 'providers/settings_provider.dart';
import 'shell/cupertino_shell.dart';
import 'shell/fluent_shell.dart';
import 'shell/macos_shell.dart';
import 'shell/material_shell.dart';
import 'shell/miuix_shell.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    // 沉浸式标题栏：透明 titlebar + 全尺寸内容 + 侧栏毛玻璃，
    // 需配合 MainFlutterWindow.swift 里的 macos_window_utils 初始化。
    //
    // 不用 MacosWindowUtilsConfig().apply()：它会 addToolbar()，而
    // macOS 26 上带 NSToolbar 的窗口会拿到更大的圆角（截断内容）。
    // 标题栏透明/隐藏/全尺寸内容已在 MainFlutterWindow.swift 里于窗口
    // 显示前同步完成（避免启动闪烁），这里只做剩余配置。
    await WindowManipulator.initialize(enableWindowDelegate: true);
    await WindowManipulator.setMaterial(
      NSVisualEffectViewMaterial.windowBackground,
    );
    // Swift 侧的预设在插件初始化过程中可能被还原（macOS 26 上实测标题栏
    // 会重新出现），这里再应用一次兜底；预设仍负责消除启动第一帧的闪烁。
    await WindowManipulator.enableFullSizeContentView();
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.hideTitle();
    // 去掉 NSToolbar 后红绿灯回到紧贴角落的紧凑位，视觉上太靠边；
    // 手动内收到接近 unified toolbar 的位置（三枚按钮原点间距 20pt）。
    await WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.closeButton,
      offset: const Offset(14, 14),
    );
    await WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.miniaturizeButton,
      offset: const Offset(34, 14),
    );
    await WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.zoomButton,
      offset: const Offset(54, 14),
    );
  }
  await StartupDiagnostics.step(
    'data-directories',
    AppDataPaths.ensureInitialized,
  );
  await StartupDiagnostics.step(
    'preferences',
    StorageService.ensureInitialized,
  );
  await StartupDiagnostics.step('app-info', AppInfo.init);
  Log.info('Art3m1s 启动');
  runApp(const ProviderScope(child: Art3m1sApp()));
}

/// 按平台选壳：macOS 原生风（macos_ui）、iOS Cupertino、
/// Windows Fluent（fluent_ui）、Linux yaru、Android Material 3 或 Miuix。
class Art3m1sApp extends ConsumerWidget {
  const Art3m1sApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isMacOS) return const MacosShellApp();
    if (Platform.isIOS) return const CupertinoShellApp();
    if (Platform.isWindows) return const FluentShellApp();
    if (Platform.isAndroid &&
        ref.watch(settingsProvider.select((s) => s.hostUiTheme)) ==
            HostUiTheme.miuix) {
      return const MiuixShellApp();
    }
    return const MaterialShellApp();
  }
}
