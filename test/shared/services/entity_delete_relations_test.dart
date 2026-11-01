// 职责: 测试实体删除时在同一事务内级联清理 entity_relations
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/database/novel_content_database.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  late NovelContentDatabase db;
  late NovelContentService service;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = NovelContentService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('deleteEntityWithRelations', () {
    test(
      'deleteItem removes character-skill relations referencing the skill',
      () async {
        final characterId = await service.createCharacterProfile(name: '林默');
        final skillId = await service.createItem(
          type: entityTypeSkill,
          title: '万能生成器',
        );
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: characterId,
          targetType: entityTypeSkill,
          targetId: skillId,
          relationType: characterSkillMastered,
        );

        await service.deleteItem(skillId);

        expect(await service.getItemById(skillId), isNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteCharacterProfile removes relations where character is source or target',
      () async {
        final characterA = await service.createCharacterProfile(name: '甲');
        final characterB = await service.createCharacterProfile(name: '乙');
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: characterA,
          targetType: entityTypeCharacter,
          targetId: characterB,
          relationType: characterRelationFriend,
        );

        await service.deleteCharacterProfile(characterA);

        expect(await service.getCharacterProfileById(characterA), isNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteItem removes skill-skill relations for both endpoints',
      () async {
        final skillA = await service.createItem(
          type: entityTypeSkill,
          title: '基础技能',
        );
        final skillB = await service.createItem(
          type: entityTypeSkill,
          title: '进阶技能',
        );
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeSkill,
          sourceId: skillA,
          targetType: entityTypeSkill,
          targetId: skillB,
          relationType: skillSkillPrerequisite,
        );

        await service.deleteItem(skillA);

        expect(await service.getItemById(skillA), isNull);
        expect(await service.getItemById(skillB), isNotNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteChapter clears chapter_id references without deleting entity relations',
      () async {
        final chapterId = await service.createChapter(
          siblingOrder: 1,
          title: '第一章',
        );
        final characterA = await service.createCharacterProfile(name: '主角');
        final characterB = await service.createCharacterProfile(name: '分身');
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: characterA,
          targetType: entityTypeCharacter,
          targetId: characterB,
          relationType: characterRelationAlterEgo,
          chapterId: chapterId,
        );

        await service.deleteChapter(chapterId);

        expect(await service.getChapterById(chapterId), isNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, hasLength(1));
        expect(relations.single.chapterId, isNull);
      },
    );

    test(
      'deleteChapter on volume clears child chapter_id references before deleting nodes',
      () async {
        final volumeId = await service.createVolume(title: '第一卷');
        final chapterId = await service.createChapter(
          siblingOrder: 1,
          title: '卷内章节',
          parentId: volumeId,
        );
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: 'character_orphan_test',
          targetType: entityTypeCharacter,
          targetId: 'character_orphan_test_2',
          relationType: characterRelationFriend,
          chapterId: chapterId,
        );

        await service.deleteChapter(volumeId);

        expect(await service.getChapterById(volumeId), isNull);
        expect(await service.getChapterById(chapterId), isNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, hasLength(1));
        expect(relations.single.chapterId, isNull);
      },
    );

    test('deleteItem is a no-op when item does not exist', () async {
      await service.deleteItem('missing_skill_id');

      final relations = await service.entityRelationsService.getAllRelations();
      expect(relations, isEmpty);
    });

    test(
      'deleteItem removes character-faction relations referencing the faction',
      () async {
        final characterId = await service.createCharacterProfile(name: '成员');
        final factionId = await service.createItem(
          type: entityTypeFaction,
          title: '天机阁',
        );
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: characterId,
          targetType: entityTypeFaction,
          targetId: factionId,
          relationType: characterFactionMember,
        );

        await service.deleteItem(factionId);

        expect(await service.getItemById(factionId), isNull);
        expect(await service.getCharacterProfileById(characterId), isNotNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteItem removes faction-faction relations referencing the faction',
      () async {
        final factionA = await service.createItem(
          type: entityTypeFaction,
          title: '上级组织',
        );
        final factionB = await service.createItem(
          type: entityTypeFaction,
          title: '下级组织',
        );
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeFaction,
          sourceId: factionA,
          targetType: entityTypeFaction,
          targetId: factionB,
          relationType: factionFactionSubordinate,
        );

        await service.deleteItem(factionB);

        expect(await service.getItemById(factionB), isNull);
        expect(await service.getItemById(factionA), isNotNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteItem removes character-item relations referencing the item',
      () async {
        final characterId = await service.createCharacterProfile(name: '持有者');
        final itemId = await service.createItem(
          type: entityTypeItem,
          title: '古剑',
        );
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: characterId,
          targetType: entityTypeItem,
          targetId: itemId,
          relationType: characterItemOwner,
        );

        await service.deleteItem(itemId);

        expect(await service.getItemById(itemId), isNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteItem removes creature-creature relations referencing the creature',
      () async {
        final predatorId = await service.createItem(
          type: entityTypeCreature,
          title: '苍狼',
        );
        final preyId = await service.createItem(
          type: entityTypeCreature,
          title: '野兔',
        );
        await service.entityRelationsService.createRelation(
          sourceType: entityTypeCreature,
          sourceId: predatorId,
          targetType: entityTypeCreature,
          targetId: preyId,
          relationType: creatureCreaturePredator,
        );

        await service.deleteItem(preyId);

        expect(await service.getItemById(preyId), isNull);
        expect(await service.getItemById(predatorId), isNotNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteForeshadowing removes relations referencing the foreshadowing',
      () async {
        final foreshadowingId = await service.createForeshadowing(
          title: '失踪的钥匙',
        );
        await db
            .into(db.entityRelations)
            .insert(
              EntityRelationsCompanion.insert(
                id: 'legacy_setup',
                sourceType: entityTypeForeshadowing,
                sourceId: foreshadowingId,
                targetType: entityTypeCharacter,
                targetId: 'character_legacy',
                relationType: 'legacy_setup',
              ),
            );

        await service.deleteForeshadowing(foreshadowingId);

        expect(await service.getForeshadowingById(foreshadowingId), isNull);
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );

    test(
      'deleteLocation removes legacy location relations referencing the location',
      () async {
        final locationId = await service.locationsService.createLocation(
          name: '青云山',
          type: locationTypeWorld,
        );
        await db
            .into(db.entityRelations)
            .insert(
              EntityRelationsCompanion.insert(
                id: 'legacy_resides',
                sourceType: entityTypeCharacter,
                sourceId: 'character_legacy',
                targetType: entityTypeLocation,
                targetId: locationId,
                relationType: 'legacy_resides',
              ),
            );

        await service.locationsService.deleteLocation(locationId);

        expect(
          await service.locationsService.getLocationById(locationId),
          isNull,
        );
        final relations = await service.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );
  });
}
