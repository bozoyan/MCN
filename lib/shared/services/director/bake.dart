// 职责: 将路径或运镜转换为误差受控的稀疏属性键，并验证全时间轴输出。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/models/director/properties.dart
//   lib/shared/services/director/commands.dart
import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../../models/director/document.dart';
import '../../models/director/sampling.dart';
import '../../models/director/properties.dart';

const bakePositionTolerance = 0.001;
const bakeFocalTolerance = 0.01;
const bakeAngleTolerance = 0.01;

double _distance(List a, List b) => math.sqrt(
  List.generate(
    a.length,
    (i) => math.pow(a[i] - b[i], 2),
  ).reduce((a, b) => a + b),
);
double bakeError(String property, dynamic a, dynamic b) => switch (property) {
  'rotation' => quaternionAngle(a, b) / bakeAngleTolerance,
  'focal_length_mm' => ((a as num) - (b as num)).abs() / bakeFocalTolerance,
  'focus_distance_m' => ((a as num) - (b as num)).abs() / bakePositionTolerance,
  'aperture_fstop' => ((a as num) - (b as num)).abs() / 0.01,
  'roll' => ((a as num) - (b as num)).abs() / bakeAngleTolerance,
  'camera_target' =>
    _distance(a['position'], b['position']) / bakePositionTolerance,
  _ => _distance(a, b) / bakePositionTolerance,
};

Json bakeControl(DirectorDocument document, String collection, String id) =>
    _bakeControl(document, collection, id, dense: false);

