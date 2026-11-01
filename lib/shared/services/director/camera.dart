// 职责: 将工程右手世界坐标转换为 GPU 零到一深度的透视机位。
// 关联文件:
//   lib/shared/services/director/scene_builder.dart
//   lib/shared/widgets/director/viewport.dart
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as v;

class DirectorCamera extends PerspectiveCamera {
  DirectorCamera({
    super.position,
    super.target,
    super.fovRadiansY,
    super.fovNear = 0.05,
    super.fovFar = 200,
  });
  @override
  v.Matrix4 getViewMatrix() => v.makeViewMatrix(position, target, up);
  @override
  CameraProjection get projection =>
      _RightHandProjection(fovRadiansY, fovNear, fovFar);
}

// Screen-space effects read positive lens planes from PerspectiveProjection.
// Inferring them from a right-handed matrix assumes the wrong sign for view Z.
class _RightHandProjection extends PerspectiveProjection {
  _RightHandProjection(double fov, double near, double far)
    : super(fovRadiansY: fov, near: near, far: far);
  @override
  v.Matrix4 getProjectionMatrix(double aspectRatio, {v.Vector2? jitter}) {
    final f = 1 / math.tan(fovRadiansY / 2);
    return v.Matrix4(
      f / aspectRatio,
      0,
      0,
      0,
      0,
      f,
      0,
      0,
      -(jitter?.x ?? 0),
      -(jitter?.y ?? 0),
      far / (near - far),
      -1,
      0,
      0,
      far * near / (near - far),
      0,
    );
  }
}
