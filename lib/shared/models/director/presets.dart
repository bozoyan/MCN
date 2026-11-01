// 职责: 定义导演台姿态、内置道具模型、运镜和添加机位的固定预设目录。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/pose.dart
//   lib/shared/models/director/rig.dart
//   lib/shared/services/director/commands.dart
import 'dart:math' as math;
import 'pose.dart';
import 'rig.dart';

export 'prop_catalog.dart';

typedef BoneEuler = List<double>;
const actorGeometries = ['actor.male.v1', 'actor.female.v1'];
ActorPose _pose(Map<String, num> values) =>
    ActorPose.standing().withValues(values);
final Map<String, ActorPose> actorPoses = {
  'neutral': _pose({}),
  't_pose': _pose({
    'left_shoulder_abduct': 73.3386,
    'right_shoulder_abduct': 73.3386,
  }),
  'walk': _pose({
    'left_shoulder_raise': -20,
    'right_shoulder_raise': 20,
    'left_hip_raise': 18,
    'right_hip_raise': -18,
  }),
  'run': _pose({
    'left_shoulder_raise': -40,
    'right_shoulder_raise': 40,
    'left_elbow_bend': 80,
    'right_elbow_bend': 80,
    'left_hip_raise': 37,
    'right_hip_raise': -32,
    'right_knee_bend': 46,
    'torso_pitch': 9,
  }),
  'sit': _pose({
    'left_hip_raise': 77.35,
    'right_hip_raise': 77.35,
    'left_knee_bend': 71.62,
    'right_knee_bend': 71.62,
  }),
  'squat': _pose({
    'left_shoulder_raise': 52,
    'right_shoulder_raise': 52,
    'torso_pitch': 20,
    'left_hip_raise': 97.4,
    'right_hip_raise': 97.4,
    'left_knee_bend': 120.32,
    'right_knee_bend': 120.32,
  }),
  'kneel': _pose({
    'left_hip_raise': 83.08,
    'left_knee_bend': 83.08,
    'right_hip_raise': -2.86,
    'right_knee_bend': 95,
  }),
  'kneel_both': _pose({'left_knee_bend': 100, 'right_knee_bend': 100}),
  'hands_hips': _pose({
    'left_shoulder_raise': -14,
    'right_shoulder_raise': -14,
    'left_shoulder_abduct': 28,
    'right_shoulder_abduct': 28,
    'left_elbow_bend': 86,
    'right_elbow_bend': 86,
  }),
  'lean': _pose({'body_roll': 10, 'torso_roll': -7, 'head_roll': -5}),
  'bow': _pose({'torso_pitch': 49, 'head_pitch': -9}),
  'think': _pose({
    'right_shoulder_raise': 29,
    'right_elbow_bend': 132,
    'left_shoulder_raise': 17,
    'left_elbow_bend': 86,
    'head_pitch': 9,
  }),
  'fight': _pose({
    'left_shoulder_raise': 40,
    'right_shoulder_raise': 29,
    'left_elbow_bend': 120,
    'right_elbow_bend': 120,
    'torso_yaw': 12,
    'left_hip_raise': 17,
    'right_hip_raise': -14,
    'left_knee_bend': 17,
    'right_knee_bend': 17,
  }),
  'kick': _pose({
    'left_shoulder_abduct': 39,
    'right_shoulder_abduct': 39,
    'right_hip_raise': 63,
    'right_knee_bend': 20,
  }),
  'throw': _pose({
    'left_shoulder_raise': 74,
    'right_shoulder_raise': -23,
    'right_shoulder_abduct': 90,
    'right_elbow_bend': 86,
    'torso_yaw': -23,
    'left_hip_raise': 23,
    'right_hip_raise': -17,
  }),
  'push': _pose({
    'left_shoulder_raise': 80,
    'right_shoulder_raise': 80,
    'left_elbow_bend': 17,
    'right_elbow_bend': 17,
    'torso_pitch': 9,
    'left_hip_raise': 23,
    'right_hip_raise': -17,
  }),
  'wave': _pose({'right_shoulder_abduct': 94, 'right_elbow_bend': 83}),
  'point': _pose({'right_shoulder_raise': 86, 'right_elbow_bend': 6}),
  'raise_hand': _pose({'right_shoulder_abduct': 154}),
  'cheer': _pose({
    'left_shoulder_abduct': 131,
    'right_shoulder_abduct': 131,
    'left_elbow_bend': 17,
    'right_elbow_bend': 17,
    'head_pitch': -12,
  }),
  'arms_crossed': _pose({
    'left_shoulder_raise': 23,
    'right_shoulder_raise': 23,
    'left_elbow_bend': 92,
    'right_elbow_bend': 92,
  }),
  'phone': _pose({
    'left_shoulder_raise': 17,
    'right_shoulder_raise': 17,
    'left_elbow_bend': 86,
    'right_elbow_bend': 86,
    'head_pitch': 23,
  }),
};
final poseIds = actorPoses.keys.toList();
final _calibratedPoses = <String, ActorPose>{};
ActorPose posePreset(String id, String geometry) {
  final base = actorPoses[id];
  if (base == null) {
    throw ArgumentError.value(id, 'pose');
  }
  if (!['sit', 'squat', 'kneel', 'kneel_both'].contains(id)) {
    return base;
  }
  return _calibratedPoses.putIfAbsent('$geometry/$id', () {
    var pose = base;
    if (id == 'kneel') {
      // 前脚与后膝共同支撑；两种模型的腿长和静止轴向分别标定。
      var low = 90.0, high = 105.0;
      for (var i = 0; i < 40; i++) {
        final angle = (low + high) / 2;
        final candidate = base.withValues({
          'left_hip_raise': angle,
          'left_knee_bend': angle,
        });
        final heights = sampleRig(geometry, candidate).contactHeights;
        if (math.min(heights['foot_l']!, heights['ball_l']!) <
            heights['calf_r']!) {
          low = angle;
        } else {
          high = angle;
        }
      }
      pose = base.withValues({'left_hip_raise': high, 'left_knee_bend': high});
    }
    return supportedPose(geometry, pose);
  });
}

