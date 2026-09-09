import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:macos_ui/macos_ui.dart';

import '../adaptive/miuix_chrome.dart';

enum PlayerHudDock { none, left, right }

/// 悬浮球停靠与回弹的纯几何，便于单测。
class PlayerHudGeometry {
  static const double ballSize = 46;
  static const double peek = 14;
  static const double snap = 28;
  static const double margin = 12;
  static const double panelWidth = 228;
  static const double panelGap = 8;

  static Offset clampFree(Offset pos, Size size, EdgeInsets pad) {
    final minX = pad.left + margin;
    final maxX = math.max(minX, size.width - pad.right - ballSize - margin);
    final minY = pad.top + margin;
    final maxY = math.max(minY, size.height - pad.bottom - ballSize - margin);
    return Offset(pos.dx.clamp(minX, maxX), pos.dy.clamp(minY, maxY));
  }

  static ({Offset pos, PlayerHudDock dock}) settle(
    Offset pos,
    Size size,
    EdgeInsets pad,
  ) {
    final free = clampFree(pos, size, pad);
    if (pos.dx <= pad.left + snap) {
      return (
        pos: Offset(-(ballSize - peek), free.dy),
        dock: PlayerHudDock.left,
      );
    }
    if (pos.dx >= size.width - pad.right - ballSize - snap) {
      return (
        pos: Offset(size.width - peek, free.dy),
        dock: PlayerHudDock.right,
      );
    }
    return (pos: free, dock: PlayerHudDock.none);
  }

  static Offset undock(
    PlayerHudDock dock,
    double y,
    Size size,
    EdgeInsets pad,
  ) {
    if (dock == PlayerHudDock.right) {
      return clampFree(
        Offset(size.width - pad.right - ballSize - margin, y),
        size,
        pad,
      );
    }
    return clampFree(Offset(pad.left + margin, y), size, pad);
  }

  static Offset dockedPos(
    PlayerHudDock dock,
    double y,
    Size size,
    EdgeInsets pad,
  ) {
    final clampedY = clampFree(Offset(0, y), size, pad).dy;
    if (dock == PlayerHudDock.right) {
      return Offset(size.width - peek, clampedY);
    }
    return Offset(-(ballSize - peek), clampedY);
  }

  static Offset panelOrigin({
    required Offset ball,
    required Size size,
    required double panelHeight,
  }) {
    var x = ball.dx;
    var y = ball.dy + ballSize + panelGap;
    if (x + panelWidth > size.width - 8) {
      x = size.width - panelWidth - 8;
    }
    if (x < 8) x = 8;
    if (y + panelHeight > size.height - 8) {
      y = ball.dy - panelHeight - panelGap;
    }
    if (y < 8) y = 8;
    return Offset(x, y);
  }
}

enum _HudChrome { material, miuix, cupertino, macos, fluent }

/// 游戏内可拖动、可贴边隐藏的控制球。外观跟当前壳走。
class PlayerHud extends StatefulWidget {
  const PlayerHud({
    super.key,
    required this.title,
    required this.showFps,
    required this.keyboardShown,
    required this.touchpadEnabled,
    required this.showTouchpadToggle,
    required this.showKeyboardToggle,
    required this.onShowFpsChanged,
    required this.onToggleKeyboard,
    required this.onTouchpadChanged,
    required this.onExit,
  });

  final String title;
  final bool showFps;
  final bool keyboardShown;
  final bool touchpadEnabled;
  final bool showTouchpadToggle;
  final bool showKeyboardToggle;
  final ValueChanged<bool> onShowFpsChanged;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<bool> onTouchpadChanged;
  final VoidCallback onExit;

  @override
  State<PlayerHud> createState() => _PlayerHudState();
}

class _PlayerHudState extends State<PlayerHud> {
  Offset _pos = const Offset(16, 60);
  PlayerHudDock _dock = PlayerHudDock.none;
  bool _panelOpen = false;
  bool _dragging = false;
  Timer? _panelTimer;
  static const _autoHide = Duration(milliseconds: 4000);

  @override
  void dispose() {
    _panelTimer?.cancel();
    super.dispose();
  }

