// 职责: 定义导演实体字段合同，以及采样使用的属性轨和运镜类型。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/properties.dart
//   lib/shared/models/director/sampling.dart
import 'document.dart';

enum TrackEasing { linear, smoothstep, hold }

const sceneObjectRequiredFields =
    'id kind name geometry_key position rotation scale color pose visible';
const sceneObjectOptionalFields = 'catalog_id deleted_at';
const sceneCameraOptionalFields = 'deleted_at focus_distance_m aperture_fstop';
const _cameraCommonFields =
    'id name position orientation_mode focal_length_mm sensor_height_mm near far';
const sceneCameraRequiredFields = {
  'free': '$_cameraCommonFields rotation',
  'look_at': '$_cameraCommonFields camera_target reference_up roll',
};
const cameraCutRequiredFields = 'id frame camera_id';

const cameraTargetRequiredFields = {
  'point': 'type position',
  'object': 'type object_id offset',
  'bone': 'type actor_id bone offset',
};

class PropertyKey {
  static const requiredFields = 'frame value easing';
  final int frame;
  final TrackEasing easing;
  final dynamic _value;
  PropertyKey.fromJson(Json json)
    : frame = json['frame'],
      easing = TrackEasing.values.byName(json['easing']),
      _value = cloneJson({'value': json['value']})['value'];
  dynamic get value => cloneJson({'value': _value})['value'];
  Json toJson() => {'frame': frame, 'value': value, 'easing': easing.name};
}

class PropertyTrack {
  static const requiredFields = 'id target_id property keys';
  final String id, targetId, property;
  final List<PropertyKey> keys;
  PropertyTrack.fromJson(Json json)
    : id = json['id'],
      targetId = json['target_id'],
      property = json['property'],
      keys = List.unmodifiable(
        (json['keys'] as List).map((k) => PropertyKey.fromJson(k)),
      );
  int keyAt(num frame) {
    var low = 0, high = keys.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (keys[middle].frame <= frame) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }
}

class CameraMove {
  static const requiredFields = 'id camera_id kind start_frame end_frame';
  final String id, cameraId, kind;
  final int start, end;
  CameraMove.fromJson(Json json)
    : id = json['id'],
      cameraId = json['camera_id'],
      kind = json['kind'],
      start = json['start_frame'],
      end = json['end_frame'];
}
