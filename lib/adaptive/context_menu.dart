import 'package:flutter/widgets.dart';

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
/// 纯 widgets 层实现，不依赖 Material/Cupertino/macos_ui 的 ancestor，
/// 三个壳共用一份，桌面右键与移动端长按都走这里。
Future<void> showAdaptiveContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<ContextMenuAction> actions,
) {
  return Navigator.of(context, rootNavigator: true).push(
    _ContextMenuRoute(position: globalPosition, actions: actions),
  );
}

class _ContextMenuRoute extends PopupRoute<void> {
  final Offset position;
  final List<ContextMenuAction> actions;

  _ContextMenuRoute({required this.position, required this.actions});

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
        child: _MenuPanel(actions: actions),
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
    return Offset(x.clamp(8, size.width), y.clamp(padding.top + 8, size.height));
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}

class _MenuPanel extends StatelessWidget {
  final List<ContextMenuAction> actions;

  const _MenuPanel({required this.actions});

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
            _MenuItem(action: action, dark: dark),
        ],
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  final ContextMenuAction action;
  final bool dark;

  const _MenuItem({required this.action, required this.dark});

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
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
