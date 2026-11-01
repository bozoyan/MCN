// 职责: 实体关系图标签本地化 — 实体类型名/关系类型名/关系分类名翻译，桌面与移动端关系图共用一份。
// 关联文件:
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart
//   lib/shared/entity_graph/data.dart
//   lib/shared/entity_graph/colors.dart
//   lib/shared/entity_graph/legend.dart
//   lib/shared/entity_graph/overview.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
//   assets/translations/en/relation.json
//   assets/translations/zh-CN/relation.json
//   assets/translations/en/character.json
//   assets/translations/zh-CN/character.json
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
import 'package:flutter/widgets.dart';

import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import 'colors.dart';

/// 关系分类本地化展示 — 图例与概览环形图共用。
String localizeRelationCategoryLabel(
  BuildContext context,
  RelationCategory category,
) {
  switch (category) {
    case RelationCategory.kin:
      return context.t(LocaleKeys.entityGraphCategoryKin);
    case RelationCategory.bond:
      return context.t(LocaleKeys.entityGraphCategoryBond);
    case RelationCategory.lover:
      return context.t(LocaleKeys.entityGraphCategoryLover);
    case RelationCategory.enemy:
      return context.t(LocaleKeys.entityGraphCategoryEnemy);
    case RelationCategory.master:
      return context.t(LocaleKeys.entityGraphCategoryMaster);
    case RelationCategory.faction:
      return context.t(LocaleKeys.entityGraphCategoryFaction);
    case RelationCategory.item:
      return context.t(LocaleKeys.entityGraphCategoryItem);
    case RelationCategory.skill:
      return context.t(LocaleKeys.entityGraphCategorySkill);
    case RelationCategory.alter:
      return context.t(LocaleKeys.entityGraphCategoryAlter);
    case RelationCategory.evolve:
      return context.t(LocaleKeys.entityGraphCategoryEvolve);
    case RelationCategory.other:
      return context.t(LocaleKeys.entityGraphCategoryOther);
  }
}

/// 实体节点的类型名（含角色细分）本地化展示。
String localizeEntityNodeTypeName(BuildContext context, String typeName) {
  switch (typeName) {
    case entityTypeCharacter:
    case characterRoleProtagonist:
      return context.t(LocaleKeys.entityTypeCharacter);
    case characterRoleAntagonist:
      return context.t(LocaleKeys.characterRoleAntagonist);
    case characterRoleSupporting:
      return context.t(LocaleKeys.characterRoleSupporting);
    case characterRoleMinor:
      return context.t(LocaleKeys.characterRoleMinor);
    case entityTypeFaction:
      return context.t(LocaleKeys.entityTypeFaction);
    case entityTypeSkill:
      return context.t(LocaleKeys.entityTypeSkill);
    case entityTypeItem:
      return context.t(LocaleKeys.entityTypeItem);
    case entityTypeLocation:
      return context.t(LocaleKeys.entityTypeLocation);
    case entityTypeChapter:
      return context.t(LocaleKeys.entityTypeChapter);
    case entityTypeCreature:
      return context.t(LocaleKeys.entityTypeCreature);
    case entityTypeForeshadowing:
      return context.t(LocaleKeys.entityTypeForeshadowing);
    default:
      return typeName;
  }
}

/// 角色 [role] 字段（protagonist / antagonist 等）本地化展示。
String localizeCharacterRoleLabel(BuildContext context, String role) {
  switch (role) {
    case characterRoleProtagonist:
      return context.t(LocaleKeys.characterRoleProtagonist);
    case characterRoleAntagonist:
      return context.t(LocaleKeys.characterRoleAntagonist);
    case characterRoleSupporting:
      return context.t(LocaleKeys.characterRoleSupporting);
    case characterRoleMinor:
    case 'background':
      return context.t(LocaleKeys.characterRoleMinor);
    default:
      return role;
  }
}

