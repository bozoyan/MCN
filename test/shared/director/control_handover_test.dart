// 职责: 验证显式控制替换的区间外曲线、边界和原子失败。
// 关联文件:
//   lib/shared/services/director/control_edit.dart
//   lib/shared/services/director/bake.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:reveric/shared/services/director/bake.dart';
import 'package:uuid/uuid.dart';
import 'contract_test.dart' show actor;

Json path(String actorId, int start, int end, {String kind = 'line'}) => {
  'id': const Uuid().v4(),
  'target_id': actorId,
  'kind': kind,
  'start_frame': start,
  'end_frame': end,
  'easing': 'smoothstep',
  'orient_to_path': false,
  'geometry': kind == 'line'
      ? {
          'start': [3, 0, 0],
          'end': [5, 0, 0],
        }
      : {
          'center': [0, 0, 0],
          'radius': 2,
          'plane_rotation': [0, 0, 0, 1],
          'start_angle': 0,
          'clockwise': false,
        },
};
void main() {
  test('replacing curved path preserves both outside halves and one undo', () {
    final h = CommandHistory(
      DirectorDocument.blank('Scene').mutate((j) => j['objects'].add(actor())),
    );
    final id = h.document.objects.single['id'];
    h.upsertPath(path(id, 10, 110, kind: 'circle'));
    final before = h.document;
    final replacement = path(id, 40, 60);
    expect(() => h.upsertPath(replacement), throwsA(isA<DocumentError>()));
    h.upsertPath(replacement, replace: true);
    expect(h.document.paths.single['id'], replacement['id']);
    for (var frame = 0; frame <= 120; frame++) {
      if (frame >= 40 && frame < 60) {
        continue;
      }
      expect(
        bakeError(
          'position',
          sampleDocument(before, frame).objects.single['position'],
          sampleDocument(h.document, frame).objects.single['position'],
        ),
        lessThanOrEqualTo(1.00000001),
      );
    }
    h.undo();
    expect(h.document.businessContent, before.businessContent);
  });
  test('replacement splits smooth interpolation without rescaling outside', () {
    final h = CommandHistory(
      DirectorDocument.blank('Scene').mutate((j) => j['objects'].add(actor())),
    );
    final id = h.document.objects.single['id'];
    h.intervalKeys(id, 'position', 0, 120, [12, 0, 0]);
    final before = h.document;
    h.upsertPath(path(id, 40, 60), replace: true);
    for (var frame = 0; frame <= 120; frame++) {
      if (frame >= 40 && frame < 60) {
        continue;
      }
      expect(
        sampleDocument(h.document, frame).objects.single['position'],
        sampleDocument(before, frame).objects.single['position'],
      );
    }
  });
  test(
    'bake retains outgoing reference, easing and later dynamic following',
    () {
      final a = actor();
      final h = CommandHistory(
        DirectorDocument.blank('Scene').mutate((j) {
          j['objects'].add(a);
          final cameraId = j['cameras'][0]['id'];
          j['tracks'].addAll([
            {
              'id': const Uuid().v4(),
              'target_id': a['id'],
              'property': 'position',
              'keys': [
                {
                  'frame': 0,
                  'value': [0, 0, 0],
                  'easing': 'linear',
                },
                {
                  'frame': 120,
                  'value': [2, 0, 0],
                  'easing': 'linear',
                },
              ],
            },
            {
              'id': const Uuid().v4(),
              'target_id': cameraId,
              'property': 'camera_target',
              'keys': [
                {
                  'frame': 72,
                  'value': {
                    'type': 'object',
                    'object_id': a['id'],
                    'offset': [0, 1, 0],
                  },
                  'easing': 'smoothstep',
                },
                {
                  'frame': 110,
                  'value': {
                    'type': 'point',
                    'position': [0, 1, 0],
                  },
                  'easing': 'hold',
                },
              ],
            },
          ]);
        }),
      );
      final camera = h.document.defaultCameraId;
      h.move(camera, 'pan_l', 24, 72);
      final before = h.document;
      final originalKey = before.tracks.last['keys'][0];
      h.bake('camera_moves', before.moves.single['id']);
      final targetKeys =
          h.document.tracks.firstWhere(
                (t) => t['property'] == 'camera_target',
              )['keys']
              as List;
      expect(targetKeys.firstWhere((k) => k['frame'] == 72), originalKey);
      for (var frame = 0; frame <= 120; frame++) {
        expect(
          quaternionAngle(
            sampleCamera(before, camera, frame)['rotation'],
            sampleCamera(h.document, camera, frame)['rotation'],
          ),
          lessThanOrEqualTo(.01000001),
        );
      }
    },
  );
  test(
    'camera mode switch preserves framing after translated motion and refuses direction animation',
    () {
      final h = CommandHistory(DirectorDocument.blank('Scene'));
      final id = h.document.defaultCameraId;
      h.setCameraMode(id, 'free', 0);
      h.intervalKeys(id, 'position', 0, 120, [3, 4, 5]);
      final before = sampleCamera(h.document, id, 73);
      h.setCameraMode(id, 'look_at', 73);
      final after = sampleCamera(h.document, id, 73);
      expect(
        quaternionAngle(before['rotation'], after['rotation']),
        lessThan(.00001),
      );
      expect(after['position'], before['position']);
      h.setCameraMode(id, 'free', 73);
      expect(
        quaternionAngle(
          before['rotation'],
          sampleCamera(h.document, id, 73)['rotation'],
        ),
        lessThan(.00001),
      );
      h.toggleKey(id, 'rotation', 73);
      final saved = h.document.businessContent;
      expect(
        () => h.setCameraMode(id, 'look_at', 73),
        throwsA(isA<DocumentError>()),
      );
      expect(h.document.businessContent, saved);
    },
  );
  test(
    'metadata keeps the compiled plan and animation edits invalidate it',
    () {
      final d = DirectorDocument.blank('Scene');
      final original = animationPlan(d);
      final renamed = d.mutate((j) {
        j['title'] = 'Renamed';
        j['revision']++;
        j['output']['width'] = 1000;
      });
      expect(identical(animationPlan(renamed), original), isTrue);
      final moved = renamed.mutate((j) => j['cameras'][0]['position'][0] = 2);
      expect(identical(animationPlan(moved), original), isFalse);
    },
  );
  test('full audit diagnoses dynamic pose bounds with frame and actor', () {
    final a = actor();
    a['scale'] = [10, 10, 10];
    final d = DirectorDocument.blank('Scene').mutate((j) {
      j['objects'].add(a);
      j['tracks'].add({
        'id': const Uuid().v4(),
        'target_id': a['id'],
        'property': 'pose',
        'keys': [
          {
            'frame': 40,
            'value': {...a['pose'], 'root_offset_y': 10},
            'easing': 'hold',
          },
        ],
      });
    });
    sampleDocument(d, 39);
    expect(
      () => animationPlan(d).audit(),
      throwsA(
        isA<DocumentError>().having(
          (e) => e.path,
          'path',
          contains('frame[40].${a['id']}.pose.'),
        ),
      ),
    );
  });
  test('free rotation bake and independent multi-turn roll remain exact', () {
    for (final free in [true, false]) {
      final h = CommandHistory(
        DirectorDocument.blank('Scene').mutate((j) {
          final c = j['cameras'][0] as Json;
          if (free) {
            c.remove('camera_target');
            c.remove('reference_up');
            c.remove('roll');
            c['orientation_mode'] = 'free';
            c['rotation'] = eulerQuaternion([.2, .3, .4]);
          } else {
            j['tracks'].add({
              'id': const Uuid().v4(),
              'target_id': c['id'],
              'property': 'roll',
              'keys': [
                {'frame': 0, 'value': -720, 'easing': 'smoothstep'},
                {'frame': 120, 'value': 1080, 'easing': 'linear'},
              ],
            });
          }
        }),
      );
      final id = h.document.defaultCameraId;
      h.move(id, 'pan_r', 24, 72);
      final before = h.document;
      h.bake('camera_moves', before.moves.single['id']);
      expect(
        h.document.cameras.single['orientation_mode'],
        free ? 'free' : 'look_at',
      );
      for (var f = 0; f <= 120; f++) {
        final a = sampleCamera(before, id, f),
            b = sampleCamera(h.document, id, f);
        expect(
          quaternionAngle(a['rotation'], b['rotation']),
          lessThanOrEqualTo(.01000001),
        );
        if (!free) {
          expect(b['roll'], a['roll']);
        }
      }
    }
  });
  test(
    'bake over budget is rejected without modifying the document or undo',
    () {
      final d = DirectorDocument.blank('Scene').mutate((j) {
        j['duration_frames'] = 720;
        for (var i = 0; i < 3; i++) {
          final a = actor();
          j['objects'].add(a);
          j['tracks'].add({
            'id': const Uuid().v4(),
            'target_id': a['id'],
            'property': 'visible',
            'keys': [
              for (var frame = 0; frame < (i == 2 ? 602 : 721); frame++)
                {'frame': frame, 'value': true, 'easing': 'hold'},
            ],
          });
        }
        j['motion_paths'].add(
          path(j['objects'][0]['id'], 0, 120, kind: 'circle'),
        );
      });
      final h = CommandHistory(d);
      expect(
        () => h.bake('motion_paths', d.paths.single['id']),
        throwsA(isA<DocumentError>()),
      );
      expect(h.document.businessContent, d.businessContent);
      expect(h.undoCount, 0);
    },
  );
  test(
    'bake quaternion error treats q and minus q equally and roll keeps winding',
    () {
      expect(bakeError('rotation', [0, 0, 0, 1], [0, 0, 0, -1]), 0);
      expect(bakeError('roll', 720, 360), 36000);
      expect(bakeError('position', [0, 0, 0], [.002, 0, 0]), 2);
      expect(bakeError('focal_length_mm', 35, 35.02), closeTo(2, 1e-10));
    },
  );
}
