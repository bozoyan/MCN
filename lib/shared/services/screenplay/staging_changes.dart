// 职责: 将导演文档一次已提交的字段改动应用到最新文档，保留其他编辑者的改动。
// 关联文件:
//   lib/shared/services/screenplay/staging.dart
//   lib/shared/models/director/document.dart
import 'package:collection/collection.dart';
import '../../models/director/document.dart';

const _equality = DeepCollectionEquality();
const _collections = {
  'objects',
  'cameras',
  'tracks',
  'motion_paths',
  'camera_cuts',
  'camera_moves',
};

DirectorDocument applyStagingChanges(
  DirectorDocument current,
  DirectorDocument before,
  DirectorDocument after,
) {
  final json = current.toJson();
  final old = before.toJson(), next = after.toJson();
  for (final key in {...old.keys, ...next.keys}) {
    if (key == 'id' ||
        key == 'revision' ||
        _equality.equals(old[key], next[key])) {
      continue;
    }
    if (_collections.contains(key)) {
      final merged = _items(
        json[key] as List,
        old[key] as List,
        next[key] as List,
        'id',
      );
      if (key == 'camera_cuts') {
        merged.sort((a, b) => (a['frame'] as int).compareTo(b['frame'] as int));
      }
      json[key] = merged;
    } else if (next[key] is Map && old[key] is Map && json[key] is Map) {
      json[key] = _fields(json[key] as Map, old[key] as Map, next[key] as Map);
    } else if (!next.containsKey(key)) {
      json.remove(key);
    } else {
      json[key] = next[key];
    }
  }
  json['revision'] = current.revision + 1;
  return DirectorDocument.fromJson(json);
}

Map<String, dynamic> _fields(Map current, Map before, Map after) {
  final result = Map<String, dynamic>.from(current);
  for (final key in {...before.keys, ...after.keys}) {
    if (_equality.equals(before[key], after[key])) {
      continue;
    }
    if (!after.containsKey(key)) {
      result.remove(key);
    } else if (key == 'keys' &&
        before[key] is List &&
        after[key] is List &&
        current[key] is List) {
      result[key as String] = _items(
        current[key] as List,
        before[key] as List,
        after[key] as List,
        'frame',
      );
    } else {
      result[key as String] = after[key];
    }
  }
  return result;
}

List<dynamic> _items(List current, List before, List after, String identity) {
  final result = [
    for (final item in current) Map<String, dynamic>.from(item as Map),
  ];
  final old = {for (final item in before) item[identity]: item as Map};
  final next = {for (final item in after) item[identity]: item as Map};
  for (final id in {...old.keys, ...next.keys}) {
    if (_equality.equals(old[id], next[id])) {
      continue;
    }
    final index = result.indexWhere((item) => item[identity] == id);
    if (!next.containsKey(id)) {
      result.removeWhere((item) => item[identity] == id);
    } else if (index < 0) {
      // 已被另一编辑者删除的元素不能被旧的字段修改重新创建。
      if (old.containsKey(id)) {
        throw DocumentError('$identity.$id', 'not_found');
      }
      result.add(Map<String, dynamic>.from(next[id]!));
    } else {
      result[index] = _fields(result[index], old[id] ?? {}, next[id]!);
    }
  }
  if (identity == 'frame') {
    result.sort((a, b) => (a['frame'] as int).compareTo(b['frame'] as int));
  }
  return result;
}
