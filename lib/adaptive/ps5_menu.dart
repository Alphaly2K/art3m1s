import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ps5_input.dart';
import 'ps5_chrome.dart';

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

/// PS5 两栏菜单：左侧选项，选中带 choices 的行时在右侧弹出选择列表。
Future<Ps5MenuResult<T>?> showPs5ListMenu<T>(
  BuildContext context, {
  required List<Ps5MenuSection<T>> sections,
  String? footerLabel,
  bool footerEnabled = false,
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
  });

  final List<Ps5MenuSection<T>> sections;
  final String? footerLabel;
  final bool footerEnabled;

  @override
  State<_Ps5ListMenuDialog<T>> createState() => _Ps5ListMenuDialogState<T>();
}

class _Ps5ListMenuDialogState<T> extends State<_Ps5ListMenuDialog<T>> {
  late List<_FlatItem<T>> _items;
  int _index = 0;
  bool _flyoutOpen = false;
  int _flyoutIndex = 0;

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
    _openFlyoutIfNeeded();
  }

  void _openFlyoutIfNeeded() {
    final item = _items[_index].item;
    _flyoutOpen = item.enabled && item.choices.isNotEmpty;
    if (_flyoutOpen) {
      final selected = item.choices.indexWhere(
        (choice) => choice.value == item.value,
      );
      _flyoutIndex = selected < 0 ? 0 : selected;
    }
  }

  void _move(int delta) {
    if (_items.isEmpty) return;
    if (_flyoutOpen) {
      final choices = _items[_index].item.choices;
      if (choices.isEmpty) return;
      setState(() {
        _flyoutIndex = (_flyoutIndex + delta).clamp(0, choices.length - 1);
      });
      return;
    }
    var next = _index;
    for (var step = 0; step < _items.length; step++) {
      next = (next + delta).clamp(0, _items.length - 1);
      if (_items[next].item.enabled) break;
    }
    setState(() {
      _index = next;
      _openFlyoutIfNeeded();
    });
  }

  void _activateLeft() {
    final item = _items[_index].item;
    if (!item.enabled) return;
    if (item.choices.isNotEmpty) {
      setState(() {
        _flyoutOpen = true;
        _openFlyoutIfNeeded();
      });
      return;
    }
    Navigator.of(
      context,
    ).pop(Ps5MenuResult<T>(itemId: item.id, value: item.value));
  }

  void _activateFlyout() {
    final item = _items[_index].item;
    if (!_flyoutOpen || item.choices.isEmpty) return;
    final choice = item.choices[_flyoutIndex];
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
        if (_flyoutOpen) {
          setState(() => _flyoutOpen = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case Ps5InputAction.right:
        if (_items[_index].item.choices.isNotEmpty) {
          setState(() {
            _flyoutOpen = true;
            _openFlyoutIfNeeded();
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case Ps5InputAction.accept:
        if (_flyoutOpen) {
          _activateFlyout();
        } else {
          _activateLeft();
        }
        return KeyEventResult.handled;
      case Ps5InputAction.back:
        if (_flyoutOpen) {
          setState(() => _flyoutOpen = false);
          return KeyEventResult.handled;
        }
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _items.isEmpty ? null : _items[_index];
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(72, 120, 24, 24),
            child: Row(
              key: const ValueKey('ps5-list-menu'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Ps5MenuPanel(
                  width: 312,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                          label: _items[i].item.label,
                          trailing: _items[i].item.trailing,
                          selected: i == _index,
                          enabled: _items[i].item.enabled,
                          destructive: _items[i].item.destructive,
                          onHover: () {
                            if (_index == i) return;
                            setState(() {
                              _index = i;
                              _openFlyoutIfNeeded();
                            });
                          },
                          onTap: () {
                            setState(() => _index = i);
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
                            onPressed: widget.footerEnabled
                                ? () => Navigator.of(
                                    context,
                                  ).pop(Ps5MenuResult<T>(itemId: 'reset'))
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (current != null &&
                    _flyoutOpen &&
                    current.item.choices.isNotEmpty) ...[
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
                              label: current.item.choices[i].label,
                              caption: current.item.choices[i].caption,
                              selected: i == _flyoutIndex,
                              checked:
                                  current.item.choices[i].value ==
                                  current.item.value,
                              onHover: () => setState(() => _flyoutIndex = i),
                              onTap: () {
                                setState(() => _flyoutIndex = i);
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
        ),
      ),
    );
  }
}

class _LeftRow extends StatelessWidget {
  const _LeftRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onHover,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final String label;
  final String? trailing;
  final bool selected;
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: selected ? Ps5Colors.menuHighlight : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
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
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? Ps5Colors.menuHighlight : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(1),
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
    );
  }
}
