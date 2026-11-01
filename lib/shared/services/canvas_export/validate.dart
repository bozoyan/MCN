// 职责: 校验导出引用与几何，按有向边诊断根、末端、循环和孤立节点。
// 关联文件:
//   lib/shared/models/canvas_export.dart
//   lib/shared/models/canvas_layout.dart
//   lib/shared/services/canvas_export/resources.dart
//   lib/shared/services/canvas_export/orchestrator.dart

import '../../database/novel_content_database.dart';
import '../../models/canvas_export.dart';
import '../../models/canvas_layout.dart';
import 'resources.dart';

CanvasExportSnapshot buildCanvasExportSnapshot({
  required CanvasEntry canvas,
  required List<CanvasNode> nodes,
  required List<CanvasEdge> edges,
  required CanvasResourceCollection resources,
  required String workId,
  required String contentKind,
  required DateTime exportedAt,
}) {
  final issues = [...resources.issues];
  final sortedNodes = [...nodes]
    ..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  final sortedEdges = [...edges]
    ..sort((a, b) {
      for (final (x, y) in [
        (a.sourceNodeId, b.sourceNodeId),
        (a.targetNodeId, b.targetNodeId),
        (a.type, b.type),
        (a.id, b.id),
      ]) {
        final result = x.compareTo(y);
        if (result != 0) {
          return result;
        }
      }
      return 0;
    });
  final nodeIds = <String>{};
  final edgeIds = <String>{};
  final outputNodes = <CanvasExportObject>[];
  if ((canvas.layout != null &&
          !canvasExportLayoutModes.contains(canvas.layout)) ||
      !['novel', 'screenplay'].contains(contentKind)) {
    issues.add(
      canvasExportIssue(
        'error',
        'unsupported_type',
        'The canvas or work has an unsupported type.',
      ),
    );
  }
  for (final node in sortedNodes) {
    void issue(String severity, String code, String message) => issues.add(
      canvasExportIssue(
        severity,
        code,
        message,
        nodeId: node.id,
        resourceType: node.refType,
        resourceId: node.refId,
      ),
    );
    if (!nodeIds.add(node.id)) {
      issue('error', 'duplicate_id', 'A node ID occurs more than once.');
    }
    if (!canvasExportNodeTypes.contains(node.type)) {
      issue('error', 'unsupported_type', 'The node type is unsupported.');
    }
    final sticky = node.type == canvasNodeTypeSticky;
    final width =
        node.width ??
        (sticky ? canvasStickyDefaultWidth : canvasReferenceDefaultWidth);
    final height =
        node.height ??
        (sticky ? canvasStickyDefaultHeight : canvasReferenceDefaultHeight);
    if (![
          node.x,
          node.y,
          width,
          height,
          node.x + width,
          node.y + height,
        ].every((n) => n.isFinite) ||
        width <= 0 ||
        height <= 0) {
      issue(
        'error',
        'invalid_geometry',
        'Node coordinates and dimensions must be finite, with positive dimensions.',
      );
    }
    final resource = resources
        .resources[canvasResourceKey(node.refType ?? '', node.refId ?? '')];
    if (!sticky) {
      if (!canvasExportResourceTypes.contains(node.refType)) {
        issue('error', 'unsupported_type', 'The resource type is unsupported.');
      } else if (resource == null || resource['status'] != 'available') {
        issue(
          'error',
          'invalid_direct_reference',
          'A directly referenced resource is missing.',
        );
      }
    } else if (node.title.trim().isEmpty && node.content.trim().isEmpty) {
      issue('warning', 'empty_content', 'The sticky note is empty.');
    }
    final color = canvasNodeColorValueOf(node.style);
    outputNodes.add({
      'id': node.id,
      'type': node.type,
      'title': sticky ? node.title : resource?['title'] ?? node.title,
      'content': sticky ? node.content : null,
      'ref_type': sticky ? null : node.refType,
      'ref_id': sticky ? null : node.refId,
      'x': node.x,
      'y': node.y,
      'width': width,
      'height': height,
      'sort_order': node.sortOrder,
      'z_index': node.zIndex,
      'color_key': sticky ? color ?? canvasStickyColorDefault : color,
    });
  }
  final outputEdges = <CanvasExportObject>[];
  for (final edge in sortedEdges) {
    final nodeId = nodeIds.contains(edge.sourceNodeId)
        ? edge.sourceNodeId
        : nodeIds.contains(edge.targetNodeId)
        ? edge.targetNodeId
        : null;
    void issue(String severity, String code, String message) => issues.add(
      canvasExportIssue(
        severity,
        code,
        message,
        edgeId: edge.id,
        nodeId: nodeId,
      ),
    );
    if (!edgeIds.add(edge.id)) {
      issue('error', 'duplicate_id', 'An edge ID occurs more than once.');
    }
    if (!canvasExportEdgeTypes.contains(edge.type)) {
      issue('error', 'unsupported_type', 'The connection type is unsupported.');
    }
    if (!nodeIds.contains(edge.sourceNodeId) ||
        !nodeIds.contains(edge.targetNodeId)) {
      issue(
        'error',
        'missing_edge_endpoint',
        'A connection endpoint is missing.',
      );
    }
    final directed = isCanvasEdgeDirected(edge.type);
    if (directed && (edge.label ?? '').trim().isEmpty) {
      issue(
        'info',
        'empty_directed_edge_label',
        'A directed connection has no label.',
      );
    }
    outputEdges.add({
      'id': edge.id,
      'source_node_id': edge.sourceNodeId,
      'target_node_id': edge.targetNodeId,
      'type': edge.type,
      'directed': directed,
      'label': edge.label ?? '',
    });
  }
  final outputResources = resources.resources.values.toList()
    ..sort((a, b) {
      final c = (a['type'] as String).compareTo(b['type'] as String);
      return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
    });
  for (final resource in outputResources) {
    final payload = resource['payload'] as CanvasExportObject?;
    if (payload == null) {
      continue;
    }
    final type = resource['type'] as String;
    final node = sortedNodes
        .where((n) => n.refType == type && n.refId == resource['id'])
        .firstOrNull;
    void issue(String severity, String code, String message) => issues.add(
      canvasExportIssue(
        severity,
        code,
        message,
        nodeId: node?.id,
        resourceType: type,
        resourceId: resource['id'] as String,
      ),
    );
    final empty = switch (type) {
      entityTypeChapter =>
        payload['node_kind'] == 'chapter' &&
            (payload['content'] as String).trim().isEmpty,
      canvasNodeRefTypeOutline =>
        (payload['content'] as String).trim().isEmpty &&
            (payload['beats'] as List).every(
              (beat) =>
                  (beat['title'] as String).trim().isEmpty &&
                  (beat['content'] as String).trim().isEmpty,
            ),
      canvasNodeRefTypeDocument =>
        payload['is_folder'] == false &&
            (payload['content'] as String).trim().isEmpty,
      canvasNodeRefTypeScreenplayScene => (payload['elements'] as List).every(
        (e) => e['type'] == 'scene_heading',
      ),
      _ => false,
    };
    if (empty) {
      issue(
        'warning',
        'empty_content',
        'The referenced resource has no written content.',
      );
    }
    if (type == canvasNodeRefTypeScreenplayScene) {
      final elementIds = <String>{};
      for (final element in payload['elements'] as List) {
        if (!canvasExportElementTypes.contains(element['type'])) {
          issue(
            'error',
            'unsupported_type',
            'A screenplay element type is unsupported.',
          );
        }
        if (!elementIds.add(element['id'] as String)) {
          issue(
            'error',
            'duplicate_id',
            'A screenplay element ID occurs more than once.',
          );
        }
      }
    }
  }
  final analysis = _analyze(nodeIds, outputEdges);
  for (final id in analysis['isolated_node_ids'] as List<String>) {
    issues.add(
      canvasExportIssue(
        'info',
        'isolated_node',
        'The node has no connections.',
        nodeId: id,
      ),
    );
  }
  if ((analysis['root_node_ids'] as List).length > 1) {
    issues.add(
      canvasExportIssue(
        'info',
        'multiple_roots',
        'The directed graph has multiple structural roots.',
      ),
    );
  }
  for (final group in analysis['cycle_groups'] as List<List<String>>) {
    issues.add(
      canvasExportIssue(
        'info',
        'cycle',
        'The directed graph contains a cycle.',
        nodeId: group.first,
      ),
    );
  }
  issues.sort((a, b) {
    for (final key in [
      'severity',
      'code',
      'node_id',
      'edge_id',
      'resource_type',
      'resource_id',
    ]) {
      final c = (a[key] as String? ?? '').compareTo(b[key] as String? ?? '');
      if (c != 0) {
        return c;
      }
    }
    return 0;
  });
  return CanvasExportSnapshot({
    'format': 'reveric.canvas',
    'format_version': 1,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'source': {
      'work_id': workId,
      'content_kind': contentKind,
      'canvas_id': canvas.id,
    },
    'canvas': {
      'title': canvas.name,
      'description': canvas.description,
      'layout': canvas.layout,
    },
    'nodes': outputNodes,
    'edges': outputEdges,
    'resources': outputResources,
    'analysis': analysis,
    'issues': issues,
  });
}

