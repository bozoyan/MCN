// 职责: 校验五类运动路径并按确定性弧长采样位置和直立朝向。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/properties.dart
//   lib/shared/models/director/sampling.dart
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;
import 'document.dart';
import 'properties.dart';

const pathKinds = ['line', 'circle', 'rectangle', 'pencil', 'pen'];
const pencilTolerance = 0.01;
const pathArcTolerance = 0.001;
const pathMinDimension = 1e-6, pathMaxDimension = 100.0;
const pathAngleLimit = 360.0;

v.Vector3 _v(List p) => v.Vector3(
  (p[0] as num).toDouble(),
  (p[1] as num).toDouble(),
  (p[2] as num).toDouble(),
);
List<double> _list(v.Vector3 p) => [p.x, p.y, p.z];

class PathSample {
  final List<double> position;
  final double yaw;
  const PathSample(this.position, this.yaw);
}

class MotionPath {
  static const requiredFields =
      'id target_id kind start_frame end_frame easing orient_to_path geometry';
  static const geometryFields = {
    'line': 'start end',
    'circle': 'center radius plane_rotation start_angle clockwise',
    'rectangle': 'center width depth plane_rotation start_corner clockwise',
    'pencil': 'points closed',
    'pen': 'nodes closed',
  };
  final Json _data;
  Json get data => cloneJson(_data);
  late final _PathGeometry _geometry = _PathGeometry(_data);
  MotionPath._(this._data);
  factory MotionPath.fromJson(dynamic value, [String path = 'motion_path']) {
    exactFields(value, path, requiredFields);
    choice(value['kind'], '$path.kind', pathKinds);
    choice(value['easing'], '$path.easing', ['linear', 'smoothstep', 'hold']);
    if (value['orient_to_path'] is! bool) {
      invalid('$path.orient_to_path', 'expected_boolean');
    }
    final g = value['geometry'];
    void point(dynamic p, String key) =>
        vector(p, '$path.geometry.$key', objectPositionLimit);
    switch (value['kind']) {
      case 'line':
        exactFields(g, '$path.geometry', geometryFields[value['kind']]!);
        point(g['start'], 'start');
        point(g['end'], 'end');
      case 'circle' || 'rectangle':
        exactFields(g, '$path.geometry', geometryFields[value['kind']]!);
        point(g['center'], 'center');
        g['plane_rotation'] = normalizeQuaternion(
          g['plane_rotation'],
          '$path.geometry.plane_rotation',
        );
        if (g['clockwise'] is! bool) {
          invalid('$path.geometry.clockwise', 'expected_boolean');
        }
        if (value['kind'] == 'circle') {
          number(
            g['radius'],
            '$path.geometry.radius',
            pathMinDimension,
            pathMaxDimension,
          );
          number(
            g['start_angle'],
            '$path.geometry.start_angle',
            -pathAngleLimit,
            pathAngleLimit,
          );
        } else {
          number(
            g['width'],
            '$path.geometry.width',
            pathMinDimension,
            pathMaxDimension,
          );
          number(
            g['depth'],
            '$path.geometry.depth',
            pathMinDimension,
            pathMaxDimension,
          );
          number(
            g['start_corner'],
            '$path.geometry.start_corner',
            0,
            3,
            integer: true,
          );
        }
      case 'pencil' || 'pen':
        final pen = value['kind'] == 'pen';
        exactFields(g, '$path.geometry', geometryFields[value['kind']]!);
        if (g['closed'] is! bool) {
          invalid('$path.geometry.closed', 'expected_boolean');
        }
        final points = g[pen ? 'nodes' : 'points'];
        if (points is! List ||
            points.length < 2 ||
            points.length > DirectorDocument.maxUnits) {
          invalid('$path.geometry', 'point_capacity');
        }
        for (final e in points.indexed) {
          if (!pen) {
            point(e.$2, 'points[${e.$1}]');
          } else {
            final n = e.$2;
            exactFields(
              n,
              '$path.geometry.nodes[${e.$1}]',
              'position smooth',
              optional: 'in_handle out_handle',
            );
            point(n['position'], 'nodes[${e.$1}].position');
            if (n['smooth'] is! bool) {
              invalid(
                '$path.geometry.nodes[${e.$1}].smooth',
                'expected_boolean',
              );
            }
            for (final handle in ['in_handle', 'out_handle']) {
              if (n.containsKey(handle)) {
                point(n[handle], 'nodes[${e.$1}].$handle');
              }
            }
            if (n['smooth'] == true &&
                n.containsKey('in_handle') &&
                n.containsKey('out_handle')) {
              final a = _v(n['in_handle']) - _v(n['position']);
              final b = _v(n['out_handle']) - _v(n['position']);
              if (a.length > 1e-9 &&
                  b.length > 1e-9 &&
                  a.normalized().dot(b.normalized()) > -0.999999) {
                invalid(
                  '$path.geometry.nodes[${e.$1}]',
                  'smooth_handles_not_collinear',
                );
              }
            }
          }
        }
    }
    final result = MotionPath._(cloneJson(value));
    result._geometry.validate(value['orient_to_path'] == true, path);
    return result;
  }
  String get id => _data['id'];
  String get targetId => _data['target_id'];
  int get start => _data['start_frame'];
  int get end => _data['end_frame'];
  bool get orient => _data['orient_to_path'];
  int get units => switch (_data['kind']) {
    'line' => 2,
    'circle' || 'rectangle' => 4,
    'pencil' => (_data['geometry']['points'] as List).length,
    _ => (_data['geometry']['nodes'] as List).fold<int>(
      0,
      (n, p) =>
          n +
          1 +
          (p.containsKey('in_handle') ? 1 : 0) +
          (p.containsKey('out_handle') ? 1 : 0),
    ),
  };
  double get length => _geometry.length;
  PathSample sample(num frame, double initialYaw) {
    var u = ((frame - start) / (end - start)).clamp(0.0, 1.0).toDouble();
    if (_data['easing'] == 'smoothstep') {
      u = u * u * (3 - 2 * u);
    } else if (_data['easing'] == 'hold' && u < 1) {
      u = 0;
    }
    return _geometry.sample(u, initialYaw);
  }
}

