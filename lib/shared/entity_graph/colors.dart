// 职责: 实体关系图颜色映射 — 实体环色、关系分类枚举与分类边色。
// 关联文件:
//   lib/shared/entity_graph/graph_widget.dart
//   lib/shared/entity_graph/edge_painter.dart
//   lib/shared/entity_graph/data.dart
//   lib/shared/entity_graph/labels.dart
//   lib/shared/entity_graph/legend.dart
//   lib/shared/entity_graph/overview.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 关系语义分类 — 驱动边色、图例与概览环形图。单一分类来源。
enum RelationCategory {
  kin,
  bond,
  lover,
  enemy,
  master,
  faction,
  item,
  skill,
  alter,
  evolve,
  other,
}

/// 实体环色（节点头像外圈与图标底色）。
///
/// 人物按角色着色：主角 accent、反派 error。配角占图上大多数节点，
/// 用 textMuted 压下去，避免整张图被高饱和色淹没；次要再用更淡的 textSubtle。
Color entityGraphRingColor(
  String entityType,
  RevericColors colors, {
  String? typeKey,
}) {
  switch (typeKey) {
    case 'protagonist':
      return colors.accent;
    case 'antagonist':
      return colors.error;
    case 'supporting':
      return colors.textMuted;
    case 'minor':
      return colors.textSubtle;
    default:
      break;
  }
  switch (entityType) {
    case 'character':
      return colors.accent;
    case 'faction':
      return const Color(0xFF5B8DB8);
    case 'skill':
      return const Color(0xFF9B6FB0);
    case 'item':
      return colors.accentAmber;
    case 'location':
      return const Color(0xFF6BA07A);
    case 'chapter':
      return const Color(0xFF5A9E9E);
    case 'creature':
      return const Color(0xFFB07A5B);
    default:
      return colors.textSubtle;
  }
}

String entityGraphIcon(String entityType) {
  switch (entityType) {
    case 'character':
      return RevericIcons.person;
    case 'faction':
      return RevericIcons.group;
    case 'skill':
      return RevericIcons.auto_awesome;
    case 'item':
      return RevericIcons.inventory_2;
    case 'location':
      return RevericIcons.place;
    case 'chapter':
      return RevericIcons.book;
    case 'creature':
      return RevericIcons.bug_beetle_outlined;
    default:
      return RevericIcons.help_outline;
  }
}

/// 关系类型 → 语义分类。[sourceType]/[targetType] 仅用于消歧同名关系
/// （如 `creator` 在 skill 与 item 语境下分属不同分类）。
RelationCategory relationCategory(
  String relationType, {
  String? sourceType,
  String? targetType,
}) {
  switch (relationType) {
    case 'family':
    case 'parent':
    case 'sibling':
    case 'grandparent':
      return RelationCategory.kin;
    case 'lover':
      return RelationCategory.lover;
    case 'enemy':
    case 'prey':
    case 'predator':
      return RelationCategory.enemy;
    case 'master_disciple':
      return RelationCategory.master;
    case 'alter_ego':
      return RelationCategory.alter;
    case 'friend':
    case 'colleague':
    case 'ally':
      return RelationCategory.bond;
    case 'prerequisite':
    case 'evolves_to':
    case 'branch':
      return RelationCategory.evolve;
    case 'member':
    case 'leader':
    case 'founder':
    case 'subordinate':
      return RelationCategory.faction;
    case 'learned':
    case 'mastering':
    case 'mastered':
      return RelationCategory.skill;
    case 'owner':
    case 'user':
    case 'former_owner':
      return RelationCategory.item;
    case 'creator':
      if (sourceType == 'skill' || targetType == 'skill') {
        return RelationCategory.skill;
      }
      if (sourceType == 'item' || targetType == 'item') {
        return RelationCategory.item;
      }
      return RelationCategory.other;
    default:
      return RelationCategory.other;
  }
}

/// 分类 → 边色（取自 mockup 固定品牌调色板，不随主题变化）。
Color relationCategoryColor(RelationCategory category) {
  switch (category) {
    case RelationCategory.kin:
      return const Color(0xFFD4845A);
    case RelationCategory.bond:
      return const Color(0xFF6BA07A);
    case RelationCategory.lover:
      return const Color(0xFFD48BA0);
    case RelationCategory.enemy:
      return const Color(0xFFC25B5B);
    case RelationCategory.master:
      return const Color(0xFF9B6FB0);
    case RelationCategory.faction:
      return const Color(0xFF5B8DB8);
    case RelationCategory.item:
      return const Color(0xFFD4A45A);
    case RelationCategory.skill:
      return const Color(0xFF9B6FB0);
    case RelationCategory.alter:
      return const Color(0xFF5A9E9E);
    case RelationCategory.evolve:
      return const Color(0xFF5A9E9E);
    case RelationCategory.other:
      return const Color(0xFF9E9484);
  }
}

/// 关系类型 → 边色。无端点消歧时 `creator` 归入 other；图内边色以
/// [buildEntityGraphEdges] 中带消歧的分类为准。保留给非图调用方（关系编辑卡片）。
Color getRelationColor(String relationType) {
  return relationCategoryColor(relationCategory(relationType));
}
