import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adaptive/ps5_chrome.dart';
import '../adaptive/ps5_sounds.dart';

/// 弹出 PS5 风格软键盘，返回输入文本；取消（Esc / 手柄 B / 取消键）返回 null。
Future<String?> showPs5OnScreenKeyboard(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? hintText,
  bool obscureText = false,
  TextInputType? keyboardType,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '关闭',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _Ps5OnScreenKeyboard(
        title: title,
        initialValue: initialValue,
        hintText: hintText,
        obscureText: obscureText,
        keyboardType: keyboardType,
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
}

const _activateShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
};

class _Ps5OnScreenKeyboard extends StatefulWidget {
  const _Ps5OnScreenKeyboard({
    required this.title,
    required this.initialValue,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
  });

  final String title;
  final String initialValue;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  State<_Ps5OnScreenKeyboard> createState() => _Ps5OnScreenKeyboardState();
}

class _Ps5OnScreenKeyboardState extends State<_Ps5OnScreenKeyboard> {
  static const _lettersTop = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _lettersMiddle = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _lettersBottom = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];
  static const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _symbols = ['-', '_', '.', '@', '/', ':', ';', "'", '"'];

  late String _text = widget.initialValue;
  bool _uppercase = false;

  bool get _numbersOnly => widget.keyboardType == TextInputType.number;

  void _insert(String char) {
    Ps5UiSounds.confirm();
    setState(() => _text += char);
  }

  void _backspace() {
    if (_text.isEmpty) return;
    Ps5UiSounds.confirm();
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  void _toggleCase() {
    Ps5UiSounds.confirm();
    setState(() => _uppercase = !_uppercase);
  }

  void _submit() {
    Ps5UiSounds.confirm();
    Navigator.of(context).pop(_text);
  }

  void _cancel() {
    Ps5UiSounds.back();
    Navigator.of(context).pop();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.gameButton9) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final hardware = HardwareKeyboard.instance;
    if (hardware.isControlPressed ||
        hardware.isMetaPressed ||
        hardware.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character != null && character.isNotEmpty) {
      final code = character.codeUnitAt(0);
      if (code >= 32 && code != 127) {
        _insert(character);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.obscureText ? '•' * _text.length : _text;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, 0.45),
          child: Ps5MenuPanel(
            width: 720,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Ps5Colors.menuMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x99101620),
                      borderRadius: BorderRadius.circular(1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            display.isEmpty ? (widget.hintText ?? '') : display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: display.isEmpty
                                  ? Ps5Colors.textMuted.withValues(alpha: 0.6)
                                  : Ps5Colors.text,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        const _BlinkingCursor(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._buildGrid(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGrid() {
    return [
      _keyRow([
        for (var i = 0; i < _lettersTop.length; i++)
          _letterKey(_lettersTop[i], autofocus: i == 0 && !_numbersOnly),
      ]),
      _keyRow([for (final char in _lettersMiddle) _letterKey(char)]),
      _keyRow([
        _OskKey(
          flex: 15,
          label: '⇧',
          accent: _uppercase,
          onPressed: _toggleCase,
        ),
        for (final char in _lettersBottom) _letterKey(char),
        _OskKey(
          flex: 15,
          icon: Icons.backspace_outlined,
          onPressed: _backspace,
        ),
      ]),
      _keyRow([
        for (var i = 0; i < _digits.length; i++)
          _OskKey(
            label: _digits[i],
            autofocus: i == 0 && _numbersOnly,
            onPressed: () => _insert(_digits[i]),
          ),
      ]),
      _keyRow([
        for (final char in _symbols)
          _OskKey(label: char, onPressed: () => _insert(char)),
      ]),
      _keyRow([
        _OskKey(
          flex: 18,
          label: _uppercase ? 'ABC' : 'abc',
          fontSize: 15,
          onPressed: _toggleCase,
        ),
        _OskKey(
          flex: 44,
          label: '空格',
          fontSize: 15,
          onPressed: () => _insert(' '),
        ),
        _OskKey(flex: 18, label: '取消', fontSize: 15, onPressed: _cancel),
        _OskKey(
          flex: 18,
          label: '完成',
          fontSize: 15,
          accent: true,
          onPressed: _submit,
        ),
      ]),
    ];
  }

  Widget _letterKey(String char, {bool autofocus = false}) {
    final label = _uppercase ? char.toUpperCase() : char;
    return _OskKey(
      label: label,
      autofocus: autofocus,
      onPressed: () => _insert(label),
    );
  }

  Widget _keyRow(List<Widget> keys) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: keys,
        ),
      ),
    );
  }
}

class _OskKey extends StatefulWidget {
  const _OskKey({
    required this.onPressed,
    this.label,
    this.icon,
    this.flex = 10,
    this.fontSize = 17,
    this.accent = false,
    this.autofocus = false,
  });

  final VoidCallback onPressed;
  final String? label;
  final IconData? icon;
  final int flex;
  final double fontSize;
  final bool accent;
  final bool autofocus;

  @override
  State<_OskKey> createState() => _OskKeyState();
}

class _OskKeyState extends State<_OskKey> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    final color = widget.accent ? Ps5Colors.accent : Ps5Colors.text;
    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FocusableActionDetector(
          autofocus: widget.autofocus,
          onFocusChange: (value) {
            if (value) Ps5UiSounds.tick();
            setState(() => _focused = value);
          },
          mouseCursor: SystemMouseCursors.click,
          shortcuts: _activateShortcuts,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: active
                          ? Ps5Colors.menuHighlight
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Center(
                      child: widget.icon != null
                          ? Icon(widget.icon, size: 19, color: color)
                          : Text(
                              widget.label ?? '',
                              maxLines: 1,
                              style: TextStyle(
                                color: color,
                                fontSize: widget.fontSize,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                    ),
                  ),
                  Positioned.fill(
                    child: Ps5AnimatedFocusBorder(
                      active: active,
                      borderRadius: 2,
                      strokeWidth: 1.5,
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

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor> {
  late final Timer _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _visible = !_visible);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _visible ? 1 : 0,
      child: const Text(
        '_',
        style: TextStyle(color: Ps5Colors.accent, fontSize: 17),
      ),
    );
  }
}
