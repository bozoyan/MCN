// 职责: 使用固定 rig 元数据求解姿态骨骼、接触探针和世界锚点。
// 关联文件:
//   lib/shared/models/director/rig_data.dart
//   lib/shared/models/director/pose.dart
//   lib/shared/services/director/actor_models.dart
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;
import 'document.dart';
import 'pose.dart';
import 'rig_data.dart';

const rigBoneNames = {
  'hips': 'pelvis',
  'spine': 'spine_01',
  'chest': 'spine_02',
  'neck': 'neck_01',
  'head': 'Head',
  'leftUpperArm': 'upperarm_l',
  'leftLowerArm': 'lowerarm_l',
  'leftHand': 'hand_l',
  'rightUpperArm': 'upperarm_r',
  'rightLowerArm': 'lowerarm_r',
  'rightHand': 'hand_r',
  'leftUpperLeg': 'thigh_l',
  'leftLowerLeg': 'calf_l',
  'leftFoot': 'foot_l',
  'rightUpperLeg': 'thigh_r',
  'rightLowerLeg': 'calf_r',
  'rightFoot': 'foot_r',
};

const rigContactRadii = {
  'foot_l': 0.0865,
  'foot_r': 0.0865,
  'ball_l': 0.025,
  'ball_r': 0.025,
  'calf_l': 0.06,
  'calf_r': 0.06,
};

v.Vector3 rigVector(List p) => v.Vector3(
  (p[0] as num).toDouble(),
  (p[1] as num).toDouble(),
  (p[2] as num).toDouble(),
);
v.Quaternion rigQuaternion(List q) => v.Quaternion(
  (q[0] as num).toDouble(),
  (q[1] as num).toDouble(),
  (q[2] as num).toDouble(),
  (q[3] as num).toDouble(),
);
v.Quaternion boneRotation(List<double> e) =>
    v.Quaternion.axisAngle(v.Vector3(1, 0, 0), e[0]) *
    v.Quaternion.axisAngle(v.Vector3(0, 1, 0), e[1]) *
    v.Quaternion.axisAngle(v.Vector3(0, 0, 1), e[2]);

class RigPose {
  final Map<String, v.Matrix4> transforms;
  final double baseline, rootOffset;
  RigPose(this.transforms, this.baseline, this.rootOffset);
  v.Vector3 localPoint(String bone, List offset) {
    final point = transforms[rigBoneNames[bone]]!.transformed3(
      rigVector(offset),
    );
    point.y += baseline + rootOffset;
    return point;
  }

  Map<String, double> get contactHeights => {
    for (final e in rigContactRadii.entries)
      e.key:
          transforms[e.key]!.getTranslation().y -
          e.value +
          baseline +
          rootOffset,
  };
}

final _baselines = <String, double>{};
double rigBaseline(String geometry) => _baselines.putIfAbsent(geometry, () {
  final rest = _transforms(geometry, poseBones(ActorPose.standing()));
  return -rigContactRadii.entries
      .map((e) => rest[e.key]!.getTranslation().y - e.value)
      .reduce(math.min);
});

Map<String, v.Matrix4> _transforms(
  String geometry,
  Map<String, List<double>> deltas,
) {
  final nodes = actorRigNodes[geometry];
  if (nodes == null) {
    invalid('geometry_key', 'unknown_value');
  }
  final byName = {
    for (final entry in rigBoneNames.entries) entry.value: entry.key,
  };
  final result = <String, v.Matrix4>{};
  v.Matrix4 visit(String name) => result.putIfAbsent(name, () {
    final node = nodes[name]!;
    final rest = rigQuaternion(node['rotation']);
    final delta = deltas[byName[name]];
    final local = v.Matrix4.compose(
      rigVector(node['position']),
      delta == null ? rest : rest * boneRotation(delta),
      rigVector(node['scale']),
    );
    final parent = node['parent'] as String?;
    return parent == null ? local : visit(parent) * local;
  });
  for (final name in nodes.keys) {
    visit(name);
  }
  return result;
}

RigPose sampleRig(String geometry, ActorPose pose) => RigPose(
  _transforms(geometry, poseBones(pose)),
  rigBaseline(geometry),
  pose['root_offset_y'],
);

/// 只在选择预设时标定显式高度；普通姿态采样不重新贴地。
ActorPose supportedPose(String geometry, ActorPose pose) {
  final rig = sampleRig(geometry, pose.withValues({'root_offset_y': 0}));
  final height = -rig.contactHeights.values.reduce(math.min);
  return pose.withValues({'root_offset_y': height});
}

List<double> boneWorldPoint(Json actor, String bone, List offset) {
  final local = sampleRig(
    actor['geometry_key'],
    ActorPose.fromJson(actor['pose']),
  ).localPoint(bone, offset);
  local.multiply(rigVector(actor['scale']));
  final world =
      rigQuaternion(actor['rotation']).asRotationMatrix().transformed(local) +
      rigVector(actor['position']);
  return [world.x, world.y, world.z];
}
