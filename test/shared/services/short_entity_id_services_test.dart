// 职责: 验证普通作品资源创建入口统一使用短 ID，并避开软删除与同批身份。
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/services/documents_service.dart
//   lib/shared/services/maps_service.dart
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/utils/short_entity_id.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';

void main() {
  late NovelContentDatabase database;

  setUp(() {
    database = NovelContentDatabase.forTest(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'mixed IDs keep chapter, foreshadowing, relation and canvas links',
    () async {
      const oldVolumeId = 'volume_aBcD0123456789XY';
      const oldChapterId = 'chapter_aBcD0123456789XY';
      const oldCharacterId = 'character_aBcD0123456789XY';
      await database
          .into(database.chapters)
          .insert(
            ChaptersCompanion.insert(
              id: oldVolumeId,
              type: nodeTypeVolume,
              siblingOrder: 1,
            ),
          );
      await database
          .into(database.chapters)
          .insert(
            ChaptersCompanion.insert(
              id: oldChapterId,
              type: nodeTypeChapter,
              siblingOrder: 1,
              parentId: const Value(oldVolumeId),
            ),
          );
      await database
          .into(database.characterProfiles)
          .insert(
            CharacterProfilesCompanion.insert(id: oldCharacterId, name: '历史角色'),
          );
      final service = NovelContentService(
        database,
        idBuilder: _countingIdBuilder(),
      );
      final chapterId = await service.createChapter(
        siblingOrder: 2,
        title: '新章节',
        parentId: oldVolumeId,
      );
      final characterId = await service.createCharacterProfile(name: '新角色');
      final foreshadowingId = await service.createForeshadowing(
        title: '跨章伏笔',
        setupChapterId: oldChapterId,
        payoffChapterId: chapterId,
      );
      final relationId = await service.entityRelationsService.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: oldCharacterId,
        targetType: entityTypeCharacter,
        targetId: characterId,
        relationType: characterRelationFriend,
        chapterId: chapterId,
      );
      final canvasId = await service.canvasService.createCanvas(name: '混合引用');
      for (final id in [oldCharacterId, characterId]) {
        await service.canvasService.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeCharacter,
          refId: id,
          x: 0,
          y: 0,
        );
      }
      expect((await service.getChapterById(chapterId))!.parentId, oldVolumeId);
      final foreshadowing = (await service.getForeshadowingById(
        foreshadowingId,
      ))!;
      expect(foreshadowing.setupChapterId, oldChapterId);
      expect(foreshadowing.payoffChapterId, chapterId);
      final relation = (await service.entityRelationsService.getRelationById(
        relationId,
      ))!;
      expect(relation.sourceId, oldCharacterId);
      expect(relation.targetId, characterId);
      expect(relation.chapterId, chapterId);
      final nodes = await database.select(database.canvasNodes).get();
      expect(
        nodes.map((row) => row.refId),
        unorderedEquals([oldCharacterId, characterId]),
      );
    },
  );

  test('ordinary resource create entry points use business prefixes', () async {
    final service = NovelContentService(
      database,
      idBuilder: _countingIdBuilder(),
    );

    expect(
      await service.createChapter(siblingOrder: 1, title: '正文'),
      startsWith('chp_'),
    );
    expect(
      await service.createChapter(
        siblingOrder: 2,
        title: '番外',
        type: nodeTypeExtra,
      ),
      startsWith('ext_'),
    );
    expect(await service.createVolume(title: '第一卷'), startsWith('vol_'));
    expect(
      await service.createCharacterProfile(name: '角色'),
      startsWith('cha_'),
    );
    expect(await service.createForeshadowing(title: '伏笔'), startsWith('fsh_'));
    expect(
      await service.locationsService.createLocation(name: '地点'),
      startsWith('loc_'),
    );

    for (final entry in [
      (type: entityTypeSkill, prefix: 'ski_'),
      (type: entityTypeItem, prefix: 'itm_'),
      (type: entityTypeFaction, prefix: 'fac_'),
      (type: entityTypeCreature, prefix: 'cre_'),
    ]) {
      expect(
        await service.createItem(type: entry.type, title: entry.type),
        startsWith(entry.prefix),
      );
    }

    expect(
      await service.documentsService.createDocument(
        type: documentTypeLore,
        title: 'lore doc',
      ),
      startsWith('lrd_'),
    );
    expect(
      await service.documentsService.createFolder(
        type: documentTypeLore,
        title: 'lore folder',
      ),
      startsWith('lrf_'),
    );
    expect(
      await service.documentsService.createDocument(
        type: documentTypeMaterial,
        title: 'material doc',
      ),
      startsWith('mtd_'),
    );
    expect(
      await service.documentsService.createFolder(
        type: documentTypeMaterial,
        title: 'material folder',
      ),
      startsWith('mtf_'),
    );
    expect(
      await service.entityRelationsService.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'source',
        targetType: entityTypeCharacter,
        targetId: 'target',
        relationType: characterRelationFriend,
      ),
      startsWith('rel_'),
    );
  });

  test(
    'soft-deleted identity is skipped instead of restored or overwritten',
    () async {
      final now = DateTime.now();
      await database
          .into(database.characterProfiles)
          .insert(
            CharacterProfilesCompanion.insert(
              id: 'cha_AAAAAA',
              name: '旧角色',
              deletedAt: Value(now),
            ),
          );
      final candidates = ['cha_AAAAAA', 'cha_BBBBBB'];
      var cursor = 0;
      final service = NovelContentService(
        database,
        idBuilder: (_) => candidates[cursor++],
      );

      final id = await service.createCharacterProfile(name: '新角色');

      expect(id, 'cha_BBBBBB');
      final tombstone = await (database.select(
        database.characterProfiles,
      )..where((table) => table.id.equals('cha_AAAAAA'))).getSingle();
      expect(tombstone.name, '旧角色');
      expect(tombstone.deletedAt, isNot(notDeletedSentinel));
    },
  );

  test(
    'batch document creation rejects repeated candidates in the same batch',
    () async {
      final candidates = ['lrd_AAAAAA', 'lrd_AAAAAA', 'lrd_BBBBBB'];
      var cursor = 0;
      final service = NovelContentService(
        database,
        idBuilder: (_) => candidates[cursor++],
      );

      final ids = await service.documentsService.createDocuments(
        type: documentTypeLore,
        entries: const [
          (title: '甲', content: '', category: ''),
          (title: '乙', content: '', category: ''),
        ],
      );

      expect(ids, ['lrd_AAAAAA', 'lrd_BBBBBB']);
      expect(
        await service.documentsService.getDocumentsByType(documentTypeLore),
        hasLength(2),
      );
    },
  );

  test(
    'copied text imports allocate final volume links after batch collisions',
    () async {
      final candidates = [
        'vol_AAAAAA',
        'chp_AAAAAA',
        'chp_AAAAAA',
        'chp_BBBBBB',
        'vol_AAAAAA',
        'vol_BBBBBB',
        'chp_BBBBBB',
        'chp_CCCCCC',
      ];
      var cursor = 0;
      final service = NovelContentService(
        database,
        idBuilder: (_) => candidates[cursor++],
      );
      await service.replaceChaptersForImport(const [
        ImportedChapterNode(title: '甲', content: '原文甲', volumeTitle: '卷甲'),
        ImportedChapterNode(title: '乙', content: '原文乙', volumeTitle: '卷甲'),
        ImportedChapterNode(title: '丙', content: '原文丙', volumeTitle: '卷乙'),
      ]);
      final rows = await service.getChapters();
      expect(rows.map((row) => row.id), [
        'vol_AAAAAA',
        'chp_AAAAAA',
        'chp_BBBBBB',
        'vol_BBBBBB',
        'chp_CCCCCC',
      ]);
      expect(rows[1].parentId, 'vol_AAAAAA');
      expect(rows[2].parentId, 'vol_AAAAAA');
      expect(rows[4].parentId, 'vol_BBBBBB');
      expect(rows.where((row) => row.isChapter).map((row) => row.content), [
        '原文甲',
        '原文乙',
        '原文丙',
      ]);
      expect(cursor, candidates.length);
    },
  );
}

ShortEntityIdBuilder _countingIdBuilder() {
  var counter = 0;
  return (type) {
    final suffix = counter.toRadixString(36).toUpperCase().padLeft(6, '0');
    counter += 1;
    return '${shortEntityIdPrefixes[type]}_$suffix';
  };
}
