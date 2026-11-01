// 职责: 实体关系图力导向布局 — BFS 径向初值、节点碰撞、多边去重吸引。
// 关联文件:
//   lib/shared/entity_graph/constants.dart
//   lib/shared/entity_graph/models.dart
//   lib/shared/entity_graph/graph_widget.dart

import 'dart:math';

import 'package:flutter/material.dart';

import 'constants.dart';
import 'models.dart';

/// 计算节点在画布逻辑坐标系中的位置（中心节点位于原点附近）。
Map<String, Offset> computeEntityGraphLayout({
  required List<EntityNodeData> nodes,
  required List<EntityEdgeData> edges,
  String? centerNodeKey,
  int layoutSeed = 42,
}) {
  if (nodes.isEmpty) {
    return {};
  }
  if (nodes.length == 1) {
    return {nodes.first.key: Offset.zero};
  }

  final adjacency = _buildAdjacency(edges);
  final positions = _initialRadialPositions(
    nodes: nodes,
    adjacency: adjacency,
    centerNodeKey: centerNodeKey,
    seed: layoutSeed,
  );

  final area = nodes.length * kEntityGraphNodeSpacing * kEntityGraphNodeSpacing;
  final k = sqrt(area / nodes.length);
  final uniquePairs = _uniqueNodePairs(edges);
  final iterations = min(300, 80 + nodes.length * 8);
  var temperature = k * 2.5;
  final cooling = temperature / iterations;
  final rng = Random(layoutSeed);

  for (var i = 0; i < iterations; i++) {
    final disp = {for (final node in nodes) node.key: Offset.zero};

    for (var a = 0; a < nodes.length; a++) {
      for (var b = a + 1; b < nodes.length; b++) {
        final keyA = nodes[a].key;
        final keyB = nodes[b].key;
        var delta = positions[keyA]! - positions[keyB]!;
        var dist = sqrt(delta.dx * delta.dx + delta.dy * delta.dy);
        if (dist < 0.01) {
          final angle = rng.nextDouble() * 2 * pi;
          delta = Offset(cos(angle), sin(angle));
          dist = 0.01;
        }
        var repForce = k * k / dist;
        if (dist < kEntityGraphMinNodeDistance) {
          final overlap = kEntityGraphMinNodeDistance - dist;
          repForce += overlap * overlap * 0.8;
        }
        final normalized = delta / dist;
        disp[keyA] = disp[keyA]! + normalized * repForce;
        disp[keyB] = disp[keyB]! - normalized * repForce;
      }
    }

    for (final pair in uniquePairs) {
      final srcPos = positions[pair.$1];
      final tgtPos = positions[pair.$2];
      if (srcPos == null || tgtPos == null) {
        continue;
      }
      var delta = srcPos - tgtPos;
      var dist = sqrt(delta.dx * delta.dx + delta.dy * delta.dy);
      if (dist < 0.01) {
        dist = 0.01;
      }
      final attForce = dist * dist / k;
      final normalized = delta / dist;
      disp[pair.$1] = disp[pair.$1]! - normalized * attForce;
      disp[pair.$2] = disp[pair.$2]! + normalized * attForce;
    }

    for (final node in nodes) {
      if (node.key == centerNodeKey) {
        continue;
      }
      final d = disp[node.key]!;
      final dist = sqrt(d.dx * d.dx + d.dy * d.dy);
      if (dist > 0) {
        final capped = min(dist, temperature);
        positions[node.key] = positions[node.key]! + (d / dist) * capped;
      }
    }

    temperature -= cooling;
    if (temperature < 0.05) {
      break;
    }
  }

  _resolveNodeCollisions(
    positions: positions,
    nodes: nodes,
    fixedKey: centerNodeKey,
    minDistance: kEntityGraphMinNodeDistance,
    seed: layoutSeed,
  );

  return positions;
}

Map<String, Set<String>> _buildAdjacency(List<EntityEdgeData> edges) {
  final adjacency = <String, Set<String>>{};
  for (final edge in edges) {
    adjacency.putIfAbsent(edge.sourceKey, () => {}).add(edge.targetKey);
    adjacency.putIfAbsent(edge.targetKey, () => {}).add(edge.sourceKey);
  }
  return adjacency;
}

Map<String, int> _bfsDepths(
  String centerKey,
  Map<String, Set<String>> adjacency,
) {
  final depths = <String, int>{centerKey: 0};
  final queue = <String>[centerKey];
  while (queue.isNotEmpty) {
    final key = queue.removeAt(0);
    final depth = depths[key]!;
    for (final neighbor in adjacency[key] ?? const {}) {
      if (depths.containsKey(neighbor)) {
        continue;
      }
      depths[neighbor] = depth + 1;
      queue.add(neighbor);
    }
  }
  return depths;
}

