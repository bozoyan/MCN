// 职责: 随观察机位方向绘制世界坐标轴指示球。
// 关联文件:
//   lib/shared/widgets/director/stage.dart
//   lib/shared/widgets/director/viewport.dart
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as v;
import '../../theme/theme.dart';
import 'viewport.dart';

class DirectorOrientation extends StatelessWidget {
  const DirectorOrientation({super.key, required this.view});
  final ViewState view;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: const Size.square(RevericSizes.directorOrientationSize),
      painter: _OrientationPainter(
        view.eye - view.target,
        RevericTheme.colorsOf(context),
        RevericTheme.typographyOf(context).uiTinySemibold,
      ),
    ),
  );
}

class _OrientationPainter extends CustomPainter {
  _OrientationPainter(this.direction, this.colors, this.textStyle);
  final v.Vector3 direction;
  final RevericColors colors;
  final TextStyle textStyle;
  @override
  void paint(Canvas canvas, Size size) {
    final forward = (-direction)..normalize();
    final right = forward.cross(v.Vector3(0, 1, 0))..normalize();
    final up = right.cross(forward)..normalize();
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, size.width / 2, Paint()..color = colors.surface);
    final axes = [
      ('X', v.Vector3(1, 0, 0), colors.error),
      ('Y', v.Vector3(0, 1, 0), colors.success),
      ('Z', v.Vector3(0, 0, 1), colors.accent),
    ]..sort((a, b) => b.$2.dot(forward).compareTo(a.$2.dot(forward)));
    for (final axis in axes) {
      final point =
          center + Offset(axis.$2.dot(right) * 22, -axis.$2.dot(up) * 22);
      canvas.drawLine(
        center,
        point,
        Paint()
          ..color = axis.$3
          ..strokeWidth = 2,
      );
      canvas.drawCircle(point, 9, Paint()..color = axis.$3);
      final label = TextPainter(
        text: TextSpan(
          text: axis.$1,
          style: textStyle.copyWith(color: colors.onAccent),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, point - Offset(label.width / 2, label.height / 2));
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_OrientationPainter oldDelegate) =>
      direction != oldDelegate.direction ||
      colors != oldDelegate.colors ||
      textStyle != oldDelegate.textStyle;
}
