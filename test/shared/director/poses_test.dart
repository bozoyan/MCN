// 职责: 验证角色姿态目录只引用人形骨骼，且每个姿态与体型都能通过文档校验。
// 关联文件:
//   lib/shared/models/director/presets.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/models/director/document.dart
import 'dart:io';
import 'package:reveric/shared/models/director/pose.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/presets.dart';
import 'package:reveric/shared/models/director/sampling.dart';

void main() {
  final d = DirectorDocument.parse(
    File('test/fixtures/director/scene.director.json').readAsStringSync(),
  );
  test('poses only target humanoid bones with xyz euler', () {
    for (final entry in actorPoses.entries) {
      for (final bone in poseBones(entry.value).entries) {
        expect(humanoidBones, contains(bone.key), reason: entry.key);
        expect(bone.value, hasLength(3), reason: '${entry.key}.${bone.key}');
      }
    }
  });
  test('every pose and body samples finite joints', () {
    final id = d.objects.first['id'];
    for (final geometry in actorGeometries) {
      for (final pose in poseIds) {
        final next = d.mutate((j) {
          final actor = (j['objects'] as List).first;
          actor['pose'] = posePreset(pose, geometry).toJson();
          actor['geometry_key'] = geometry;
        });
        final joints = sampleDocument(next, 0).joints[id]!;
        expect(joints.keys, unorderedEquals(humanoidBones));
        for (final e in joints.values) {
          expect(e.every((v) => v.isFinite), isTrue, reason: pose);
        }
      }
    }
  });
}
