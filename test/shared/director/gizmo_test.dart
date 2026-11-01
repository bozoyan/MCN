// 职责: 验证手柄投影、等高拖动和保留倾斜的旋转手势。
// 关联文件:
//   lib/shared/widgets/director/pointer_gesture.dart
//   lib/shared/widgets/director/gizmo.dart
//   lib/shared/services/director/camera.dart
import 'dart:ui';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/widgets/director/pointer_gesture.dart';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:reveric/shared/services/director/camera.dart';
import 'package:reveric/shared/widgets/director/gizmo.dart';

void main() {
  test(
    'dragging an airborne object preserves height and constrains only the selected axis',
    () {
      final camera = DirectorCamera(
        position: Vector3(4, 5, 8),
        target: Vector3(0, 2, 0),
      );
      const size = Size(800, 600), offset = Offset(40, 60);
      final start = camera.worldToScreen(Vector3(0, 2, 0), size)! + offset;
      final end = camera.worldToScreen(Vector3(1, 2, 1), size)! + offset;
      final gesture = ViewportGesture()
        ..camera = camera
        ..viewportSize = size
        ..originGlobal = offset
        ..down = start
        ..original = {
          'position': [0, 2, 0],
          'rotation': eulerQuaternion([0.3, 0.2, -0.4]),
        };
      gesture.ground = gesture.planePoint(start);
      for (final handle in [null, GizmoHandle.x, GizmoHandle.z]) {
        gesture.handle = handle;
        final next = gesture.positionAt(end)!;
        expect(next[0], closeTo(handle == GizmoHandle.z ? 0 : 1, 1e-4));
        expect(next[1], 2);
        expect(next[2], closeTo(handle == GizmoHandle.x ? 0 : 1, 1e-4));
      }
    },
  );
  test('elevated Y ring turns without resetting pitch or roll', () {
    final camera = DirectorCamera(
      position: Vector3(4, 5, 8),
      target: Vector3(0, 2, 0),
    );
    const size = Size(800, 600);
    final ring = GizmoProjection(
      camera: camera,
      size: size,
      position: Vector3(0, 2, 0),
      mode: 'rotate',
    );
    final original = eulerQuaternion([0.3, 0.2, -0.4]);
    final gesture = ViewportGesture()
      ..camera = camera
      ..viewportSize = size
      ..originGlobal = Offset.zero
      ..down = ring.ringPoint(0)
      ..handle = GizmoHandle.y_ring
      ..lastRingAngle = 0
      ..original = {
        'position': [0, 2, 0],
        'rotation': original,
      };
    final turned = quaternionEuler(gesture.rotationAt(ring.ringPoint(0.5)!));
    expect(turned[0], closeTo(0.3, 1e-5));
    expect(turned[1], closeTo(0.7, 1e-5));
    expect(turned[2], closeTo(-0.4, 1e-5));
    final snapped = quaternionEuler(
      gesture.rotationAt(ring.ringPoint(0.5)!, snap: true),
    );
    expect(snapped[0], closeTo(0.3, 1e-5));
    expect(snapped[1], closeTo(math.pi / 4, 1e-5));
    expect(snapped[2], closeTo(-0.4, 1e-5));
    gesture.handle = null;
    final free = quaternionEuler(
      gesture.rotationAt(gesture.down! + const Offset(60, 0)),
    );
    expect(free[0], closeTo(0.3, 1e-5));
    expect(free[1], closeTo(0.2 + math.pi / 6, 1e-5));
    expect(free[2], closeTo(-0.4, 1e-5));
  });
  test('world X/Z endpoints and Y ring are independently selectable', () {
    final camera = DirectorCamera(
      position: Vector3(4, 4, 6),
      target: Vector3(0, 0, 0),
    );
    final move = GizmoProjection(
      camera: camera,
      size: const Size(720, 1280),
      position: Vector3.zero(),
      mode: 'move',
    );
    expect(move.hitTest(move.endpoint(GizmoHandle.x)!), GizmoHandle.x);
    expect(move.hitTest(move.endpoint(GizmoHandle.z)!), GizmoHandle.z);
    expect(move.hitTest(const Offset(-100, -100)), isNull);
    final ring = GizmoProjection(
      camera: camera,
      size: const Size(720, 1280),
      position: Vector3.zero(),
      mode: 'rotate',
    );
    expect(ring.hitTest(ring.ringPoint(math.pi / 2)!), GizmoHandle.y_ring);
    expect(ring.ring.length, 65);
  });
}
