// 职责: 持有视口指针快照并计算保留高度与倾斜的平移、旋转手势。
// 关联文件:
//   lib/shared/widgets/director/viewport.dart
//   lib/shared/widgets/director/gizmo.dart
//   lib/shared/models/director/sampling.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math.dart' as v;

import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/widgets/director/gizmo.dart';
import 'package:reveric/shared/services/director/camera.dart';

class ViewportGesture {
  Offset? down;
  Offset? originGlobal;
  Size? viewportSize;
  DirectorCamera? camera;
  v.Vector3? ground;
  Json? original;
  int buttons = 0, generation = 0;
  bool dragging = false, valid = true, orbit = false, moved = false;
  double scale = 1, accumulatedAngle = 0;
  double? lastRingAngle;
  GizmoHandle? handle;
  final Set<int> pointers = {};

  /// 在对象当前高度的水平面上求交，旋转环再抬高 0.04 米。
  v.Vector3? planePoint(Offset global, {bool ring = false}) {
    final ray = camera!.screenPointToRay(global - originGlobal!, viewportSize!);
    if (ray.direction.y.abs() < 1e-6) {
      return null;
    }
    final height =
        (original!['position'][1] as num).toDouble() + (ring ? 0.04 : 0);
    final t = (height - ray.origin.y) / ray.direction.y;
    return t < 0 ? null : ray.origin + ray.direction * t;
  }

  List<double>? positionAt(Offset global) {
    final point = planePoint(global), start = ground;
    if (point == null || start == null) {
      return null;
    }
    final p = original!['position'] as List;
    return [
      (p[0] as num).toDouble() +
          (handle == GizmoHandle.z ? 0 : point.x - start.x),
      (p[1] as num).toDouble(),
      (p[2] as num).toDouble() +
          (handle == GizmoHandle.x ? 0 : point.z - start.z),
    ];
  }

  List<double> rotationAt(Offset global, {bool snap = false}) {
    var angle = (global.dx - down!.dx) * math.pi / 360;
    if (handle == GizmoHandle.y_ring) {
      final point = planePoint(global, ring: true);
      if (point != null && lastRingAngle != null) {
        final p = original!['position'] as List;
        final now = math.atan2(point.x - p[0], point.z - p[2]);
        var delta = now - lastRingAngle!;
        if (delta > math.pi) {
          delta -= 2 * math.pi;
        }
        if (delta < -math.pi) {
          delta += 2 * math.pi;
        }
        accumulatedAngle += delta;
        lastRingAngle = now;
        angle = accumulatedAngle;
      }
    }
    final rotation = original!['rotation'] as List;
    if (snap) {
      final yaw = quaternionYaw(rotation);
      angle = ((yaw + angle) / (math.pi / 12)).round() * math.pi / 12 - yaw;
    }
    return rotateQuaternionYaw(rotation, angle);
  }

  void clearDrag() {
    down = null;
    ground = null;
    original = null;
    dragging = false;
    valid = true;
    orbit = false;
    moved = false;
    handle = null;
    lastRingAngle = null;
    accumulatedAngle = 0;
  }
}
