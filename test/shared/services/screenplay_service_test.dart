// 职责: 验证剧本结构不变量、锚点移动、元素 reconcile 与派生统计。
// 关联文件:
//   lib/shared/services/screenplay_service.dart
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
//   lib/shared/models/screenplay_element.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/data-deletion.md

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/entity_relations_service.dart';
import 'package:reveric/shared/services/maps_service.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  late NovelContentDatabase db;
  late ScreenplayService service;
  late ScreenplayRow root;
  late CreatedSeason initial;

  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = ScreenplayService(db);
    initial = await service.createInitialStructure(plannedEpisodeCount: 8);
    root = (await db.screenplayDao.getRoot())!;
  });

  tearDown(() => db.close());

  test(
    'scene properties preserve body, validate input and support clearing',
    () async {
      final id = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        title: '东门遇险',
        interiorExterior: screenplayInteriorExterior,
        emotion: ['紧张', '警觉'],
        events: [
          {'title': '遇袭', 'summary': '来人堵住门口', 'state_change': '退路被截断'},
        ],
      );
      await service.writeElements(
        sceneId: id,
        elements: const [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: '从门外奔入门内。',
          ),
        ],
      );
      final original = await service.readDocument(initial.episodeId);
      final summary =
          (await db.screenplayDao.watchScenes(initial.episodeId).first).single;
      expect(summary.title, '东门遇险');
      expect(summary.emotion, ['紧张', '警觉']);
      expect(summary.interiorExterior, screenplayInteriorExterior);
      expect(original.scenes[id]!.events!.single['state_change'], '退路被截断');
      await expectLater(
        service.updateScene(
          sceneId: id,
          title: 'should not persist',
          events: const Value([
            {'title': '缺摘要'},
          ]),
        ),
        throwsA(isA<ScreenplayServiceException>()),
      );
      expect((await db.screenplayDao.getScene(id))!.title, '东门遇险');
      await service.updateScene(
        sceneId: id,
        title: '',
        emotion: const Value([]),
        events: const Value([]),
        interiorExterior: const Value(null),
      );
      final cleared = (await db.screenplayDao.getScene(id))!;
      expect(cleared.title, '');
      expect(cleared.emotion, isEmpty);
      expect(cleared.events, isEmpty);
      expect(
        (await db.screenplayDao.getElementRows(id)).single.textContent,
        '从门外奔入门内。',
      );
    },
  );

  test(
    'rejects invalid raw fields before normalization without changing content',
    () async {
      final sceneId = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      await service.writeElements(
        sceneId: sceneId,
        elements: const [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: 'Original',
          ),
        ],
      );
      const invalid = [
        ScreenplayElement(
          type: ScreenplayElementType.action,
          text: 'Changed',
          extension: 'VO',
        ),
        ScreenplayElement(
          type: ScreenplayElementType.action,
          text: 'Changed',
          characterId: ' ',
        ),
        ScreenplayElement(
          type: ScreenplayElementType.character,
          text: 'Illegal',
          characterId: 'person',
        ),
      ];
      for (final element in invalid) {
        await expectLater(
          service.writeElements(sceneId: sceneId, elements: [element]),
          throwsA(isA<ScreenplayElementValidationException>()),
        );
        await expectLater(
          db.screenplayDao.reconcileElements(
            sceneId: sceneId,
            elements: [element],
          ),
          throwsA(isA<ScreenplayElementValidationException>()),
        );
        expect(
          (await db.screenplayDao.getElementRows(sceneId)).single.textContent,
          'Original',
        );
      }
    },
  );

  test(
    'initializes one season and episode and protects last records',
    () async {
      final seasons = await db.screenplayDao.getSeasons(root.id);
      final episodes = await db.screenplayDao.getEpisodes(initial.seasonId);
      expect(seasons, hasLength(1));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.plannedEpisodeCount, 8);
      expect(episodes, hasLength(1));
      expect(episodes.single.episodeNumber, 1);

      expect(
        () => service.deleteSeason(initial.seasonId),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (error) => error.errorCode,
            'errorCode',
            'last_season_required',
          ),
        ),
      );
      expect(
        () => service.deleteEpisode(initial.episodeId),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (error) => error.errorCode,
            'errorCode',
            'last_episode_required',
          ),
        ),
      );
    },
  );

  test('soft deletes scene elements with their scene or episode', () async {
    final standaloneSceneId = await service.createScene(
      screenplayId: root.id,
      episodeId: initial.episodeId,
    );
    await service.writeElements(
      sceneId: standaloneSceneId,
      elements: const [
        ScreenplayElement(type: ScreenplayElementType.action, text: '独立场次。'),
      ],
    );

    await service.deleteScene(standaloneSceneId);

    final deletedStandaloneScene = await (db.select(
      db.screenplayScenes,
    )..where((table) => table.id.equals(standaloneSceneId))).getSingle();
    final deletedStandaloneElement =
        await (db.select(db.screenplaySceneElements)..where(
              (table) =>
                  table.sceneId.equals(standaloneSceneId) &
                  table.type.equals('action'),
            ))
            .getSingle();
    expect(deletedStandaloneScene.deletedAt, isNot(notDeletedSentinel));
    expect(deletedStandaloneElement.deletedAt, isNot(notDeletedSentinel));

    final episodeId = await service.createEpisode(seasonId: initial.seasonId);
    final nestedSceneId = await service.createScene(
      screenplayId: root.id,
      episodeId: episodeId,
    );
    await service.writeElements(
      sceneId: nestedSceneId,
      elements: const [
        ScreenplayElement(type: ScreenplayElementType.action, text: '分集场次。'),
      ],
    );

    await service.deleteEpisode(episodeId);

    final deletedEpisode = await (db.select(
      db.screenplayEpisodes,
    )..where((table) => table.id.equals(episodeId))).getSingle();
    final deletedNestedScene = await (db.select(
      db.screenplayScenes,
    )..where((table) => table.id.equals(nestedSceneId))).getSingle();
    final deletedNestedElement =
        await (db.select(db.screenplaySceneElements)..where(
              (table) =>
                  table.sceneId.equals(nestedSceneId) &
                  table.type.equals('action'),
            ))
            .getSingle();
    expect(deletedEpisode.deletedAt, isNot(notDeletedSentinel));
    expect(deletedNestedScene.deletedAt, isNot(notDeletedSentinel));
    expect(deletedNestedElement.deletedAt, isNot(notDeletedSentinel));
  });

  test(
    'renumbers seasons and moves episodes across seasons atomically',
    () async {
      final second = await service.createSeason(screenplayId: root.id);
      final third = await service.createSeason(screenplayId: root.id);
      await service.moveSeason(third.seasonId, 1);
      expect(
        (await db.screenplayDao.getSeasons(
          root.id,
        )).map((row) => (row.id, row.seasonNumber)),
        [(third.seasonId, 1), (initial.seasonId, 2), (second.seasonId, 3)],
      );

      final extra = await service.createEpisode(seasonId: initial.seasonId);
      await service.updateEpisode(
        episodeId: extra,
        targetSeasonId: second.seasonId,
        episodeNumber: 1,
      );
      expect(
        (await db.screenplayDao.getEpisodes(
          second.seasonId,
        )).map((row) => row.id),
        [extra, second.episodeId],
      );
      expect(
        (await db.screenplayDao.getEpisodes(
          second.seasonId,
        )).map((row) => row.episodeNumber),
        [1, 2],
      );
      expect(
        (await db.screenplayDao.getEpisodes(initial.seasonId)).single.id,
        initial.episodeId,
      );
    },
  );

  test('writes the episode outline as one whole document', () async {
    final episodeId = initial.episodeId;
    expect((await db.screenplayDao.getEpisode(episodeId))!.outline, '');

    await service.updateEpisodeOutline(
      episodeId: episodeId,
      outline: '## Logline\n\n林岚回山里的木屋等一个人。',
    );
    expect(
      (await db.screenplayDao.getEpisode(episodeId))!.outline,
      '## Logline\n\n林岚回山里的木屋等一个人。',
    );

    // 整段覆盖，不做部分合并。
    await service.updateEpisodeOutline(episodeId: episodeId, outline: '重写。');
    expect((await db.screenplayDao.getEpisode(episodeId))!.outline, '重写。');
  });

  test(
    'moves scenes by stable anchors and clears an out-of-episode beat',
    () async {
      final secondEpisode = await service.createEpisode(
        seasonId: initial.seasonId,
      );
      final beat = await service.createBeat(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        actNumber: 1,
      );
      final first = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        beatId: beat,
        synopsis: 'first',
      );
      final second = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        synopsis: 'second',
      );
      final anchor = await service.createScene(
        screenplayId: root.id,
        episodeId: secondEpisode,
        synopsis: 'anchor',
      );

      await service.moveSceneBefore(first, anchor);
      expect(
        (await db.screenplayDao.getSceneRows(
          secondEpisode,
        )).map((row) => row.id),
        [first, anchor],
      );
      expect((await db.screenplayDao.getScene(first))!.beatId, isNull);
      expect(
        (await db.screenplayDao.getSceneRows(
          initial.episodeId,
        )).map((row) => row.id),
        [second],
      );
    },
  );

  test('whole-screenplay scenes group and renumber per episode', () async {
    final secondEpisode = await service.createEpisode(
      seasonId: initial.seasonId,
    );
    final first = await service.createScene(
      screenplayId: root.id,
      episodeId: initial.episodeId,
      synopsis: 'first',
    );
    final second = await service.createScene(
      screenplayId: root.id,
      episodeId: initial.episodeId,
      synopsis: 'second',
    );
    final other = await service.createScene(
      screenplayId: root.id,
      episodeId: secondEpisode,
      synopsis: 'other',
    );

    final grouped = await db.screenplayDao
        .watchScenesOfScreenplay(root.id)
        .first;
    expect(grouped.keys.toSet(), {initial.episodeId, secondEpisode});
    expect(grouped[initial.episodeId]!.map((scene) => scene.id), [
      first,
      second,
    ]);
    expect(grouped[initial.episodeId]!.map((scene) => scene.sceneNumber), [
      1,
      2,
    ]);
    expect(grouped[secondEpisode]!.single.id, other);
    expect(grouped[secondEpisode]!.single.sceneNumber, 1);

    final episodes = await db.screenplayDao
        .watchEpisodesOfScreenplay(root.id)
        .first;
    expect(episodes.map((episode) => episode.id).toSet(), {
      initial.episodeId,
      secondEpisode,
    });
  });

  test(
    'reconciles elements without changing retained ids and updates cast',
    () async {
      await db
          .into(db.characterProfiles)
          .insert(
            CharacterProfilesCompanion.insert(id: 'character_1', name: '林默'),
          );
      final sceneId = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      final first = await service.writeElements(
        sceneId: sceneId,
        elements: const [
          ScreenplayElement(type: ScreenplayElementType.action, text: '雨夜。'),
          ScreenplayElement(
            type: ScreenplayElementType.character,
            characterId: 'character_1',
          ),
          ScreenplayElement(type: ScreenplayElementType.dialogue, text: '开始吧。'),
          ScreenplayElement(type: ScreenplayElementType.note, text: '稍后润色'),
        ],
      );
      final actionId = first.elements.first.id;
      final dialogueId = first.elements[2].id;
      expect(first.metrics.dialogueLineCount, 1);
      expect(first.metrics.pageEighths, greaterThan(0));
      expect(await db.screenplayDao.getSceneCharacters(sceneId), hasLength(1));

      var stableElements = first.elements;
      for (var attempt = 0; attempt < 10; attempt++) {
        stableElements = (await service.writeElements(
          sceneId: sceneId,
          elements: stableElements,
        )).elements;
        expect(
          stableElements.map((element) => element.id),
          first.elements.map((element) => element.id),
        );
      }
      expect(
        await (db.select(
          db.screenplaySceneElements,
        )..where((table) => table.sceneId.equals(sceneId))).get(),
        hasLength(5),
      );

      final second = await service.writeElements(
        sceneId: sceneId,
        elements: [
          first.elements.first.copyWith(text: '暴雨夜。'),
          first.elements[1],
          const ScreenplayElement(
            type: ScreenplayElementType.dialogue,
            text: '继续。',
          ),
        ],
      );
      expect(second.elements.first.id, actionId);
      expect(second.elements[1].id, first.elements[1].id);
      expect(second.elements[2].id, isNot(dialogueId));
      final rawOldDialogue = await (db.select(
        db.screenplaySceneElements,
      )..where((table) => table.id.equals(dialogueId!))).getSingle();
      expect(rawOldDialogue.deletedAt, isNot(notDeletedSentinel));
      final rowsAfterDelete = await (db.select(
        db.screenplaySceneElements,
      )..where((table) => table.sceneId.equals(sceneId))).get();
      expect(rowsAfterDelete, hasLength(6));
      expect(
        rowsAfterDelete.where((row) => row.type == 'scene_heading'),
        hasLength(1),
      );
      expect(
        rowsAfterDelete.where((row) => row.deletedAt != notDeletedSentinel),
        hasLength(2),
      );
    },
  );

  test(
    'appearance matrix stream refreshes from the shared cast rows',
    () async {
      await db
          .into(db.characterProfiles)
          .insert(
            CharacterProfilesCompanion.insert(
              id: 'character_matrix',
              name: '苏遥',
            ),
          );
      final beatId = await service.createBeat(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        actNumber: 1,
        title: '抉择',
      );
      final sceneId = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        beatId: beatId,
        synopsis: '苏遥决定离开。',
      );
      final refreshed = expectLater(
        db.screenplayDao.watchAppearanceMatrix(initial.episodeId),
        emitsThrough(
          isA<List<ScreenplayAppearanceMatrixRow>>().having(
            (rows) => rows.single.characterIds,
            'characterIds',
            ['character_matrix'],
          ),
        ),
      );
      final outlineRefreshed = expectLater(
        db.screenplayDao.watchOutline(initial.episodeId),
        emitsThrough(
          isA<List<ScreenplayOutlineEntry>>()
              .having(
                (rows) => rows.single.scene.synopsis,
                'synopsis',
                '苏遥决定离开。',
              )
              .having((rows) => rows.single.beatTitle, 'beatTitle', '抉择')
              .having((rows) => rows.single.characterIds, 'characterIds', [
                'character_matrix',
              ]),
        ),
      );

      await service.replaceCast(
        sceneId: sceneId,
        characterIds: const ['character_matrix'],
      );

      await refreshed;
      await outlineRefreshed;
    },
  );

  test(
    'rejects dialogue without a character and preserves stored elements',
    () async {
      final sceneId = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      expect(
        () => service.writeElements(
          sceneId: sceneId,
          elements: const [
            ScreenplayElement(
              type: ScreenplayElementType.dialogue,
              text: '无人台词',
            ),
          ],
        ),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (error) => error.errorCode,
            'errorCode',
            'dialogue_character_required',
          ),
        ),
      );
      expect(await db.screenplayDao.getElementRows(sceneId), isEmpty);
    },
  );

  test('rejects an unknown supplied element id without writing', () async {
    final sceneId = await service.createScene(
      screenplayId: root.id,
      episodeId: initial.episodeId,
    );
    expect(
      () => service.writeElements(
        sceneId: sceneId,
        elements: const [
          ScreenplayElement(
            id: 'element_unknown',
            type: ScreenplayElementType.action,
            text: '不应写入',
          ),
        ],
      ),
      throwsA(
        isA<ScreenplayServiceException>().having(
          (error) => error.errorCode,
          'errorCode',
          'invalid_element_ref',
        ),
      ),
    );
    expect(await db.screenplayDao.getElementRows(sceneId), isEmpty);
  });

  test(
    'screenplay evidence includes ended summaries and excludes hard-deleted relations',
    () async {
      final sceneId = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      final relations = EntityRelationsService(db);
      final id = await relations.createRelation(
        sourceType: 'character',
        sourceId: 'a',
        targetType: 'character',
        targetId: 'b',
        relationType: 'friend',
        status: 'ended',
        sceneId: sceneId,
      );
      await db.customStatement(
        "UPDATE entity_relations SET change_logs = '{}' WHERE id = ?",
        [id],
      );
      final document = await service.readDocument(initial.episodeId);
      expect(document.evidence[id], sceneId);
      expect(document.evidenceVersions[id], isNot(contains('changeLogs')));
      await relations.deleteRelation(id);
      expect(
        (await service.readDocument(
          initial.episodeId,
          evidenceIds: {id},
        )).evidence,
        isEmpty,
      );
    },
  );

  test(
    'scene evidence is exclusive and is cleared when its scene is deleted',
    () async {
      final sceneId = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      final relations = EntityRelationsService(db);
      final relationId = await relations.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'a',
        targetType: entityTypeCharacter,
        targetId: 'b',
        relationType: characterRelationFriend,
        sceneId: sceneId,
      );
      expect(
        (await relations.getRelationsForSceneEvidence(sceneId)).single.id,
        relationId,
      );
      expect(
        () => relations.correctCurrentFields(
          id: relationId,
          chapterId: const Value('chapter_1'),
        ),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (error) => error.errorCode,
            'errorCode',
            'mutually_exclusive_fields',
          ),
        ),
      );
      await service.deleteScene(sceneId);
      expect((await relations.getRelationById(relationId))!.sceneId, isNull);
      expect(
        (await relations.getRelationById(
          relationId,
        ))!.changeLogs.single.sceneId,
        sceneId,
      );
      final change = await relations.recordChange(
        id: relationId,
        relationType: 'enemy',
        proof: 'new',
        reason: 'new',
      );
      await relations.removeChange(
        id: relationId,
        snapshotId: change.changeId!,
      );
      expect((await relations.getRelationById(relationId))!.sceneId, isNull);
      expect(
        (await relations.getRelationById(
          relationId,
        ))!.changeLogs.single.sceneId,
        sceneId,
      );
    },
  );

  test(
    'blocks deleting characters and locations referenced by scenes',
    () async {
      await db
          .into(db.characterProfiles)
          .insert(
            CharacterProfilesCompanion.insert(id: 'character_used', name: '角色'),
          );
      await db
          .into(db.locations)
          .insert(LocationsCompanion.insert(id: 'location_used', name: '地点'));
      final sceneId = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        locationId: 'location_used',
      );
      await service.writeElements(
        sceneId: sceneId,
        elements: const [
          ScreenplayElement(
            type: ScreenplayElementType.character,
            characterId: 'character_used',
          ),
        ],
      );
      expect(
        () => NovelContentService(db).deleteCharacterProfile('character_used'),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (error) => error.errorCode,
            'errorCode',
            'entity_in_use',
          ),
        ),
      );
      expect(
        () => LocationsService(db).deleteLocation('location_used'),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (error) => error.errorCode,
            'errorCode',
            'entity_in_use',
          ),
        ),
      );

      final characterScenes = await NovelContentService(
        db,
      ).getCharacterScreenplayScenes('character_used');
      expect(characterScenes, hasLength(1));
      expect(characterScenes.single.sceneId, sceneId);
      expect(characterScenes.single.sources, contains('dialogue'));
      expect(characterScenes.single.seasonNumber, isNotNull);
      expect(characterScenes.single.episodeNumber, isNotNull);
      expect(characterScenes.single.sceneNumber, greaterThan(0));

      final locationScenes = await LocationsService(
        db,
      ).getScreenplaySceneReferences('location_used');
      expect(locationScenes, hasLength(1));
      expect(locationScenes.single.sceneId, sceneId);
      expect(locationScenes.single.sources, ['heading']);
    },
  );
}