typedef MovePreset = ({String id, String group, String base, bool subject});

const moveGroups = ['basic', 'follow', 'space'];
// base 对齐视频节点的运镜大类；subject = 需要机位设了注视目标才生效。
const List<MovePreset> movePresets = [
  (id: 'static', group: 'basic', base: 'static', subject: false),
  (id: 'pan_l', group: 'basic', base: 'pan', subject: false),
  (id: 'pan_r', group: 'basic', base: 'pan', subject: false),
  (id: 'tilt_u', group: 'basic', base: 'tilt', subject: false),
  (id: 'tilt_d', group: 'basic', base: 'tilt', subject: false),
  (id: 'dolly_in', group: 'basic', base: 'push', subject: false),
  (id: 'dolly_out', group: 'basic', base: 'pull', subject: false),
  (id: 'zoom_in', group: 'basic', base: 'push', subject: false),
  (id: 'zoom_out', group: 'basic', base: 'pull', subject: false),
  (id: 'truck_l', group: 'basic', base: 'track', subject: false),
  (id: 'truck_r', group: 'basic', base: 'track', subject: false),
  (id: 'handheld', group: 'basic', base: 'pan', subject: false),
  (id: 'slide_reveal', group: 'basic', base: 'track', subject: false),
  (id: 'foreground_pass', group: 'basic', base: 'track', subject: true),
  (id: 'fly_through', group: 'basic', base: 'push', subject: false),
  (id: 'whip_pan', group: 'basic', base: 'pan', subject: false),
  (id: 'crash_zoom', group: 'basic', base: 'push', subject: false),
  (id: 'rack_focus', group: 'basic', base: 'focus', subject: true),
  (id: 'follow_pan', group: 'follow', base: 'pan', subject: true),
  (id: 'follow', group: 'follow', base: 'track', subject: true),
  (id: 'lead', group: 'follow', base: 'track', subject: true),
  (id: 'side_follow', group: 'follow', base: 'track', subject: true),
  (id: 'orbit', group: 'follow', base: 'orbit', subject: true),
  (id: 'orbit_half', group: 'follow', base: 'orbit', subject: true),
  (id: 'orbit_full', group: 'follow', base: 'orbit', subject: true),
  (id: 'crane_up', group: 'space', base: 'crane', subject: false),
  (id: 'crane_down', group: 'space', base: 'crane', subject: false),
  (id: 'rise_out', group: 'space', base: 'crane', subject: false),
  (id: 'spiral_up', group: 'space', base: 'orbit', subject: false),
  (id: 'spiral_down', group: 'space', base: 'orbit', subject: false),
  (id: 'aerial', group: 'space', base: 'track', subject: false),
  (id: 'fpv', group: 'space', base: 'push', subject: true),
  (id: 'dive', group: 'space', base: 'crane', subject: true),
];
final moveKinds = [for (final m in movePresets) m.id];
MovePreset movePreset(String id) => movePresets.firstWhere((m) => m.id == id);

const cameraPresets = [
  'current',
  'front_medium',
  'front_close',
  'side_close',
  'over_left',
  'over_right',
  'high_45',
  'low_angle',
  'bird',
  'dutch',
];

/// 以主体脚下位置 [x, z] 和主体朝向 [yaw]（弧度）计算预设机位的
/// position / target / 焦距。荷兰角的 roll 由新建机位命令显式设置。
({List<double> position, List<double> target, double focal}) cameraPresetPose(
  String preset,
  double x,
  double z,
  double yaw,
) {
  List<double> around(double angle, double distance, double height) => [
    x + math.sin(yaw + angle) * distance,
    height,
    z + math.cos(yaw + angle) * distance,
  ];
  final head = [x, 1.6, z], chest = [x, 1.3, z];
  return switch (preset) {
    'front_medium' => (position: around(0, 3.2, 1.5), target: chest, focal: 35),
    'front_close' => (position: around(0, 1.6, 1.55), target: head, focal: 50),
    'side_close' => (
      position: around(math.pi / 2, 1.8, 1.5),
      target: head,
      focal: 50,
    ),
    'over_left' => (
      position: around(math.pi - 0.35, 1.6, 1.6),
      target: head,
      focal: 40,
    ),
    'over_right' => (
      position: around(math.pi + 0.35, 1.6, 1.6),
      target: head,
      focal: 40,
    ),
    'high_45' => (position: around(0, 3, 3), target: chest, focal: 35),
    'low_angle' => (position: around(0, 2.2, 0.4), target: head, focal: 28),
    'bird' => (position: around(0, 1.2, 6), target: [x, 0, z], focal: 24),
    'dutch' => (position: around(0.6, 2.6, 2.1), target: chest, focal: 35),
    _ => (position: around(0, 4, 1.6), target: chest, focal: 35),
  };
}
