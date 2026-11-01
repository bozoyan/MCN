// 职责: 验证实体类型组合允许的关系类型。
// 关联文件:
//   lib/shared/utils/entity_relation_types.dart
//   lib/shared/database/novel_content_database.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/utils/entity_relation_types.dart';

void main() {
  group('validRelationTypesFor', () {
    test('supports same-type relation groups used by entity selection', () {
      expect(
        validRelationTypesFor(entityTypeFaction, entityTypeFaction),
        factionRelationTypes,
      );
      expect(
        validRelationTypesFor(entityTypeSkill, entityTypeSkill),
        skillRelationTypes,
      );
      expect(
        validRelationTypesFor(entityTypeItem, entityTypeItem),
        itemRelationTypes,
      );
      expect(
        validRelationTypesFor(entityTypeCreature, entityTypeCreature),
        creatureRelationTypes,
      );
    });

    test('keeps unsupported combinations explicit', () {
      expect(
        validRelationTypesFor(entityTypeFaction, entityTypeSkill),
        isEmpty,
      );
    });
  });
}