  _HudChrome _chrome(BuildContext context) {
    if (usesMiuixChrome(context)) return _HudChrome.miuix;
    if (Platform.isIOS) return _HudChrome.cupertino;
    if (Platform.isMacOS && MacosTheme.maybeOf(context) != null) {
      return _HudChrome.macos;
    }
    if (Platform.isWindows && fluent.FluentTheme.maybeOf(context) != null) {
      return _HudChrome.fluent;
    }
    return _HudChrome.material;
  }

  void _resetTimer() {
    _panelTimer?.cancel();
    _panelTimer = Timer(_autoHide, () {
      if (mounted) setState(() => _panelOpen = false);
    });
  }

  void _closePanel() {
    _panelTimer?.cancel();
    if (_panelOpen) setState(() => _panelOpen = false);
  }

  void _onTap(Size size, EdgeInsets pad) {
    if (_dock != PlayerHudDock.none) {
      setState(() {
        _pos = PlayerHudGeometry.undock(_dock, _pos.dy, size, pad);
        _dock = PlayerHudDock.none;
        _panelOpen = true;
      });
      _resetTimer();
      return;
    }
    setState(() => _panelOpen = !_panelOpen);
    if (_panelOpen) {
      _resetTimer();
    } else {
      _panelTimer?.cancel();
    }
  }

