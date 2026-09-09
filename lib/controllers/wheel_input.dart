import 'dart:collection';

/// Artemis 的原生滚轮键码与待发送脉冲队列。
///
/// Core 的按键边沿按帧去重，所以同一帧直接发送多个同向滚轮脉冲只会保留一个。
/// 宿主在每个显示帧取一个脉冲，桌面滚轮和移动端双指拖动共用这条路径。
class WheelInputQueue {
  static const int wheelUpKey = 136;
  static const int wheelDownKey = 137;
  static const int maxPending = 12;

  final ListQueue<int> _pending = ListQueue<int>();

  int get length => _pending.length;

  void addScrollDelta(double dy) {
    if (dy == 0) return;
    addKey(dy < 0 ? wheelUpKey : wheelDownKey);
  }

  void addKey(int key) {
    if (key != wheelUpKey && key != wheelDownKey) {
      throw ArgumentError.value(key, 'key', '不是 Artemis 滚轮键码');
    }
    // 用户反向滚动时丢弃旧方向的积压，避免停止后还继续向原方向翻页。
    if (_pending.isNotEmpty && _pending.last != key) _pending.clear();
    if (_pending.length == maxPending) _pending.removeFirst();
    _pending.addLast(key);
  }

  int? take() => _pending.isEmpty ? null : _pending.removeFirst();

  void clear() => _pending.clear();
}
