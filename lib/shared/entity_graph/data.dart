// 职责: 实体关系图数据组装 — 关系筛选、节点/边构建、默认中心节点解析、中心统计与分类聚合。
// 关联文件:
//   lib/shared/entity_graph/models.dart
//   lib/shared/entity_graph/labels.dart
//   lib/shared/entity_graph/colors.dart
//   lib/shared/entity_graph/legend.dart
//   lib/shared/entity_graph/overview.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart
//   lib/shared/database/novel_content_database.dart

import 'package:flutter/widgets.dart';

import '../database/novel_content_database.dart';
import 'colors.dart';
import 'labels.dart';
import 'models.dart';

/// 关系图工具栏可筛选的实体类型（不含章节、伏笔、地点等无图谱节点类型）。
const List<String> kEntityGraphFilterableEntityTypes = <String>[
  entityTypeCharacter,
  entityTypeFaction,
  entityTypeSkill,
  entityTypeItem,
  entityTypeCreature,
];

/// 关系图默认仅展示人物之间的关系。
const Set<String> kEntityGraphDefaultEntityTypeFilter = {entityTypeCharacter};

String entityGraphEntityKey(String entityType, String entityId) {
  return '${entityType}_$entityId';
}

String entityGraphKeyFromRelationEnd({
  required String type,
  required String id,
}) {
  return entityGraphEntityKey(type, id);
}

Map<String, String> buildEntityGraphNameMap({
  required List<CharacterProfile> characters,
  required List<Item> factions,
  required List<Item> skills,
  required List<Item> items,
  required List<Item> creatures,
}) {
  final map = <String, String>{};
  for (final c in characters) {
    map[entityGraphEntityKey(entityTypeCharacter, c.id)] = c.name;
  }
  for (final f in factions) {
    map[entityGraphEntityKey(entityTypeFaction, f.id)] = f.title;
  }
  for (final s in skills) {
    map[entityGraphEntityKey(entityTypeSkill, s.id)] = s.title;
  }
  for (final i in items) {
    map[entityGraphEntityKey(entityTypeItem, i.id)] = i.title;
  }
  for (final c in creatures) {
    map[entityGraphEntityKey(entityTypeCreature, c.id)] = c.title;
  }
  return map;
}

Map<String, String?> buildEntityGraphAvatarMap({
  required List<CharacterProfile> characters,
}) {
  final map = <String, String?>{};
  for (final c in characters) {
    map[entityGraphEntityKey(entityTypeCharacter, c.id)] = c.avatarAssetId;
  }
  return map;
}

Map<String, String> buildEntityGraphTypeNameMap({
  required List<CharacterProfile> characters,
  required List<Item> factions,
  required List<Item> skills,
  required List<Item> items,
  required List<Item> creatures,
}) {
  final map = <String, String>{};
  for (final c in characters) {
    map[entityGraphEntityKey(entityTypeCharacter, c.id)] = c.role;
  }
  for (final f in factions) {
    map[entityGraphEntityKey(entityTypeFaction, f.id)] = entityTypeFaction;
  }
  for (final s in skills) {
    map[entityGraphEntityKey(entityTypeSkill, s.id)] = entityTypeSkill;
  }
  for (final i in items) {
    map[entityGraphEntityKey(entityTypeItem, i.id)] = entityTypeItem;
  }
  for (final c in creatures) {
    map[entityGraphEntityKey(entityTypeCreature, c.id)] = entityTypeCreature;
  }
  return map;
}

Set<String> entityKeysInRelations(List<RelationSummary> relations) {
  final keys = <String>{};
  for (final relation in relations.where((r) => r.status == 'active')) {
    keys.add(
      entityGraphKeyFromRelationEnd(
        type: relation.sourceType,
        id: relation.sourceId,
      ),
    );
    keys.add(
      entityGraphKeyFromRelationEnd(
        type: relation.targetType,
        id: relation.targetId,
      ),
    );
  }
  return keys;
}

/// 可作为中心点的实体：出现在 [relations] 中且能解析出名称，按名称排序。
List<String> entityGraphCenterCandidateKeys({
  required List<RelationSummary> relations,
  required Map<String, String> nameMap,
}) {
  final keys = entityKeysInRelations(
    relations,
  ).where(nameMap.containsKey).toList();
  keys.sort((a, b) {
    final nameCmp = nameMap[a]!.compareTo(nameMap[b]!);
    if (nameCmp != 0) {
      return nameCmp;
    }
    return a.compareTo(b);
  });
  return keys;
}

