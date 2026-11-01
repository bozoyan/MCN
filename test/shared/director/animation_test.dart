// 职责: 验证稀疏属性、动态目标和相机运镜在任意 seek 下的一致结果。
// 关联文件:
//   lib/shared/models/director/sampling.dart
//   lib/shared/models/director/pose.dart
//   lib/shared/models/director/rig.dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/pose.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/models/director/rig.dart';
import 'package:reveric/shared/models/director/presets.dart';
import 'package:uuid/uuid.dart';
import 'contract_test.dart' show actor;

Json track(String id, String property, List<Json> keys) => {
  'id': const Uuid().v4(),
  'target_id': id,
  'property': property,
  'keys': keys,
};
Json key(int frame, dynamic value, [String easing = 'linear']) => {
  'frame': frame,
  'value': value,
  'easing': easing,
};
void main() {
  test(
    'late single key preserves base and full pose interpolates height atomically',
    () {
      final d = DirectorDocument.blank('Scene').mutate((j) {
        final a = actor();
        j['objects'].add(a);
        j['tracks'].add(
          track(a['id'], 'position', [
            key(24, [3, 0, 0]),
          ]),
        );
        j['tracks'].add(
          track(a['id'], 'pose', [
            key(24, ActorPose.standing().toJson()),
            key(
              48,
              ActorPose.standing().withValues({
                'root_offset_y': -0.6,
                'head_yaw': 90,
              }).toJson(),
            ),
          ]),
        );
      });
      expect(sampleDocument(d, 23).objects.single['position'], [0, 0, 0]);
      expect(sampleDocument(d, 24).objects.single['position'], [3, 0, 0]);
      expect(
        sampleDocument(d, 36).objects.single['pose']['root_offset_y'],
        closeTo(-0.3, 1e-10),
      );
      expect(sampleDocument(d, 36).objects.single['pose']['head_yaw'], 45);
      expect(
        sampleDocument(d, 120).objects.single['pose']['root_offset_y'],
        -0.6,
      );
    },
  );
  test(
    'colors interpolate in linear sRGB and direction follows great circle',
    () {
      expect(
        sampleTrack({
          'property': 'color',
          'keys': [key(0, '#000000'), key(24, '#FFFFFF')],
        }, 12),
        '#BCBCBC',
      );
      for (final end in [
        [0, 1, 0],
        [-0.99999, 0.004472, 0],
        [1, 0.000001, 0],
      ]) {
        final value =
            sampleTrack({
                  'property': 'lighting.key_direction',
                  'keys': [
                    key(0, [1, 0, 0]),
                    key(24, end),
                  ],
                }, 12)
                as List;
        expect(
          value.fold<double>(0, (s, n) => s + (n as num) * n),
          closeTo(1, 1e-10),
        );
      }
      final q = slerp([0, 0, 0, 1], [0, 0, 0, -1], 0.5);
      expect(quaternionAngle(q, [0, 0, 0, 1]), 0);
    },
  );
  test(
    'object and bone targets resolve at the current frame during target blending',
    () {
      final d = DirectorDocument.blank('Scene').mutate((j) {
        final a = actor();
        j['objects'].add(a);
        j['tracks'].add(
          track(a['id'], 'position', [
            key(0, [0, 0, 0]),
            key(100, [4, 0, 0]),
          ]),
        );
        j['tracks'].add(
          track(j['cameras'][0]['id'], 'camera_target', [
            key(0, {
              'type': 'point',
              'position': [0, 0, 0],
            }),
            key(100, {
              'type': 'bone',
              'actor_id': a['id'],
              'bone': 'head',
              'offset': [0, 0, 0],
            }),
          ]),
        );
      });
      final sample = sampleDocument(d, 50);
      final world = boneWorldPoint(sample.objects.single, 'head', [0, 0, 0]);
      expect(
        sample.cameras.values.single['target'][0],
        closeTo(world[0] / 2, 1e-10),
      );
      expect(
        sample.cameras.values.single['target'][1],
        closeTo(world[1] / 2, 1e-10),
      );
    },
  );
  test(
    'look-at transports frame through the pole and seek is deterministic',
    () {
      final d = DirectorDocument.blank('Scene').mutate((j) {
        final c = j['cameras'][0];
        c['position'] = [0, 3, 0];
        c['camera_target'] = {
          'type': 'point',
          'position': [0, 0, 1],
        };
        j['tracks'].add(
          track(c['id'], 'camera_target', [
            key(0, {
              'type': 'point',
              'position': [0, 0, 1],
            }),
            key(100, {
              'type': 'point',
              'position': [0, 0, -1],
            }),
          ]),
        );
      });
      final samples = [
        for (final f in [0, 25, 49, 50, 51, 75, 100])
          sampleCamera(d, d.defaultCameraId, f),
      ];
      final fresh = DirectorDocument.parse(d.encode());
      for (var i = samples.length - 1; i >= 0; i--) {
        expect(
          sampleCamera(
            fresh,
            fresh.defaultCameraId,
            [0, 25, 49, 50, 51, 75, 100][i],
          ),
          samples[i],
        );
      }
      expect(
        quaternionAngle(samples[2]['rotation'], samples[4]['rotation']),
        lessThan(1),
      );
    },
  );
  test(
    'all move presets sample finite output and chained relative moves hold endpoints',
    () {
      for (final kind in moveKinds) {
        final d = DirectorDocument.blank('Scene').mutate((j) {
          final a = actor();
          j['objects'].add(a);
          j['cameras'][0]['camera_target'] = {
            'type': 'bone',
            'actor_id': a['id'],
            'bone': 'chest',
            'offset': [0, 0, 0],
          };
          j['camera_moves'].add({
            'id': const Uuid().v4(),
            'camera_id': j['cameras'][0]['id'],
            'kind': kind,
            'start_frame': 12,
            'end_frame': 48,
          });
        });
        for (final f in [0, 12, 24, 48, 72, 120]) {
          final c = sampleCamera(d, d.defaultCameraId, f);
          expect(
            (c['rotation'] as List).every((n) => (n as num).isFinite),
            isTrue,
            reason: kind,
          );
        }
        expect(
          sampleCamera(d, d.defaultCameraId, 48)['position'],
          sampleCamera(d, d.defaultCameraId, 72)['position'],
        );
      }
      final d = DirectorDocument.blank('Scene').mutate((j) {
        for (final start in [0, 48]) {
          j['camera_moves'].add({
            'id': const Uuid().v4(),
            'camera_id': j['cameras'][0]['id'],
            'kind': 'dolly_in',
            'start_frame': start,
            'end_frame': start + 48,
          });
        }
      });
      final initial = sampleCamera(d, d.defaultCameraId, 0)['position'] as List,
          end = sampleCamera(d, d.defaultCameraId, 96)['position'] as List;
      expect(
        math.sqrt(
          List.generate(
            3,
            (i) => math.pow(end[i] - initial[i], 2),
          ).reduce((a, b) => a + b),
        ),
        closeTo(3, 1e-8),
      );
    },
  );
}
