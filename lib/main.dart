import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:macos_window_utils/macos/ns_window_button_type.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:window_manager/window_manager.dart';

import 'services/app_info.dart';
import 'services/app_data_paths.dart';
import 'services/logger.dart';
import 'services/platform_capabilities.dart';
import 'services/sentry_telemetry_sink.dart';
import 'services/storage_service.dart';
import 'services/startup_diagnostics.dart';
import 'services/telemetry_service.dart';
import 'models/host_ui_theme.dart';
import 'providers/settings_provider.dart';
import 'shell/cupertino_shell.dart';
import 'shell/desktop_shell_mode.dart';
import 'shell/fluent_shell.dart';
import 'shell/macos_shell.dart';
import 'shell/material_shell.dart';
import 'shell/miuix_shell.dart';
import 'shell/ps5_shell.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 由构建期 `--dart-define=SENTRY_DSN=...` 注入（见 tool/secrets.example.env）。
/// 任何情况下不要把真实 DSN 写进源码或提交记录。
const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final liquidGlassEnabled = PlatformCapabilities.supportsLiquidGlass;
  if (liquidGlassEnabled) {
    await LiquidGlassWidgets.initialize();
  }
  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (isDesktop) {
    await windowManager.ensureInitialized();
  }
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

  // 崩溃/错误上报：默认关闭，用户在设置中明确开启且构建注入了 DSN 才启用。
  final crashReporting = await _loadCrashReportingPreference();
  TelemetryService.instance.setEnabled(crashReporting);
  Widget appRoot(Widget child) {
    if (!liquidGlassEnabled) return child;
    return LiquidGlassWidgets.wrap(adaptiveQuality: true, child: child);
  }

  void startApp() {
    runApp(appRoot(const ProviderScope(child: Art3m1sApp())));
  }

  if (_sentryDsn.isEmpty || !crashReporting) {
    startApp();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      // 不随事件发送 IP 等默认 PII；日志在 TelemetryService 侧已脱敏。
      options.sendDefaultPii = false;
      options.enableLogs = true;
      // 采样保持低位，避免性能数据淹没事件配额；profiling 关闭。
      options.tracesSampleRate = 0.2;
      // Session Replay 会记录画面内容，对本应用不适用。
      options.replay.sessionSampleRate = 0.0;
      options.replay.onErrorSampleRate = 0.0;
    },
    appRunner: () => runApp(
      appRoot(SentryWidget(child: const ProviderScope(child: Art3m1sApp()))),
    ),
  );
  TelemetryService.instance.registerSink(const SentryTelemetrySink());
}

Future<bool> _loadCrashReportingPreference() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('crash_reporting_enabled') ?? false;
  } catch (_) {
    return false;
  }
}

/// 按平台选壳：桌面窗口化时使用平台原生壳，全屏时自动切换为 PS5 大屏壳；
/// iOS 使用 Cupertino，Android 使用 Material 3 或 Miuix。
class Art3m1sApp extends ConsumerStatefulWidget {
  const Art3m1sApp({super.key});

  @override
  ConsumerState<Art3m1sApp> createState() => _Art3m1sAppState();
}

class _Art3m1sAppState extends ConsumerState<Art3m1sApp> {
  DesktopShellController? _desktopShell;

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) return;
    final controller = DesktopShellController();
    _desktopShell = controller;
    unawaited(controller.syncWindowState());
  }

  @override
  void dispose() {
    _desktopShell?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktopShell = _desktopShell;
    if (desktopShell != null) {
      return AnimatedBuilder(
        animation: desktopShell,
        builder: (context, _) {
          final bigScreen = desktopShell.mode == DesktopShellMode.bigScreen;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 480),
            reverseDuration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) {
              final scale = Tween<double>(
                begin: 0.975,
                end: 1,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: bigScreen
                ? Ps5ShellApp(
                    key: const ValueKey('desktop-big-screen'),
                    onExitBigScreen: desktopShell.exitBigScreen,
                  )
                : KeyedSubtree(
                    key: const ValueKey('desktop-standard'),
                    child: _buildStandardDesktopShell(desktopShell),
                  ),
          );
        },
      );
    }
    if (Platform.isIOS) {
      // ignore: deprecated_member_use
      return const CupertinoShellApp();
    }
    if (Platform.isAndroid &&
        ref.watch(settingsProvider.select((s) => s.hostUiTheme)) ==
            HostUiTheme.miuix) {
      return const MiuixShellApp();
    }
    return const MaterialShellApp();
  }

  Widget _buildStandardDesktopShell(DesktopShellController controller) {
    if (Platform.isMacOS) {
      return MacosShellApp(onEnterBigScreen: controller.enterBigScreen);
    }
    if (Platform.isWindows) {
      return FluentShellApp(onEnterBigScreen: controller.enterBigScreen);
    }
    return MaterialShellApp(onEnterBigScreen: controller.enterBigScreen);
  }
}
