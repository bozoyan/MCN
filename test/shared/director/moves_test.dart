// 职责: 验证运镜片段、注视目标的确定性采样。
// 关联文件:
//   lib/shared/models/director/sampling.dart
//   lib/shared/models/director/presets.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/presets.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/models/director/properties.dart';
import 'package:reveric/shared/services/director/bake.dart';

void main() {
  final base = DirectorDocument.parse(
    File('test/fixtures/director/scene.director.json').readAsStringSync(),
  );
  final camId = base.activeCameras.first['id'] as String;
  DirectorDocument withMove(String kind, {String? lookAt, int start = 24}) =>
      base.mutate((j) {
        j['camera_moves'] = [
          {
            'id': '60000000-0000-4000-8000-0000000000aa',
            'camera_id': camId,
            'kind': kind,
            'start_frame': start,
            'end_frame': 72,
          },
        ];
        if (lookAt != null) {
          j['cameras'][0]['camera_target'] = {
            'type': 'object',
            'object_id': lookAt,
            'offset': [0, 1.3, 0],
          };
        }
      });
  List<double> pos(DirectorDocument d, int f) => [
    for (final v in sampleCamera(d, camId, f)['position'])
      (v as num).toDouble(),
  ];
  List<double> tgt(DirectorDocument d, int f) => [
    for (final v in sampleCamera(d, camId, f)['target']) (v as num).toDouble(),
  ];

  test(
    'every move kind is valid, starts at the base pose and holds its end',
    () {
      final actor = base.objects.first['id'];
      final noMove = base.mutate((j) => j['camera_moves'] = []);
      for (final kind in moveKinds) {
        final d = withMove(kind, lookAt: actor);
        if (kind != 'follow_pan' && kind != 'lead' && kind != 'orbit') {
          expect(pos(d, 24), [
            for (final v in pos(noMove, 24)) closeTo(v, 1e-9),
          ], reason: kind);
        }
        expect(pos(d, 72), pos(d, 120), reason: '$kind holds end pose');
        expect(tgt(d, 72), tgt(d, 120), reason: '$kind holds end target');
      }
    },
  );

  test('dolly and pan move by the documented amounts', () {
    final dolly = withMove('dolly_in');
    final p0 = pos(dolly, 24), p1 = pos(dolly, 72);
    final moved = math.sqrt(
      List.generate(
        3,
        (i) => math.pow(p1[i] - p0[i], 2),
      ).reduce((a, b) => a + b),
    );
    expect(moved, closeTo(1.5, 1e-9));
    final pan = withMove('pan_l');
    expect(
      quaternionAngle(
        sampleCamera(pan, camId, 24)['rotation'],
        sampleCamera(pan, camId, 72)['rotation'],
      ),
      closeTo(30, 1e-9),
    );
  });

  test('translations preserve direction while zooms preserve position', () {
    for (final kind in [
      'truck_l',
      'truck_r',
      'slide_reveal',
      'fly_through',
      'aerial',
    ]) {
      final d = withMove(kind);
      final a = sampleCamera(d, camId, 24), b = sampleCamera(d, camId, 72);
      expect(pos(d, 72), isNot(pos(d, 24)), reason: kind);
      expect(
        quaternionAngle(a['rotation'], b['rotation']),
        closeTo(0, 1e-5),
        reason: kind,
      );
    }
    final left = withMove('truck_l'), right = withMove('truck_r');
    expect(pos(left, 72)[0], lessThan(pos(left, 24)[0]));
    expect(pos(right, 72)[0], greaterThan(pos(right, 24)[0]));
    for (final kind in ['zoom_out', 'crash_zoom']) {
      final d = withMove(kind);
      final a = sampleCamera(d, camId, 24), b = sampleCamera(d, camId, 72);
      expect(b['position'], a['position']);
      expect(
        b['focal_length_mm'],
        kind == 'zoom_out'
            ? lessThan(a['focal_length_mm'])
            : greaterThan(a['focal_length_mm']),
      );
      expect(moveChannels(kind, 'look_at'), {'focal_length_mm'});
    }
    final rapid = withMove('crash_zoom');
    expect(
      sampleCamera(rapid, camId, 44)['focal_length_mm'],
      sampleCamera(rapid, camId, 72)['focal_length_mm'],
    );
  });

  test('orbit presets preserve radius and reach half and full turns', () {
    final actor = base.objects.first['id'];
    final half = withMove('orbit_half', lookAt: actor);
    final full = withMove('orbit_full', lookAt: actor);
    final center = tgt(full, 24), start = pos(full, 24);
    final end = pos(half, 72);
    expect(end[0] - center[0], closeTo(-(start[0] - center[0]), 1e-9));
    expect(end[2] - center[2], closeTo(-(start[2] - center[2]), 1e-9));
    expect(pos(full, 72), [for (final v in start) closeTo(v, 1e-9)]);
    expect(pos(full, 48), [for (final v in end) closeTo(v, 1e-9)]);
    for (final kind in ['spiral_up', 'spiral_down']) {
      final d = withMove(kind);
      expect(
        pos(d, 72)[1] - pos(d, 24)[1],
        closeTo(kind == 'spiral_up' ? 1.5 : -1.5, 1e-9),
      );
    }
  });

  test('handheld motion is reproducible across seek order and settles', () {
    final d = withMove('handheld');
    final samples = [
      for (final f in [24, 31, 42, 57, 72]) sampleCamera(d, camId, f),
    ];
    expect(samples[2]['position'], isNot(samples.first['position']));
    final fresh = DirectorDocument.parse(d.encode());
    for (final entry in [24, 31, 42, 57, 72].indexed.toList().reversed) {
      expect(sampleCamera(fresh, camId, entry.$2), samples[entry.$1]);
    }
    expect(pos(d, 72), [for (final v in pos(d, 24)) closeTo(v, 1e-9)]);
  });

  test(
    'rack focus changes depth without changing framing and can be baked',
    () {
      final d = withMove('rack_focus', lookAt: base.objects.first['id']).mutate(
        (j) {
          j['cameras'][0]['position'] = [0, 1.3, 5];
          j['objects'][0]['position'] = [0, 0, 0];
          j['cameras'][0]['focus_distance_m'] = 1.0;
        },
      );
      final a = sampleCamera(d, camId, 24), b = sampleCamera(d, camId, 72);
      expect(a['focus_distance_m'], 1);
      expect(b['focus_distance_m'], closeTo(5, 1e-9));
      expect(b['aperture_fstop'], 2.8);
      expect(b['position'], a['position']);
      expect(b['focal_length_mm'], a['focal_length_mm']);
      expect(quaternionAngle(a['rotation'], b['rotation']), closeTo(0, 1e-5));
      final baked = DirectorDocument.fromJson(
        bakeControl(d, 'camera_moves', d.moves.single['id']),
      );
      expect(baked.moves, isEmpty);
      for (var f = 0; f <= 120; f++) {
        final before = sampleCamera(d, camId, f),
            after = sampleCamera(baked, camId, f);
        for (final key in ['focus_distance_m', 'aperture_fstop']) {
          expect(
            bakeError(key, before[key], after[key]),
            lessThanOrEqualTo(1.00000001),
            reason: '$key at $f',
          );
        }
      }
      expect(DirectorDocument.parse(baked.encode()).toJson(), baked.toJson());
    },
  );

  test(
    'rack focus follows concurrent camera motion and holds its final depth',
    () {
      final d = withMove('rack_focus', lookAt: base.objects.first['id']).mutate(
        (j) {
          j['objects'][0]['position'] = [0, 0, 0];
          j['cameras'][0]['position'] = [0, 1.3, 5];
          j['tracks'] = [
            {
              'id': '40000000-0000-4000-8000-000000000099',
              'target_id': camId,
              'property': 'position',
              'keys': [
                {
                  'frame': 24,
                  'value': [0, 1.3, 5],
                  'easing': 'linear',
                },
                {
                  'frame': 72,
                  'value': [0, 1.3, 2],
                  'easing': 'linear',
                },
                {
                  'frame': 120,
                  'value': [0, 1.3, 1],
                  'easing': 'linear',
                },
              ],
            },
          ];
        },
      );
      expect(sampleCamera(d, camId, 72)['focus_distance_m'], closeTo(2, 1e-9));
      expect(sampleCamera(d, camId, 120)['focus_distance_m'], closeTo(2, 1e-9));
      final fresh = DirectorDocument.parse(d.encode());
      expect(
        sampleCamera(fresh, camId, 120)['focus_distance_m'],
        closeTo(2, 1e-9),
      );
    },
  );

  test('new spatial moves can be baked in both camera modes', () {
    for (final kind in [
      'handheld',
      'whip_pan',
      'side_follow',
      'orbit_full',
      'spiral_up',
      'fpv',
      'dive',
    ]) {
      for (final mode in ['look_at', if (!movePreset(kind).subject) 'free']) {
        final d = withMove(kind, lookAt: base.objects.first['id']).mutate((j) {
          if (mode == 'free') {
            final c = j['cameras'][0] as Json;
            c['orientation_mode'] = mode;
            c['rotation'] = [0, 0, 0, 1];
            c.remove('camera_target');
            c.remove('reference_up');
            c.remove('roll');
          }
        });
        final baked = DirectorDocument.fromJson(
          bakeControl(d, 'camera_moves', d.moves.single['id']),
        );
        for (var f = 0; f <= 120; f++) {
          final before = sampleCamera(d, camId, f),
              after = sampleCamera(baked, camId, f);
          expect(
            bakeError('position', before['position'], after['position']),
            lessThanOrEqualTo(1.00000001),
            reason: '$kind $mode $f',
          );
          expect(
            quaternionAngle(before['rotation'], after['rotation']),
            lessThanOrEqualTo(bakeAngleTolerance + 1e-8),
            reason: '$kind $mode $f',
          );
        }
      }
    }
  });

  test('subject moves need a look-at target; look-at drives the target', () {
    final actor = base.objects[1];
    expect(() => withMove('orbit'), throwsA(isA<DocumentError>()));
    final driven = withMove('static', lookAt: actor['id']);
    expect(tgt(driven, 10), [
      closeTo(actor['position'][0], 1e-6),
      closeTo(1.3, 1e-6),
      closeTo(actor['position'][2], 1e-6),
    ]);
    final orbit = withMove('orbit', lookAt: actor['id']);
    expect(pos(orbit, 72), isNot(pos(orbit, 24)));
  });

  test('look-at follows elevated, scaled and tilted actors', () {
    final actorId = base.objects.first['id'];
    final d = base.mutate((j) {
      j['camera_moves'] = [];
      j['cameras'][0]['camera_target'] = {
        'type': 'object',
        'object_id': actorId,
        'offset': [0, 1.3, 0],
      };
      j['objects'][0]['position'] = [1, 3, 2];
      j['objects'][0]['scale'] = [2, 2, 2];
      j['objects'][0]['rotation'] = eulerQuaternion([0, 0, math.pi / 2]);
    });
    final target = tgt(d, 0);
    expect(target[0], closeTo(-1.6, 1e-9));
    expect(target[1], closeTo(3, 1e-9));
    expect(target[2], closeTo(2, 1e-9));
  });
  test(
    'follow and lead track vertical displacement without doubling the target offset',
    () {
      final actor = base.objects.first['id'];
      for (final kind in ['follow', 'lead']) {
        final d = withMove(kind, lookAt: actor, start: 0).mutate((j) {
          j['objects'][0]['rotation'] = [0, 0, 0, 1];
          j['tracks'] = [
            {
              'id': '40000000-0000-4000-8000-000000000001',
              'target_id': actor,
              'property': 'position',
              'keys': [
                {
                  'frame': 0,
                  'value': [0, 0, 0],
                  'easing': 'linear',
                },
                {
                  'frame': 72,
                  'value': [1, 3, 2],
                  'easing': 'linear',
                },
              ],
            },
          ];
        });
        expect(pos(d, 72)[1] - pos(d, 0)[1], closeTo(3, 1e-9));
        final target = tgt(d, 72);
        expect(target[0], closeTo(1, 1e-9));
        expect(target[1], closeTo(4.3, 1e-9));
        expect(target[2], closeTo(2, 1e-9));
      }
    },
  );
}
