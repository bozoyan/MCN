// 职责: 显式替换路径与运镜控制并保留选区外的关键帧和采样曲线。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/services/director/bake.dart
//   lib/shared/services/director/commands.dart
import 'package:uuid/uuid.dart';
import '../../models/director/document.dart';
import '../../models/director/properties.dart';
import '../../models/director/sampling.dart';
import 'bake.dart';

/// 重叠控制先转换为经过全帧验证的键；不缩短原预设的时间而改变其进度。
Json upsertControl(
  DirectorDocument document,
  String collection,
  Json control, {
  bool replace = false,
}) {
  final camera = collection == 'camera_moves';
  final ownerKey = camera ? 'camera_id' : 'target_id';
  final target = control[ownerKey] as String;
  final start = control['start_frame'] as int;
  final end = control['end_frame'] as int;
  if (start < 0 || start >= end || end > document.durationFrames) {
    invalid('interval', 'invalid_interval');
  }
  final channels = camera
      ? moveChannels(
          control['kind'],
          document.camera(target)!['orientation_mode'],
        )
      : {'position', if (control['orient_to_path'] == true) 'rotation'};
  final existing = camera ? document.moves : document.paths;
  final overlaps = existing
      .where(
        (s) =>
            s['id'] != control['id'] &&
            s[ownerKey] == target &&
            s['start_frame'] < end &&
            s['end_frame'] > start,
      )
      .toList();
  if (overlaps.isNotEmpty && !replace) {
    invalid(collection, 'replace_required');
  }
  var prepared = document;
  for (final overlap in overlaps) {
    prepared = DirectorDocument.fromJson(
      bakeControl(prepared, collection, overlap['id']),
    );
  }
  final next = prepared.toJson();
  final previousIndex = (next[collection] as List).indexWhere(
    (s) => s['id'] == control['id'],
  );
  (next[collection] as List).removeWhere((s) => s['id'] == control['id']);
  for (final track in (next['tracks'] as List).where(
    (t) => t['target_id'] == target && channels.contains(t['property']),
  )) {
    final keys = track['keys'] as List;
    var conflict = keys.any((k) => k['frame'] > start && k['frame'] < end);
    for (var i = 0; i + 1 < keys.length; i++) {
      conflict =
          conflict ||
          (keys[i]['frame'] < end &&
              keys[i + 1]['frame'] > start &&
              keys[i]['easing'] != 'hold');
    }
    if (!conflict) {
      continue;
    }
    if (!replace) {
      invalid('$collection.${control['id']}', 'replace_required');
    }
    final source = cloneJson(track);
    final sourceKeys = source['keys'] as List;
    final property = track['property'] as String;
    dynamic Function(int) at = (frame) => sampleTrack(source, frame);
    // Splitting a moving reference blend cannot be represented by a point
    // without freezing its outside dependency. Require explicit target keys.
    if (property == 'camera_target') {
      for (var i = 0; i + 1 < sourceKeys.length; i++) {
        final a = sourceKeys[i], b = sourceKeys[i + 1];
        if (a['easing'] != 'hold' &&
            ((a['frame'] < start && b['frame'] > start) ||
                (a['frame'] < end && b['frame'] > end)) &&
            (a['value']['type'] != 'point' || b['value']['type'] != 'point')) {
          invalid('tracks.${track['id']}', 'target_handover_keys_required');
        }
      }
      at = (int frame) {
        final exact = sourceKeys.where((k) => k['frame'] == frame).firstOrNull;
        if (exact != null) {
          return exact['value'];
        }
        final i = trackKeyAt(source, frame);
        if (i >= 0 &&
            (sourceKeys[i]['easing'] == 'hold' || i == sourceKeys.length - 1)) {
          return sourceKeys[i]['value'];
        }
        return {
          'type': 'point',
          'position': sampleTrack(
            source,
            frame,
            targetAt: (t) => (t['position'] as List)
                .map((n) => (n as num).toDouble())
                .toList(),
          ),
        };
      };
    }
    keys.removeWhere((k) => k['frame'] >= start && k['frame'] < end);
    void put(int frame, dynamic value, String easing) {
      keys.removeWhere((k) => k['frame'] == frame);
      keys.add({'frame': frame, 'value': value, 'easing': easing});
    }

    // Preserve integer samples on both sides of an interpolation split.
    for (var i = 0; i + 1 < sourceKeys.length; i++) {
      final a = sourceKeys[i], b = sourceKeys[i + 1];
      if (a['easing'] == 'hold') {
        continue;
      }
      if (a['frame'] < start && b['frame'] >= start) {
        for (var f = a['frame'] + 1; f < start; f++) {
          put(f, at(f), f == start - 1 ? 'hold' : 'linear');
        }
      }
      if (a['frame'] < end && b['frame'] > end) {
        for (var f = end; f < b['frame']; f++) {
          put(f, at(f), 'linear');
        }
      }
    }
    if (trackKeyAt(source, start) >= 0) {
      put(start, at(start), 'hold');
    }
    // An existing outgoing key belongs to the next controller and is retained.
    keys.sort((a, b) => (a['frame'] as int).compareTo(b['frame']));
  }
  (next['tracks'] as List).removeWhere((t) => (t['keys'] as List).isEmpty);
  final controls = next[collection] as List;
  controls.insert(
    previousIndex < 0
        ? controls.length
        : previousIndex.clamp(0, controls.length),
    cloneJson(control),
  );
  final result = DirectorDocument.fromJson(next);
  if (camera) {
    sampleCamera(result, target, start);
  } else {
    sampleDocument(result, start);
  }
  return result.toJson();
}

Json newMove(String cameraId, String kind, int start, int end) => {
  'id': const Uuid().v4(),
  'camera_id': cameraId,
  'kind': kind,
  'start_frame': start,
  'end_frame': end,
};
