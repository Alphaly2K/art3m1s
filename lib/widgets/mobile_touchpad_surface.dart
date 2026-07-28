import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class MobileTouchpadSurface extends StatefulWidget {
  const MobileTouchpadSurface({
    super.key,
    required this.child,
    required this.onMove,
    required this.onTap,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final Widget child;
  final ValueChanged<Offset> onMove;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  @override
  State<MobileTouchpadSurface> createState() => _MobileTouchpadSurfaceState();
}

class _MobileTouchpadSurfaceState extends State<MobileTouchpadSurface> {
  Offset _longPressOffset = Offset.zero;
  bool _dragging = false;

  @override
  void dispose() {
    if (_dragging) widget.onDragEnd();
    super.dispose();
  }

  void _startDrag(LongPressStartDetails _) {
    _longPressOffset = Offset.zero;
    _dragging = true;
    widget.onDragStart();
  }

  void _moveDrag(LongPressMoveUpdateDetails details) {
    final delta = details.offsetFromOrigin - _longPressOffset;
    _longPressOffset = details.offsetFromOrigin;
    widget.onMove(delta);
  }

  void _endDrag() {
    if (!_dragging) return;
    _dragging = false;
    _longPressOffset = Offset.zero;
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: const {PointerDeviceKind.touch},
      onTap: widget.onTap,
      onPanUpdate: (details) => widget.onMove(details.delta),
      onLongPressStart: _startDrag,
      onLongPressMoveUpdate: _moveDrag,
      onLongPressEnd: (_) => _endDrag(),
      onLongPressCancel: _endDrag,
      child: widget.child,
    );
  }
}
