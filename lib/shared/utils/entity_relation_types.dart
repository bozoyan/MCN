// 职责: 查询端点类型组合允许的主要关系类型。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/services/ai/tools.dart
import '../database/novel_content_database.dart';

List<String> validRelationTypesFor(String sourceType, String targetType) {
  if (sourceType == entityTypeCharacter && targetType == entityTypeCharacter) {
    return characterRelationTypes;
  }
  if (sourceType == entityTypeCharacter && targetType == entityTypeFaction) {
    return characterFactionRelationTypes;
  }
  if (sourceType == entityTypeCharacter && targetType == entityTypeSkill) {
    return characterSkillRelationTypes;
  }
  if (sourceType == entityTypeCharacter && targetType == entityTypeItem) {
    return characterItemRelationTypes;
  }
  if (sourceType == entityTypeFaction && targetType == entityTypeFaction) {
    return factionRelationTypes;
  }
  if (sourceType == entityTypeSkill && targetType == entityTypeSkill) {
    return skillRelationTypes;
  }
  if (sourceType == entityTypeItem && targetType == entityTypeItem) {
    return itemRelationTypes;
  }
  if (sourceType == entityTypeCreature && targetType == entityTypeCreature) {
    return creatureRelationTypes;
  }
  return [];
}
