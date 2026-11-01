// 职责: 实体关系图数据模型 — 节点与边的可视化 DTO。
// 关联文件:
//   lib/shared/entity_graph/graph_widget.dart
//   lib/shared/entity_graph/data.dart
//   lib/shared/entity_graph/colors.dart
//   lib/shared/entity_graph/edge_painter.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart

import 'package:flutter/material.dart';

import 'colors.dart';

class EntityNodeData {
  const EntityNodeData({
    required this.key,
    required this.entityType,
    required this.entityId,
    required this.name,
    this.typeName,
    this.typeKey,
    this.avatarAssetId,
  });

  final String key;
  final String entityType;
  final String entityId;
  final String name;
  final String? typeName;

  /// 原始类型/角色键（如 `protagonist`），用于环色；展示文案走 [typeName]。
  final String? typeKey;
  final String? avatarAssetId;
}

class EntityEdgeData {
  const EntityEdgeData({
    required this.id,
    required this.sourceKey,
    required this.targetKey,
    required this.relationType,
    required this.label,
    required this.color,
    required this.category,
    required this.directed,
  });

  final String id;
  final String sourceKey;
  final String targetKey;
  final String relationType;
  final String label;
  final Color color;
  final RelationCategory category;
  final bool directed;
}
