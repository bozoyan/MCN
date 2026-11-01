// 职责: 固定画布 v1 导出快照、问题与文件产物的不可变边界。
// 关联文件:
//   lib/shared/services/canvas_export/orchestrator.dart
//   lib/shared/services/canvas_export/resources.dart
//   lib/shared/services/canvas_export/format.dart

import 'dart:typed_data';

import 'canvas_layout.dart' show canvasNodeCustomColorPattern;

typedef CanvasExportObject = Map<String, dynamic>;

// 导出格式的枚举独立于应用内部枚举；扩展此契约时必须升级 format_version。
const canvasExportResourceTypes = [
  'chapter',
  'outline',
  'character',
  'foreshadowing',
  'location',
  'item',
  'faction',
  'skill',
  'creature',
  'document',
  'screenplay_scene',
];
const canvasExportNodeTypes = ['sticky', 'reference'];
const canvasExportEdgeTypes = [
  'relationship',
  'causal',
  'timeline',
  'foreshadow_payoff',
  'association',
];
const canvasExportLayoutModes = ['auto', 'tree_lr', 'tree_tb', 'grid'];
const canvasExportColorKeys = [
  'sand',
  'sage',
  'rose',
  'stone',
  'red',
  'orange',
  'yellow',
  'green',
  'teal',
  'blue',
  'purple',
  'pink',
];

/// 自定义颜色 `#RRGGBB` 的 JSON Schema pattern。
const canvasExportCustomColorPattern = canvasNodeCustomColorPattern;
const canvasExportElementTypes = [
  'scene_heading',
  'action',
  'character',
  'parenthetical',
  'dialogue',
  'transition',
  'subtitle',
  'note',
];

enum CanvasExportFormat { zip, json }

class CanvasExportSnapshot {
  CanvasExportSnapshot(CanvasExportObject value)
    : json = _freeze(value) as CanvasExportObject;

  final CanvasExportObject json;
  String get title => (json['canvas'] as CanvasExportObject)['title'] as String;
  List<CanvasExportObject> get nodes =>
      (json['nodes'] as List).cast<CanvasExportObject>();
  List<CanvasExportObject> get edges =>
      (json['edges'] as List).cast<CanvasExportObject>();
  List<CanvasExportObject> get resources =>
      (json['resources'] as List).cast<CanvasExportObject>();
  List<CanvasExportObject> get issues =>
      (json['issues'] as List).cast<CanvasExportObject>();
  bool get hasErrors => issues.any((issue) => issue['severity'] == 'error');
}

Object? _freeze(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries) entry.key: _freeze(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freeze));
  }
  return value;
}

class CanvasExportArtifact {
  CanvasExportArtifact({
    required this.format,
    required this.title,
    required Uint8List bytes,
  }) : bytes = bytes.asUnmodifiableView();
  final CanvasExportFormat format;
  final String title;
  final Uint8List bytes;
}

class CanvasExportException implements Exception {
  const CanvasExportException(this.code);
  final String code;
}

CanvasExportObject canvasExportIssue(
  String severity,
  String code,
  String message, {
  String? nodeId,
  String? edgeId,
  String? resourceType,
  String? resourceId,
}) => {
  'severity': severity,
  'code': code,
  'node_id': nodeId,
  'edge_id': edgeId,
  'resource_type': resourceType,
  'resource_id': resourceId,
  'message': message,
};
