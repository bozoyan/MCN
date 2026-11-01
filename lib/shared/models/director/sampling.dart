// 职责: 按文档快照确定性求值稀疏属性、姿态、路径、运镜与切镜。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/pose.dart
//   lib/shared/models/director/rig.dart
//   lib/shared/models/director/animation_math.dart
//   lib/shared/services/director/scene_builder.dart
import 'dart:math' as math;
import 'document.dart';
import 'pose.dart';
import 'entities.dart';
import 'rig.dart';
import 'properties.dart';
import 'animation_math.dart';
export 'animation_math.dart';
export 'pose.dart' show humanoidBones;

class FrameSample {
  final List<Json> objects;
  final Map<String, Json> cameras;
  final Map<String, Map<String, List<double>>> joints;
  final Json lighting;
  final String cameraId;
  FrameSample(
    this.objects,
    this.cameras,
    this.joints,
    this.lighting,
    this.cameraId,
  );
}

/// 使用二分查找；首键前由调用方保留基础值，单键不补零帧。
int trackKeyAt(Json track, num frame) {
  final keys = track['keys'] as List;
  var low = 0, high = keys.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (keys[middle]['frame'] <= frame) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low - 1;
}

String _color(String a, String b, double u) {
  double linear(int value) {
    final c = value / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  int srgb(double value) =>
      ((value <= 0.0031308
                  ? 12.92 * value
                  : 1.055 * math.pow(value, 1 / 2.4) - 0.055) *
              255)
          .round()
          .clamp(0, 255);
  final x = int.parse(a.substring(1), radix: 16),
      y = int.parse(b.substring(1), radix: 16);
  return '#${[16, 8, 0].map((shift) {
    final first = linear((x >> shift) & 255), second = linear((y >> shift) & 255);
    return srgb(first + (second - first) * u).toRadixString(16).padLeft(2, '0');
  }).join().toUpperCase()}';
}

dynamic sampleTrack(
  Json track,
  num frame, {
  dynamic base,
  List<double> Function(Json)? targetAt,
}) {
  final keys = track['keys'] as List;
  final index = trackKeyAt(track, frame);
  if (index < 0) {
    return base;
  }
  return _sampleSegment(
    track['property'],
    keys[index],
    index + 1 < keys.length ? keys[index + 1] : null,
    frame,
    targetAt: targetAt,
  );
}

dynamic _sampleSegment(
  String property,
  Json a,
  Json? b,
  num frame, {
  List<double> Function(Json)? targetAt,
}) {
  dynamic resolved(dynamic value) =>
      property == 'camera_target' && targetAt != null ? targetAt(value) : value;
  if (b == null || frame == a['frame'] || a['easing'] == 'hold') {
    return resolved(a['value']);
  }
  var u = ((frame - a['frame']) / (b['frame'] - a['frame'])).toDouble();
  if (a['easing'] == 'smoothstep') {
    u = smooth(u);
  }
  final x = resolved(a['value']), y = resolved(b['value']);
  switch (property) {
    case 'rotation':
      return slerp(x, y, u);
    case 'lighting.key_direction':
      return directionSlerp(x, y, u);
    case 'pose':
      return {
        for (final p in poseParameters) p.id: x[p.id] + (y[p.id] - x[p.id]) * u,
      };
    case 'color':
      return _color(x, y, u);
    case 'visible':
      return x;
    case 'camera_target':
      if (targetAt == null) {
        invalid('camera_target', 'world_resolver_required');
      }
  }
  if (x is num) {
    return x + (y - x) * u;
  }
  return [
    for (var i = 0; i < (x as List).length; i++) x[i] + (y[i] - x[i]) * u,
  ];
}

dynamic samplePropertyTrack(
  PropertyTrack track,
  num frame, {
  dynamic base,
  List<double> Function(Json)? targetAt,
}) {
  final index = track.keyAt(frame);
  if (index < 0) {
    return base;
  }
  return _sampleSegment(
    track.property,
    track.keys[index].toJson(),
    index + 1 < track.keys.length ? track.keys[index + 1].toJson() : null,
    frame,
    targetAt: targetAt,
  );
}

