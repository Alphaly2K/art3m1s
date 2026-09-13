import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ps5_input.dart';
import 'ps5_chrome.dart';
import 'ps5_sounds.dart';

class Ps5MenuChoice<T> {
  const Ps5MenuChoice({required this.value, required this.label, this.caption});

  final T value;
  final String label;
  final String? caption;
}

class Ps5MenuItem<T> {
  const Ps5MenuItem({
    required this.id,
    required this.label,
    this.trailing,
    this.choices = const [],
    this.value,
    this.enabled = true,
    this.destructive = false,
  });

  final String id;
  final String label;
  final String? trailing;
  final List<Ps5MenuChoice<T>> choices;
  final T? value;
  final bool enabled;
  final bool destructive;
}

class Ps5MenuSection<T> {
  const Ps5MenuSection({this.title, required this.items});

  final String? title;
  final List<Ps5MenuItem<T>> items;
}

class Ps5MenuResult<T> {
  const Ps5MenuResult({required this.itemId, this.value});

  final String itemId;
  final T? value;
}

/// PS5 两栏菜单：左侧选项，选中带 choices 的行并确认后进入右侧选择列表。
///
/// 手柄按层层选中、层层进入：方向键上下先走第一级，确认/右键进入子菜单，
/// 左键或返回退回第一级。[anchor] 不为空时菜单贴在锚点右侧。
Future<Ps5MenuResult<T>?> showPs5ListMenu<T>(
  BuildContext context, {
  required List<Ps5MenuSection<T>> sections,
  String? footerLabel,
  bool footerEnabled = false,
  Rect? anchor,
  Widget? header,
}) {
  return showGeneralDialog<Ps5MenuResult<T>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _Ps5ListMenuDialog<T>(
        sections: sections,
        footerLabel: footerLabel,
        footerEnabled: footerEnabled,
        anchor: anchor,
        header: header,
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.03, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _FlatItem<T> {
  const _FlatItem({
    required this.item,
    this.sectionTitle,
    this.showTitle = false,
  });

  final Ps5MenuItem<T> item;
  final String? sectionTitle;
  final bool showTitle;
}

class _Ps5ListMenuDialog<T> extends StatefulWidget {
  const _Ps5ListMenuDialog({
    required this.sections,
    this.footerLabel,
    this.footerEnabled = false,
    this.anchor,
    this.header,
  });

  final List<Ps5MenuSection<T>> sections;
  final String? footerLabel;
  final bool footerEnabled;
  final Rect? anchor;
  final Widget? header;

  @override
  State<_Ps5ListMenuDialog<T>> createState() => _Ps5ListMenuDialogState<T>();
}

class _Ps5ListMenuDialogState<T> extends State<_Ps5ListMenuDialog<T>> {
  late List<_FlatItem<T>> _items;
  int _index = 0;
  bool _inFlyout = false;
  int _flyoutIndex = 0;

  bool get _hasFooter => widget.footerLabel != null;

  int get _leftCount => _items.length + (_hasFooter ? 1 : 0);

  bool get _footerFocused => _hasFooter && _index == _items.length;

  bool get _leftActive => !_inFlyout;

  bool get _flyoutVisible {
    if (_footerFocused || _index < 0 || _index >= _items.length) return false;
    final item = _items[_index].item;
    return item.enabled && item.choices.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _items = [
      for (final section in widget.sections)
        for (var i = 0; i < section.items.length; i++)
          _FlatItem(
            item: section.items[i],
            sectionTitle: section.title,
            showTitle: i == 0 && section.title != null,
          ),
    ];
    final firstEnabled = _items.indexWhere((item) => item.item.enabled);
    _index = firstEnabled < 0 ? 0 : firstEnabled;
    _syncFlyoutIndex();
  }

  void _syncFlyoutIndex() {
    if (_footerFocused || _index < 0 || _index >= _items.length) {
      _inFlyout = false;
      return;
    }
    final item = _items[_index].item;
    if (!item.enabled || item.choices.isEmpty) {
      _inFlyout = false;
      return;
    }
    final selected = item.choices.indexWhere(
      (choice) => choice.value == item.value,
    );
    _flyoutIndex = selected < 0 ? 0 : selected;
  }

  bool _leftEnabled(int index) {
    if (index < 0 || index >= _leftCount) return false;
    if (index == _items.length) return widget.footerEnabled;
    return _items[index].item.enabled;
  }

  void _move(int delta) {
    if (_leftCount == 0) return;
    if (_inFlyout) {
      final choices = _items[_index].item.choices;
      if (choices.isEmpty) return;
      Ps5UiSounds.tick();
      setState(() {
        _flyoutIndex = (_flyoutIndex + delta).clamp(0, choices.length - 1);
      });
      return;
    }
    var next = _index;
    for (var step = 0; step < _leftCount; step++) {
      final candidate = next + delta;
      if (candidate < 0 || candidate >= _leftCount) break;
      next = candidate;
      if (_leftEnabled(next)) break;
    }
    if (next != _index) Ps5UiSounds.tick();
    setState(() {
      _index = next;
      _inFlyout = false;
      _syncFlyoutIndex();
    });
  }

  void _enterFlyout() {
    if (!_flyoutVisible) return;
    setState(() {
      _inFlyout = true;
      _syncFlyoutIndex();
    });
  }

  void _leaveFlyout() {
    if (!_inFlyout) return;
    setState(() => _inFlyout = false);
  }

  void _activateLeft() {
    if (_footerFocused) {
      if (!widget.footerEnabled) return;
      Ps5UiSounds.confirm();
      Navigator.of(context).pop(Ps5MenuResult<T>(itemId: 'reset'));
      return;
    }
    final item = _items[_index].item;
    if (!item.enabled) return;
    if (item.choices.isNotEmpty) {
      Ps5UiSounds.confirm();
      _enterFlyout();
      return;
    }
    Ps5UiSounds.confirm();
    Navigator.of(
      context,
    ).pop(Ps5MenuResult<T>(itemId: item.id, value: item.value));
  }

  void _activateFlyout() {
    final item = _items[_index].item;
    if (!_inFlyout || item.choices.isEmpty) return;
    final choice = item.choices[_flyoutIndex];
    Ps5UiSounds.confirm();
    Navigator.of(
      context,
    ).pop(Ps5MenuResult<T>(itemId: item.id, value: choice.value));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final action = ps5InputAction(event.logicalKey);
    switch (action) {
      case Ps5InputAction.up:
        _move(-1);
        return KeyEventResult.handled;
      case Ps5InputAction.down:
        _move(1);
        return KeyEventResult.handled;
      case Ps5InputAction.left:
        if (_inFlyout) {
          _leaveFlyout();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case Ps5InputAction.right:
        if (_flyoutVisible && !_inFlyout) {
          _enterFlyout();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case Ps5InputAction.accept:
        if (_inFlyout) {
          _activateFlyout();
        } else {
          _activateLeft();
        }
        return KeyEventResult.handled;
      case Ps5InputAction.back:
        if (_inFlyout) {
          Ps5UiSounds.back();
          _leaveFlyout();
          return KeyEventResult.handled;
        }
        Ps5UiSounds.back();
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = (!_footerFocused && _index >= 0 && _index < _items.length)
        ? _items[_index]
        : null;
    final safe = MediaQuery.paddingOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: CustomSingleChildLayout(
        delegate: _Ps5MenuPlacementDelegate(
          anchor: widget.anchor,
          safePadding: safe,
        ),
        child: Row(
          key: const ValueKey('ps5-list-menu'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Ps5MenuPanel(
              width: 312,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.header != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: widget.header!,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Divider(
                          height: 1,
                          thickness: 0.6,
                          color: Color(0x22FFFFFF),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    for (var i = 0; i < _items.length; i++) ...[
                      if (_items[i].showTitle)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
                          child: Text(
                            _items[i].sectionTitle!,
                            style: const TextStyle(
                              color: Ps5Colors.menuMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      if (i > 0 &&
                          _items[i].sectionTitle != null &&
                          _items[i].showTitle)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Divider(
                            height: 1,
                            thickness: 0.6,
                            color: Color(0x22FFFFFF),
                          ),
                        ),
                      _LeftRow(
                        key: ValueKey('ps5-menu-item-${_items[i].item.id}'),
                        label: _items[i].item.label,
                        trailing: _items[i].item.trailing,
                        selected: _leftActive && i == _index,
                        marked: i == _index,
                        enabled: _items[i].item.enabled,
                        destructive: _items[i].item.destructive,
                        onHover: () {
                          if (_index == i && !_inFlyout) return;
                          setState(() {
                            _index = i;
                            _inFlyout = false;
                            _syncFlyoutIndex();
                          });
                        },
                        onTap: () {
                          setState(() {
                            _index = i;
                            _inFlyout = false;
                          });
                          _activateLeft();
                        },
                      ),
                    ],
                    if (widget.footerLabel != null) ...[
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: _FooterButton(
                          label: widget.footerLabel!,
                          enabled: widget.footerEnabled,
                          selected: _leftActive && _footerFocused,
                          onPressed: widget.footerEnabled
                              ? () => Navigator.of(
                                  context,
                                ).pop(Ps5MenuResult<T>(itemId: 'reset'))
                              : null,
                          onHover: widget.footerEnabled
                              ? () {
                                  if (_footerFocused && !_inFlyout) return;
                                  setState(() {
                                    _index = _items.length;
                                    _inFlyout = false;
                                  });
                                }
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (current != null && _flyoutVisible) ...[
              const SizedBox(width: 10),
              Ps5MenuPanel(
                width: 340,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < current.item.choices.length; i++)
                        Ps5MenuChoiceRow(
                          key: ValueKey(
                            _inFlyout && i == _flyoutIndex
                                ? 'ps5-flyout-selected'
                                : 'ps5-menu-choice-$i',
                          ),
                          label: current.item.choices[i].label,
                          caption: current.item.choices[i].caption,
                          selected: _inFlyout && i == _flyoutIndex,
                          checked:
                              current.item.choices[i].value ==
                              current.item.value,
                          onHover: () => setState(() {
                            _inFlyout = true;
                            _flyoutIndex = i;
                          }),
                          onTap: () {
                            setState(() {
                              _inFlyout = true;
                              _flyoutIndex = i;
                            });
                            _activateFlyout();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Ps5MenuPlacementDelegate extends SingleChildLayoutDelegate {
  const _Ps5MenuPlacementDelegate({
    required this.anchor,
    required this.safePadding,
  });

  final Rect? anchor;
  final EdgeInsets safePadding;

  static const double _gap = 12;
  static const double _margin = 24;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    if (anchor == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    var x = anchor!.right + _gap;
    if (x + childSize.width > size.width - _margin) {
      x = anchor!.left - _gap - childSize.width;
    }
    final maxX = size.width > childSize.width
        ? size.width - childSize.width
        : 0.0;
    x = x.clamp(_margin < maxX ? _margin : 0.0, maxX);

    var y = anchor!.top;
    if (y + childSize.height > size.height - _margin) {
      y = size.height - childSize.height - _margin;
    }
    final maxY = size.height > childSize.height
        ? size.height - childSize.height
        : 0.0;
    y = y.clamp(_margin < maxY ? _margin : 0.0, maxY);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_Ps5MenuPlacementDelegate oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.safePadding != safePadding;
  }
}

class _LeftRow extends StatelessWidget {
  const _LeftRow({
    super.key,
    required this.label,
    required this.selected,
    required this.marked,
    required this.enabled,
    required this.onHover,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final String label;
  final String? trailing;
  final bool selected;
  final bool marked;
  final bool enabled;
  final bool destructive;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Ps5Colors.menuMuted.withValues(alpha: 0.45)
        : destructive
        ? Ps5Colors.danger
        : Ps5Colors.text;
    return Padding(
      key: selected ? const ValueKey('ps5-menu-selected') : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Ps5Colors.menuHighlight
                      : marked
                      ? const Color(0x14FFFFFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF656A72)
                        : Colors.transparent,
                    width: selected ? 1 : 0,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: TextStyle(
                          color: enabled ? Ps5Colors.menuMuted : color,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Ps5AnimatedFocusBorder(
                  active: selected,
                  borderRadius: 1,
                  strokeWidth: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.enabled,
    required this.selected,
    required this.onPressed,
    this.onHover,
  });

  final String label;
  final bool enabled;
  final bool selected;
  final VoidCallback? onPressed;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover?.call(),
      child: GestureDetector(
        onTap: onPressed,
        child: Stack(
          children: [
            AnimatedContainer(
              key: selected ? const ValueKey('ps5-menu-selected') : null,
              duration: const Duration(milliseconds: 140),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? Ps5Colors.menuHighlight
                    : enabled
                    ? const Color(0x22FFFFFF)
                    : const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(1),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF656A72)
                      : Colors.transparent,
                  width: selected ? 1 : 0,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? Ps5Colors.text
                      : Ps5Colors.menuMuted.withValues(alpha: 0.55),
                  fontSize: 15,
                ),
              ),
            ),
            Positioned.fill(
              child: Ps5AnimatedFocusBorder(
                active: selected,
                borderRadius: 1,
                strokeWidth: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
