import 'dart:ui';

import 'wheel_input.dart';

/// Resolves a two-finger sequence into either scrolling or a tap on release.
class TwoFingerGestureTracker {
  static const double dragThreshold = 6;
  static const double wheelNotch = 40;

  Offset? _start;
  Offset? _last;
  bool _dragged = false;
  double _scrollAccum = 0;

  bool get active => _start != null;

  void begin(List<Offset> positions) {
    reset();
    if (positions.length != 2) return;
    _start = _midpoint(positions);
    _last = _start;
  }

  List<int> move(List<Offset> positions, {required bool scrollEnabled}) {
    if (!active || positions.length != 2) return const [];
    final midpoint = _midpoint(positions);
    if ((midpoint - _start!).distance > dragThreshold) _dragged = true;
    final dy = midpoint.dy - _last!.dy;
    _last = midpoint;
    if (!scrollEnabled) return const [];

    _scrollAccum += dy;
    final keys = <int>[];
    while (_scrollAccum >= wheelNotch) {
      _scrollAccum -= wheelNotch;
      keys.add(WheelInputQueue.wheelUpKey);
    }
    while (_scrollAccum <= -wheelNotch) {
      _scrollAccum += wheelNotch;
      keys.add(WheelInputQueue.wheelDownKey);
    }
    return keys;
  }

  /// Returns true only for an uninterrupted, non-dragged two-finger release.
  bool end({bool cancelled = false}) {
    final tapped = active && !cancelled && !_dragged;
    reset();
    return tapped;
  }

  void reset() {
    _start = null;
    _last = null;
    _dragged = false;
    _scrollAccum = 0;
  }

  static Offset _midpoint(List<Offset> positions) =>
      (positions[0] + positions[1]) / 2;
}
