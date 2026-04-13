import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 조이스틱이 움직일 때마다 호출됩니다.
/// [leftPower]  : 좌측 모터 출력  -1.0 (최대후진) ~ 1.0 (최대전진)
/// [rightPower] : 우측 모터 출력  -1.0 (최대후진) ~ 1.0 (최대전진)
/// 정지 시 둘 다 0.0
typedef JoystickCallback = void Function(double leftPower, double rightPower);

class JoystickController extends StatefulWidget {
  final JoystickCallback onChanged;
  const JoystickController({super.key, required this.onChanged});

  @override
  State<JoystickController> createState() => _JoystickControllerState();
}

class _JoystickControllerState extends State<JoystickController> {
  Offset _stick = Offset.zero; // -1.0 ~ 1.0 정규화된 스틱 위치
  bool _dragging = false;
  int? _activePointer;
  double _baseRadius = 0;

  double get _maxDrag => _baseRadius * 0.65;

  // 조이스틱 x/y → 탱크 드라이브 좌/우 모터 파워 변환
  // 전형적인 "믹스" 알고리즘:
  //   forward  = y  (위=+1, 아래=-1)
  //   turn     = x  (오른쪽=+1, 왼쪽=-1)
  //   left  = forward + turn
  //   right = forward - turn
  // → -1~1로 클램핑
  static (double left, double right) _mix(double x, double y) {
    final left = (y + x).clamp(-1.0, 1.0);
    final right = (y - x).clamp(-1.0, 1.0);
    return (left, right);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_activePointer != null) return;
    _activePointer = e.pointer;
    HapticFeedback.lightImpact();
    _update(e.localPosition);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;
    _update(e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    _release();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointer) return;
    _release();
  }

  void _release() {
    _activePointer = null;
    setState(() {
      _stick = Offset.zero;
      _dragging = false;
    });
    widget.onChanged(0.0, 0.0);
  }

  void _update(Offset localPos) {
    final center = Offset(_baseRadius, _baseRadius);
    Offset delta = localPos - center;
    final dist = delta.distance;
    if (dist > _maxDrag) delta = delta / dist * _maxDrag;

    // -1 ~ 1 정규화
    final nx = (delta.dx / _maxDrag).clamp(-1.0, 1.0);
    final ny = -(delta.dy / _maxDrag).clamp(-1.0, 1.0); // 위가 +

    // 데드존 5%
    final magnitude = sqrt(nx * nx + ny * ny);
    if (magnitude < 0.05) {
      setState(() {
        _stick = Offset.zero;
        _dragging = true;
      });
      widget.onChanged(0.0, 0.0);
      return;
    }

    setState(() {
      _stick = Offset(delta.dx, delta.dy);
      _dragging = true;
    });

    final (left, right) = _mix(nx, ny);
    widget.onChanged(left, right);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = min(constraints.maxWidth, constraints.maxHeight);
      _baseRadius = size / 2;
      return Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _JoystickPainter(
              stick: _stick,
              baseRadius: _baseRadius,
              dragging: _dragging,
            ),
          ),
        ),
      );
    });
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset stick;
  final double baseRadius;
  final bool dragging;

  const _JoystickPainter({
    required this.stick,
    required this.baseRadius,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final sc = c + stick;
    final sr = baseRadius * 0.36;

    // 베이스 채우기
    canvas.drawCircle(
        c, baseRadius - 2, Paint()..color = const Color(0xFF1E293B));
    // 베이스 테두리
    canvas.drawCircle(
        c,
        baseRadius - 1.5,
        Paint()
          ..color = const Color(0xFF334155)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // 가이드 십자선
    final guide = Paint()
      ..color = const Color(0xFF2D3F55)
      ..strokeWidth = 0.8;
    canvas.drawLine(c + Offset(0, -(baseRadius - 14)),
        c + Offset(0, (baseRadius - 14)), guide);
    canvas.drawLine(c + Offset(-(baseRadius - 14), 0),
        c + Offset((baseRadius - 14), 0), guide);

    // 가이드 내부 원 (이동 범위 표시)
    canvas.drawCircle(
        c,
        baseRadius * 0.65,
        Paint()
          ..color = const Color(0xFF263348)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);

    // 방향 삼각형 힌트
    for (final angle in [0.0, pi / 2, pi, 3 * pi / 2]) {
      _drawArrow(canvas, c, baseRadius, angle, const Color(0xFF3D5068));
    }

    // 스틱 → 베이스 중심 연결선 (드래그 중일 때)
    if (dragging && stick != Offset.zero) {
      canvas.drawLine(
          c,
          sc,
          Paint()
            ..color = const Color(0xFF2563EB).withOpacity(0.3)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
    }

    // 스틱 핸들 채우기
    canvas.drawCircle(
        sc,
        sr - 1,
        Paint()
          ..color = dragging
              ? const Color(0xFF1D4ED8).withOpacity(0.92)
              : const Color(0xFF2D3F55));
    // 스틱 테두리
    canvas.drawCircle(
        sc,
        sr,
        Paint()
          ..color = dragging ? const Color(0xFF60A5FA) : const Color(0xFF475569)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0);
    // 스틱 하이라이트
    canvas.drawCircle(sc, sr * 0.3,
        Paint()..color = Colors.white.withOpacity(dragging ? 0.22 : 0.08));
  }

  void _drawArrow(
      Canvas canvas, Offset c, double r, double angle, Color color) {
    final dist = r * 0.74;
    final tip = r * 0.86;
    final as = r * 0.09;
    final ca = cos(angle), sa = sin(angle);
    final tipPt = c + Offset(ca * tip, sa * tip);
    final leftPt = c + Offset(ca * dist - sa * as, sa * dist + ca * as);
    final rightPt = c + Offset(ca * dist + sa * as, sa * dist - ca * as);
    final path = Path()
      ..moveTo(tipPt.dx, tipPt.dy)
      ..lineTo(leftPt.dx, leftPt.dy)
      ..lineTo(rightPt.dx, rightPt.dy)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_JoystickPainter o) =>
      o.stick != stick || o.dragging != dragging;
}
