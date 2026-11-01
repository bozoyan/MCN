// 职责: 验证右手工程机位的投影和拾取射线互逆。
// 关联文件:
//   lib/shared/services/director/camera.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:reveric/shared/services/director/camera.dart';

void main() {
  test('depth effects receive positive perspective clip planes', () {
    final camera = DirectorCamera(fovNear: 0.05, fovFar: 200);
    expect(camera.projection, isA<PerspectiveProjection>());
    final lens = camera.projection as PerspectiveProjection;
    expect(lens.near, 0.05);
    expect(lens.far, 200);
    final matrix = lens.getProjectionMatrix(16 / 9);
    for (final entry in [(0.05, 0.0), (200.0, 1.0)]) {
      final clip = matrix.transform(Vector4(0, 0, -entry.$1, 1));
      expect(clip.z / clip.w, closeTo(entry.$2, 1e-6));
    }
  });
  test('negative X stays screen-left and ray reaches projected point', () {
    final camera = DirectorCamera(
      position: Vector3(0, 1.6, 5),
      target: Vector3(0, 1, 0),
    );
    const size = Size(720, 1280);
    final point = Vector3(-0.8, 1.15, 0),
        screen = camera.worldToScreen(point, size)!;
    expect(screen.dx, lessThan(360));
    final ray = camera.screenPointToRay(screen, size),
        direction = point - ray.origin;
    expect(
      direction.normalized().dot(ray.direction.normalized()),
      closeTo(1, 1e-6),
    );
  });
}
