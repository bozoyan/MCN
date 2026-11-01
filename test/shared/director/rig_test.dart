// 职责: 验证真实模型 rig 元数据、预设支撑和显式姿态高度的合成。
// 关联文件:
//   lib/shared/models/director/rig.dart
//   lib/shared/models/director/rig_data.dart
//   lib/shared/models/director/presets.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:reveric/shared/models/director/pose.dart';
import 'package:reveric/shared/models/director/presets.dart';
import 'package:reveric/shared/models/director/rig.dart';
import 'package:reveric/shared/models/director/rig_data.dart';

void main() {
  test('kinematics rest transforms exactly match both shipped GLBs', () {
    for (final geometry in actorGeometries) {
      final gender = geometry.split('.')[1];
      final bytes = File(
        'assets/director/models/quaternius-standard-$gender.glb',
      ).readAsBytesSync();
      final length = ByteData.sublistView(bytes).getUint32(12, Endian.little);
      final glb =
          jsonDecode(utf8.decode(bytes.sublist(20, 20 + length))) as Map;
      final nodes = glb['nodes'] as List;
      final parents = {
        for (var i = 0; i < nodes.length; i++)
          for (final child in nodes[i]['children'] ?? []) child: i,
      };
      for (final entry in actorRigNodes[geometry]!.entries) {
        final i = nodes.indexWhere((n) => n['name'] == entry.key),
            node = nodes[i];
        expect(entry.value['position'], node['translation'] ?? [0, 0, 0]);
        expect(entry.value['rotation'], node['rotation'] ?? [0, 0, 0, 1]);
        expect(entry.value['scale'], node['scale'] ?? [1, 1, 1]);
        expect(
          entry.value['parent'],
          parents.containsKey(i) ? nodes[parents[i]!]['name'] : null,
        );
      }
    }
  });
  test('sit squat and kneel presets support both bodies at all scales', () {
    for (final geometry in actorGeometries) {
      for (final preset in ['sit', 'squat', 'kneel', 'kneel_both']) {
        final pose = posePreset(preset, geometry);
        final rig = sampleRig(geometry, pose);
        final designated = preset.startsWith('kneel')
            ? ['calf_r']
            : ['foot_l', 'foot_r', 'ball_l', 'ball_r'];
        for (final scale in [0.5, 1.0, 2.0]) {
          final heights = rig.contactHeights;
          expect(
            heights.values.every((h) => h * scale >= -0.001),
            isTrue,
            reason: '$geometry $preset $heights',
          );
          expect(
            designated.map((p) => heights[p]!).reduce(math.min) * scale,
            closeTo(0, 0.001),
            reason: '$geometry $preset $heights',
          );
        }
      }
    }
  });
  test(
    'bone world anchors use the same forward TRS rotation as renderer nodes',
    () {
      final pose = ActorPose.standing().withValues({
        'body_pitch': 90,
        'root_offset_y': -.67,
      });
      final rotation = v.Quaternion.axisAngle(v.Vector3(0, 1, 0), -math.pi / 2);
      final actor = <String, dynamic>{
        'geometry_key': 'actor.male.v1',
        'pose': pose.toJson(),
        'position': [19.5, 0, 0],
        'rotation': [rotation.x, rotation.y, rotation.z, rotation.w],
        'scale': [1, 1, 1],
      };
      final local = sampleRig(
        'actor.male.v1',
        pose,
      ).localPoint('head', [0, 0, 0]);
      final expected = v.Matrix4.compose(
        v.Vector3(19.5, 0, 0),
        rotation,
        v.Vector3.all(1),
      ).transformed3(local);
      final actual = boneWorldPoint(actor, 'head', [0, 0, 0]);
      expect(v.Vector3.array(actual).distanceTo(expected), lessThan(1e-9));
    },
  );
  test('height follows object scale once and is not world-ground snapping', () {
    for (final geometry in actorGeometries) {
      final pose = ActorPose.standing().withValues({'root_offset_y': 0.7});
      for (final scale in [0.5, 1.0, 2.0]) {
        final actor = <String, dynamic>{
          'geometry_key': geometry,
          'pose': pose.toJson(),
          'position': [0, 2, 0],
          'rotation': [0, 0, 0, 1],
          'scale': [scale, scale, scale],
        };
        final base = {...actor, 'pose': ActorPose.standing().toJson()};
        expect(
          boneWorldPoint(actor, 'head', [0, 0, 0])[1] -
              boneWorldPoint(base, 'head', [0, 0, 0])[1],
          closeTo(0.7 * scale, 1e-10),
        );
        expect(
          sampleRig(geometry, pose).contactHeights.values.reduce(math.min),
          closeTo(0.7, 1e-10),
        );
      }
    }
  });
}