CanvasExportObject _analyze(Set<String> ids, List<CanvasExportObject> edges) {
  final next = {for (final id in ids) id: <String>{}},
      previous = {for (final id in ids) id: <String>{}};
  final connected = <String>{}, directed = <String>{};
  for (final edge in edges) {
    final a = edge['source_node_id'] as String,
        b = edge['target_node_id'] as String;
    if (!ids.contains(a) || !ids.contains(b)) {
      continue;
    }
    connected.addAll([a, b]);
    if (edge['directed'] == true) {
      next[a]!.add(b);
      previous[b]!.add(a);
      directed.addAll([a, b]);
    }
  }
  final order = ids.toList()..sort(), finished = <String>[], seen = <String>{};
  final adjacent = {for (final id in order) id: next[id]!.toList()..sort()};
  for (final start in order) {
    if (!seen.add(start)) {
      continue;
    }
    final stack = <(String, int)>[(start, 0)];
    while (stack.isNotEmpty) {
      final (id, index) = stack.last;
      if (index == adjacent[id]!.length) {
        finished.add(id);
        stack.removeLast();
      } else {
        stack[stack.length - 1] = (id, index + 1);
        final child = adjacent[id]![index];
        if (seen.add(child)) {
          stack.add((child, 0));
        }
      }
    }
  }
  seen.clear();
  final cycles = <List<String>>[];
  for (final start in finished.reversed) {
    if (!seen.add(start)) {
      continue;
    }
    final members = <String>[], stack = [start];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      members.add(id);
      for (final parent in previous[id]!) {
        if (seen.add(parent)) {
          stack.add(parent);
        }
      }
    }
    members.sort();
    if (members.length > 1 || next[start]!.contains(start)) {
      cycles.add(members);
    }
  }
  cycles.sort((a, b) => a.first.compareTo(b.first));
  return {
    'root_node_ids': [
      for (final id in order)
        if (directed.contains(id) && previous[id]!.isEmpty) id,
    ],
    'terminal_node_ids': [
      for (final id in order)
        if (directed.contains(id) && next[id]!.isEmpty) id,
    ],
    'cycle_groups': cycles,
    'isolated_node_ids': [
      for (final id in order)
        if (!connected.contains(id)) id,
    ],
  };
}
