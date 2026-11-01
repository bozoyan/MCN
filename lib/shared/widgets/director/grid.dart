// 职责: 在导演观察视角绘制经过近裁剪的世界地面网格。
// 关联文件:
//   lib/shared/widgets/director/viewport.dart
//   lib/shared/services/director/camera.dart
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as v;
import '../../services/director/camera.dart';

class DirectorGridPainter extends CustomPainter {
  DirectorGridPainter(this.camera, this.color);
  final DirectorCamera camera;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final forward = (camera.target - camera.position)..normalize();
    final pen = Paint()
      ..color = color
      ..strokeWidth = 0.7;
    void line(v.Vector3 a, v.Vector3 b) {
      final da = (a - camera.position).dot(forward);
      final db = (b - camera.position).dot(forward);
      const near = 0.06;
      if (da < near && db < near) {
        return;
      }
      final clippedA = da < near ? a + (b - a) * ((near - da) / (db - da)) : a;
      final clippedB = db < near ? b + (a - b) * ((near - db) / (da - db)) : b;
      final p = camera.worldToScreen(clippedA, size);
      final q = camera.worldToScreen(clippedB, size);
      if (p != null && q != null) {
        canvas.drawLine(p, q, pen);
      }
    }

    for (var i = -20; i <= 20; i++) {
      final x = i.toDouble();
      line(v.Vector3(x, 0, -20), v.Vector3(x, 0, 20));
      line(v.Vector3(-20, 0, x), v.Vector3(20, 0, x));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DirectorGridPainter oldDelegate) =>
      camera.position != oldDelegate.camera.position ||
      camera.target != oldDelegate.camera.target ||
      camera.fovRadiansY != oldDelegate.camera.fovRadiansY ||
      color != oldDelegate.color;
}