  void _onPanStart() {
    _panelTimer?.cancel();
    setState(() {
      _dragging = true;
      _panelOpen = false;
      if (_dock != PlayerHudDock.none) {
        _dock = PlayerHudDock.none;
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size size, EdgeInsets pad) {
    setState(() {
      _pos = PlayerHudGeometry.clampFree(_pos + details.delta, size, pad);
    });
  }

  void _onPanEnd(Size size, EdgeInsets pad) {
    final settled = PlayerHudGeometry.settle(_pos, size, pad);
    setState(() {
      _pos = settled.pos;
      _dock = settled.dock;
      _dragging = false;
      _panelOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = _chrome(context);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final pad = MediaQuery.paddingOf(context);
          final ball = _dock == PlayerHudDock.none
              ? PlayerHudGeometry.clampFree(_pos, size, pad)
              : PlayerHudGeometry.dockedPos(_dock, _pos.dy, size, pad);
          return Stack(
            children: [
              if (_panelOpen && _dock == PlayerHudDock.none)
                _buildPanel(context, chrome, size, ball),
              AnimatedPositioned(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: ball.dx,
                top: ball.dy,
                child: GestureDetector(
                  onTap: () => _onTap(size, pad),
                  onPanStart: (_) => _onPanStart(),
                  onPanUpdate: (d) => _onPanUpdate(d, size, pad),
                  onPanEnd: (_) => _onPanEnd(size, pad),
                  child: _buildBall(context, chrome),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBall(BuildContext context, _HudChrome chrome) {
    final open = _panelOpen && _dock == PlayerHudDock.none;
    final icon = open ? Icons.close : Icons.tune;
    return switch (chrome) {
      _HudChrome.material => _MaterialBall(open: open, icon: icon),
      _HudChrome.miuix => _MiuixBall(open: open, icon: icon),
      _HudChrome.cupertino => _CupertinoBall(open: open),
      _HudChrome.macos => _MacosBall(open: open),
      _HudChrome.fluent => _FluentBall(open: open, icon: icon),
    };
  }

  Widget _buildPanel(
    BuildContext context,
    _HudChrome chrome,
    Size size,
    Offset ball,
  ) {
    const estimatedHeight = 248.0;
    final origin = PlayerHudGeometry.panelOrigin(
      ball: ball,
      size: size,
      panelHeight: estimatedHeight,
    );
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (_) => _resetTimer(),
        onPointerMove: (_) => _resetTimer(),
        child: _HudPanel(
          chrome: chrome,
          title: widget.title,
          showFps: widget.showFps,
          keyboardShown: widget.keyboardShown,
          touchpadEnabled: widget.touchpadEnabled,
          showTouchpadToggle: widget.showTouchpadToggle,
          showKeyboardToggle: widget.showKeyboardToggle,
          onClose: _closePanel,
          onShowFpsChanged: () {
            widget.onShowFpsChanged(!widget.showFps);
            _resetTimer();
          },
          onToggleKeyboard: () {
            widget.onToggleKeyboard();
            _resetTimer();
          },
          onTouchpadChanged: () {
            widget.onTouchpadChanged(!widget.touchpadEnabled);
            _resetTimer();
          },
          onExit: widget.onExit,
        ),
      ),
    );
  }
}

class _HudPanel extends StatelessWidget {
  const _HudPanel({
    required this.chrome,
    required this.title,
    required this.showFps,
    required this.keyboardShown,
    required this.touchpadEnabled,
    required this.showTouchpadToggle,
    required this.showKeyboardToggle,
    required this.onClose,
    required this.onShowFpsChanged,
    required this.onToggleKeyboard,
    required this.onTouchpadChanged,
    required this.onExit,
  });

  final _HudChrome chrome;
  final String title;
  final bool showFps;
  final bool keyboardShown;
  final bool touchpadEnabled;
  final bool showTouchpadToggle;
  final bool showKeyboardToggle;
  final VoidCallback onClose;
  final VoidCallback onShowFpsChanged;
  final VoidCallback onToggleKeyboard;
  final VoidCallback onTouchpadChanged;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return switch (chrome) {
      _HudChrome.material => _material(context),
      _HudChrome.miuix => _miuix(context),
      _HudChrome.cupertino => _cupertino(context),
      _HudChrome.macos => _macos(context),
      _HudChrome.fluent => _fluent(context),
    };
  }

  List<_HudItem> get _items => [
    _HudItem(label: '帧率', on: showFps, onTap: onShowFpsChanged),
    if (showKeyboardToggle)
      _HudItem(label: '虚拟键盘', on: keyboardShown, onTap: onToggleKeyboard),
    if (showTouchpadToggle)
      _HudItem(label: '触摸板鼠标', on: touchpadEnabled, onTap: onTouchpadChanged),
    _HudItem(label: '退出游戏', destructive: true, onTap: onExit),
  ];

  Widget _material(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: PlayerHudGeometry.panelWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, color: scheme.onSurface, onClose: onClose),
            for (final item in _items)
              ListTile(
                dense: true,
                title: Text(
                  item.label,
                  style: TextStyle(
                    color: item.destructive ? scheme.error : scheme.onSurface,
                  ),
                ),
                trailing: item.on == null
                    ? null
                    : Switch.adaptive(
                        value: item.on!,
                        onChanged: (_) => item.onTap(),
                      ),
                onTap: item.onTap,
              ),
          ],
        ),
      ),
    );
  }

  Widget _miuix(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return SizedBox(
      width: PlayerHudGeometry.panelWidth,
      child: MiuixCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, color: theme.colors.onSurface, onClose: onClose),
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) const MiuixInsetDivider(),
              if (_items[i].on != null)
                MiuixSwitchPreference(
                  title: _items[i].label,
                  value: _items[i].on!,
                  onChanged: (_) => _items[i].onTap(),
                )
              else
                MiuixBasicComponent(
                  title: _items[i].label,
                  titleColor: _items[i].destructive
                      ? MiuixBasicComponentColors(
                          color: theme.colors.error,
                          disabledColor: theme.colors.disabledOnSurface,
                        )
                      : null,
                  onClick: _items[i].onTap,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cupertino(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: PlayerHudGeometry.panelWidth,
          color: CupertinoColors.secondarySystemBackground
              .resolveFrom(context)
              .withValues(alpha: 0.86),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context, color: label, onClose: onClose),
              for (final item in _items)
                CupertinoListTile(
                  title: Text(
                    item.label,
                    style: TextStyle(
                      color: item.destructive
                          ? CupertinoColors.destructiveRed
                          : label,
                    ),
                  ),
                  trailing: item.on == null
                      ? null
                      : CupertinoSwitch(
                          value: item.on!,
                          onChanged: (_) => item.onTap(),
                        ),
                  onTap: item.onTap,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _macos(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: PlayerHudGeometry.panelWidth,
      decoration: BoxDecoration(
        color: dark ? const Color(0xF22C2C2E) : const Color(0xF5F6F6F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dark ? const Color(0x33FFFFFF) : const Color(0x22000000),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(
            context,
            color: theme.typography.body.color ?? const Color(0xFF1D1D1F),
            onClose: onClose,
          ),
          for (final item in _items) _MacosRow(item: item),
        ],
      ),
    );
  }

  Widget _fluent(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    return fluent.Acrylic(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: PlayerHudGeometry.panelWidth,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(
              context,
              color: theme.resources.textFillColorPrimary,
              onClose: onClose,
            ),
            for (final item in _items)
              fluent.ListTile(
                title: Text(
                  item.label,
                  style: TextStyle(
                    color: item.destructive
                        ? const Color(0xFFC42B1C)
                        : theme.resources.textFillColorPrimary,
                  ),
                ),
                trailing: item.on == null
                    ? null
                    : fluent.ToggleSwitch(
                        checked: item.on!,
                        onChanged: (_) => item.onTap(),
                      ),
                onPressed: item.onTap,
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required Color color,
    required VoidCallback onClose,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.close,
                size: 16,
                color: color.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudItem {
  const _HudItem({
    required this.label,
    required this.onTap,
    this.on,
    this.destructive = false,
  });

  final String label;
  final bool? on;
  final bool destructive;
  final VoidCallback onTap;
}

class _MacosRow extends StatelessWidget {
  const _MacosRow({required this.item});

  final _HudItem item;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                style: theme.typography.body.copyWith(
                  color: item.destructive ? MacosColors.systemRedColor : null,
                ),
              ),
            ),
            if (item.on != null)
              MacosSwitch(value: item.on!, onChanged: (_) => item.onTap()),
          ],
        ),
      ),
    );
  }
}

