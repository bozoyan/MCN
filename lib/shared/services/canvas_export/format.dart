// 职责: 从同一导出快照生成 JSON、离线 Schema、开发说明、完整审阅稿及固定 ZIP。
// 关联文件:
//   lib/shared/models/canvas_export.dart
//   lib/shared/models/screenplay_element_render.dart
//   lib/shared/services/canvas_export/schema.dart
//   lib/shared/services/canvas_export/svg.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../../models/canvas_export.dart';
import '../../models/canvas_export_preview.dart';
import '../../models/screenplay_element.dart';
import '../../models/screenplay_element_render.dart';
import 'schema.dart';
import 'svg.dart';

const _json = JsonEncoder.withIndent('  ');
String canvasExportJson(CanvasExportSnapshot snapshot) {
  final content = {
    for (final entry in snapshot.json.entries)
      if (entry.key != 'issues') entry.key: entry.value,
  };
  return '${_json.convert(content)}\n';
}

/// ZIP 内含预览 SVG，必须带上主 isolate 解析好的 [preview]。
CanvasExportArtifact encodeCanvasExport(
  CanvasExportSnapshot snapshot,
  CanvasExportFormat format, {
  CanvasExportPreview? preview,
}) {
  if (snapshot.hasErrors) {
    throw const CanvasExportException('invalid_snapshot');
  }
  final json = canvasExportJson(snapshot);
  if (format == CanvasExportFormat.json) {
    return CanvasExportArtifact(
      format: format,
      title: snapshot.title,
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
  }
  if (preview == null) {
    throw const CanvasExportException('missing_preview');
  }
  final files = <String, String>{
    'canvas.json': json,
    'canvas.schema.json': '${_json.convert(canvasExportSchema())}\n',
    'README.md': canvasExportReadme(snapshot),
    'review.md': canvasExportReview(snapshot),
    'preview.svg': canvasExportSvg(snapshot, preview),
  };
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return CanvasExportArtifact(
    format: format,
    title: snapshot.title,
    bytes: Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
  );
}

String _block(String text) {
  var width = 3;
  for (final match in RegExp(r'`+').allMatches(text)) {
    if (match.group(0)!.length >= width) {
      width = match.group(0)!.length + 1;
    }
  }
  final fence = '`' * width;
  return '$fence\n$text\n$fence\n';
}

String _anchor(String kind, String id) =>
    '$kind-${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';

String canvasExportReadme(CanvasExportSnapshot snapshot) =>
    '''# Canvas handoff

Format: reveric.canvas, version 1. Exported at: ${snapshot.json['exported_at']}.

canvas.json is the sole machine-readable source. canvas.schema.json is the complete offline JSON Schema Draft 2020-12 contract; all references are local. Reject unknown format versions. Files use UTF-8 without a BOM, UTC ISO 8601 timestamps, string IDs and logical pixel coordinates.

## Identity and snapshots

Identify nodes by (work_id, canvas_id, node_id), resources by (work_id, resource_type, resource_id), and connections by their original edge ID. Outline IDs are document IDs. Renaming, moving and reordering keep identity; deleting and recreating makes a new object. This is a full snapshot, not a deletion instruction or an incremental patch. Keep engine GUID, media and voice mappings separately so a later import cannot overwrite them.

All canvas nodes and connections are retained. Direct resources contain complete saved business content; indirect dependencies contain identity only. A directly referenced dependency has one content entry. Containers do not implicitly include children. Media, local paths, metadata, synchronization state, chat and AI settings are excluded.

## Fields and integration

canvas.layout records the last arrangement mode; current node coordinates are authoritative. Nodes retain type, title, content/reference, position, dimensions, sort_order, z_index and approved color_key. Connections retain endpoints, original type, shared directed semantics and the full label. Resource status describes reference validity, while payload.status is the source business state. Each resource type has its own fixed payload. Screenplay elements retain order, types, notes, newlines and character/location IDs.

Structural roots and terminals use directed connections only and are not game entrances or endings. Undirected relationships carry no narrative direction. Coordinates and array order do not define choice order. Free-text labels are author notes, not executable conditions. This package does not run in a game engine without an adapter. The receiving team must choose flow edge types and define entrances, endings, choices, conditions and native mappings. No variable evaluation, gameplay execution, media binding or reverse synchronization is supplied.

The canvas allows one connection per endpoint pair and type. To represent two choices reaching the same scene, use separate sticky nodes and connect both to the scene; do not merge their labels or node IDs.

preview.svg is a static structural preview using saved geometry. Full text is in canvas.json and review.md; preview summaries may be shortened. review.md expands each resource once. All five files derive from the same frozen snapshot, even if editing continues during encoding.
''';

String canvasExportReview(CanvasExportSnapshot snapshot) {
  final out = StringBuffer('# Canvas review\n\n')
    ..writeln(_block(snapshot.title));
  for (final node in snapshot.nodes) {
    out.writeln(
      '<a id="${_anchor('node', node['id'] as String)}"></a>\n## Node\n',
    );
    out.writeln(
      _block(
        'ID: ${node['id']}\nType: ${node['type']}\nTitle: ${node['title']}',
      ),
    );
    if (node['type'] == 'sticky') {
      out.writeln(_block(node['content'] as String));
    } else {
      out.writeln(
        '[Referenced resource](#${_anchor('resource', '${node['ref_type']}:${node['ref_id']}')})\n',
      );
    }
    for (final edge in snapshot.edges.where(
      (e) =>
          e['source_node_id'] == node['id'] ||
          e['target_node_id'] == node['id'],
    )) {
      out.writeln(
        _block(
          'Connection ID: ${edge['id']}\nType: ${edge['type']}\nDirected: ${edge['directed']}\nSource: ${edge['source_node_id']}\nTarget: ${edge['target_node_id']}\nLabel: ${edge['label']}',
        ),
      );
    }
  }
  final characters = {
    for (final resource in snapshot.resources)
      if (resource['type'] == 'character')
        resource['id'] as String: resource['title'] as String,
  };
  final locations = {
    for (final resource in snapshot.resources)
      if (resource['type'] == 'location')
        resource['id'] as String: resource['title'] as String,
  };
  for (final resource in snapshot.resources) {
    out.writeln(
      '<a id="${_anchor('resource', '${resource['type']}:${resource['id']}')}"></a>\n## Resource\n',
    );
    out.writeln(
      _block(
        'ID: ${resource['id']}\nType: ${resource['type']}\nTitle: ${resource['title']}\nStatus: ${resource['status']}\nDetail: ${resource['detail_level']}',
      ),
    );
    final payload = resource['payload'] as CanvasExportObject?;
    if (payload == null) {
      continue;
    }
    for (final entry in payload.entries) {
      out.writeln('### ${entry.key}\n');
      out.writeln(
        _block(
          entry.value is String
              ? entry.value as String
              : _json.convert(entry.value),
        ),
      );
    }
    if (resource['type'] == 'screenplay_scene') {
      out.writeln('### Script (including notes)\n');
      out.writeln(
        _block(
          renderScreenplayElements(
            [
              for (final e in payload['elements'] as List)
                ScreenplayElement(
                  id: e['id'] as String,
                  type: screenplayElementTypeFromName(e['type'] as String),
                  text: e['text'] as String,
                  characterId: e['character_id'] as String?,
                  extension: e['extension'] as String,
                  locationId: e['location_id'] as String?,
                  interiorExterior: e['interior_exterior'] as String?,
                  timeLabel: e['time_label'] as String?,
                ),
            ],
            characterNames: characters,
            locationNames: locations,
            includeNotes: true,
          ),
        ),
      );
    }
  }
  return out.toString();
}