Map<String, Offset> _initialRadialPositions({
  required List<EntityNodeData> nodes,
  required Map<String, Set<String>> adjacency,
  required String? centerNodeKey,
  required int seed,
}) {
  final positions = <String, Offset>{};
  final rng = Random(seed);

  if (centerNodeKey != null && nodes.any((n) => n.key == centerNodeKey)) {
    positions[centerNodeKey] = Offset.zero;
    final depths = _bfsDepths(centerNodeKey, adjacency);
    final maxKnownDepth = depths.values.fold<int>(0, max);
    final byDepth = <int, List<String>>{};
    for (final node in nodes) {
      final depth = depths[node.key] ?? maxKnownDepth + 1;
      byDepth.putIfAbsent(depth, () => []).add(node.key);
    }

    for (final entry in byDepth.entries) {
      final depth = entry.key;
      final keys = entry.value..sort();
      if (depth == 0) {
        continue;
      }
      final radius = kEntityGraphNodeSpacing * depth * 1.05;
      for (var i = 0; i < keys.length; i++) {
        final angle = (2 * pi * i / keys.length) - pi / 2;
        positions[keys[i]] = Offset(cos(angle) * radius, sin(angle) * radius);
      }
    }
  }

  for (final node in nodes) {
    positions.putIfAbsent(
      node.key,
      () => Offset(
        (rng.nextDouble() - 0.5) * kEntityGraphNodeSpacing * 2,
        (rng.nextDouble() - 0.5) * kEntityGraphNodeSpacing * 2,
      ),
    );
  }

  return positions;
}

List<(String, String)> _uniqueNodePairs(List<EntityEdgeData> edges) {
  final pairs = <String, (String, String)>{};
  for (final edge in edges) {
    final pairKey = _undirectedPairKey(edge.sourceKey, edge.targetKey);
    pairs.putIfAbsent(pairKey, () => (edge.sourceKey, edge.targetKey));
  }
  return pairs.values.toList();
}

String _undirectedPairKey(String a, String b) {
  return a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
}

void _resolveNodeCollisions({
  required Map<String, Offset> positions,
  required List<EntityNodeData> nodes,
  required String? fixedKey,
  required double minDistance,
  required int seed,
}) {
  final rng = Random(seed + 7);
  for (var iter = 0; iter < 60; iter++) {
    var moved = false;
    for (var a = 0; a < nodes.length; a++) {
      for (var b = a + 1; b < nodes.length; b++) {
        final keyA = nodes[a].key;
        final keyB = nodes[b].key;
        var delta = positions[keyA]! - positions[keyB]!;
        var dist = sqrt(delta.dx * delta.dx + delta.dy * delta.dy);
        if (dist >= minDistance) {
          continue;
        }
        if (dist < 0.01) {
          final angle = rng.nextDouble() * 2 * pi;
          delta = Offset(cos(angle), sin(angle));
          dist = 0.01;
        }
        final push = (minDistance - dist) / 2;
        final norm = delta / dist;
        if (keyA != fixedKey) {
          positions[keyA] = positions[keyA]! + norm * push;
          moved = true;
        }
        if (keyB != fixedKey) {
          positions[keyB] = positions[keyB]! - norm * push;
          moved = true;
        }
      }
    }
    if (!moved) {
      break;
    }
  }
}

/// 节点与标签的轴对齐包围盒（以节点中心为锚点）。
Rect entityGraphNodeBounds(Offset center, {required bool includeLabels}) {
  return Rect.fromLTRB(
    center.dx - kEntityGraphNodeWidgetWidth / 2,
    center.dy - kEntityGraphNodeTotalSize / 2,
    center.dx + kEntityGraphNodeWidgetWidth / 2,
    center.dy +
        kEntityGraphNodeTotalSize / 2 +
        (includeLabels ? kEntityGraphNodeLabelExtent : 0),
  );
}

Rect computeEntityGraphContentBounds(
  Map<String, Offset> positions, {
  required bool includeLabels,
}) {
  if (positions.isEmpty) {
    return Rect.zero;
  }
  var bounds = entityGraphNodeBounds(
    positions.values.first,
    includeLabels: includeLabels,
  );
  for (final pos in positions.values.skip(1)) {
    bounds = bounds.expandToInclude(
      entityGraphNodeBounds(pos, includeLabels: includeLabels),
    );
  }
  return bounds;
}

double entityGraphNodeClipRadius({required bool includeLabels}) {
  if (!includeLabels) {
    return kEntityGraphNodeTotalSize / 2;
  }
  return kEntityGraphNodeTotalSize / 2 + 12;
}