class _MaterialBall extends StatelessWidget {
  const _MaterialBall({required this.open, required this.icon});

  final bool open;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: open ? 6 : 3,
      shape: const CircleBorder(),
      color: scheme.primaryContainer,
      child: SizedBox(
        width: PlayerHudGeometry.ballSize,
        height: PlayerHudGeometry.ballSize,
        child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
      ),
    );
  }
}

class _MiuixBall extends StatelessWidget {
  const _MiuixBall({required this.open, required this.icon});

  final bool open;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Container(
      width: PlayerHudGeometry.ballSize,
      height: PlayerHudGeometry.ballSize,
      decoration: BoxDecoration(
        color: open ? theme.colors.primary : theme.colors.surfaceContainerHigh,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: 20,
        color: open ? theme.colors.onPrimary : theme.colors.onSurface,
      ),
    );
  }
}

class _CupertinoBall extends StatelessWidget {
  const _CupertinoBall({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: PlayerHudGeometry.ballSize,
          height: PlayerHudGeometry.ballSize,
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          child: Icon(
            open ? CupertinoIcons.xmark : CupertinoIcons.slider_horizontal_3,
            size: 18,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

class _MacosBall extends StatelessWidget {
  const _MacosBall({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final dark = MacosTheme.of(context).brightness == Brightness.dark;
    return Container(
      width: PlayerHudGeometry.ballSize,
      height: PlayerHudGeometry.ballSize,
      decoration: BoxDecoration(
        color: dark ? const Color(0xF23A3A3C) : const Color(0xF5FFFFFF),
        shape: BoxShape.circle,
        border: Border.all(
          color: dark ? const Color(0x33FFFFFF) : const Color(0x33000000),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: MacosIcon(
        open ? CupertinoIcons.xmark : CupertinoIcons.slider_horizontal_3,
        size: 16,
        color: dark ? const Color(0xFFE4E4E7) : const Color(0xFF1D1D1F),
      ),
    );
  }
}

class _FluentBall extends StatelessWidget {
  const _FluentBall({required this.open, required this.icon});

  final bool open;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    return fluent.Acrylic(
      shape: const CircleBorder(),
      child: Container(
        width: PlayerHudGeometry.ballSize,
        height: PlayerHudGeometry.ballSize,
        alignment: Alignment.center,
        color: open
            ? theme.accentColor.darker
            : theme.resources.controlFillColorSecondary,
        child: Icon(
          icon,
          size: 18,
          color: theme.resources.textFillColorPrimary,
        ),
      ),
    );
  }
}
