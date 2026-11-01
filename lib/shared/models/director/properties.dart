// 职责: 集中定义导演属性的目标、数值边界、插值和控制通道。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/pose.dart
//   lib/shared/models/director/sampling.dart
import 'dart:math' as math;

import 'document.dart';
import 'pose.dart';
import 'entities.dart';

const objectPositionLimit = 50.0;
const cameraPositionLimit = 100.0;
const cameraOpticsRanges = <String, (double, double)>{
  'sensor_height_mm': (1, 100),
  'near': (.001, 10),
  'far': (.01, 10000),
};

enum PropertyKind {
  vector,
  rotation,
  scale,
  color,
  visible,
  pose,
  target,
  scalar,
  direction,
}

class DirectorProperty {
  final String id;
  final PropertyKind kind;
  final double? min, max;
  const DirectorProperty(this.id, this.kind, [this.min, this.max]);
}

const directorProperties = {
  'position': DirectorProperty(
    'position',
    PropertyKind.vector,
    -objectPositionLimit,
    objectPositionLimit,
  ),
  'rotation': DirectorProperty('rotation', PropertyKind.rotation),
  'scale': DirectorProperty('scale', PropertyKind.scale, 0.1, 10),
  'color': DirectorProperty('color', PropertyKind.color),
  'visible': DirectorProperty('visible', PropertyKind.visible),
  'pose': DirectorProperty('pose', PropertyKind.pose),
  'camera_target': DirectorProperty('camera_target', PropertyKind.target),
  'focal_length_mm': DirectorProperty(
    'focal_length_mm',
    PropertyKind.scalar,
    18,
    120,
  ),
  'focus_distance_m': DirectorProperty(
    'focus_distance_m',
    PropertyKind.scalar,
    0.2,
    200,
  ),
  'aperture_fstop': DirectorProperty(
    'aperture_fstop',
    PropertyKind.scalar,
    0,
    32,
  ),
  'roll': DirectorProperty(
    'roll',
    PropertyKind.scalar,
    -double.maxFinite,
    double.maxFinite,
  ),
  'lighting.ambient_intensity': DirectorProperty(
    'lighting.ambient_intensity',
    PropertyKind.scalar,
    0,
    4,
  ),
  'lighting.key_intensity': DirectorProperty(
    'lighting.key_intensity',
    PropertyKind.scalar,
    0,
    4,
  ),
  'lighting.key_direction': DirectorProperty(
    'lighting.key_direction',
    PropertyKind.direction,
  ),
};

List<String> propertiesFor({
  Json? object,
  Json? camera,
  bool lighting = false,
}) {
  if (lighting) {
    return directorProperties.keys
        .where((k) => k.startsWith('lighting.'))
        .toList();
  }
  if (camera != null) {
    return [
      'position',
      'focal_length_mm',
      'focus_distance_m',
      'aperture_fstop',
      if (camera['orientation_mode'] == 'free')
        'rotation'
      else ...[
        'camera_target',
        'roll',
      ],
    ];
  }
  return [
    'position',
    'rotation',
    'scale',
    'color',
    'visible',
    if (object?['kind'] == 'actor') 'pose',
  ];
}

List<double> unitDirection(dynamic value, String path) {
  vector(value, path, double.maxFinite);
  final largest = (value as List)
      .map((v) => (v as num).abs().toDouble())
      .reduce(math.max);
  if (largest == 0) {
    invalid(path, 'zero_direction');
  }
  final scaled = [for (final v in value) (v as num) / largest];
  final length = math.sqrt(scaled.fold<double>(0, (a, b) => a + b * b));
  if (largest <= 1 && (largest * length - 1).abs() <= 1e-15) {
    return [for (final v in value) (v as num).toDouble()];
  }
  return [for (final v in scaled) v / length];
}

void validateColor(dynamic value, String path) {
  if (value is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
    invalid(path, 'invalid_color');
  }
}

void validateTarget(dynamic target, String path, Map<String, Json> objects) {
  fields(target, path, 'type');
  switch (target['type']) {
    case 'point':
      exactFields(target, path, cameraTargetRequiredFields['point']!);
      vector(target['position'], '$path.position', cameraPositionLimit);
    case 'object':
      exactFields(target, path, cameraTargetRequiredFields['object']!);
      if (!objects.containsKey(target['object_id'])) {
        invalid('$path.object_id', 'missing_target');
      }
      vector(target['offset'], '$path.offset', cameraPositionLimit);
    case 'bone':
      exactFields(target, path, cameraTargetRequiredFields['bone']!);
      if (objects[target['actor_id']]?['kind'] != 'actor') {
        invalid('$path.actor_id', 'actor_required');
      }
      choice(target['bone'], '$path.bone', humanoidBones);
      vector(target['offset'], '$path.offset', cameraPositionLimit);
    default:
      invalid('$path.type', 'unknown_value');
  }
}

dynamic validatePropertyValue(
  String property,
  dynamic value,
  String path, {
  Json? object,
  Json? camera,
  Map<String, Json> objects = const {},
}) {
  switch (directorProperties[property]!.kind) {
    case PropertyKind.rotation:
      return normalizeQuaternion(value, path);
    case PropertyKind.direction:
      return unitDirection(value, path);
    case PropertyKind.pose:
      return ActorPose.fromJson(value, path).toJson();
    case PropertyKind.target:
      validateTarget(value, path, objects);
    case PropertyKind.vector:
      vector(
        value,
        path,
        camera == null ? objectPositionLimit : cameraPositionLimit,
      );
    case PropertyKind.scale:
      final definition = directorProperties[property]!;
      vector(value, path, definition.max!);
      for (final n in value) {
        number(n, path, definition.min!, definition.max!);
      }
      if (object?['kind'] == 'actor' &&
          (value as List).any((v) => v != value[0])) {
        invalid(path, 'uniform_required');
      }
    case PropertyKind.color:
      validateColor(value, path);
    case PropertyKind.visible:
      if (value is! bool) {
        invalid(path, 'expected_boolean');
      }
    case PropertyKind.scalar:
      final definition = directorProperties[property]!;
      number(value, path, definition.min!, definition.max!);
  }
  return value;
}

Set<String> moveChannels(String kind, String mode) {
  final direction = mode == 'free' ? 'rotation' : 'camera_target';
  return switch (kind) {
    'rack_focus' => {'focus_distance_m', 'aperture_fstop'},
    'zoom_in' || 'zoom_out' || 'crash_zoom' => {'focal_length_mm'},
    'pan_l' ||
    'pan_r' ||
    'tilt_u' ||
    'tilt_d' ||
    'follow_pan' ||
    'whip_pan' => {direction},
    'static' => {
      'position',
      direction,
      'focal_length_mm',
      'focus_distance_m',
      'aperture_fstop',
      if (mode == 'look_at') 'roll',
    },
    _ => {'position', direction},
  };
}
