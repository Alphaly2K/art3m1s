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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? Ps5Colors.accent : Ps5Colors.line,
          width: selected ? 1.4 : 0.8,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Ps5Colors.accentSoft,
                  blurRadius: 22,
                  spreadRadius: 1,
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
          padding: const EdgeInsets.only(left: 2, bottom: 10),
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
        Ps5Panel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Ps5Colors.line),
                children[i],
              ],
            ],
          ),
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
    required this.control,
  });

  final String label;
  final String? caption;
  final Widget control;

  @override
  Widget build(BuildContext context) {
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
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Ps5Colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 24),
          control,
        ],
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
    barrierColor: const Color(0xAA000000),
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Ps5Panel(
            opaque: true,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 16),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Ps5Colors.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final option in options)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: option.value == selected
                                  ? Ps5Colors.accentSoft
                                  : Ps5Colors.backgroundRaised,
                              borderRadius: BorderRadius.circular(7),
                              child: InkWell(
                                onTap: () =>
                                    Navigator.of(ctx).pop(option.value),
                                autofocus: option.value == selected,
                                borderRadius: BorderRadius.circular(7),
                                hoverColor: Ps5Colors.panelHover,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              option.label,
                                              style: TextStyle(
                                                color: option.value == selected
                                                    ? Ps5Colors.accent
                                                    : Ps5Colors.text,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (option.caption != null) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                option.caption!,
                                                style: const TextStyle(
                                                  color: Ps5Colors.textMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (option.value == selected)
                                        const Icon(
                                          Icons.check_rounded,
                                          color: Ps5Colors.accent,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
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
