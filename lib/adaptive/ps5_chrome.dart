import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 标记当前 Navigator 位于 PS5 大屏壳中。
///
/// 对话框与文件入口据此选择同一套自绘控件，避免桌面平台在 PS5 界面里
/// 突然弹回 macOS / Windows 原生文件选择器。
class Ps5ChromeScope extends InheritedWidget {
  const Ps5ChromeScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<Ps5ChromeScope>()
            ?.enabled ??
        false;
  }

  @override
  bool updateShouldNotify(Ps5ChromeScope oldWidget) {
    return enabled != oldWidget.enabled;
  }
}

bool usesPs5Chrome(BuildContext context) => Ps5ChromeScope.of(context);

abstract final class Ps5Colors {
  static const background = Color(0xFF05080D);
  static const backgroundRaised = Color(0xFF0A1019);
  static const panel = Color(0xE6111823);
  static const panelStrong = Color(0xFF111A28);
  static const panelHover = Color(0xFF1B2738);
  static const line = Color(0x2EFFFFFF);
  static const text = Color(0xFFF4F7FB);
  static const textMuted = Color(0xFF9CA9B8);
  static const accent = Color(0xFF3CE7FF);
  static const accentSoft = Color(0x333CE7FF);
  static const blue = Color(0xFF1677FF);
  static const danger = Color(0xFFFF5D6C);
  static const success = Color(0xFF50E3A4);
  static const menuPanel = Color(0xF21B1E25);
  static const menuHighlight = Color(0xFF3A3E48);
  static const menuMuted = Color(0xFF8E949E);
}

