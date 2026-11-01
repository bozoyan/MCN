// 职责: 投影并命中编辑专用的世界坐标移动箭头与 Y 旋转环。
// 关联文件:
//   lib/shared/widgets/director/viewport.dart
//   lib/shared/services/director/camera.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../shared/theme/theme.dart';
import 'package:vector_math/vector_math.dart' as v;

import 'package:reveric/shared/services/director/camera.dart';

enum GizmoHandle {
  x,
  z,
  // ignore: constant_identifier_names
  y_ring,
}

class GizmoProjection {
  final DirectorCamera camera;
  final Size size;
  final v.Vector3 position;
  final String mode;
  static const double radius = 0.9;
  GizmoProjection({
    required this.camera,
    required this.size,
    required this.position,
    required this.mode,
  });
  v.Vector3 get center => position + v.Vector3(0, 0.04, 0);
  Offset? get origin => camera.worldToScreen(center, size);
  Offset? endpoint(GizmoHandle axis) => camera.worldToScreen(
    center +
        (axis == GizmoHandle.x ? v.Vector3(0.9, 0, 0) : v.Vector3(0, 0, 0.9)),
    size,
  );
  Offset? ringPoint(double angle) => camera.worldToScreen(
    center + v.Vector3(math.sin(angle) * radius, 0, math.cos(angle) * radius),
    size,
  );
  List<Offset?> get ring =>
      List.generate(65, (i) => ringPoint(i / 64 * 2 * math.pi));
  GizmoHandle? hitTest(Offset point, {double tolerance = 12}) {
    final start = origin;
    if (start == null) {
      return null;
    }
    if (mode == 'move') {
      GizmoHandle? closest;
      var distance = tolerance;
      for (final axis in [GizmoHandle.x, GizmoHandle.z]) {
        final end = endpoint(axis);
        if (end != null) {
          final d = segmentDistance(point, start + (end - start) * 0.18, end);
          if (d <= distance) {
            distance = d;
            closest = axis;
          }
        }
      }
      return closest;
    }
    if (mode == 'rotate') {
      final points = ring;
      for (var i = 0; i < points.length - 1; i++) {
        if (points[i] != null &&
            points[i + 1] != null &&
            segmentDistance(point, points[i]!, points[i + 1]!) <= tolerance) {
          return GizmoHandle.y_ring;
        }
      }
    }
    return null;
  }

  static double segmentDistance(Offset point, Offset a, Offset b) {
    final delta = b - a;
    if (delta.distanceSquared < 1e-8) {
      return (point - a).distance;
    }
    final fraction =
        (((point - a).dx * delta.dx + (point - a).dy * delta.dy) /
                delta.distanceSquared)
            .clamp(0.0, 1.0);
    return (point - (a + delta * fraction)).distance;
  }
}

class GizmoPainter extends CustomPainter {
  final GizmoProjection projection;
  final RevericColors colors;
  final TextStyle labelStyle;
  final GizmoHandle? active;
  // 选中对象当前偏航（弧度），旋转环上的手柄与角度读数都按它摆放。
  final double yaw;
  GizmoPainter(
    this.projection,
    this.colors,
    this.active,
    this.labelStyle,
    this.yaw,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final start = projection.origin;
    if (start == null) {
      return;
    }
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (projection.mode == 'move') {
      for (final axis in [GizmoHandle.x, GizmoHandle.z]) {
        final end = projection.endpoint(axis);
        if (end == null || (end - start).distance < 2) {
          continue;
        }
        paint.color = axis == GizmoHandle.x ? colors.error : colors.accent;
        paint.strokeWidth = active == axis ? 5 : 3;
        canvas.drawLine(start, end, paint);
        final direction = (end - start) / (end - start).distance,
            normal = Offset(-direction.dy, direction.dx);
        final arrow = Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(
            (end - direction * 12 + normal * 6).dx,
            (end - direction * 12 + normal * 6).dy,
          )
          ..lineTo(
            (end - direction * 12 - normal * 6).dx,
            (end - direction * 12 - normal * 6).dy,
          )
          ..close();
        canvas.drawPath(arrow, Paint()..color = paint.color);
        final text = TextPainter(
          text: TextSpan(
            text: axis == GizmoHandle.x ? 'X' : 'Z',
            style: labelStyle.copyWith(color: paint.color),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, end + normal * 10);
      }
    }
    if (projection.mode == 'rotate') {
      paint.color = colors.success;
      paint.strokeWidth = active == GizmoHandle.y_ring ? 3 : 2;
      final points = projection.ring;
      for (var i = 0; i < points.length - 1; i++) {
        if (points[i] != null && points[i + 1] != null) {
          canvas.drawLine(points[i]!, points[i + 1]!, paint);
        }
      }
      final handle = projection.ringPoint(yaw);
      if (handle != null) {
        canvas.drawCircle(handle, 7, Paint()..color = colors.success);
        canvas.drawCircle(
          handle,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colors.surface,
        );
        final degrees = ((yaw * 180 / math.pi).round() % 360 + 540) % 360 - 180;
        final text = TextPainter(
          text: TextSpan(
            text: '$degrees°',
            style: labelStyle.copyWith(color: colors.textPrimary),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, handle + const Offset(11, -6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant GizmoPainter oldDelegate) => true;
}
