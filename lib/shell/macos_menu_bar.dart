import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/library_actions.dart';
import '../providers/settings_provider.dart';
import '../services/app_data_paths.dart';

/// macOS 原生菜单栏（Finder 风格）：在标准 App / 窗口菜单之外补上应用相关的
/// 文件 / 视图 / 访达项。用 [PlatformMenuBar] 覆盖默认 MainMenu.xib；标准项（关于/
/// 服务/隐藏/退出/最小化/缩放/全屏）走 [PlatformProvidedMenuItem]。
///
/// 复制/粘贴等文本编辑快捷键由 Flutter 文本框自身处理，不依赖 Edit 菜单，故此处
/// 未重建 Edit 菜单也不影响输入框的 ⌘C/⌘V/⌘A/⌘Z。
class MacosMenuBar extends ConsumerWidget {
  const MacosMenuBar({
    super.key,
    required this.onOpenSettings,
    required this.onOpenAbout,
    required this.child,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = LibraryActions(context, ref);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Art3m1s',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(label: '关于 Art3m1s', onSelected: onOpenAbout),
                PlatformMenuItem(
                  label: '设置…',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: onOpenSettings,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: '文件',
          menus: [
            PlatformMenuItem(
              label: '添加游戏目录…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: actions.pickDirectory,
            ),
            PlatformMenuItem(
              label: '添加 PFS 归档…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
                shift: true,
              ),
              onSelected: actions.pickPfs,
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '在访达中显示应用数据',
                  onSelected: _revealAppData,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: '视图',
          menus: [
            PlatformMenuItem(
              label: settings.debugOverlay ? '隐藏调试面板' : '显示调试面板',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyD,
                meta: true,
                alt: true,
              ),
              onSelected: () =>
                  notifier.setDebugOverlay(!settings.debugOverlay),
            ),
            PlatformMenuItem(
              label: settings.showFps ? '隐藏帧率' : '显示帧率',
              onSelected: () => notifier.setShowFps(!settings.showFps),
            ),
          ],
        ),
        const PlatformMenu(
          label: '窗口',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}

/// 在访达中打开应用数据目录（存档 / 封面缓存等落于此）。
Future<void> _revealAppData() async {
  try {
    final dir = await AppDataPaths.ensureInitialized();
    await Process.run('open', [dir.path]);
  } catch (_) {}
}
