// 职责: 将导演批次命令映射到编辑器共用命令并返回实际资源身份。
// 关联文件:
//   lib/shared/services/director/commands.dart
//   lib/shared/services/screenplay/staging_edit.dart
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/path.dart
import 'package:uuid/uuid.dart';
import '../../models/director/document.dart';
import '../../models/director/entities.dart';
import '../../models/director/path.dart';
import '../../models/director/presets.dart';
import '../../models/director/properties.dart';
import 'commands.dart';

// 必填与可选参数同时供执行边界与能力查询使用。
const directorCommandFields = <String, (String, String)>{
  'set_title': ('title', ''),
  'set_duration': ('duration_frames', ''),
  'set_output': ('output', ''),
  'set_key': ('target_id property frame value', 'easing'),
  'remove_key': ('target_id property frame', ''),
  'set_base': ('target_id property value', ''),
  'apply_pose': ('target_id preset', 'frame'),
  'upsert_path': ('data', 'replace'),
  'upsert_move': ('data', 'replace'),
  'bake': ('collection id', ''),
  'set_camera_mode': ('camera_id mode frame', ''),
  'add_camera': ('name preset frame', 'subject_id'),
  'set_cut': ('frame camera_id', ''),
  'set_default_camera': ('camera_id', ''),
};

List<Json> applyDirectorCommands(CommandHistory history, List<Json> commands) {
  final results = <Json>[];
  for (final command in commands) {
    final op = command['op'];
    final fields = directorCommandFields[op];
    if (fields == null) {
      invalid('command.op', 'unknown_value');
    }
    exactFields(command, 'command', 'op ${fields.$1}', optional: fields.$2);
    String text(String key) {
      label(command[key], 'command.$key', 256);
      return command[key];
    }

    int frame() => number(
      command['frame'],
      'command.frame',
      0,
      history.document.durationFrames,
      integer: true,
    ).toInt();
    String camera() {
      final id = text('camera_id');
      if (!history.document.isCamera(id)) {
        invalid('camera_id', 'camera_required');
      }
      return id;
    }

    String? resultId;
    switch (op) {
      case 'set_title':
        history.execute((j) => j['title'] = command['title']);
        resultId = history.document.id;
      case 'set_duration':
        history.execute(
          (j) => j['duration_frames'] = command['duration_frames'],
        );
        resultId = history.document.id;
      case 'set_output':
        if (command['output'] is! Json) {
          invalid('output', 'expected_object');
        }
        history.execute((j) => j['output'] = cloneJson(command['output']));
        resultId = history.document.id;
      case 'set_key' || 'remove_key' || 'set_base':
        final target = text('target_id'), property = text('property');
        final document = history.document;
        final object = document.objects
            .where((o) => o['id'] == target)
            .firstOrNull;
        final cam = document.camera(target);
        if (object == null && cam == null && target != document.id) {
          invalid('target_id', 'missing_target');
        }
        choice(
          property,
          'property',
          propertiesFor(
            object: object,
            camera: cam,
            lighting: target == document.id,
          ),
        );
        if (op == 'set_key') {
          if (command.containsKey('easing')) {
            choice(
              command['easing'],
              'easing',
              TrackEasing.values.map((e) => e.name).toList(),
            );
          }
          history.upsertKey(
            target,
            property,
            frame(),
            command['value'],
            easing: command['easing'],
          );
        } else if (op == 'remove_key') {
          history.removeKey(target, property, frame());
        } else {
          history.timelineVisible = false;
          history.editProperty(target, property, command['value'], 0);
          history.timelineVisible = true;
        }
        resultId = history.document.tracks
            .where((t) => t['target_id'] == target && t['property'] == property)
            .firstOrNull?['id'];
      case 'apply_pose':
        final target = text('target_id'), preset = text('preset');
        final actor = history.document.objects
            .where((o) => o['id'] == target)
            .firstOrNull;
        if (actor == null) {
          invalid('target_id', 'missing_target');
        }
        if (actor['kind'] != 'actor') {
          invalid('target_id', 'actor_required');
        }
        choice(preset, 'preset', poseIds);
        final pose = posePreset(preset, actor['geometry_key']).toJson();
        if (command.containsKey('frame')) {
          history.upsertKey(target, 'pose', frame(), pose);
        } else {
          final timelineVisible = history.timelineVisible;
          try {
            history.timelineVisible = false;
            history.editProperty(target, 'pose', pose, 0);
          } finally {
            history.timelineVisible = timelineVisible;
          }
        }
        resultId = target;
      case 'upsert_path' || 'upsert_move':
        if (command['data'] is! Json) {
          invalid('data', 'expected_object');
        }
        if (command.containsKey('replace') && command['replace'] is! bool) {
          invalid('replace', 'expected_boolean');
        }
        final data = cloneJson(command['data']);
        data['id'] ??= const Uuid().v4();
        if (op == 'upsert_path') {
          MotionPath.fromJson(data);
          if (!history.document.objects.any(
            (o) => o['id'] == data['target_id'] && o['kind'] == 'actor',
          )) {
            invalid('target_id', 'actor_required');
          }
        } else {
          exactFields(data, 'data', CameraMove.requiredFields);
          choice(data['kind'], 'kind', moveKinds);
          if (!history.document.isCamera(data['camera_id'])) {
            invalid('camera_id', 'camera_required');
          }
        }
        for (final key in ['start_frame', 'end_frame']) {
          number(
            data[key],
            key,
            0,
            history.document.durationFrames,
            integer: true,
          );
        }
        if (op == 'upsert_path') {
          history.upsertPath(data, replace: command['replace'] == true);
        } else {
          history.upsertMove(data, replace: command['replace'] == true);
        }
        resultId = data['id'];
      case 'bake':
        final collection = text('collection'), id = text('id');
        choice(collection, 'collection', ['motion_paths', 'camera_moves']);
        if (!(history.document.toJson()[collection] as List).any(
          (v) => v['id'] == id,
        )) {
          invalid('id', 'not_found');
        }
        history.bake(collection, id);
        resultId = id;
      case 'set_camera_mode':
        resultId = camera();
        history.setCameraMode(resultId, text('mode'), frame());
      case 'add_camera':
        final preset = text('preset');
        choice(preset, 'preset', cameraPresets);
        final subject = command.containsKey('subject_id')
            ? text('subject_id')
            : null;
        if (subject != null &&
            !history.document.objects.any(
              (o) => o['id'] == subject && o['kind'] == 'actor',
            )) {
          invalid('subject_id', 'actor_required');
        }
        resultId = history.addCamera(text('name'), preset, subject, frame());
      case 'set_cut':
        final f = frame();
        history.setCut(f, camera());
        resultId = history.document.cuts.firstWhere(
          (c) => c['frame'] == f,
        )['id'];
      case 'set_default_camera':
        resultId = camera();
        history.setDefaultCamera(resultId);
    }
    results.add({'op': op, 'id': resultId});
  }
  return results;
}
