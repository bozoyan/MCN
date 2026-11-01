// 职责: 实体关系图布局算法测试 — 验证节点最小间距与中心锚定。
// 关联文件:
//   lib/shared/entity_graph/layout.dart
//   lib/shared/entity_graph/constants.dart
//   lib/shared/entity_graph/models.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/entity_graph/colors.dart';
import 'package:reveric/shared/entity_graph/constants.dart';
import 'package:reveric/shared/entity_graph/layout.dart';
import 'package:reveric/shared/entity_graph/data.dart';
import 'package:reveric/shared/entity_graph/models.dart';

void main() {
  test('computeEntityGraphLayout keeps nodes separated around center', () {
    final nodes = <EntityNodeData>[
      const EntityNodeData(
        key: 'character_a',
        entityType: 'character',
        entityId: 'a',
        name: 'A',
      ),
      const EntityNodeData(
        key: 'character_b',
        entityType: 'character',
        entityId: 'b',
        name: 'B',
      ),
      const EntityNodeData(
        key: 'character_c',
        entityType: 'character',
        entityId: 'c',
        name: 'C',
      ),
      const EntityNodeData(
        key: 'faction_f1',
        entityType: 'faction',
        entityId: 'f1',
        name: 'Faction',
      ),
    ];
    final edges = <EntityEdgeData>[
      const EntityEdgeData(
        id: '1',
        sourceKey: 'character_a',
        targetKey: 'character_b',
        relationType: 'friend',
        label: 'friend',
        color: Colors.green,
        category: RelationCategory.bond,
        directed: false,
      ),
      const EntityEdgeData(
        id: '2',
        sourceKey: 'character_a',
        targetKey: 'character_c',
        relationType: 'friend',
        label: 'friend',
        color: Colors.green,
        category: RelationCategory.bond,
        directed: false,
      ),
      const EntityEdgeData(
        id: '3',
        sourceKey: 'character_a',
        targetKey: 'faction_f1',
        relationType: 'member',
        label: 'member',
        color: Colors.blue,
        category: RelationCategory.faction,
        directed: false,
      ),
    ];

    final positions = computeEntityGraphLayout(
      nodes: nodes,
      edges: edges,
      centerNodeKey: 'character_a',
    );

    expect(positions['character_a'], Offset.zero);

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = positions[nodes[i].key]!;
        final b = positions[nodes[j].key]!;
        final dist = (a - b).distance;
        expect(
          dist,
          greaterThanOrEqualTo(kEntityGraphMinNodeDistance * 0.85),
          reason: '${nodes[i].key} vs ${nodes[j].key}',
        );
      }
    }
  });

  test('entityGraphLayoutFingerprint tracks topology and generation', () {
    final nodes = <EntityNodeData>[
      const EntityNodeData(
        key: 'character_a',
        entityType: 'character',
        entityId: 'a',
        name: 'A',
      ),
    ];
    final edges = <EntityEdgeData>[
      const EntityEdgeData(
        id: '1',
        sourceKey: 'character_a',
        targetKey: 'character_b',
        relationType: 'friend',
        label: 'friend',
        color: Colors.green,
        category: RelationCategory.bond,
        directed: false,
      ),
    ];

    final base = entityGraphLayoutFingerprint(
      nodes: nodes,
      edges: edges,
      centerNodeKey: 'character_a',
      layoutGeneration: 0,
    );
    final relayout = entityGraphLayoutFingerprint(
      nodes: nodes,
      edges: edges,
      centerNodeKey: 'character_a',
      layoutGeneration: 1,
    );
    final moreEdges = entityGraphLayoutFingerprint(
      nodes: nodes,
      edges: [
        ...edges,
        const EntityEdgeData(
          id: '2',
          sourceKey: 'character_a',
          targetKey: 'character_c',
          relationType: 'friend',
          label: 'friend',
          color: Colors.green,
          category: RelationCategory.bond,
          directed: false,
        ),
      ],
      centerNodeKey: 'character_a',
      layoutGeneration: 0,
    );

    expect(relayout, isNot(equals(base)));
    expect(moreEdges, isNot(equals(base)));
  });
}
