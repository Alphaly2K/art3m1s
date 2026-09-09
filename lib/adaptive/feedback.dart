import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 轻量提示。
///
/// Material 壳里走 [ScaffoldMessenger]（保持平台惯例）；
/// macOS / Cupertino 壳没有 ScaffoldMessenger，退化为顶层 Overlay toast。
void notify(BuildContext context, String message) {
  final messenger = MiuixTheme.maybeOf(context) == null
      ? ScaffoldMessenger.maybeOf(context)
      : null;
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

/// 不可交互的长任务进度层；用于 SAF 复制等不能瞬间完成的操作。
class BlockingProgressController {
  BlockingProgressController._(this._entry, this._message);

  OverlayEntry? _entry;
  final ValueNotifier<String> _message;

  void update(String message) {
    if (_entry == null) return;
    _message.value = message;
  }

  void close() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    if (entry.mounted) entry.remove();
    _message.dispose();
  }
}

BlockingProgressController? showBlockingProgress(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final miuix = MiuixTheme.maybeOf(context) != null;
  final notifier = ValueNotifier(message);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x55000000)),
          Center(
            child: _ProgressCard(title: title, message: notifier, miuix: miuix),
          ),
        ],
      ),
    ),
  );
  overlay.insert(entry);
  return BlockingProgressController._(entry, notifier);
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.message,
    required this.miuix,
  });

  final String title;
  final ValueListenable<String> message;
  final bool miuix;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (miuix)
            const MiuixInfiniteProgressIndicator()
          else
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                ValueListenableBuilder<String>(
                  valueListenable: message,
                  builder: (context, value, _) => Text(value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: miuix ? MiuixCard(child: content) : Card(child: content),
    );
  }
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
              color: dark ? const Color(0xEE3A3A3C) : const Color(0xEE2C2C2E),
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
