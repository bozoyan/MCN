// 职责: 验证导演新合同的完整字段、控制冲突、预算和独立快照。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/pose.dart
//   lib/shared/models/director/path.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/pose.dart';
import 'package:uuid/uuid.dart';

Json actor() => {
  'id': const Uuid().v4(),
  'kind': 'actor',
  'name': 'Actor',
  'geometry_key': 'actor.male.v1',
  'position': [0, 0, 0],
  'rotation': [0, 0, 0, 1],
  'scale': [1, 1, 1],
  'color': '#4477AA',
  'visible': true,
  'pose': ActorPose.standing().toJson(),
};

void main() {
  test(
    'optional depth-of-field settings preserve old cameras and reject invalid optics',
    () {
      final source = DirectorDocument.blank('Optics').toJson();
      (source['cameras'][0] as Json).remove('focus_distance_m');
      (source['cameras'][0] as Json).remove('aperture_fstop');
      final document = DirectorDocument.fromJson(source);
      expect(document.cameras.single['focus_distance_m'], 10);
      expect(document.cameras.single['aperture_fstop'], 0);
      final edited = document.mutate((j) {
        j['cameras'][0]['focus_distance_m'] = 2.5;
        j['cameras'][0]['aperture_fstop'] = 1.4;
      });
      expect(DirectorDocument.parse(edited.encode()).toJson(), edited.toJson());
      for (final entry in [
        ('focus_distance_m', 0),
        ('focus_distance_m', 201),
        ('aperture_fstop', -1),
        ('aperture_fstop', 33),
        ('aperture_fstop', null),
      ]) {
        expect(
          () => document.mutate((j) => j['cameras'][0][entry.$1] = entry.$2),
          throwsA(isA<DocumentError>()),
        );
      }
    },
  );
  test('blank and complete pose round trip without legacy fields', () {
    final d = DirectorDocument.blank(
      'Scene',
    ).mutate((j) => j['objects'].add(actor()));
    expect(DirectorDocument.parse(d.encode()).toJson(), d.toJson());
    expect(d.objects.single['pose'].length, 26);
    expect(d.toJson().containsKey('action_clips'), isFalse);
    for (final edit in <void Function(Json)>[
      (j) => j['action_clips'] = [],
      (j) => j['cameras'][0]['target'] = [0, 1, 0],
      (j) => j['cameras'][0]['look_at_id'] = null,
      (j) => j['cameras'][0]['rotation'] = null,
      (j) => j['cameras'][0].remove('reference_up'),
      (j) => j['objects'][0]['pose'].remove('root_offset_y'),
      (j) => j['objects'][0]['pose']['root_offset_y'] = -51,
      (j) => j['objects'][0]['pose']['unknown'] = 0,
      (j) => j['objects'][0]['pose'] = 'neutral',
      (j) => j['lighting']['key_direction'] = [0, 0, 0],
      (j) => j['default_camera_id'] = 'missing',
    ]) {
      expect(() => d.mutate(edit), throwsA(isA<DocumentError>()));
    }
  });
  test('free mode requires rotation and rejects look-at fields', () {
    final d = DirectorDocument.blank('Scene').mutate((j) {
      final c = j['cameras'][0] as Json;
      c.remove('camera_target');
      c.remove('reference_up');
      c.remove('roll');
      c['orientation_mode'] = 'free';
      c['rotation'] = [0, 0, 0, 2];
    });
    expect(d.cameras.single['rotation'], [0, 0, 0, 1]);
    expect(
      () => d.mutate((j) => j['cameras'][0]['camera_target'] = null),
      throwsA(isA<DocumentError>()),
    );
  });
  test('single late pose key is valid and target structures are strict', () {
    final d = DirectorDocument.blank('Scene').mutate((j) {
      final a = actor();
      j['objects'].add(a);
      j['tracks'].add({
        'id': const Uuid().v4(),
        'target_id': a['id'],
        'property': 'pose',
        'keys': [
          {
            'frame': 48,
            'value': ActorPose.standing().withValues({
              'root_offset_y': -0.5,
            }).toJson(),
            'easing': 'linear',
          },
        ],
      });
      j['cameras'][0]['camera_target'] = {
        'type': 'bone',
        'actor_id': a['id'],
        'bone': 'head',
        'offset': [0, 0, 0],
      };
    });
    expect(d.tracks.single['keys'], hasLength(1));
    expect(
      () => d.mutate(
        (j) => j['cameras'][0]['camera_target']['position'] = [0, 0, 0],
      ),
      throwsA(isA<DocumentError>()),
    );
    expect(
      () => d.mutate((j) => j['cameras'][0]['camera_target'].remove('offset')),
      throwsA(isA<DocumentError>()),
    );
    final copy = d.instantiate();
    expect(
      copy.cameras.single['camera_target']['actor_id'],
      copy.objects.single['id'],
    );
    expect(copy.tracks.single['target_id'], copy.objects.single['id']);
  });
  test('cuts switch exactly at their frame and identities are remapped', () {
    final d = DirectorDocument.blank('Scene').mutate((j) {
      final second = DirectorDocument.newCamera('B', [3, 2, 5], [0, 1, 0], 50);
      j['cameras'].add(second);
      j['camera_cuts'].add({
        'id': const Uuid().v4(),
        'frame': 48,
        'camera_id': second['id'],
      });
    });
    expect(d.cameraAt(47), d.defaultCameraId);
    expect(d.cameraAt(48), d.cameras.last['id']);
    final copy = d.instantiate();
    expect(copy.cameraAt(48), copy.cameras.last['id']);
    expect(
      () => d.mutate(
        (j) => j['camera_cuts'].add({
          ...j['camera_cuts'][0],
          'id': const Uuid().v4(),
        }),
      ),
      throwsA(isA<DocumentError>()),
    );
  });
  test('direction keys reject antipodal interpolation but allow a hold', () {
    final d = DirectorDocument.blank('Scene');
    Json track(String easing) => {
      'id': const Uuid().v4(),
      'target_id': d.id,
      'property': 'lighting.key_direction',
      'keys': [
        {
          'frame': 12,
          'value': [1, 0, 0],
          'easing': easing,
        },
        {
          'frame': 24,
          'value': [-1, 0, 0],
          'easing': 'hold',
        },
      ],
    };
    expect(
      () => d.mutate((j) => j['tracks'].add(track('linear'))),
      throwsA(isA<DocumentError>()),
    );
    expect(
      d.mutate((j) => j['tracks'].add(track('hold'))).tracks,
      hasLength(1),
    );
  });
  test('track and path counts are independent of the shared key budget', () {
    final d = DirectorDocument.blank('Scene').mutate((j) {
      for (var i = 0; i < 26; i++) {
        final a = actor();
        if (i < 20) {
          a['kind'] = 'prop';
          a['geometry_key'] = 'prop.cube.v1';
          a['pose'] = 'none';
        }
        j['objects'].add(a);
        for (final property in [
          'position',
          'rotation',
          'scale',
          'color',
          'visible',
        ]) {
          if (j['tracks'].length == 128) {
            break;
          }
          j['tracks'].add({
            'id': const Uuid().v4(),
            'target_id': a['id'],
            'property': property,
            'keys': [
              {'frame': 0, 'value': a[property], 'easing': 'hold'},
            ],
          });
        }
      }
      j['duration_frames'] = 720;
      for (var i = 0; i < 128; i++) {
        j['motion_paths'].add({
          'id': const Uuid().v4(),
          'target_id': j['objects'].last['id'],
          'kind': 'line',
          'start_frame': i,
          'end_frame': i + 1,
          'easing': 'linear',
          'orient_to_path': false,
          'geometry': {
            'start': [0, 0, 0],
            'end': [1, 0, 0],
          },
        });
      }
    });
    expect(d.tracks, hasLength(128));
    expect(d.paths, hasLength(128));
    expect(
      () => d.mutate(
        (j) => j['tracks'].add({
          'id': const Uuid().v4(),
          'target_id': j['objects'].last['id'],
          'property': 'color',
          'keys': [
            {'frame': 0, 'value': '#000000', 'easing': 'hold'},
          ],
        }),
      ),
      throwsA(isA<DocumentError>()),
    );
    expect(
      () => d.mutate(
        (j) => j['motion_paths'].add({
          ...j['motion_paths'].last,
          'id': const Uuid().v4(),
          'start_frame': 128,
          'end_frame': 129,
        }),
      ),
      throwsA(isA<DocumentError>()),
    );
  });
  test('file budget measures actual UTF-8 bytes before decoding', () {
    final text = DirectorDocument.blank('Scene').encode();
    final exact = text.padRight(5 * 1024 * 1024);
    expect(DirectorDocument.parse(exact).title, 'Scene');
    expect(
      () => DirectorDocument.parse('$exact '),
      throwsA(
        isA<DocumentError>().having(
          (e) => e.reason,
          'reason',
          'file_too_large',
        ),
      ),
    );
    expect(
      () => DirectorDocument.fromJson({'oversize': '汉' * (2 * 1024 * 1024)}),
      throwsA(
        isA<DocumentError>().having(
          (e) => e.reason,
          'reason',
          'file_too_large',
        ),
      ),
    );
  });
  test('2048 shared units accepted and 2049 rejected', () {
    final d = DirectorDocument.blank('Scene').mutate((j) {
      for (var i = 0; i < 3; i++) {
        final a = actor();
        j['objects'].add(a);
        j['tracks'].add({
          'id': const Uuid().v4(),
          'target_id': a['id'],
          'property': 'position',
          'keys': [
            for (var k = 0; k < (i == 2 ? 606 : 721); k++)
              {
                'frame': k,
                'value': [0, 0, 0],
                'easing': 'linear',
              },
          ],
        });
      }
      j['duration_frames'] = 720;
    });
    expect(d.tracks, hasLength(3));
    expect(
      () => d.mutate(
        (j) => j['camera_cuts'].add({
          'id': const Uuid().v4(),
          'frame': 0,
          'camera_id': d.defaultCameraId,
        }),
      ),
      throwsA(isA<DocumentError>()),
    );
  });
}
