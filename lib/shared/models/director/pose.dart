// 职责: 定义完整姿态参数、边界与语义参数到骨骼角度的唯一映射。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/presets.dart
//   lib/shared/models/director/rig.dart
import 'dart:math' as math;

import 'document.dart';

class PoseParameter {
  final String id;
  final double min, max, initial;
  const PoseParameter(this.id, this.min, this.max, [this.initial = 0]);
}

const poseParameters = [
  PoseParameter('body_pitch', -180, 180),
  PoseParameter('body_yaw', -360, 360),
  PoseParameter('body_roll', -180, 180),
  PoseParameter('torso_pitch', -90, 90),
  PoseParameter('torso_yaw', -90, 90),
  PoseParameter('torso_roll', -90, 90),
  PoseParameter('head_pitch', -90, 90),
  PoseParameter('head_yaw', -120, 120),
  PoseParameter('head_roll', -90, 90),
  PoseParameter('left_shoulder_raise', -180, 180),
  PoseParameter('left_shoulder_abduct', -90, 180),
  PoseParameter('left_shoulder_twist', -180, 180),
  PoseParameter('right_shoulder_raise', -180, 180),
  PoseParameter('right_shoulder_abduct', -90, 180),
  PoseParameter('right_shoulder_twist', -180, 180),
  PoseParameter('left_elbow_bend', 0, 160),
  PoseParameter('right_elbow_bend', 0, 160),
  PoseParameter('left_hip_raise', -120, 160),
  PoseParameter('left_hip_abduct', -90, 90),
  PoseParameter('left_hip_twist', -180, 180),
  PoseParameter('right_hip_raise', -120, 160),
  PoseParameter('right_hip_abduct', -90, 90),
  PoseParameter('right_hip_twist', -180, 180),
  PoseParameter('left_knee_bend', 0, 160),
  PoseParameter('right_knee_bend', 0, 160),
  PoseParameter('root_offset_y', -50, 50),
];

class ActorPose {
  final Map<String, double> values;
  ActorPose._(this.values);
  factory ActorPose.standing() => ActorPose._(
    Map.unmodifiable({for (final p in poseParameters) p.id: p.initial}),
  );
  factory ActorPose.fromJson(dynamic value, [String path = 'pose']) {
    exactFields(value, path, poseParameters.map((p) => p.id).join(' '));
    return ActorPose._(
      Map.unmodifiable({
        for (final p in poseParameters)
          p.id: number(value[p.id], '$path.${p.id}', p.min, p.max).toDouble(),
      }),
    );
  }
  Json toJson() => Map<String, dynamic>.from(values);
  double operator [](String key) => values[key]!;
  ActorPose withValues(Map<String, num> changes) =>
      ActorPose.fromJson({...values, ...changes});
}

const humanoidBones = [
  'hips',
  'spine',
  'chest',
  'neck',
  'head',
  'leftUpperArm',
  'leftLowerArm',
  'leftHand',
  'rightUpperArm',
  'rightLowerArm',
  'rightHand',
  'leftUpperLeg',
  'leftLowerLeg',
  'leftFoot',
  'rightUpperLeg',
  'rightLowerLeg',
  'rightFoot',
];

/// XYZ 骨骼局部角度；左侧镜像只在此处执行，渲染和纯运动学直接消费。
Map<String, List<double>> poseBones(ActorPose pose) {
  double r(String name) => pose[name] * math.pi / 180;
  final bones = <String, List<double>>{
    for (final bone in humanoidBones) bone: [0, 0, 0],
    'hips': [r('body_pitch'), r('body_yaw'), r('body_roll')],
    'spine': [r('torso_pitch'), r('torso_yaw'), r('torso_roll')],
    'head': [r('head_pitch'), r('head_yaw'), r('head_roll')],
  };
  for (final side in ['left', 'right']) {
    final sign = side == 'left' ? -1.0 : 1.0;
    bones['${side}UpperArm'] = [
      r('${side}_shoulder_twist'),
      sign * r('${side}_shoulder_raise'),
      sign * (1.28 - r('${side}_shoulder_abduct')),
    ];
    bones['${side}LowerArm'] = [r('${side}_elbow_bend'), 0, 0];
    bones['${side}UpperLeg'] = [
      -r('${side}_hip_raise'),
      sign * r('${side}_hip_twist'),
      sign * r('${side}_hip_abduct'),
    ];
    bones['${side}LowerLeg'] = [r('${side}_knee_bend'), 0, 0];
  }
  return bones;
}