/// 关系类型本地化展示。`sourceType`/`targetType` 用于消歧同名但语义不同的关系类型。
String localizeRelationTypeLabel(
  BuildContext context,
  String type, {
  String? sourceType,
  String? targetType,
}) {
  if (sourceType == entityTypeFaction && targetType == entityTypeFaction) {
    if (type == factionFactionSubordinate) {
      return context.t(LocaleKeys.relationFactionSubordinate);
    }
  }
  if (sourceType == entityTypeSkill && targetType == entityTypeSkill) {
    if (type == skillSkillPrerequisite) {
      return context.t(LocaleKeys.relationSkillPrerequisite);
    }
    if (type == skillSkillEvolvesTo) {
      return context.t(LocaleKeys.relationSkillEvolvesTo);
    }
    if (type == skillSkillBranch) {
      return context.t(LocaleKeys.relationSkillBranch);
    }
  }
  if (sourceType == entityTypeItem && targetType == entityTypeItem) {
    if (type == itemItemPartOf) {
      return context.t(LocaleKeys.relationItemPartOf);
    }
    if (type == itemItemEvolvesTo) {
      return context.t(LocaleKeys.relationItemEvolvesTo);
    }
  }
  if (sourceType == entityTypeCreature && targetType == entityTypeCreature) {
    if (type == creatureCreatureEvolvesTo) {
      return context.t(LocaleKeys.relationCreatureEvolvesTo);
    }
    if (type == creatureCreaturePrey) {
      return context.t(LocaleKeys.relationCreaturePrey);
    }
    if (type == creatureCreaturePredator) {
      return context.t(LocaleKeys.relationCreaturePredator);
    }
  }
  if (type == characterRelationFamily) {
    return context.t(LocaleKeys.relationCharacterFamily);
  }
  if (type == characterRelationParent) {
    return context.t(LocaleKeys.relationCharacterParent);
  }
  if (type == characterRelationSibling) {
    return context.t(LocaleKeys.relationCharacterSibling);
  }
  if (type == characterRelationGrandparent) {
    return context.t(LocaleKeys.relationCharacterGrandparent);
  }
  if (type == characterRelationFriend) {
    return context.t(LocaleKeys.relationCharacterFriend);
  }
  if (type == characterRelationEnemy) {
    return context.t(LocaleKeys.relationCharacterEnemy);
  }
  if (type == characterRelationLover) {
    return context.t(LocaleKeys.relationCharacterLover);
  }
  if (type == characterRelationMasterDisciple) {
    return context.t(LocaleKeys.relationCharacterMasterDisciple);
  }
  if (type == characterRelationColleague) {
    return context.t(LocaleKeys.relationCharacterColleague);
  }
  if (type == characterRelationSubordinate) {
    return context.t(LocaleKeys.relationCharacterSubordinate);
  }
  if (type == characterRelationAlterEgo) {
    return context.t(LocaleKeys.relationCharacterAlterEgo);
  }
  if (type == characterFactionMember) {
    return context.t(LocaleKeys.relationFactionMember);
  }
  if (type == characterFactionLeader) {
    return context.t(LocaleKeys.relationFactionLeader);
  }
  if (type == characterFactionFounder) {
    return context.t(LocaleKeys.relationFactionFounder);
  }
  if (type == characterFactionAlly) {
    return context.t(LocaleKeys.relationFactionAlly);
  }
  if (type == characterSkillLearned) {
    return context.t(LocaleKeys.relationSkillLearned);
  }
  if (type == characterSkillMastering) {
    return context.t(LocaleKeys.relationSkillMastering);
  }
  if (type == characterSkillMastered) {
    return context.t(LocaleKeys.relationSkillMastered);
  }
  if (type == characterSkillCreator) {
    return context.t(LocaleKeys.relationSkillCreator);
  }
  if (type == characterItemOwner) {
    return context.t(LocaleKeys.relationItemOwner);
  }
  if (type == characterItemUser) {
    return context.t(LocaleKeys.relationItemUser);
  }
  if (type == characterItemCreator) {
    return context.t(LocaleKeys.relationItemCreator);
  }
  if (type == characterItemFormerOwner) {
    return context.t(LocaleKeys.relationItemFormerOwner);
  }
  if (type == factionFactionSubordinate) {
    return context.t(LocaleKeys.relationFactionSubordinate);
  }
  if (type == skillSkillPrerequisite) {
    return context.t(LocaleKeys.relationSkillPrerequisite);
  }
  if (type == skillSkillEvolvesTo) {
    return context.t(LocaleKeys.relationEvolvesTo);
  }
  if (type == skillSkillBranch) {
    return context.t(LocaleKeys.relationSkillBranch);
  }
  if (type == itemItemPartOf) {
    return context.t(LocaleKeys.relationItemPartOf);
  }
  if (type == creatureCreaturePrey) {
    return context.t(LocaleKeys.relationCreaturePrey);
  }
  if (type == creatureCreaturePredator) {
    return context.t(LocaleKeys.relationCreaturePredator);
  }
  return type;
}
