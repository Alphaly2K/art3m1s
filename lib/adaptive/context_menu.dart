import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'miuix_chrome.dart';

/// 上下文菜单的一项。
class ContextMenuAction {
  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback onSelected;

  const ContextMenuAction({
    required this.label,
    this.icon,
    this.destructive = false,
    required this.onSelected,
  });
}

/// 在 [globalPosition]（屏幕坐标）弹出上下文菜单。
///
/// 移动端走平台动作表 / 底栏；桌面端在指针位置弹出菜单。
Future<void> showAdaptiveContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<ContextMenuAction> actions,
) {
  if (actions.isEmpty) return Future.value();
  if (usesMiuixChrome(context)) {
    return _showMiuixMenu(context, actions);
  }
  if (Platform.isIOS) {
    return _showCupertinoMenu(context, actions);
  }
  if (Platform.isAndroid) {
    return _showMaterialMenu(context, actions);
  }
  if (Platform.isWindows && fluent.FluentTheme.maybeOf(context) != null) {
    return _showFluentMenu(context, globalPosition, actions);
  }
  return _showDesktopFlyout(context, globalPosition, actions);
}

Future<void> _showMiuixMenu(
  BuildContext context,
  List<ContextMenuAction> actions,
) async {
  final selected = await showMiuixSheet<ContextMenuAction>(
    context: context,
    content: (context, dismiss) {
      final theme = MiuixTheme.of(context);
      Widget row(ContextMenuAction action) {
        return MiuixBasicComponent(
          title: action.label,
          titleColor: action.destructive
              ? MiuixBasicComponentColors(
                  color: theme.colors.error,
                  disabledColor: theme.colors.disabledOnSurface,
                )
              : null,
          onClick: () => dismiss(action),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiuixCard(
              child: Column(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const MiuixHorizontalDivider(),
                    row(actions[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            MiuixCard(
              child: MiuixBasicComponent(title: '取消', onClick: () => dismiss()),
            ),
          ],
        ),
      );
    },
  );
  selected?.onSelected();
}

Future<void> _showCupertinoMenu(
  BuildContext context,
  List<ContextMenuAction> actions,
) async {
  final selected = await showCupertinoModalPopup<ContextMenuAction>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => CupertinoActionSheet(
      actions: [
        for (final action in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: action.destructive,
            onPressed: () => Navigator.of(ctx).pop(action),
            child: Text(action.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('取消'),
      ),
    ),
  );
  selected?.onSelected();
}

Future<void> _showMaterialMenu(
  BuildContext context,
  List<ContextMenuAction> actions,
) async {
  final selected = await showModalBottomSheet<ContextMenuAction>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              ListTile(
                leading: action.icon == null
                    ? null
                    : Icon(
                        action.icon,
                        color: action.destructive ? scheme.error : null,
                      ),
                title: Text(
                  action.label,
                  style: action.destructive
                      ? TextStyle(color: scheme.error)
                      : null,
                ),
                onTap: () => Navigator.of(ctx).pop(action),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  selected?.onSelected();
}

Future<void> _showFluentMenu(
  BuildContext context,
  Offset globalPosition,
  List<ContextMenuAction> actions,
) {
  return Navigator.of(context, rootNavigator: true).push(
    _DesktopMenuRoute(position: globalPosition, actions: actions, fluent: true),
  );
}

Future<void> _showDesktopFlyout(
  BuildContext context,
  Offset globalPosition,
  List<ContextMenuAction> actions,
) {
  return Navigator.of(context, rootNavigator: true).push(
    _DesktopMenuRoute(
      position: globalPosition,
      actions: actions,
      fluent: false,
    ),
  );
}

class _DesktopMenuRoute extends PopupRoute<void> {
  final Offset position;
  final List<ContextMenuAction> actions;
  final bool fluent;

  _DesktopMenuRoute({
    required this.position,
    required this.actions,
    required this.fluent,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return FadeTransition(
      opacity: animation,
      child: CustomSingleChildLayout(
        delegate: _MenuLayout(
          anchor: position,
          padding: MediaQuery.paddingOf(context),
        ),
        child: fluent
            ? _FluentMenuPanel(actions: actions)
            : _MacosMenuPanel(actions: actions),
      ),
    );
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  final Offset anchor;
  final EdgeInsets padding;

  _MenuLayout({required this.anchor, required this.padding});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.dx;
    var y = anchor.dy;
    if (x + childSize.width > size.width - 8) {
      x = size.width - childSize.width - 8;
    }
    if (y + childSize.height > size.height - padding.bottom - 8) {
      y = anchor.dy - childSize.height;
    }
    return Offset(
      x.clamp(8, size.width - childSize.width - 8),
      y.clamp(padding.top + 8, size.height - childSize.height - 8),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}

class _MacosMenuPanel extends StatelessWidget {
  final List<ContextMenuAction> actions;

  const _MacosMenuPanel({required this.actions});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: dark ? const Color(0xF52C2C2E) : const Color(0xF5F2F2F7),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: dark ? const Color(0x33FFFFFF) : const Color(0x22000000),
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in actions)
            _MacosMenuItem(action: action, dark: dark),
        ],
      ),
    );
  }
}

class _MacosMenuItem extends StatefulWidget {
  final ContextMenuAction action;
  final bool dark;

  const _MacosMenuItem({required this.action, required this.dark});

  @override
  State<_MacosMenuItem> createState() => _MacosMenuItemState();
}

class _MacosMenuItemState extends State<_MacosMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final baseColor = action.destructive
        ? const Color(0xFFFF453A)
        : (widget.dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E));
    final fg = _hover ? const Color(0xFFFFFFFF) : baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop();
          action.onSelected();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _hover
                ? (action.destructive
                      ? const Color(0xFFFF453A)
                      : const Color(0xFF0A64D0))
                : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              if (action.icon != null) ...[
                Icon(action.icon, size: 15, color: fg),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
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

class _FluentMenuPanel extends StatelessWidget {
  final List<ContextMenuAction> actions;

  const _FluentMenuPanel({required this.actions});

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    return fluent.FlyoutContent(
      padding: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in actions)
            fluent.FlyoutListTile(
              icon: action.icon == null ? null : Icon(action.icon, size: 16),
              text: Text(
                action.label,
                style: TextStyle(
                  color: action.destructive
                      ? const Color(0xFFC42B1C)
                      : theme.resources.textFillColorPrimary,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                action.onSelected();
              },
            ),
        ],
      ),
    );
  }
}
