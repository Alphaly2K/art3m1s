import 'package:flutter/widgets.dart';

class MobileGameCursor extends StatelessWidget {
  const MobileGameCursor({super.key});

  static const size = Size(22, 28);

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 28,
      child: CustomPaint(painter: _SystemArrowCursorPainter()),
    );
  }
}

class _SystemArrowCursorPainter extends CustomPainter {
  const _SystemArrowCursorPainter();

  static final Path _arrow = Path()
    ..moveTo(1.5, 1.5)
    ..lineTo(1.5, 22)
    ..lineTo(6.8, 17.1)
    ..lineTo(11.2, 26.1)
    ..lineTo(15.1, 24.2)
    ..lineTo(10.8, 15.5)
    ..lineTo(18, 15.1)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _arrow,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      _arrow,
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SystemArrowCursorPainter oldDelegate) => false;
}