class _PathGeometry {
  final Json path;
  final List<v.Vector3> points = [];
  final List<double> distances = [0];
  late final bool closed;
  double length = 0;
  _PathGeometry(this.path) {
    final g = path['geometry'];
    closed =
        path['kind'] == 'circle' ||
        path['kind'] == 'rectangle' ||
        g['closed'] == true;
    switch (path['kind']) {
      case 'line':
        points.addAll([_v(g['start']), _v(g['end'])]);
      case 'circle':
        length = 2 * math.pi * (g['radius'] as num);
        return;
      case 'rectangle':
        final w = (g['width'] as num) / 2, d = (g['depth'] as num) / 2;
        final corners = [
          v.Vector3(-w, 0, -d),
          v.Vector3(w, 0, -d),
          v.Vector3(w, 0, d),
          v.Vector3(-w, 0, d),
        ];
        for (var i = 0; i <= 4; i++) {
          final index =
              ((g['start_corner'] as int) + (g['clockwise'] == true ? -i : i)) %
              4;
          points.add(_transform(corners[index]));
        }
      case 'pencil':
        for (final p in g['points']) {
          final point = _v(p);
          if (points.isEmpty || points.last.distanceTo(point) > 1e-10) {
            points.add(point);
          }
        }
        if (closed && points.first.distanceTo(points.last) > 1e-10) {
          points.add(points.first.clone());
        }
      case 'pen':
        final nodes = g['nodes'] as List;
        points.add(_v(nodes.first['position']));
        final count = closed ? nodes.length : nodes.length - 1;
        for (var i = 0; i < count; i++) {
          final a = nodes[i], b = nodes[(i + 1) % nodes.length];
          _bezier(
            _v(a['position']),
            _v(a['out_handle'] ?? a['position']),
            _v(b['in_handle'] ?? b['position']),
            _v(b['position']),
            pathArcTolerance / count,
            0,
          );
        }
    }
    for (var i = 1; i < points.length; i++) {
      length += points[i - 1].distanceTo(points[i]);
      distances.add(length);
    }
  }
  v.Vector3 _transform(v.Vector3 local) {
    final g = path['geometry'], q = g['plane_rotation'] as List;
    return v.Quaternion(
          (q[0] as num).toDouble(),
          (q[1] as num).toDouble(),
          (q[2] as num).toDouble(),
          (q[3] as num).toDouble(),
        ).asRotationMatrix().transformed(local) +
        _v(g['center']);
  }

  void _bezier(
    v.Vector3 a,
    v.Vector3 b,
    v.Vector3 c,
    v.Vector3 d,
    double tolerance,
    int depth,
  ) {
    final polygon = a.distanceTo(b) + b.distanceTo(c) + c.distanceTo(d);
    if (polygon - a.distanceTo(d) <= tolerance) {
      points.add(d);
      return;
    }
    if (depth >= 24 || points.length > 16384) {
      invalid('motion_path.geometry', 'subdivision_capacity');
    }
    final ab = (a + b) / 2, bc = (b + c) / 2, cd = (c + d) / 2;
    final abc = (ab + bc) / 2, bcd = (bc + cd) / 2, middle = (abc + bcd) / 2;
    _bezier(a, ab, abc, middle, tolerance / 2, depth + 1);
    _bezier(middle, bcd, cd, d, tolerance / 2, depth + 1);
  }

