// 职责: 验证五种路径的弧长、边界、转向窗口与确定性采样。
// 关联文件:
//   lib/shared/models/director/path.dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/path.dart';
import 'package:reveric/shared/models/director/document.dart';

MotionPath path(String kind, Json geometry, {bool orient = true}) =>
    MotionPath.fromJson({
      'id': 'path',
      'target_id': 'actor',
      'kind': kind,
      'start_frame': 0,
      'end_frame': 100,
      'easing': 'linear',
      'orient_to_path': orient,
      'geometry': geometry,
    });
void main() {
  test(
    'line and rectangle use analytic lengths with intentional corner turn',
    () {
      final line = path('line', {
        'start': [0, 0, 0],
        'end': [0, 3, 4],
      });
      expect(line.length, 5);
      expect(line.sample(50, 0).position, [0, 1.5, 2]);
      final rectangle = path('rectangle', {
        'center': [0, 0, 0],
        'width': 4,
        'depth': 2,
        'plane_rotation': [0, 0, 0, 1],
        'start_corner': 0,
        'clockwise': false,
      });
      expect(rectangle.length, 12);
      expect(rectangle.sample(0, 0).position, [-2, 0, -1]);
      expect(rectangle.sample(100 / 3, 0).yaw, closeTo(0, 1e-10));
      expect(
        rectangle.sample(100 / 3 - 0.001, 0).yaw,
        closeTo(math.pi / 2, 1e-10),
      );
      expect(rectangle.sample(100, 0).position, [-2, 0, -1]);
    },
  );
  test('circle is analytic and respects rotated plane', () {
    final circle = path('circle', {
      'center': [0, 0, 0],
      'radius': 2,
      'plane_rotation': [0, 0, 0, 1],
      'start_angle': 0,
      'clockwise': false,
    });
    expect(circle.length, closeTo(4 * math.pi, 1e-10));
    expect(circle.sample(25, 0).position[2], closeTo(2, 1e-10));
    expect(circle.sample(100, 0).position[0], closeTo(2, 1e-10));
    expect(
      () => path('circle', {
        'center': [49, 0, 0],
        'radius': 2,
        'plane_rotation': [0, 0, 0, 1],
        'start_angle': 0,
        'clockwise': false,
      }),
      throwsA(isA<DocumentError>()),
    );
  });
  test(
    'rotated circle plane follows positive right-handed quaternion direction',
    () {
      final circle = path('circle', {
        'center': [0, 0, 0],
        'radius': 2,
        'plane_rotation': [0, 0, math.sin(math.pi / 4), math.cos(math.pi / 4)],
        'start_angle': 0,
        'clockwise': false,
      });
      final start = circle.sample(0, 0).position;
      expect(start[0], closeTo(0, 1e-9));
      expect(start[1], closeTo(2, 1e-9));
      expect(start[2], closeTo(0, 1e-9));
    },
  );
  test('pencil stays on polyline while heading smoothly crosses a corner', () {
    final pencil = path('pencil', {
      'points': [
        [0, 0, 0],
        [1, 0, 0],
        [1, 0, 1],
      ],
      'closed': false,
    });
    expect(pencil.sample(50, 0).position, [1, 0, 0]);
    expect(pencil.sample(50, 0).yaw, closeTo(math.pi / 4, 1e-10));
    expect(pencil.sample(45, 0).yaw, closeTo(math.pi / 2, 1e-10));
    expect(pencil.sample(55, 0).yaw, closeTo(0, 1e-10));
    final reverse = {
      'points': [
        [0, 0, 0],
        [1, 0, 0],
        [0, 0, 0],
      ],
      'closed': false,
    };
    expect(() => path('pencil', reverse), throwsA(isA<DocumentError>()));
    expect(path('pencil', reverse, orient: false).length, 2);
  });
  test(
    'vertical segments keep deterministic preceding heading and closed seam is smooth',
    () {
      final pencil = path('pencil', {
        'points': [
          [0, 0, 0],
          [0, 1, 0],
          [1, 1, 0],
          [1, 2, 0],
        ],
        'closed': false,
      });
      expect(pencil.sample(10, 0.8).yaw, 0.8);
      expect(pencil.sample(90, 0.8).yaw, closeTo(math.pi / 2, 1e-10));
      final closed = path('pencil', {
        'points': [
          [0, 0, 0],
          [1, 0, 0],
          [1, 0, 1],
          [0, 0, 1],
        ],
        'closed': true,
      });
      expect(
        closed.sample(0, 0).yaw,
        closeTo(closed.sample(100, 0).yaw, 1e-10),
      );
    },
  );
  test(
    'pen adaptive arc table and pencil simplification preserve error bounds',
    () {
      final pen = path('pen', {
        'nodes': [
          {
            'position': [0, 0, 0],
            'out_handle': [0, 0, 1],
            'smooth': false,
          },
          {
            'position': [1, 0, 1],
            'in_handle': [0, 0, 1],
            'smooth': false,
          },
        ],
        'closed': false,
      });
      expect(pen.length, greaterThan(math.sqrt(2)));
      expect(pen.sample(0, 0).position, [0, 0, 0]);
      expect(pen.sample(100, 0).position, [1, 0, 1]);
      final first = pen.sample(63, 0).position;
      pen.sample(20, 0);
      expect(pen.sample(63, 0).position, first);
      final points = [
        for (var i = 0; i <= 100; i++) [i / 100, 0.0, 0.005 * math.sin(i / 10)],
      ];
      expect(simplifyPencil(points), hasLength(2));
      expect(
        () => simplifyPencil([
          [0, 0, 0],
          [1, 0, 0],
          [1, 0, 1],
        ], maxPoints: 2),
        throwsA(isA<DocumentError>()),
      );
      expect(
        () => path('line', {
          'start': [0, 0, 0],
          'end': [0, 0, 0],
        }),
        throwsA(isA<DocumentError>()),
      );
    },
  );
}
