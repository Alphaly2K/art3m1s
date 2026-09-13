import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adaptive/ps5_chrome.dart';
import '../adaptive/ps5_sounds.dart';
import '../controllers/ps5_input.dart';

/// 大屏游戏内的底部控制台。
///
/// 只占用屏幕下方，保留游戏画面作为上下文；操作项保持扁平轨道，
/// 避免用装饰性大卡片稀释真正可用的游戏控制。
class Ps5PlayerMenu extends StatefulWidget {
  const Ps5PlayerMenu({
    super.key,
    required this.title,
    required this.showFps,
    required this.onShowFpsChanged,
    required this.onResume,
    required this.onExit,
  });

  final String title;
  final bool showFps;
  final ValueChanged<bool> onShowFpsChanged;
  final VoidCallback onResume;
  final VoidCallback onExit;

  @override
  State<Ps5PlayerMenu> createState() => _Ps5PlayerMenuState();
}

class _Ps5PlayerMenuState extends State<Ps5PlayerMenu> {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonB): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.gameButton9): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonStart): Ps5MenuIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonMode): Ps5MenuIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                Ps5UiSounds.back();
                widget.onResume();
                return null;
              },
            ),
            Ps5MenuIntent: CallbackAction<Ps5MenuIntent>(
              onInvoke: (_) {
                Ps5UiSounds.back();
                widget.onResume();
                return null;
              },
            ),
          },
          child: FocusTraversalGroup(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('ps5-player-menu-backdrop'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onResume,
                    child: _Ps5PlayerMenuBackdrop(),
                  ),
                ),
                Positioned(
                  left: 30,
                  right: 30,
                  top: 22,
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Ps5Colors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        const _Ps5MenuClock(),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 22,
                  child: SafeArea(
                    top: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(2, 0, 2, 9),
                              child: Row(
                                children: [
                                  Text(
                                    '游戏菜单',
                                    style: TextStyle(
                                      color: Ps5Colors.text,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    '游戏已暂停',
                                    style: TextStyle(
                                      color: Ps5Colors.menuMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Ps5MenuPanel(
                              key: const ValueKey('ps5-player-menu'),
                              child: SizedBox(
                                height: 92,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _Ps5PlayerAction(
                                        key: const ValueKey(
                                          'ps5-player-action-resume',
                                        ),
                                        icon: Icons.play_arrow_rounded,
                                        label: '继续游戏',
                                        caption: '返回当前进度',
                                        autofocus: true,
                                        onPressed: widget.onResume,
                                      ),
                                    ),
                                    const _Ps5PlayerActionDivider(),
                                    Expanded(
                                      child: _Ps5PlayerAction(
                                        key: const ValueKey(
                                          'ps5-player-action-fps',
                                        ),
                                        icon: Icons.speed_rounded,
                                        label: '显示帧率',
                                        caption: widget.showFps ? '已开启' : '已关闭',
                                        onPressed: () {
                                          widget.onShowFpsChanged(
                                            !widget.showFps,
                                          );
                                        },
                                      ),
                                    ),
                                    const _Ps5PlayerActionDivider(),
                                    Expanded(
                                      child: _Ps5PlayerAction(
                                        key: const ValueKey(
                                          'ps5-player-action-exit',
                                        ),
                                        icon: Icons.power_settings_new_rounded,
                                        label: '退出游戏',
                                        caption: '返回资料库',
                                        destructive: true,
                                        onPressed: widget.onExit,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 11),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _Ps5PlayerHint(
                                    input: 'ESC / MENU',
                                    label: '返回游戏',
                                  ),
                                  SizedBox(width: 28),
                                  _Ps5PlayerHint(
                                    input: 'ENTER / ×',
                                    label: '选择',
                                  ),
                                ],
                              ),
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
      ),
    );
  }
}

class _Ps5PlayerMenuBackdrop extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: const ColoredBox(color: Color(0x52000000)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x08000000), Color(0xC905080D)],
              stops: [0.2, 0.78],
            ),
          ),
        ),
      ],
    );
  }
}

class _Ps5PlayerAction extends StatefulWidget {
  const _Ps5PlayerAction({
    super.key,
    required this.icon,
    required this.label,
    required this.caption,
    required this.onPressed,
    this.destructive = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onPressed;
  final bool destructive;
  final bool autofocus;

  @override
  State<_Ps5PlayerAction> createState() => _Ps5PlayerActionState();
}

class _Ps5PlayerActionState extends State<_Ps5PlayerAction> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  void _activate() {
    Ps5UiSounds.confirm();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    final foreground = active
        ? Ps5Colors.text
        : widget.destructive
        ? Ps5Colors.danger
        : Ps5Colors.textMuted;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (value) {
        if (value) Ps5UiSounds.tick();
        setState(() => _focused = value);
      },
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
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: widget.label,
        hint: widget.caption,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _activate,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed ? 0.985 : 1,
              duration: const Duration(milliseconds: 90),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: active
                      ? Ps5Colors.menuHighlight.withValues(alpha: 0.82)
                      : Colors.transparent,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 25, color: foreground),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Ps5Colors.menuMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ps5PlayerActionDivider extends StatelessWidget {
  const _Ps5PlayerActionDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: VerticalDivider(width: 1, thickness: 1, color: Ps5Colors.line),
    );
  }
}

class _Ps5PlayerHint extends StatelessWidget {
  const _Ps5PlayerHint({required this.input, required this.label});

  final String input;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          input,
          style: const TextStyle(
            color: Ps5Colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Ps5Colors.menuMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Ps5MenuClock extends StatefulWidget {
  const _Ps5MenuClock();

  @override
  State<_Ps5MenuClock> createState() => _Ps5MenuClockState();
}

class _Ps5MenuClockState extends State<_Ps5MenuClock> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hour:$minute',
      style: const TextStyle(
        color: Ps5Colors.text,
        fontSize: 22,
        fontWeight: FontWeight.w300,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
