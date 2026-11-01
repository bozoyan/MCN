// 职责: 验证绝对时间采样、最短弧转身及属性插值边界。
// 关联文件:
//   lib/shared/models/director/sampling.dart
//   lib/shared/models/director/presets.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/sampling.dart';

void main() {
  final d = DirectorDocument.parse(
    File('test/fixtures/director/motion.director.json').readAsStringSync(),
  );
  test('entry absolute seek out of order', () {
    for (final pair in [
      (120, 0.0, 4.0),
      (0, -2.0, 5.0),
      (96, 0.0, 4.2),
      (48, -1.0, 4.6),
    ]) {
      final s = sampleDocument(d, pair.$1);
      expect(s.objects.first['position'][2], closeTo(pair.$2, 1e-10));
      expect(
        s.cameras[d.activeCameras.first['id']]!['position'][2],
        closeTo(pair.$3, 1e-10),
      );
    }
  });
  test('shortest slerp crosses 180 degrees', () {
    final q = slerp(
      yawQuaternion(170 * math.pi / 180),
      yawQuaternion(-170 * math.pi / 180),
      0.5,
    );
    expect(quaternionYaw(q).abs(), closeTo(math.pi, 1e-10));
  });
  test(
    'Euler edits preserve arbitrary orientation, including singular pitch',
    () {
      for (final angles in <List<double>>[
        [0.3, 2.4, -0.7],
        [math.pi, 0, 0],
        [0, 0, math.pi],
        [math.pi / 2, 0.7, -0.4],
        [-math.pi / 2, 0.7, -0.4],
        [1.2, -2.5, 2.8],
      ]) {
        final q = eulerQuaternion(angles);
        final restored = eulerQuaternion(quaternionEuler(q));
        final dot = List.generate(
          4,
          (i) => q[i] * restored[i],
        ).reduce((a, b) => a + b);
        expect(dot.abs(), closeTo(1, 1e-10), reason: '$angles');
      }
    },
  );
  test(
    'airborne tumble samples deterministically after document round trip',
    () {
      final actor = d.objects.first['id'];
      final flight = d.mutate((j) {
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
                'frame': 24,
                'value': [0, 3, 2],
                'easing': 'linear',
              },
              {
                'frame': 48,
                'value': [0, 0.2, 4],
                'easing': 'hold',
              },
            ],
          },
          {
            'id': '40000000-0000-4000-8000-000000000002',
            'target_id': actor,
            'property': 'rotation',
            'keys': [
              {
                'frame': 0,
                'value': [0, 0, 0, 1],
                'easing': 'linear',
              },
              {
                'frame': 24,
                'value': eulerQuaternion([math.pi / 2, 0, 0]),
                'easing': 'linear',
              },
              {
                'frame': 48,
                'value': eulerQuaternion([math.pi / 2, math.pi / 2, 0]),
                'easing': 'hold',
              },
            ],
          },
        ];
      });
      final restored = DirectorDocument.parse(flight.encode());
      for (final frame in [48, 12, 0, 36, 24, 120]) {
        expect(
          sampleDocument(restored, frame).objects,
          sampleDocument(flight, frame).objects,
        );
      }
      expect(sampleDocument(restored, 12).objects.first['position'], [
        0,
        1.5,
        1,
      ]);
      final halfway =
          sampleDocument(restored, 12).objects.first['rotation'] as List;
      expect(halfway[0], closeTo(math.sin(math.pi / 8), 1e-10));
      expect(halfway[3], closeTo(math.cos(math.pi / 8), 1e-10));
      expect(sampleDocument(restored, 120).objects.first['position'], [
        0,
        0.2,
        4,
      ]);
      expect(
        () => flight.mutate(
          (j) => j['tracks'][0]['keys'][1]['value'][1] = double.infinity,
        ),
        throwsA(isA<DocumentError>()),
      );
      expect(
        () => flight.mutate(
          (j) => j['tracks'][1]['keys'][1]['value'] = [0, 0, 0, 0],
        ),
        throwsA(isA<DocumentError>()),
      );
    },
  );
  test('smoothstep and hold', () {
    final t = {
      'property': 'position',
      'keys': [
        {
          'frame': 0,
          'value': [0, 0, 0],
          'easing': 'smoothstep',
        },
        {
          'frame': 24,
          'value': [2, 0, 2],
          'easing': 'hold',
        },
      ],
    };
    expect(sampleTrack(t, 12), [1.0, 0.0, 1.0]);
    t['keys'] = [
      {
        'frame': 0,
        'value': [0, 0, 0],
        'easing': 'hold',
      },
      {
        'frame': 24,
        'value': [2, 0, 2],
        'easing': 'hold',
      },
    ];
    expect(sampleTrack(t, 23), [0.0, 0.0, 0.0]);
    expect(sampleTrack(t, 24), [2, 0, 2]);
  });
}
