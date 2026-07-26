import 'dart:async';

import 'package:flutter/material.dart';

/// 轻量提示。
///
/// Material 壳里走 [ScaffoldMessenger]（保持平台惯例）；
/// macOS / Cupertino 壳没有 ScaffoldMessenger，退化为顶层 Overlay toast。
void notify(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Toast(message: message));
  overlay.insert(entry);
  Timer(const Duration(milliseconds: 2400), () {
    if (entry.mounted) entry.remove();
  });
}

class _Toast extends StatelessWidget {
  final String message;

  const _Toast({required this.message});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 48,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xEE3A3A3C)
                  : const Color(0xEE2C2C2E),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 13,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
