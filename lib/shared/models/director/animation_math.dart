// 职责: 提供姿态、属性与相机共用的旋转及方向插值数学。
// 关联文件:
//   lib/shared/models/director/sampling.dart
//   lib/shared/models/director/properties.dart
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;
import 'document.dart';
import 'properties.dart';

double smooth(double u) => u * u * (3 - 2 * u);
List<double> yawQuaternion(double angle) => [
  0,
  math.sin(angle / 2),
  0,
  math.cos(angle / 2),
];

/// 属性面板使用 YXZ 欧拉角（弧度），按 X、Y、Z 返回。
/// 俯仰到达 ±90° 时将 roll 归零，保留等价姿态。
List<double> quaternionEuler(List q) {
  final x = (q[0] as num).toDouble(),
      y = (q[1] as num).toDouble(),
      z = (q[2] as num).toDouble(),
      w = (q[3] as num).toDouble();
  final sinPitch = (2 * (w * x - y * z)).clamp(-1.0, 1.0);
  if (sinPitch.abs() >= 1 - 1e-12) {
    return [
      math.asin(sinPitch),
      math.atan2(2 * (w * y - x * z), 1 - 2 * (y * y + z * z)),
      0,
    ];
  }
  return [
    math.asin(sinPitch),
    math.atan2(2 * (x * z + w * y), 1 - 2 * (x * x + y * y)),
    math.atan2(2 * (x * y + w * z), 1 - 2 * (x * x + z * z)),
  ];
}

List<double> eulerQuaternion(List<double> angles) => multiplyQuaternion(
  yawQuaternion(angles[1]),
  multiplyQuaternion(
    [math.sin(angles[0] / 2), 0, 0, math.cos(angles[0] / 2)],
    [0, 0, math.sin(angles[2] / 2), math.cos(angles[2] / 2)],
  ),
);

double quaternionYaw(List q) => quaternionEuler(q)[1];

/// 绕世界 Y 轴叠加旋转，保留已有俯仰和侧倾。
List<double> rotateQuaternionYaw(List q, double angle) =>
    multiplyQuaternion(yawQuaternion(angle), q);
List<double> slerp(List a, List b, double t) {
  final x = a.map((v) => (v as num).toDouble()).toList();
  var y = b.map((v) => (v as num).toDouble()).toList();
  var dot = List.generate(4, (i) => x[i] * y[i]).reduce((a, b) => a + b);
  if (dot < 0) {
    y = y.map((v) => -v).toList();
    dot = -dot;
  }
  List<double> result;
  if (dot > 0.9995) {
    result = List.generate(4, (i) => x[i] + (y[i] - x[i]) * t);
  } else {
    final angle = math.acos(dot.clamp(-1, 1)), s = math.sin(angle);
    result = List.generate(
      4,
      (i) =>
          (math.sin((1 - t) * angle) * x[i] + math.sin(t * angle) * y[i]) / s,
    );
  }
  final norm = math.sqrt(result.fold<double>(0, (a, b) => a + b * b));
  return result.map((v) => v / norm).toList();
}

List<double> multiplyQuaternion(List a, List b) {
  final ax = (a[0] as num).toDouble(),
      ay = (a[1] as num).toDouble(),
      az = (a[2] as num).toDouble(),
      aw = (a[3] as num).toDouble();
  final bx = (b[0] as num).toDouble(),
      by = (b[1] as num).toDouble(),
      bz = (b[2] as num).toDouble(),
      bw = (b[3] as num).toDouble();
  return [
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw,
    aw * bw - ax * bx - ay * by - az * bz,
  ];
}

List<double> directionSlerp(List a, List b, double u) {
  final x = unitDirection(a, 'direction'), y = unitDirection(b, 'direction');
  final dot = List.generate(
    3,
    (i) => x[i] * y[i],
  ).reduce((a, b) => a + b).clamp(-1.0, 1.0);
  if (dot <= -0.999999) {
    invalid('direction', 'opposite_directions');
  }
  if (dot >= 0.999999) {
    return unitDirection([
      for (var i = 0; i < 3; i++) x[i] + (y[i] - x[i]) * u,
    ], 'direction');
  }
  final angle = math.acos(dot), sine = math.sin(angle);
  return unitDirection([
    for (var i = 0; i < 3; i++)
      (x[i] * math.sin((1 - u) * angle) + y[i] * math.sin(u * angle)) / sine,
  ], 'direction');
}

List<double> rotateVector(List q, List point) {
  final result = multiplyQuaternion(multiplyQuaternion(q, [...point, 0]), [
    -q[0],
    -q[1],
    -q[2],
    q[3],
  ]);
  return result.take(3).toList();
}

List<double> lookQuaternion(List forward, List up) {
  final f = v.Vector3.array(unitDirection(forward, 'camera.forward'));
  final reference = v.Vector3.array(unitDirection(up, 'camera.up'));
  final right = f.cross(reference);
  if (right.length < 1e-10) {
    invalid('camera', 'parallel_reference_up');
  }
  right.normalize();
  final corrected = right.cross(f)..normalize();
  final matrix = v.Matrix3.columns(right, corrected, -f);
  final q = v.Quaternion.fromRotation(matrix)..normalize();
  return [q.x, q.y, q.z, q.w];
}

double quaternionAngle(List a, List b) {
  final dot = List.generate(
    4,
    (i) => (a[i] as num) * (b[i] as num),
  ).reduce((a, b) => a + b).abs().clamp(0.0, 1.0);
  return 2 * math.acos(dot) * 180 / math.pi;
}
