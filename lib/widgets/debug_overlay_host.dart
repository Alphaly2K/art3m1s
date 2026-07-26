import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/logger.dart';

/// 调试浮层的宿主：监听设置与 Log 的切换请求，把 [DebugOverlay]
/// 插入所在 Navigator 的 Overlay。原逻辑在 LibraryScreen 里，
/// 拆出来后三个壳都能包一层复用。
class DebugOverlayHost extends ConsumerStatefulWidget {
  final Widget child;

  const DebugOverlayHost({super.key, required this.child});

  @override
  ConsumerState<DebugOverlayHost> createState() => _DebugOverlayHostState();
}

class _DebugOverlayHostState extends ConsumerState<DebugOverlayHost> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    Log.bind(_onToggle);
  }

  void _onToggle() {
    if (Log.overlayVisible) {
      _show();
    } else {
      _hide();
    }
  }

  void _show() {
    if (_entry != null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (_) => const DebugOverlay());
    overlay.insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(settingsProvider.select((s) => s.debugOverlay));
    if (enabled && _entry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    } else if (!enabled && _entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hide());
    }
    return widget.child;
  }
}