  void validate(bool orient, String at) {
    if (length < 1e-9) {
      invalid(at, 'zero_length_path');
    }
    if (path['kind'] == 'circle') {
      // Each axis extremum of a rotated circle is analytic.
      final g = path['geometry'], center = _v(g['center']);
      final x = _transform(v.Vector3(1, 0, 0)) - center;
      final z = _transform(v.Vector3(0, 0, 1)) - center;
      for (var i = 0; i < 3; i++) {
        final extent =
            (g['radius'] as num) * math.sqrt(x[i] * x[i] + z[i] * z[i]);
        if (center[i].abs() + extent > 50) {
          invalid(at, 'path_out_of_bounds');
        }
      }
    } else {
      for (final p in points) {
        vector(_list(p), at, 50);
      }
    }
    if (orient && path['kind'] == 'pencil') {
      final headings = _headings(0);
      for (var i = closed ? 0 : 1; i < headings.length; i++) {
        if (math.cos(headings[i] - headings[(i - 1) % headings.length]) <=
            -0.999999) {
          invalid(at, 'ambiguous_reverse_heading');
        }
      }
    }
  }

  List<double> _headings(double initial) {
    var yaw = initial;
    final result = <double>[];
    for (var i = 0; i < points.length - 1; i++) {
      final d = points[i + 1] - points[i];
      if (d.x * d.x + d.z * d.z > 1e-16) {
        yaw = math.atan2(d.x, d.z);
      }
      result.add(yaw);
    }
    if (closed) {
      // A closed loop has a deterministic predecessor for initial vertical segments.
      for (var i = 0; i < result.length; i++) {
        final d = points[i + 1] - points[i];
        if (d.x * d.x + d.z * d.z > 1e-16) {
          break;
        }
        result[i] = result.last;
      }
    }
    return result;
  }

  PathSample sample(double u, double initialYaw) {
    if (path['kind'] == 'circle') {
      final g = path['geometry'];
      final sign = g['clockwise'] == true ? -1.0 : 1.0;
      final a =
          (g['start_angle'] as num) * math.pi / 180 + sign * u * math.pi * 2;
      final radius = (g['radius'] as num).toDouble();
      final p = _transform(
        v.Vector3(radius * math.cos(a), 0, radius * math.sin(a)),
      );
      final tangent =
          _transform(v.Vector3(-math.sin(a) * sign, 0, math.cos(a) * sign)) -
          _v(g['center']);
      var yaw = initialYaw;
      if (tangent.x * tangent.x + tangent.z * tangent.z > 1e-16) {
        yaw = math.atan2(tangent.x, tangent.z);
      } else {
        final prior = a - sign * 1e-7;
        final t =
            _transform(
              v.Vector3(-math.sin(prior) * sign, 0, math.cos(prior) * sign),
            ) -
            _v(g['center']);
        yaw = math.atan2(t.x, t.z);
      }
      return PathSample(_list(p), yaw);
    }
    final distance = u * length;
    var index = distances.length - 2;
    for (var i = 0; i < distances.length - 1; i++) {
      if (distance < distances[i + 1]) {
        index = i;
        break;
      }
    }
    final segment = distances[index + 1] - distances[index];
    final t = segment == 0 ? 0.0 : (distance - distances[index]) / segment;
    final p = points[index] + (points[index + 1] - points[index]) * t;
    final headings = _headings(initialYaw);
    var yaw = headings[index];
    if (path['kind'] == 'pencil') {
      for (var corner = closed ? 0 : 1; corner < headings.length; corner++) {
        final incoming = (corner - 1) % headings.length;
        final half = math.min(
          0.1,
          math.min(
                distances[incoming + 1] - distances[incoming],
                distances[corner + 1] - distances[corner],
              ) /
              2,
        );
        var offset = distance - distances[corner];
        if (closed && corner == 0 && distance > length / 2) {
          offset -= length;
        }
        if (half > 0 && offset.abs() <= half) {
          final progress = (offset + half) / (2 * half);
          final eased = progress * progress * (3 - 2 * progress);
          final delta = math.atan2(
            math.sin(headings[corner] - headings[incoming]),
            math.cos(headings[corner] - headings[incoming]),
          );
          yaw = headings[incoming] + delta * eased;
          break;
        }
      }
    }
    return PathSample(_list(p), yaw);
  }
}

/// Ramer–Douglas–Peucker 保留端点；结果超过预算时拒绝而非截断。
List<List<double>> simplifyPencil(
  List<List<double>> input, {
  int maxPoints = 2048,
}) {
  if (input.length < 2) {
    invalid('pencil', 'points_required');
  }
  final points = input.map(_v).toList();
  final keep = <int>{0, points.length - 1};
  void reduce(int a, int b) {
    if (b <= a + 1) {
      return;
    }
    final line = points[b] - points[a];
    var farthest = -1, distance = pencilTolerance;
    for (var i = a + 1; i < b; i++) {
      final u = line.length2 == 0
          ? 0.0
          : ((points[i] - points[a]).dot(line) / line.length2).clamp(0.0, 1.0);
      final d = points[i].distanceTo(points[a] + line * u);
      if (d > distance) {
        distance = d;
        farthest = i;
      }
    }
    if (farthest >= 0) {
      keep.add(farthest);
      if (keep.length > maxPoints) {
        invalid('pencil', 'point_capacity');
      }
      reduce(a, farthest);
      reduce(farthest, b);
    }
  }

  reduce(0, points.length - 1);
  return [for (final i in keep.toList()..sort()) _list(points[i])];
}