/// 用户指定的中心优先；不在候选里则回退到默认中心。
String? resolveEffectiveCenterEntityKey({
  required String? overrideKey,
  required String? defaultKey,
  required List<String> candidateKeys,
}) {
  if (overrideKey != null && candidateKeys.contains(overrideKey)) {
    return overrideKey;
  }
  return defaultKey;
}

/// 默认视图中心：主角 → 图中首个角色 → 关系最多节点。
String? resolveDefaultCenterEntityKey({
  required List<CharacterProfile> characters,
  required List<RelationSummary> relations,
}) {
  final graphKeys = entityKeysInRelations(relations);
  if (graphKeys.isEmpty) {
    return null;
  }

  String? firstCharacterKey;
  for (final character in characters) {
    final key = entityGraphEntityKey(entityTypeCharacter, character.id);
    if (!graphKeys.contains(key)) {
      continue;
    }
    if (character.role == characterRoleProtagonist) {
      return key;
    }
    firstCharacterKey ??= key;
  }
  if (firstCharacterKey != null) {
    return firstCharacterKey;
  }

  return _highestDegreeEntityKey(relations);
}

String? _highestDegreeEntityKey(List<RelationSummary> relations) {
  final degree = <String, int>{};
  for (final relation in relations.where((r) => r.status == 'active')) {
    final src = entityGraphKeyFromRelationEnd(
      type: relation.sourceType,
      id: relation.sourceId,
    );
    final tgt = entityGraphKeyFromRelationEnd(
      type: relation.targetType,
      id: relation.targetId,
    );
    degree[src] = (degree[src] ?? 0) + 1;
    degree[tgt] = (degree[tgt] ?? 0) + 1;
  }
  if (degree.isEmpty) {
    return null;
  }
  return degree.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// 仅保留两端实体类型均在 [entityTypes] 内的关系。
List<RelationSummary> filterRelationsByEntityTypes(
  List<RelationSummary> relations,
  Set<String> entityTypes,
) {
  if (entityTypes.isEmpty) {
    return const [];
  }
  return relations
      .where(
        (relation) =>
            relation.status == 'active' &&
            entityTypes.contains(relation.sourceType) &&
            entityTypes.contains(relation.targetType),
      )
      .toList();
}

/// 按 BFS 深度展开关系网。以 [selectedEntityKey] 或 [defaultCenterEntityKey] 为起点。
List<RelationSummary> filterEntityGraphRelations({
  required List<RelationSummary> allRelations,
  String? selectedEntityKey,
  String? defaultCenterEntityKey,
  required int depth,
  String? relationType,
  Set<String>? entityTypes,
}) {
  var relations = entityTypes == null
      ? allRelations.where((r) => r.status == 'active').toList()
      : filterRelationsByEntityTypes(allRelations, entityTypes);

  relations = relationType == null
      ? relations
      : relations
            .where((relation) => relation.relationType == relationType)
            .toList();

  final centerKey = selectedEntityKey ?? defaultCenterEntityKey;
  if (centerKey == null) {
    return relations;
  }

  final parts = centerKey.split('_');
  if (parts.length < 2) {
    return relations;
  }

  final visited = <String>{centerKey};
  final result = <RelationSummary>[];
  var currentKeys = <String>{centerKey};

  for (var d = 0; d < depth; d++) {
    final nextKeys = <String>{};
    for (final relation in relations.where((r) => r.status == 'active')) {
      final srcKey = entityGraphKeyFromRelationEnd(
        type: relation.sourceType,
        id: relation.sourceId,
      );
      final tgtKey = entityGraphKeyFromRelationEnd(
        type: relation.targetType,
        id: relation.targetId,
      );

      if (currentKeys.contains(srcKey) || currentKeys.contains(tgtKey)) {
        if (!result.any((r) => r.id == relation.id)) {
          result.add(relation);
        }
        if (!visited.contains(srcKey)) {
          visited.add(srcKey);
          nextKeys.add(srcKey);
        }
        if (!visited.contains(tgtKey)) {
          visited.add(tgtKey);
          nextKeys.add(tgtKey);
        }
      }
    }
    if (nextKeys.isEmpty) {
      break;
    }
    currentKeys = nextKeys;
  }

  return result;
}

List<RelationSummary> relationsForEntityKey(
  List<RelationSummary> allRelations,
  String key,
) {
  return allRelations.where((relation) {
    final srcKey = entityGraphKeyFromRelationEnd(
      type: relation.sourceType,
      id: relation.sourceId,
    );
    final tgtKey = entityGraphKeyFromRelationEnd(
      type: relation.targetType,
      id: relation.targetId,
    );
    return srcKey == key || tgtKey == key;
  }).toList();
}

List<EntityNodeData> buildEntityGraphNodes({
  required BuildContext context,
  required List<RelationSummary> relations,
  required Map<String, String> nameMap,
  required Map<String, String?> avatarMap,
  required Map<String, String> typeNameMap,
}) {
  final keys = entityKeysInRelations(relations);

  return keys.map((key) {
    final parts = key.split('_');
    final entityType = parts[0];
    final entityId = parts.sublist(1).join('_');
    final rawTypeName = typeNameMap[key] ?? entityType;

    return EntityNodeData(
      key: key,
      entityType: entityType,
      entityId: entityId,
      name: nameMap[key] ?? key,
      typeName: localizeEntityNodeTypeName(context, rawTypeName),
      typeKey: rawTypeName,
      avatarAssetId: avatarMap[key],
    );
  }).toList();
}

List<EntityEdgeData> buildEntityGraphEdges({
  required BuildContext context,
  required List<RelationSummary> relations,
  bool includeEdgeLabels = true,
}) {
  return relations.where((r) => r.status == 'active').map((relation) {
    final category = relationCategory(
      relation.relationType,
      sourceType: relation.sourceType,
      targetType: relation.targetType,
    );
    return EntityEdgeData(
      id: relation.id,
      sourceKey: entityGraphKeyFromRelationEnd(
        type: relation.sourceType,
        id: relation.sourceId,
      ),
      targetKey: entityGraphKeyFromRelationEnd(
        type: relation.targetType,
        id: relation.targetId,
      ),
      relationType: relation.relationType,
      label: includeEdgeLabels
          ? localizeRelationTypeLabel(
              context,
              relation.relationType,
              sourceType: relation.sourceType,
              targetType: relation.targetType,
            )
          : '',
      color: relationCategoryColor(category),
      category: category,
      directed: isRelationDirected(relation.relationType),
    );
  }).toList();
}

/// 关系类型是否为有向（source → target）。用于边的箭头渲染。
/// 与 mockup `directed: true` 集合一致。
bool isRelationDirected(String relationType) {
  switch (relationType) {
    case 'parent':
    case 'grandparent':
    case 'master_disciple':
    case 'subordinate':
    case 'creator':
    case 'prerequisite':
    case 'evolves_to':
    case 'prey':
    case 'predator':
      return true;
    default:
      return false;
  }
}

/// 中心节点的直接/间接关系数。direct = 一跳邻居数；
/// indirect = 两跳外不重复节点数（排除中心与直接邻居）。
({int direct, int indirect}) entityGraphCenterStats(
  List<EntityEdgeData> edges,
  String? centerKey,
) {
  if (centerKey == null) {
    return (direct: 0, indirect: 0);
  }
  final directNeighbors = <String>{};
  for (final edge in edges) {
    if (edge.sourceKey == centerKey) {
      directNeighbors.add(edge.targetKey);
    } else if (edge.targetKey == centerKey) {
      directNeighbors.add(edge.sourceKey);
    }
  }
  if (directNeighbors.isEmpty) {
    return (direct: 0, indirect: 0);
  }
  final indirect = <String>{};
  for (final edge in edges) {
    String? other;
    if (edge.sourceKey == centerKey || edge.targetKey == centerKey) {
      continue;
    }
    if (directNeighbors.contains(edge.sourceKey)) {
      other = edge.targetKey;
    } else if (directNeighbors.contains(edge.targetKey)) {
      other = edge.sourceKey;
    }
    if (other != null &&
        other != centerKey &&
        !directNeighbors.contains(other)) {
      indirect.add(other);
    }
  }
  return (direct: directNeighbors.length, indirect: indirect.length);
}

/// 按关系分类聚合计数，驱动图例与概览环形图。
Map<RelationCategory, int> relationCategoryCounts(List<EntityEdgeData> edges) {
  final counts = <RelationCategory, int>{};
  for (final edge in edges) {
    counts[edge.category] = (counts[edge.category] ?? 0) + 1;
  }
  return counts;
}

int entityGraphLayoutFingerprint({
  required List<EntityNodeData> nodes,
  required List<EntityEdgeData> edges,
  String? centerNodeKey,
  required int layoutGeneration,
}) {
  return Object.hash(
    layoutGeneration,
    centerNodeKey,
    Object.hashAll(nodes.map((n) => n.key)),
    Object.hashAll(edges.map((e) => e.id)),
  );
}