class Ps5Panel extends StatelessWidget {
  const Ps5Panel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.selected = false,
    this.opaque = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: opaque ? Ps5Colors.panelStrong : Ps5Colors.panel,
        borderRadius: BorderRadius.circular(5),
        border: selected
            ? Border.all(color: Ps5Colors.accent, width: 1.4)
            : null,
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Ps5Colors.accentSoft,
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ]
            : opaque
            ? const [
                BoxShadow(
                  color: Color(0x73000000),
                  blurRadius: 36,
                  offset: Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class Ps5Button extends StatelessWidget {
  const Ps5Button({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.primary = false,
    this.destructive = false,
    this.minimumWidth,
    this.autofocus = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final bool primary;
  final bool destructive;
  final double? minimumWidth;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = destructive
        ? Ps5Colors.danger
        : primary
        ? Ps5Colors.background
        : Ps5Colors.text;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 42, minWidth: minimumWidth ?? 0),
      child: Material(
        color: !enabled
            ? Ps5Colors.panelHover
            : destructive
            ? const Color(0x22FF5D6C)
            : primary
            ? Ps5Colors.accent
            : Ps5Colors.panelHover,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onPressed,
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(7),
          hoverColor: primary ? const Color(0x22000000) : Ps5Colors.accentSoft,
          focusColor: Ps5Colors.accentSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: enabled ? foreground : Ps5Colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                ],
                DefaultTextStyle(
                  style: TextStyle(
                    color: enabled ? foreground : Ps5Colors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    decoration: TextDecoration.none,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Ps5IconButton extends StatelessWidget {
  const Ps5IconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.destructive = false,
    this.size = 44,
    this.autofocus = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool destructive;
  final double size;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: selected
              ? Ps5Colors.accentSoft
              : destructive
              ? const Color(0x22FF5D6C)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onPressed,
            autofocus: autofocus,
            customBorder: const CircleBorder(),
            hoverColor: destructive
                ? const Color(0x33FF5D6C)
                : Ps5Colors.accentSoft,
            child: Icon(
              icon,
              size: size * 0.46,
              color: !selected && destructive
                  ? Ps5Colors.danger
                  : selected
                  ? Ps5Colors.accent
                  : Ps5Colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class Ps5Switch extends StatefulWidget {
  const Ps5Switch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<Ps5Switch> createState() => _Ps5SwitchState();
}

class _Ps5SwitchState extends State<Ps5Switch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    void toggle() {
      if (enabled) widget.onChanged!(!widget.value);
    }

    return FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            toggle();
            return null;
          },
        ),
      },
      child: Semantics(
        toggled: widget.value,
        enabled: enabled,
        button: true,
        child: GestureDetector(
          onTap: enabled ? toggle : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: !enabled
                  ? Ps5Colors.panelHover
                  : widget.value
                  ? Ps5Colors.accent
                  : const Color(0xFF243043),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _focused
                    ? Colors.white
                    : widget.value
                    ? Ps5Colors.accent
                    : Ps5Colors.line,
                width: _focused ? 1.6 : 1,
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: widget.value
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: enabled
                      ? widget.value
                            ? Ps5Colors.background
                            : Ps5Colors.textMuted
                      : Ps5Colors.textMuted.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Ps5SegmentedControl<T> extends StatelessWidget {
  const Ps5SegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Ps5Colors.backgroundRaised,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Ps5Colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Material(
                color: option.value == value
                    ? Ps5Colors.accentSoft
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                child: InkWell(
                  onTap: () => onChanged(option.value),
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: option.value == value
                            ? Ps5Colors.accent
                            : Ps5Colors.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class Ps5Field extends StatelessWidget {
  const Ps5Field({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Ps5Colors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          autofocus: autofocus,
          obscureText: obscureText,
          keyboardType: keyboardType,
          enableSuggestions: !obscureText,
          autocorrect: false,
          onChanged: onChanged,
          style: const TextStyle(color: Ps5Colors.text, fontSize: 15),
          cursorColor: Ps5Colors.accent,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Ps5Colors.textMuted.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: Ps5Colors.backgroundRaised,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: const BorderSide(color: Ps5Colors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: const BorderSide(color: Ps5Colors.accent, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class Ps5Section extends StatelessWidget {
  const Ps5Section({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Ps5Colors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 0.6, color: Ps5Colors.line),
              children[i],
            ],
          ],
        ),
      ],
    );
  }
}

class Ps5SettingRow extends StatelessWidget {
  const Ps5SettingRow({
    super.key,
    required this.label,
    this.caption,
    this.control,
    this.trailing,
    this.onPressed,
  });

  final String label;
  final String? caption;
  final Widget? control;
  final String? trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed != null || trailing != null) {
      return _Ps5SettingMenuRow(
        label: label,
        caption: caption,
        trailing: trailing,
        control: control,
        onPressed: onPressed,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Ps5Colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Ps5Colors.menuMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 24),
          ?control,
        ],
      ),
    );
  }
}

class _Ps5SettingMenuRow extends StatefulWidget {
  const _Ps5SettingMenuRow({
    required this.label,
    this.caption,
    this.trailing,
    this.control,
    this.onPressed,
  });

  final String label;
  final String? caption;
  final String? trailing;
  final Widget? control;
  final VoidCallback? onPressed;

  @override
  State<_Ps5SettingMenuRow> createState() => _Ps5SettingMenuRowState();
}

class _Ps5SettingMenuRowState extends State<_Ps5SettingMenuRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: FocusableActionDetector(
        onFocusChange: (value) => setState(() => _focused = value),
        mouseCursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: active ? Ps5Colors.menuHighlight : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Ps5Colors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (widget.caption != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Ps5Colors.menuMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 16),
                    Text(
                      widget.trailing!,
                      style: const TextStyle(
                        color: Ps5Colors.menuMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  if (widget.control != null) ...[
                    const SizedBox(width: 16),
                    widget.control!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showPs5Confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0xAA000000),
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Ps5Panel(
            opaque: true,
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Ps5Colors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(
                    color: Ps5Colors.textMuted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Ps5Button(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 10),
                    Ps5Button(
                      autofocus: true,
                      primary: !destructive,
                      destructive: destructive,
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

Future<T?> showPs5OptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<({T value, String label, String? caption})> options,
  required T selected,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
          child: Ps5MenuPanel(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Ps5Colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
                      child: Column(
                        children: [
                          for (final option in options)
                            Ps5MenuChoiceRow(
                              label: option.label,
                              caption: option.caption,
                              selected: option.value == selected,
                              checked: option.value == selected,
                              autofocus: option.value == selected,
                              onTap: () => Navigator.of(ctx).pop(option.value),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 从屏幕右侧贴边滑入的 PS5 侧栏（设置、关于等）。
///
/// 点击遮罩或手柄 B 键关闭；内容区域自行滚动。
Future<T?> showPs5SideMenu<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  double width = 460,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x73000000),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonB ||
                  event.logicalKey == LogicalKeyboardKey.gameButton9)) {
            Navigator.of(ctx).pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Ps5MenuPanel(
                key: const ValueKey('ps5-side-menu'),
                width: width,
                borderRadius: 0,
                child: SizedBox(
                  height: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(26, 20, 16, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Ps5Colors.text,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            Ps5IconButton(
                              icon: Icons.close_rounded,
                              tooltip: '关闭',
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.6,
                        color: Color(0x32FFFFFF),
                      ),
                      Flexible(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final motion = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(motion),
          child: child,
        ),
      );
    },
  );
}

class Ps5FocusShine extends StatefulWidget {
  const Ps5FocusShine({
    super.key,
    required this.active,
    this.borderRadius = 12,
  });

  final bool active;
  final double borderRadius;

  @override
  State<Ps5FocusShine> createState() => _Ps5FocusShineState();
}

class _Ps5FocusShineState extends State<Ps5FocusShine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(Ps5FocusShine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller
        ..forward(from: 0)
        ..repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: CustomPaint(
              painter: _Ps5ShinePainter(progress: _controller.value),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _Ps5ShinePainter extends CustomPainter {
  const _Ps5ShinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final eased = Curves.easeInOutCubic.transform(progress);
    final origin = -1.45 + 3.05 * eased;
    final gloss = Paint()
      ..shader = LinearGradient(
        begin: Alignment(origin, origin),
        end: Alignment(origin + 0.72, origin + 0.72),
        colors: const [
          Color(0x00FFFFFF),
          Color(0x18FFFFFF),
          Color(0x66FFFFFF),
          Color(0x24FFFFFF),
          Color(0x00FFFFFF),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, gloss);

    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final direction = Offset(size.width / diagonal, size.height / diagonal);
    final normal = Offset(-direction.dy, direction.dx);
    final center = direction * (-diagonal * 0.35 + diagonal * 1.7 * eased);
    final reach = diagonal * 0.8;
    for (var ribbon = 0; ribbon < 3; ribbon++) {
      final path = Path();
      const samples = 42;
      for (var sample = 0; sample <= samples; sample++) {
        final across = -reach + reach * 2 * sample / samples;
        final ripple = math.sin(across / 18 + ribbon * 0.9) * (5.5 - ribbon);
        final point =
            center + normal * across + direction * (ripple + ribbon * 8);
        if (sample == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.32 - ribbon * 0.07)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 + ribbon * 1.3
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 + ribbon * 2),
      );
    }
  }

  @override
  bool shouldRepaint(_Ps5ShinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class Ps5FocusFrame extends StatelessWidget {
  const Ps5FocusFrame({
    super.key,
    required this.selected,
    required this.child,
    this.borderRadius = 18,
    this.innerRadius = 12,
  });

  final bool selected;
  final Widget child;
  final double borderRadius;
  final double innerRadius;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.all(selected ? 3 : 4),
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.96)
              : Colors.transparent,
          width: selected ? 2.2 : 0,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x8A000000),
                  blurRadius: 26,
                  spreadRadius: 1,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Ps5FocusShine(active: selected, borderRadius: innerRadius),
          ],
        ),
      ),
    );
  }
}

class Ps5MenuPanel extends StatelessWidget {
  const Ps5MenuPanel({
    super.key,
    required this.child,
    this.width,
    this.borderRadius = 3,
  });

  final Widget child;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Ps5Colors.menuPanel,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class Ps5MenuChoiceRow extends StatefulWidget {
  const Ps5MenuChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.checked,
    required this.onTap,
    this.caption,
    this.onHover,
    this.autofocus = false,
  });

  final String label;
  final String? caption;
  final bool selected;
  final bool checked;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback? onHover;

  @override
  State<Ps5MenuChoiceRow> createState() => _Ps5MenuChoiceRowState();
}

class _Ps5MenuChoiceRowState extends State<Ps5MenuChoiceRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => widget.onHover?.call(),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: active ? Ps5Colors.menuHighlight : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
                border: Border.all(
                  color: active
                      ? Colors.white.withValues(alpha: 0.78)
                      : Colors.transparent,
                  width: active ? 1.4 : 0,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: widget.checked
                        ? const Icon(
                            Icons.check_rounded,
                            color: Ps5Colors.text,
                            size: 18,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Ps5Colors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (widget.caption != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.caption!,
                            style: const TextStyle(
                              color: Ps5Colors.menuMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Ps5GameLibraryGlyph extends StatelessWidget {
  const Ps5GameLibraryGlyph({
    super.key,
    this.color = Colors.white,
    this.size = 54,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Ps5LibraryGlyphPainter(color: color)),
    );
  }
}

class _Ps5LibraryGlyphPainter extends CustomPainter {
  const _Ps5LibraryGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cell = size.width / 7.2;
    final gap = cell * 0.38;
    final top = size.height * 0.08;
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 3; col++) {
        final x = (size.width - (cell * 3 + gap * 2)) / 2 + col * (cell + gap);
        final y = top + row * (cell + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cell, cell),
            Radius.circular(cell * 0.22),
          ),
          paint,
        );
      }
    }
    final padLeft = size.width * 0.18;
    final padTop = size.height * 0.58;
    final pad = RRect.fromRectAndRadius(
      Rect.fromLTWH(padLeft, padTop, size.width * 0.64, size.height * 0.28),
      Radius.circular(size.width * 0.08),
    );
    canvas.drawRRect(pad, paint);
    canvas.drawCircle(
      Offset(padLeft + size.width * 0.14, padTop + size.height * 0.14),
      size.width * 0.055,
      paint,
    );
    canvas.drawCircle(
      Offset(
        padLeft + size.width * 0.64 - size.width * 0.14,
        padTop + size.height * 0.14,
      ),
      size.width * 0.055,
      paint,
    );
  }

  @override
  bool shouldRepaint(_Ps5LibraryGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
