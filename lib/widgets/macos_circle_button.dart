import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

/// Finder 工具栏风格的半透明圆形按钮（hover 加深）。
///
/// [onTapWithPosition] 提供点击的屏幕坐标（用于在按钮旁弹菜单）；
/// 只需要普通点击时用 [onPressed]。
class MacosCircleButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final void Function(Offset globalPosition)? onTapWithPosition;

  const MacosCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.onTapWithPosition,
  }) : assert(
          onPressed != null || onTapWithPosition != null,
          '至少提供一种点击回调',
        );

  @override
  State<MacosCircleButton> createState() => _MacosCircleButtonState();
}

class _MacosCircleButtonState extends State<MacosCircleButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = MacosTheme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0x33FFFFFF) : const Color(0x14000000);
    final hover = dark ? const Color(0x4DFFFFFF) : const Color(0x22000000);
    // 图标前景显式随亮暗自适应，避免深色下用主题默认色偏暗看不清。
    final iconColor = dark ? const Color(0xFFE4E4E7) : const Color(0xFF1D1D1F);
    return MacosTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            widget.onTapWithPosition?.call(d.globalPosition);
            widget.onPressed?.call();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hover ? hover : base,
              shape: BoxShape.circle,
            ),
            child: MacosIcon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}
