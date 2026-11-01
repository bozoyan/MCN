// 职责: 验证 AI 批次沿编辑器命令处理路径、运镜、模式和切镜。
// 关联文件:
//   lib/shared/services/director/batch_commands.dart
//   lib/shared/services/director/commands.dart
//   lib/shared/models/director/sampling.dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/presets.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/services/director/batch_commands.dart';
import 'package:reveric/shared/services/director/commands.dart';

double distance3(List a, List b) => math.sqrt(
  List.generate(
    3,
    (i) => math.pow((a[i] as num) - (b[i] as num), 2),
  ).fold<double>(0, (sum, n) => sum + n),
);

void main() {
  test('apply_pose resolves the actor model independently of editor mode', () {
    for (final geometry in actorGeometries) {
      for (final timeline in [false, true]) {
        for (final autoKey in [false, true]) {
          final h = CommandHistory(DirectorDocument.blank('Pose'));
          addTearDown(h.dispose);
          h.addObject(geometry, 'Actor');
          final actor = h.document.objects.single;
          final id = actor['id'];
          h.execute((j) {
            j['objects'][0]['position'] = [1, 2, 3];
            j['objects'][0]['rotation'] = [0, 1, 0, 0];
            j['objects'][0]['scale'] = [2, 2, 2];
          });
          h.timelineVisible = timeline;
          h.autoKey = autoKey;
          final transform = h.document.objects.single;
          final result = applyDirectorCommands(h, [
            {'op': 'apply_pose', 'target_id': id, 'preset': 'sit'},
          ]);
          expect(result.single['id'], id);
          expect(
            h.document.objects.single['pose'],
            posePreset('sit', geometry).toJson(),
          );
          expect(h.document.tracks, isEmpty);
          expect(h.timelineVisible, timeline);
          applyDirectorCommands(h, [
            {
              'op': 'apply_pose',
              'target_id': id,
              'preset': 'squat',
              'frame': 24,
            },
          ]);
          expect(h.document.tracks.single['keys'], hasLength(1));
          expect(
            sampleDocument(h.document, 0).objects.single['pose'],
            posePreset('sit', geometry).toJson(),
          );
          expect(
            sampleDocument(h.document, 24).objects.single['pose'],
            posePreset('squat', geometry).toJson(),
          );
          h.upsertKey(
            id,
            'pose',
            24,
            posePreset('squat', geometry).toJson(),
            easing: 'hold',
          );
          applyDirectorCommands(h, [
            {
              'op': 'apply_pose',
              'target_id': id,
              'preset': 'kneel',
              'frame': 24,
            },
          ]);
          expect(h.document.tracks.single['keys'], hasLength(1));
          expect(h.document.tracks.single['keys'][0]['easing'], 'hold');
          expect(
            sampleDocument(h.document, 24).objects.single['pose'],
            posePreset('kneel', geometry).toJson(),
          );
          for (final field in [
            'position',
            'rotation',
            'scale',
            'geometry_key',
          ]) {
            expect(h.document.objects.single[field], transform[field]);
          }
          final before = h.document;
          expect(
            () => applyDirectorCommands(h, [
              {'op': 'apply_pose', 'target_id': id, 'preset': 'neutral'},
            ]),
            throwsA(
              isA<DocumentError>().having(
                (e) => e.reason,
                'reason',
                'open_timeline',
              ),
            ),
          );
          expect(h.document, same(before));
          expect(h.timelineVisible, timeline);
          expect(h.autoKey, autoKey);
        }
      }
    }
  });

  test('path and move batches use editor handover and checked Bake', () {
    final h = CommandHistory(DirectorDocument.blank('Batch'));
    addTearDown(h.dispose);
    h.addObject('actor.male.v1', 'Actor');
    final actor = h.document.objects.single['id'];
    final camera = h.document.defaultCameraId;
    final result = applyDirectorCommands(h, [
      {
        'op': 'upsert_path',
        'data': {
          'target_id': actor,
          'kind': 'line',
          'start_frame': 0,
          'end_frame': 48,
          'easing': 'linear',
          'orient_to_path': false,
          'geometry': {
            'start': [0, 0, 0],
            'end': [2, 0, 0],
          },
        },
      },
      {
        'op': 'upsert_move',
        'data': {
          'camera_id': camera,
          'kind': 'dolly_in',
          'start_frame': 0,
          'end_frame': 48,
        },
      },
    ]);
    expect(result.every((r) => r['id'] is String), isTrue);
    final before = h.document;
    expect(sampleDocument(before, 24).objects.single['position'], [1, 0, 0]);
    applyDirectorCommands(h, [
      {'op': 'bake', 'collection': 'motion_paths', 'id': result[0]['id']},
      {'op': 'bake', 'collection': 'camera_moves', 'id': result[1]['id']},
    ]);
    expect(h.document.paths, isEmpty);
    expect(h.document.moves, isEmpty);
    for (var frame = 0; frame <= before.durationFrames; frame++) {
      final a = sampleDocument(before, frame),
          b = sampleDocument(h.document, frame);
      expect(
        distance3(a.objects.single['position'], b.objects.single['position']),
        lessThanOrEqualTo(.001),
      );
      expect(
        distance3(
          a.cameras[camera]!['position'],
          b.cameras[camera]!['position'],
        ),
        lessThanOrEqualTo(.001),
      );
    }
  });

  test('camera preset, mode and cut commands retain editor semantics', () {
    final h = CommandHistory(DirectorDocument.blank('Camera'));
    addTearDown(h.dispose);
    final added = applyDirectorCommands(h, [
      {'op': 'add_camera', 'name': 'B', 'preset': 'front_medium', 'frame': 0},
    ]).single['id'];
    final before = sampleCamera(h.document, added, 0);
    applyDirectorCommands(h, [
      {'op': 'set_camera_mode', 'camera_id': added, 'mode': 'free', 'frame': 0},
      {'op': 'set_cut', 'camera_id': added, 'frame': 48},
    ]);
    expect(
      quaternionAngle(
        before['rotation'],
        sampleCamera(h.document, added, 0)['rotation'],
      ),
      lessThanOrEqualTo(.01),
    );
    expect(h.document.cameraAt(47), h.document.defaultCameraId);
    expect(h.document.cameraAt(48), added);
    expect(
      () => applyDirectorCommands(h, [
        {'op': 'action'},
      ]),
      throwsA(isA<DocumentError>()),
    );
    expect(
      () => applyDirectorCommands(h, [
        {
          'op': 'set_key',
          'target_id': added,
          'property': 'roll',
          'frame': 0,
          'value': 1,
        },
      ]),
      throwsA(isA<DocumentError>()),
    );
  });
}
