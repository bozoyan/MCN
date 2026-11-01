// 职责: 构造保存与备份回归使用的完整姿态、五类路径、双模式机位和切镜场景。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/services/director/commands.dart
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:uuid/uuid.dart';

DirectorDocument animatedDirectorDocument() {
  final h = CommandHistory(DirectorDocument.blank('Animated scene'));
  try {
    h.addObject('actor.male.v1', 'Actor');
    final actor = h.document.objects.single['id'];
    final camera = h.document.cameras.single['id'];
    h.setLookAt(camera, actor);
    h.autoKey = true;
    final pose = h.document.objects.single['pose'] as Json;
    h.editProperty(actor, 'pose', pose, 12);
    h.editProperty(actor, 'pose', {
      ...pose,
      'root_offset_y': 0.4,
      'head_yaw': 30.0,
    }, 60);
    h.editProperty(camera, 'roll', 10.0, 24);
    h.editProperty(h.document.id, 'lighting.key_intensity', 1.5, 48);
    final geometries = <String, Json>{
      'line': {
        'start': [0, 0, 0],
        'end': [1, 0, 0],
      },
      'circle': {
        'center': [0, 0, 0],
        'radius': 1,
        'plane_rotation': [0, 0, 0, 1],
        'start_angle': 0,
        'clockwise': true,
      },
      'rectangle': {
        'center': [0, 0, 0],
        'width': 2,
        'depth': 2,
        'plane_rotation': [0, 0, 0, 1],
        'start_corner': 0,
        'clockwise': false,
      },
      'pencil': {
        'points': [
          [0, 0, 0],
          [1, 0, 0],
          [1, 0, 1],
        ],
        'closed': false,
      },
      'pen': {
        'nodes': [
          {
            'position': [0, 0, 0],
            'smooth': false,
            'out_handle': [0.5, 0, 0],
          },
          {
            'position': [1, 0, 1],
            'smooth': false,
            'in_handle': [1, 0, 0.5],
          },
        ],
        'closed': false,
      },
    };
    final free = DirectorDocument.newCamera('Free', [3, 2, 5], [0, 1, 0], 50);
    h.execute((j) {
      j['cameras'].add(free);
      j['motion_paths'] = [
        for (final e in geometries.entries.indexed)
          {
            'id': const Uuid().v4(),
            'target_id': actor,
            'kind': e.$2.key,
            'start_frame': e.$1 * 24,
            'end_frame': (e.$1 + 1) * 24,
            'easing': 'smoothstep',
            'orient_to_path': true,
            'geometry': e.$2.value,
          },
      ];
    });
    h.setCameraMode(free['id'], 'free', 0);
    h.setCut(48, free['id']);
    h.setCut(96, camera);
    return h.document;
  } finally {
    h.dispose();
  }
}