List<double> objectWorldPoint(Json object, List<double> local) {
  final rotated = rotateVector(object['rotation'], [
    for (var i = 0; i < 3; i++) local[i] * object['scale'][i],
  ]);
  return [for (var i = 0; i < 3; i++) object['position'][i] + rotated[i]];
}

final _plans = Expando<AnimationPlan>();
AnimationPlan animationPlan(DirectorDocument document) =>
    _plans[document.animationIdentity] ??= AnimationPlan(document);
FrameSample sampleDocument(DirectorDocument document, num frame) =>
    animationPlan(document).sample(frame);
Json sampleCamera(DirectorDocument document, String cameraId, num frame) =>
    animationPlan(document).camera(cameraId, frame);

class AnimationPlan {
  final DirectorDocument document;
  late final Map<String, Json> _baseObjects = {
    for (final object in document.objects) object['id']: object,
  };
  late final Map<String, Json> _baseCameras = {
    for (final camera in document.cameras) camera['id']: camera,
  };
  late final Map<String, List<PropertyTrack>> tracks = {
    for (final id in [document.id, ..._baseObjects.keys, ..._baseCameras.keys])
      id: document.propertyTracks.where((t) => t.targetId == id).toList(),
  };
  final Map<(String, num), Json> _objects = {};
  final Map<String, _CameraPlan> _cameras = {};
  AnimationPlan(this.document);
  List<Json> objects(num frame) => [
    for (final id in _baseObjects.keys) object(id, frame),
  ];

  /// 求值单个对象；相机只依赖实际引用的对象，不受无关对象错误阻塞。
  Json object(String id, num frame) => _objects.putIfAbsent((id, frame), () {
    final object = cloneJson(_baseObjects[id]!);
    for (final track in tracks[object['id']]!) {
      final property = track.property;
      object[property] = samplePropertyTrack(
        track,
        frame,
        base: object[property],
      );
    }
    final paths =
        document.samplingPaths
            .where((p) => p.targetId == object['id'] && p.start <= frame)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    for (final path in paths) {
      final initial = objectsBeforePath(object['id'], path.start, path.id);
      final sampled = path.sample(frame, quaternionYaw(initial['rotation']));
      bool manualAfter(String property) => tracks[object['id']]!.any(
        (t) =>
            t.property == property &&
            t.keys.any((k) => k.frame >= path.end && k.frame <= frame),
      );
      if (!manualAfter('position')) {
        object['position'] = sampled.position;
      }
      if (path.orient && !manualAfter('rotation')) {
        object['rotation'] = yawQuaternion(sampled.yaw);
      }
    }
    vector(object['position'], 'frame[$frame].${object['id']}.position', 50);
    if (object['kind'] == 'actor') {
      final rig = sampleRig(
        object['geometry_key'],
        ActorPose.fromJson(object['pose']),
      );
      for (final bone in humanoidBones) {
        final local = rig.localPoint(bone, [0, 0, 0]);
        vector(
          objectWorldPoint(object, [local.x, local.y, local.z]),
          'frame[$frame].${object['id']}.pose.$bone.world_position',
          50,
        );
      }
    }
    return object;
  });
  Json objectsBeforePath(String id, num frame, String excluded) {
    final object = cloneJson(_baseObjects[id]!);
    for (final track in tracks[id]!) {
      object[track.property] = samplePropertyTrack(
        track,
        frame,
        base: object[track.property],
      );
    }
    for (final path
        in document.samplingPaths
            .where(
              (p) => p.targetId == id && p.id != excluded && p.end <= frame,
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start))) {
      final manualRotation = tracks[id]!.any(
        (t) =>
            t.property == 'rotation' &&
            t.keys.any((k) => k.frame >= path.end && k.frame <= frame),
      );
      if (path.orient && !manualRotation) {
        object['rotation'] = yawQuaternion(
          path.sample(path.end, quaternionYaw(object['rotation'])).yaw,
        );
      }
    }
    return object;
  }

  List<double> target(Json descriptor, num frame) {
    switch (descriptor['type']) {
      case 'point':
        return _list(descriptor['position']);
      case 'object':
        return objectWorldPoint(
          object(descriptor['object_id'], frame),
          _list(descriptor['offset']),
        );
      case 'bone':
        return boneWorldPoint(
          object(descriptor['actor_id'], frame),
          descriptor['bone'],
          descriptor['offset'],
        );
      default:
        invalid('camera_target.type', 'unknown_value');
    }
  }

  Json camera(String id, num frame) {
    number(frame, 'frame', 0, document.durationFrames);
    try {
      return cloneJson(
        _cameras
            .putIfAbsent(id, () => _CameraPlan(this, _baseCameras[id]!))
            .sample(frame),
      );
    } on DocumentError catch (error) {
      invalid('frame[$frame].cameras.$id.${error.path}', error.reason);
    }
  }

  FrameSample sample(num frame) {
    number(frame, 'frame', 0, document.durationFrames);
    final os = objects(frame);
    final light = lighting(frame);
    return FrameSample(
      os.map(cloneJson).toList(),
      {for (final id in _baseCameras.keys) id: camera(id, frame)},
      {
        for (final o in os.where((o) => o['kind'] == 'actor'))
          o['id']: poseBones(ActorPose.fromJson(o['pose'])),
      },
      light,
      document.cameraAt(frame),
    );
  }

  Json lighting(num frame) {
    final lighting = document.lighting;
    for (final t in tracks[document.id]!) {
      final key = t.property.substring('lighting.'.length);
      lighting[key] = samplePropertyTrack(t, frame, base: lighting[key]);
    }
    return lighting;
  }

  void audit() {
    for (var frame = 0; frame <= document.durationFrames; frame++) {
      sample(frame);
    }
  }
}