Json _bakeControl(
  DirectorDocument document,
  String collection,
  String id, {
  required bool dense,
}) {
  if (!['motion_paths', 'camera_moves'].contains(collection)) {
    invalid('collection', 'invalid');
  }
  final segments = collection == 'motion_paths'
      ? document.paths
      : document.moves;
  final segment = segments.where((s) => s['id'] == id).firstOrNull;
  if (segment == null) {
    invalid('id', 'not_found');
  }
  final camera = collection == 'camera_moves';
  final targetId = segment[camera ? 'camera_id' : 'target_id'] as String;
  final mode = camera
      ? document.camera(targetId)!['orientation_mode'] as String
      : '';
  final channels = camera
      ? moveChannels(segment['kind'], mode)
      : {'position', if (segment['orient_to_path'] == true) 'rotation'};
  // Rotation depends on target/up history; retaining roll explicitly also preserves its winding.
  if (camera && mode == 'look_at' && channels.contains('camera_target')) {
    channels.add('roll');
  }
  final start = segment['start_frame'] as int,
      end = segment['end_frame'] as int;
  final samples = [
    for (var frame = 0; frame <= document.durationFrames; frame++)
      sampleDocument(document, frame),
  ];
  Json owner(FrameSample sample) => camera
      ? sample.cameras[targetId]!
      : sample.objects.firstWhere((o) => o['id'] == targetId);
  dynamic value(int frame, String property) {
    final state = owner(samples[frame]);
    return property == 'camera_target'
        ? {'type': 'point', 'position': state['target']}
        : state[property];
  }

  final next = document.toJson();
  (next[collection] as List).removeWhere((s) => s['id'] == id);
  for (final property in channels) {
    if (property == 'roll' &&
        camera &&
        !moveChannels(segment['kind'], mode).contains('roll') &&
        document.tracks.any(
          (t) => t['target_id'] == targetId && t['property'] == 'roll',
        )) {
      // Independent authored roll already has its own keys and winding.
      continue;
    }
    final values = [for (var f = start; f <= end; f++) value(f, property)];
    final keep = <int>{0, values.length - 1};
    void simplify(int a, int b) {
      if (b <= a + 1) {
        return;
      }
      var worst = 1.0, index = -1;
      final track = {
        'property': property,
        'keys': [
          {'frame': a, 'value': values[a], 'easing': 'linear'},
          {'frame': b, 'value': values[b], 'easing': 'linear'},
        ],
      };
      for (var f = a + 1; f < b; f++) {
        final interpolated = property == 'camera_target'
            ? {
                'type': 'point',
                'position': sampleTrack(
                  track,
                  f,
                  targetAt: (target) => (target['position'] as List)
                      .cast<num>()
                      .map((n) => n.toDouble())
                      .toList(),
                ),
              }
            : sampleTrack(track, f);
        final error = bakeError(property, values[f], interpolated);
        if (error > worst) {
          worst = error;
          index = f;
        }
      }
      if (index >= 0) {
        keep.add(index);
        simplify(a, index);
        simplify(index, b);
      }
    }

    if (dense) {
      keep.addAll(List.generate(values.length, (i) => i));
    } else {
      simplify(0, values.length - 1);
    }
    final tracks = next['tracks'] as List;
    var track = tracks
        .where((t) => t['target_id'] == targetId && t['property'] == property)
        .firstOrNull;
    if (track == null) {
      track = {
        'id': const Uuid().v4(),
        'target_id': targetId,
        'property': property,
        'keys': <Json>[],
      };
      tracks.add(track);
    }
    final keys = track['keys'] as List;
    final original = cloneJson(track);
    final originalKeys = original['keys'] as List;
    final outgoing = originalKeys.where((k) => k['frame'] == end).firstOrNull;
    // The incoming interpolation may end at the control start with a value
    // different from the controller's first value. Preserve all output frames.
    final incoming = originalKeys.where((k) => k['frame'] < start).lastOrNull;
    if (incoming != null && incoming['easing'] != 'hold') {
      final i = originalKeys.indexOf(incoming);
      if (i + 1 < originalKeys.length &&
          originalKeys[i + 1]['frame'] == start) {
        for (var f = (incoming['frame'] as int) + 1; f < start; f++) {
          keys.removeWhere((k) => k['frame'] == f);
          keys.add({
            'frame': f,
            'value': value(f, property),
            'easing': 'linear',
          });
        }
      }
    }
    keys.removeWhere((k) => k['frame'] >= start && k['frame'] <= end);
    for (final index in keep.toList()..sort()) {
      keys.add({
        'frame': start + index,
        'value': values[index],
        'easing': index == values.length - 1 ? 'hold' : 'linear',
      });
    }
    if (outgoing != null) {
      keys.removeWhere((k) => k['frame'] == end);
      keys.add(outgoing);
      // Keep the final baked sample independent of the outgoing reference/key.
      keys.removeWhere((k) => k['frame'] == end - 1);
      keys.add({
        'frame': end - 1,
        'value': value(end - 1, property),
        'easing': 'hold',
      });
    }
    keys.sort((a, b) => (a['frame'] as int).compareTo(b['frame']));
  }
  final baked = DirectorDocument.fromJson(next);
  for (var frame = 0; frame <= document.durationFrames; frame++) {
    final before = owner(samples[frame]),
        after = owner(sampleDocument(baked, frame));
    for (final property in channels) {
      final a = property == 'camera_target'
          ? {'position': before['target']}
          : before[property];
      final b = property == 'camera_target'
          ? {'position': after['target']}
          : after[property];
      if (bakeError(property, a, b) > 1 + 1e-8) {
        if (!dense) {
          return _bakeControl(document, collection, id, dense: true);
        }
        invalid('bake.frame[$frame].$targetId.$property', 'error_tolerance');
      }
    }
    if (camera &&
        quaternionAngle(before['rotation'], after['rotation']) >
            bakeAngleTolerance + 1e-8) {
      if (!dense) {
        return _bakeControl(document, collection, id, dense: true);
      }
      invalid('bake.frame[$frame].$targetId.rotation', 'error_tolerance');
    }
    // A path can drive another camera's object/bone target. Its final view must
    // meet the same angular tolerance as a directly baked camera.
    if (!camera) {
      final afterFrame = sampleDocument(baked, frame);
      for (final cameraId in samples[frame].cameras.keys) {
        final oldCamera = samples[frame].cameras[cameraId]!,
            newCamera = afterFrame.cameras[cameraId]!;
        for (final property in [
          'position',
          'rotation',
          'focal_length_mm',
          'focus_distance_m',
          'aperture_fstop',
          if (oldCamera['orientation_mode'] == 'look_at') ...[
            'camera_target',
            'roll',
          ],
        ]) {
          final a = property == 'camera_target'
              ? {'position': oldCamera['target']}
              : oldCamera[property];
          final b = property == 'camera_target'
              ? {'position': newCamera['target']}
              : newCamera[property];
          if (bakeError(property, a, b) > 1 + 1e-8) {
            if (!dense) {
              return _bakeControl(document, collection, id, dense: true);
            }
            invalid(
              'bake.frame[$frame].$cameraId.$property',
              'error_tolerance',
            );
          }
        }
      }
    }
  }
  return baked.toJson();
}
