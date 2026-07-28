import 'dart:ui';

class MobileTouchpadPointer {
  MobileTouchpadPointer({required int stageWidth, required int stageHeight})
    : _stageSize = Size(stageWidth.toDouble(), stageHeight.toDouble()),
      _position = Offset(stageWidth / 2, stageHeight / 2);

  Size _stageSize;
  Offset _position;

  Offset get position => _position;

  void updateStageSize(int width, int height) {
    _stageSize = Size(width.toDouble(), height.toDouble());
    _position = _clamp(_position);
  }

  void setPosition(Offset position) {
    _position = _clamp(position);
  }

  Offset moveBy(Offset displayDelta, double displayScale) {
    if (displayScale <= 0) return _position;
    _position = _clamp(_position + displayDelta / displayScale);
    return _position;
  }

  Offset displayPosition({
    required Offset origin,
    required double displayScale,
  }) {
    return origin + _position * displayScale;
  }

  Offset _clamp(Offset position) {
    return Offset(
      position.dx.clamp(
        0.0,
        (_stageSize.width - 1).clamp(0.0, double.infinity),
      ),
      position.dy.clamp(
        0.0,
        (_stageSize.height - 1).clamp(0.0, double.infinity),
      ),
    );
  }
}