List<double> _list(List value) => [
  for (final n in value) (n as num).toDouble(),
];
List<double> _add(List a, List b) => [
  for (var i = 0; i < 3; i++) (a[i] as num).toDouble() + b[i],
];
List<double> _sub(List a, List b) => [
  for (var i = 0; i < 3; i++) (a[i] as num).toDouble() - b[i],
];
List<double> _scale(List a, double scale) => [
  for (final n in a) (n as num) * scale,
];

class _CameraPlan {
  final AnimationPlan plan;
  final Json base;
  late final List<CameraMove> moves =
      plan.document.cameraMoves.where((m) => m.cameraId == base['id']).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final List<Json> _anchors = [];
  final Map<int, Json> _frames = {};
  final Map<String, Json> _focusEnds = {};
  _CameraPlan(this.plan, this.base);
  List<PropertyTrack> get tracks => plan.tracks[base['id']]!;
  Json _manual(num frame) {
    final result = cloneJson(base);
    for (final t in tracks) {
      final property = t.property;
      if (property == 'camera_target') {
        result['target'] = samplePropertyTrack(
          t,
          frame,
          base: plan.target(base['camera_target'], frame),
          targetAt: (v) => plan.target(v, frame),
        );
      } else {
        result[property] = samplePropertyTrack(
          t,
          frame,
          base: result[property],
        );
      }
    }
    if (base['orientation_mode'] == 'look_at') {
      result['target'] ??= plan.target(base['camera_target'], frame);
    } else {
      result['target'] = _add(
        result['position'],
        rotateVector(result['rotation'], [0, 0, -1]),
      );
    }
    return result;
  }

  Json _raw(num frame, int count) {
    final result = _manual(frame);
    for (var i = 0; i < count; i++) {
      final move = moves[i];
      if (move.start > frame) {
        break;
      }
      final value = move.kind == 'rack_focus' && frame >= move.end
          ? _focusEnds.putIfAbsent(
              move.id,
              () => _apply(move, _anchors[i], move.end, _raw(move.end, i)),
            )
          : _apply(move, _anchors[i], math.min(frame, move.end), result);
      for (final channel in moveChannels(move.kind, base['orientation_mode'])) {
        final overridden = tracks.any(
          (t) =>
              t.property == channel &&
              t.keys.any((k) => k.frame >= move.end && k.frame <= frame),
        );
        if (!overridden) {
          result[channel == 'camera_target' ? 'target' : channel] =
              value[channel == 'camera_target' ? 'target' : channel];
        }
      }
    }
    if (base['orientation_mode'] == 'free') {
      result['target'] = _add(
        result['position'],
        rotateVector(result['rotation'], [0, 0, -1]),
      );
    }
    return result;
  }

  void _compile() {
    while (_anchors.length < moves.length) {
      final index = _anchors.length, move = moves[index];
      Json? anchor;
      for (var frame = 0; frame <= move.start; frame++) {
        final current = _raw(frame, index);
        _orient(current, anchor);
        anchor = current;
      }
      _anchors.add(anchor!);
    }
  }

  Json sample(num frame) {
    _compile();
    final integer = frame.floor();
    for (var f = _frames.length; f <= integer; f++) {
      final raw = _raw(f, moves.length);
      _orient(raw, _frames[f - 1]);
      validateCamera(raw, 'frame[$f].cameras.${base['id']}');
      _frames[f] = raw;
    }
    if (frame == integer) {
      return _frames[integer]!;
    }
    final raw = _raw(frame, moves.length);
    _orient(raw, _frames[integer]);
    validateCamera(raw, 'frame[$frame].cameras.${base['id']}');
    return raw;
  }

  void _orient(Json camera, Json? previous) {
    if (base['orientation_mode'] == 'free') {
      camera['up'] = rotateVector(camera['rotation'], [0, 1, 0]);
      return;
    }
    final forward = unitDirection(
      _sub(camera['target'], camera['position']),
      'camera.forward',
    );
    List<double> up;
    if (previous == null) {
      up = _list(base['reference_up']);
    } else {
      // Transport the unrolled frame along the shortest forward-vector arc.
      final prior = _list(previous['_forward']);
      final cross = [
        prior[1] * forward[2] - prior[2] * forward[1],
        prior[2] * forward[0] - prior[0] * forward[2],
        prior[0] * forward[1] - prior[1] * forward[0],
      ];
      final dot = List.generate(
        3,
        (i) => prior[i] * forward[i],
      ).reduce((a, b) => a + b).clamp(-1.0, 1.0);
      up = _list(previous['_reference_up']);
      if (dot > -0.999999 && cross.any((v) => v.abs() > 1e-12)) {
        up = rotateVector(
          normalizeQuaternion([...cross, 1 + dot], 'camera.transport'),
          up,
        );
      }
    }
    final unrolled = lookQuaternion(forward, up);
    camera['_forward'] = forward;
    camera['_reference_up'] = rotateVector(unrolled, [0, 1, 0]);
    final roll = (camera['roll'] as num) * math.pi / 180;
    camera['rotation'] = multiplyQuaternion(unrolled, [
      0,
      0,
      -math.sin(roll / 2),
      math.cos(roll / 2),
    ]);
    camera['up'] = rotateVector(camera['rotation'], [0, 1, 0]);
    vector(camera['target'], 'camera.target', 100);
  }

  Json _apply(CameraMove move, Json anchor, num frame, Json current) {
    final result = cloneJson(anchor);
    final start = move.start;
    final t = ((frame - start) / (move.end - start)).clamp(0, 1).toDouble();
    final u = smooth(t);
    var p = _list(anchor['position']), target = _list(anchor['target']);
    final forward = rotateVector(anchor['rotation'], [0, 0, -1]);
    final up = rotateVector(anchor['rotation'], [0, 1, 0]);
    final right = rotateVector(anchor['rotation'], [1, 0, 0]);
    void turn(List<double> axis, double angle) {
      final q = [..._scale(axis, math.sin(angle / 2)), math.cos(angle / 2)];
      target = _add(p, rotateVector(q, _sub(target, p)));
      result['rotation'] = multiplyQuaternion(q, anchor['rotation']);
    }

    Json subjectDescriptor() {
      final targetTrack = tracks
          .where((t) => t.property == 'camera_target')
          .firstOrNull;
      final index = targetTrack == null ? -1 : targetTrack.keyAt(frame);
      return index < 0 ? base['camera_target'] : targetTrack!.keys[index].value;
    }

    List<double> subject(num f) {
      final descriptor = subjectDescriptor();
      if (descriptor['type'] == 'point') {
        invalid('camera_moves.${move.id}', 'subject_target_required');
      }
      return _list(_manual(f)['target']);
    }

    switch (move.kind) {
      case 'static':
        break;
      case 'pan_l' || 'pan_r':
        turn(up, (move.kind == 'pan_l' ? 1 : -1) * u * math.pi / 6);
      case 'tilt_u' || 'tilt_d':
        turn(right, (move.kind == 'tilt_u' ? 1 : -1) * u * math.pi / 12);
      case 'dolly_in' || 'dolly_out':
        final step = _scale(
          forward,
          (move.kind == 'dolly_in' ? 1.5 : -1.5) * u,
        );
        p = _add(p, step);
        target = _add(target, step);
      case 'truck_l' || 'truck_r' || 'slide_reveal':
        final step = _scale(right, (move.kind == 'truck_l' ? -1.5 : 1.5) * u);
        p = _add(p, step);
        target = _add(target, step);
      case 'foreground_pass':
        p = _add(p, _scale(right, 1.5 * u));
        target = subject(frame);
      case 'fly_through':
        final step = _scale(forward, 5 * t * t);
        p = _add(p, step);
        target = _add(target, step);
      case 'whip_pan':
        turn(up, -smooth((t / 0.35).clamp(0, 1)) * math.pi / 2);
      case 'handheld':
        // Analytic noise keeps seeks reproducible and settles at both boundaries.
        final envelope = math.pow(math.sin(math.pi * t), 2).toDouble();
        final seconds = (frame - start) / plan.document.fps;
        final sway = envelope * math.sin(seconds * 7.3);
        final bob = envelope * math.sin(seconds * 11.7);
        final step = _add(_scale(right, 0.025 * sway), _scale(up, 0.018 * bob));
        p = _add(p, step);
        target = _add(target, step);
        final q = multiplyQuaternion(
          [..._scale(up, math.sin(0.008 * sway)), math.cos(0.008 * sway)],
          [..._scale(right, math.sin(0.006 * bob)), math.cos(0.006 * bob)],
        );
        target = _add(p, rotateVector(q, _sub(target, p)));
        result['rotation'] = multiplyQuaternion(q, anchor['rotation']);
      case 'zoom_in':
        result['focal_length_mm'] = math.min(
          120,
          (anchor['focal_length_mm'] as num) * (1 + u),
        );
      case 'zoom_out':
        result['focal_length_mm'] = math.max(
          18,
          (anchor['focal_length_mm'] as num) / (1 + u),
        );
      case 'crash_zoom':
        result['focal_length_mm'] = math.min(
          120,
          (anchor['focal_length_mm'] as num) *
              (1 + 2 * smooth((t / 0.35).clamp(0, 1))),
        );
      case 'follow_pan':
        target = subject(frame);
      case 'rack_focus':
        final offset = _sub(subject(frame), current['position']);
        final focusForward = unitDirection(
          _sub(current['target'], current['position']),
          'camera.focus',
        );
        final depth = List.generate(
          3,
          (i) => offset[i] * focusForward[i],
        ).reduce((a, b) => a + b).clamp(0.2, 200.0);
        final initial = anchor['focus_distance_m'] as num;
        result['focus_distance_m'] = initial + (depth - initial) * u;
        final aperture = anchor['aperture_fstop'] as num;
        result['aperture_fstop'] = aperture > 0 ? aperture : 2.8;
      case 'follow':
        p = _add(p, _sub(subject(frame), subject(start)));
        target = subject(frame);
      case 'lead':
        final descriptor = subjectDescriptor();
        final id = descriptor['object_id'] ?? descriptor['actor_id'];
        final actor = plan.object(id, frame);
        final initial = plan.object(id, start);
        final deltaYaw =
            quaternionYaw(actor['rotation']) -
            quaternionYaw(initial['rotation']);
        p = _add(
          subject(frame),
          rotateVector(yawQuaternion(deltaYaw), _sub(p, subject(start))),
        );
        target = subject(frame);
      case 'side_follow':
        final descriptor = subjectDescriptor();
        final id = descriptor['object_id'] ?? descriptor['actor_id'];
        final initial = plan.object(id, start);
        final actor = plan.object(id, frame);
        final offset = _sub(p, subject(start));
        final radius = math.sqrt(offset[0] * offset[0] + offset[2] * offset[2]);
        final initialLocal = rotateVector(
          yawQuaternion(-quaternionYaw(initial['rotation'])),
          offset,
        );
        // Enter the side position continuously instead of snapping at the cut.
        final initialAngle = math.atan2(initialLocal[0], initialLocal[2]);
        final delta = math.atan2(
          math.sin(math.pi / 2 - initialAngle),
          math.cos(math.pi / 2 - initialAngle),
        );
        final angle = initialAngle + delta * u;
        final distance = radius + (math.max(0.5, radius) - radius) * u;
        final local = [
          math.sin(angle) * distance,
          initialLocal[1],
          math.cos(angle) * distance,
        ];
        p = _add(
          subject(frame),
          rotateVector(yawQuaternion(quaternionYaw(actor['rotation'])), local),
        );
        target = subject(frame);
      case 'orbit' || 'orbit_half' || 'orbit_full':
        final angle = switch (move.kind) {
          'orbit_half' => math.pi,
          'orbit_full' => 2 * math.pi,
          _ => math.pi / 2,
        };
        p = _add(
          subject(frame),
          rotateVector(yawQuaternion(u * angle), _sub(p, subject(start))),
        );
        target = subject(frame);
      case 'crane_up' || 'crane_down':
        final lift = _scale(up, (move.kind == 'crane_up' ? 1.2 : -1.2) * u);
        p = _add(p, lift);
        target = _add(target, lift);
      case 'rise_out':
        p = _add(_add(p, _scale(forward, -2 * u)), _scale(up, 1.5 * u));
      case 'spiral_up' || 'spiral_down':
        final center = target;
        p = _add(
          center,
          rotateVector(yawQuaternion(u * math.pi), _sub(p, center)),
        );
        p = _add(p, [0, (move.kind == 'spiral_up' ? 1.5 : -1.5) * u, 0]);
        result['rotation'] = lookQuaternion(_sub(target, p), up);
      case 'aerial':
        final horizontal = [forward[0], 0.0, forward[2]];
        final length = math.sqrt(
          horizontal[0] * horizontal[0] + horizontal[2] * horizontal[2],
        );
        // At a vertical view, camera-up defines the screen-forward flight axis.
        final direction = length > 1e-6
            ? _scale(horizontal, 1 / length)
            : unitDirection([up[0], 0, up[2]], 'camera.aerial');
        final step = _scale(direction, 4 * u);
        p = _add(p, step);
        target = _add(target, step);
      case 'dive' || 'fpv':
        final center = subject(frame);
        final offset = _sub(p, subject(start));
        p = _add(center, _scale(offset, 1 - 0.65 * u));
        if (move.kind == 'fpv') {
          final wave = math.sin(2 * math.pi * t) * math.sin(math.pi * t);
          p = _add(p, _add(_scale(right, 0.6 * wave), _scale(up, 0.3 * wave)));
        }
        target = center;
    }
    result['position'] = p;
    result['target'] = target;
    return result;
  }
}
