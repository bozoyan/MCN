// 职责: 验证人工文档拆合场、撤销、并发基线与 AI 接管的原子事务。
// 关联文件:
//   lib/shared/services/screenplay_edit_orchestrator.dart
//   lib/shared/models/screenplay_document.dart
//   lib/shared/services/working_overlay.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/models/screenplay_document.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/screenplay_edit_orchestrator.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';

void main() {
  late NovelContentDatabase db;
  late AppDatabase app;
  late ScreenplayService service;
  late WorkingOverlayService overlay;
  late String episodeId;
  late String a;
  late String b;
  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    app = AppDatabase.forTest(NativeDatabase.memory());
    service = ScreenplayService(db);
    overlay = WorkingOverlayService(
      db,
      NovelContentService(db),
      novelActionsService: NovelActionsService(app),
    );
    final initial = await service.createInitialStructure();
    episodeId = initial.episodeId;
    final root = (await db.screenplayDao.getRoot())!;
    a = await service.createScene(
      screenplayId: root.id,
      episodeId: episodeId,
      timeLabel: 'night',
    );
    b = await service.createScene(
      screenplayId: root.id,
      episodeId: episodeId,
      synopsis: 'B synopsis',
    );
    for (final id in [a, b]) {
      await service.writeElements(
        sceneId: id,
        elements: [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: id == a ? 'beforeafter' : 'second',
          ),
        ],
      );
    }
  });
  tearDown(() async {
    await db.close();
    await app.close();
  });
  Future<ScreenplayDocument> save(
    ScreenplayDocument old,
    ScreenplayDocument next,
  ) async => (await ScreenplayEditOrchestrator().save(
    database: db,
    service: service,
    overlay: overlay,
    baseline: old,
    target: next,
  )).document;

  for (final kind in ['character', 'location']) {
    test(
      'editor saves and reopens after rollback leaves a missing $kind',
      () async {
        final content = NovelContentService(db);
        late String id;
        if (kind == 'character') {
          id = await content.createCharacterProfile(name: 'Role');
          await service.writeElements(
            sceneId: a,
            elements: [
              ScreenplayElement(
                type: ScreenplayElementType.character,
                characterId: id,
              ),
              const ScreenplayElement(
                type: ScreenplayElementType.dialogue,
                text: 'Before',
              ),
            ],
          );
        } else {
          id = await content.locationsService.createLocation(name: 'Place');
          await service.updateScene(sceneId: a, locationId: Value(id));
        }
        final resourceType = kind == 'character' ? 'characters' : 'locations';
        final created = await overlay.stageCreateChange(
          resourcePath: '/$resourceType/$id',
          resourceType: resourceType,
          resourceId: id,
          previewText: 'Created',
          source: workingChangeSourceAi,
        );
        await overlay.rollbackChange(created.id);
        final baseline = await service.readDocument(episodeId);
        final last = baseline.sceneElements(a).last.id;
        final target = baseline.withBodyEdits([
          for (final e in baseline.elements)
            e.id == last ? e.copyWith(text: 'Edited after rollback') : e,
        ]);
        await save(baseline, target);
        final reloaded = await ScreenplayService(db).readDocument(episodeId);
        expect(reloaded.sceneElements(a).last.text, 'Edited after rollback');
        if (kind == 'character') {
          expect(reloaded.sceneElements(a)[1].characterId, id);
          expect(
            reloaded.sceneElements(a).last.type,
            ScreenplayElementType.dialogue,
          );
          final replacement = await content.createCharacterProfile(
            name: 'Replacement',
          );
          final repaired = reloaded
              .withBodyEdits([
                for (final e in reloaded.elements)
                  e.characterId == id
                      ? e.copyWith(characterId: replacement)
                      : e,
              ])
              .copyWith(
                scenes: {
                  ...reloaded.scenes,
                  a: reloaded.scenes[a]!.withCast({replacement}),
                },
              );
          await save(reloaded, repaired);
          expect((await service.readDocument(episodeId)).scenes[a]!.cast, {
            replacement,
          });
        } else {
          expect(reloaded.sceneElements(a).first.locationId, id);
          final replacement = await content.locationsService.createLocation(
            name: 'Replacement',
          );
          await save(
            reloaded,
            reloaded.copyWith(
              elements: [
                for (final e in reloaded.elements)
                  e.sceneId == a && e.isHeading
                      ? e.copyWith(locationId: replacement)
                      : e,
              ],
            ),
          );
          expect(
            (await service.readDocument(
              episodeId,
            )).sceneElements(a).first.locationId,
            replacement,
          );
        }
      },
    );
  }

  test(
    'location overwrite migrates scene, map, children and relation references',
    () async {
      final content = NovelContentService(db);
      final locations = content.locationsService;
      final winner = await locations.createLocation(name: 'Old');
      final change = await overlay.stageTextChange(
        resourcePath: '/locations/$winner/name',
        resourceType: 'locations',
        resourceId: winner,
        field: 'name',
        oldText: 'Old',
        newText: 'New',
        source: workingChangeSourceAi,
      );
      final loser = await locations.createLocation(name: 'Old');
      final child = await locations.createLocation(
        name: 'Child',
        parentId: loser,
      );
      await service.updateScene(sceneId: a, locationId: Value(loser));
      await db
          .into(db.novelMaps)
          .insert(
            NovelMapsCompanion.insert(
              id: 'map',
              name: 'Map',
              locationId: Value(loser),
            ),
          );
      await db
          .into(db.mapLocations)
          .insert(
            MapLocationsCompanion.insert(
              id: 'pin',
              mapId: 'map',
              locationId: loser,
            ),
          );
      await db
          .into(db.entityRelations)
          .insert(
            EntityRelationsCompanion.insert(
              id: 'relation',
              sourceType: entityTypeLocation,
              sourceId: loser,
              targetType: entityTypeCharacter,
              targetId: 'character',
              relationType: 'legacy',
            ),
          );
      await overlay.rollbackChange(change.id);
      expect(await locations.getLocationById(loser), isNull);
      expect((await locations.getLocationById(child))!.parentId, winner);
      expect((await db.screenplayDao.getScene(a))!.locationId, winner);
      expect((await db.select(db.novelMaps).getSingle()).locationId, winner);
      expect((await db.select(db.mapLocations).getSingle()).locationId, winner);
      expect(
        (await db.select(db.entityRelations).getSingle()).sourceId,
        winner,
      );
      final baseline = await service.readDocument(episodeId);
      await save(
        baseline,
        baseline.withBodyEdits([
          for (final e in baseline.elements)
            e.sceneId == a && !e.isHeading
                ? e.copyWith(text: 'still editable')
                : e,
        ]),
      );
      expect(
        (await db.screenplayDao.getElementRows(a)).last.textContent,
        'still editable',
      );
    },
  );

  test(
    'new scene collision never takes over an unrelated active AI change',
    () async {
      final root = (await db.screenplayDao.getRoot())!;
      final episode = (await db.screenplayDao.getEpisode(episodeId))!;
      final otherEpisode = await service.createEpisode(
        seasonId: episode.seasonId,
      );
      final otherScene = await service.createScene(
        screenplayId: root.id,
        episodeId: otherEpisode,
      );
      final change = await overlay.stageTextChange(
        resourcePath: 'scenes/$otherScene/title',
        resourceType: workingChangeResourceTypeScreenplayScenes,
        resourceId: otherScene,
        field: 'title',
        oldText: '',
        newText: 'unrelated AI title',
        source: workingChangeSourceAi,
        sourceSessionId: 'other-session',
      );
      final baseline = await service.readDocument(episodeId);
      final split = baseline.split(
        ScreenplayPosition(baseline.sceneElements(a).last.id!, 6),
      );
      final target = split
          .remapIdentities({split.newSceneIds.single: otherScene}, const {})
          .copyWith(newSceneIds: {otherScene});
      service = ScreenplayService(
        db,
        idBuilder: (type) {
          expect(type, ShortEntityIdType.screenplayScene);
          return 'scn_000099';
        },
      );
      final saved = await save(baseline, target);
      expect(saved.sceneOrder, [a, 'scn_000099', b]);
      expect(
        (await db.screenplayDao.getScene(otherScene))!.title,
        'unrelated AI title',
      );
      expect(
        (await db.workingChangeDao.getById(change.id))!.status,
        workingChangeStatusActive,
      );
      expect(
        (await db.screenplayDao.getDocumentElements(
          otherEpisode,
        )).single.sceneId,
        otherScene,
      );
    },
  );

  test(
    'manual scene properties survive saved undo and field history rollback',
    () async {
      final baseline = await service.readDocument(episodeId);
      final old = baseline.scenes[a]!;
      final next = baseline.copyWith(
        scenes: {
          ...baseline.scenes,
          a: ScreenplayDocumentScene(
            id: a,
            synopsis: old.synopsis,
            stage: old.stage,
            cast: old.cast,
            title: '追逐',
            emotion: ['紧张'],
            events: [
              {'title': '追赶', 'summary': '追赶来人'},
            ],
          ),
        },
      );
      final saved = await save(baseline, next);
      expect(saved.scenes[a]!.title, '追逐');
      final patches = await db.workingChangeDao.getByResource(
        'scenes/$a/title',
      );
      expect(patches, hasLength(1));
      expect(patches.single.source, workingChangeSourceManual);
      expect(patches.single.status, workingChangeStatusCommitted);
      await overlay.rollbackChange(patches.single.id);
      expect((await db.screenplayDao.getScene(a))!.title, '');
      expect((await db.screenplayDao.getScene(a))!.emotion, ['紧张']);
      final current = await service.readDocument(episodeId);
      await save(current, baseline);
      expect((await db.screenplayDao.getScene(a))!.events, isNull);
      expect(
        (await db.screenplayDao.getElementRows(a)).single.textContent,
        'beforeafter',
      );
    },
  );

  test(
    'split, saved undo and redo preserve scene and element identities',
    () async {
      final original = await service.readDocument(episodeId);
      final text = original.sceneElements(a).last;
      final split = original.split(ScreenplayPosition(text.id!, 6));
      final saved = await save(original, split);
      expect(saved.sceneOrder, hasLength(3));
      expect(saved.sceneElements(a).last.id, text.id);
      final newId = saved.sceneOrder[1];
      expect(saved.sceneElements(newId).first.timeLabel, 'night');
      expect(saved.sceneElements(newId).last.text, 'after');
      final undone = await save(saved, original);
      expect(
        sameScreenplayElements(undone.elements, original.elements),
        isTrue,
      );
      final redone = await save(undone, saved);
      expect(sameScreenplayElements(redone.elements, saved.elements), isTrue);
      expect(
        (await db.screenplayDao.getDocumentElements(
          episodeId,
        )).map((e) => e.id).toSet().length,
        saved.elements.length,
      );
    },
  );

  test(
    'merge archives metadata, restores evidence and retains moved body ID',
    () async {
      await db
          .into(db.entityRelations)
          .insert(
            EntityRelationsCompanion.insert(
              id: 'relation',
              sourceType: 'characters',
              sourceId: 'one',
              targetType: 'characters',
              targetId: 'two',
              relationType: 'knows',
              sceneId: Value(b),
            ),
          );
      final original = await service.readDocument(episodeId);
      final bodyId = original.sceneElements(b).last.id;
      final merged = await save(original, original.merge(b));
      expect(merged.sceneOrder, [a]);
      expect(merged.sceneElements(a).last.id, bodyId);
      expect(merged.evidence['relation'], isNull);
      final archived = await (db.select(
        db.screenplayScenes,
      )..where((t) => t.id.equals(b))).getSingle();
      expect(archived.synopsis, 'B synopsis');
      expect(archived.deletedAt, isNot(notDeletedSentinel));
      final restored = await save(merged, original);
      expect(restored.evidence['relation'], b);
      expect(
        sameScreenplayElements(restored.elements, original.elements),
        isTrue,
      );
    },
  );

  test('stale text fails without taking over AI proposals', () async {
    final old = await service.readDocument(episodeId);
    final ai = await overlay.stageCreateChange(
      resourcePath: '/scenes/$a',
      resourceType: 'screenplay_scenes',
      resourceId: a,
      previewText: 'AI',
      source: workingChangeSourceAi,
    );
    await service.writeElements(
      sceneId: a,
      elements: [old.sceneElements(a).last.copyWith(text: 'external')],
    );
    final draft = old.withBodyEdits([
      for (final e in old.elements)
        e.sceneId == a && !e.isHeading ? e.copyWith(text: 'local') : e,
    ]);
    await expectLater(
      save(old, draft),
      throwsA(
        isA<ScreenplayServiceException>().having(
          (e) => e.errorCode,
          'code',
          'stale_screenplay_edit',
        ),
      ),
    );
    expect(
      (await db.workingChangeDao.getById(ai.id))!.status,
      workingChangeStatusActive,
    );
    expect(
      (await db.screenplayDao.getElementRows(a)).single.textContent,
      'external',
    );
  });

  test(
    'actual dirty scene takeover excludes unchanged and externally edited scenes',
    () async {
      final old = await service.readDocument(episodeId);
      final ai = <String>[];
      for (final id in [a, b]) {
        ai.add(
          (await overlay.stageCreateChange(
            resourcePath: '/scenes/$id',
            resourceType: 'screenplay_scenes',
            resourceId: id,
            previewText: 'AI',
            source: workingChangeSourceAi,
          )).id,
        );
      }
      await service.writeElements(
        sceneId: b,
        elements: [old.sceneElements(b).last.copyWith(text: 'external B')],
      );
      final draft = old.withBodyEdits([
        for (final e in old.elements)
          e.sceneId == a && !e.isHeading ? e.copyWith(text: 'local A') : e,
      ]);
      await save(old, draft);
      expect(
        (await db.workingChangeDao.getById(ai.first))!.status,
        workingChangeStatusCommitted,
      );
      expect(
        (await db.workingChangeDao.getById(ai.last))!.status,
        workingChangeStatusActive,
      );
      expect(
        (await db.screenplayDao.getElementRows(b)).single.textContent,
        'external B',
      );
    },
  );

  test(
    'validation failure rolls back AI takeover and structural changes',
    () async {
      final old = await service.readDocument(episodeId);
      final ai = await overlay.stageCreateChange(
        resourcePath: '/scenes/$a',
        resourceType: 'screenplay_scenes',
        resourceId: a,
        previewText: 'AI',
        source: workingChangeSourceAi,
      );
      final split = old.split(
        ScreenplayPosition(old.sceneElements(a).last.id!, 3),
      );
      final invalid = split.copyWith(
        elements: [
          for (final e in split.elements)
            e.isHeading && !old.scenes.containsKey(e.sceneId)
                ? e.copyWith(locationId: 'missing')
                : e,
        ],
      );
      await expectLater(
        save(old, invalid),
        throwsA(isA<ScreenplayServiceException>()),
      );
      expect(
        sameScreenplayElements(
          (await service.readDocument(episodeId)).elements,
          old.elements,
        ),
        isTrue,
      );
      expect(
        (await db.workingChangeDao.getById(ai.id))!.status,
        workingChangeStatusActive,
      );
    },
  );
  test(
    'changed evidence invalidates a pending structural confirmation',
    () async {
      await db
          .into(db.entityRelations)
          .insert(
            EntityRelationsCompanion.insert(
              id: 'proof',
              sourceType: 'characters',
              sourceId: 'a',
              targetType: 'characters',
              targetId: 'b',
              relationType: 'knows',
              sceneId: Value(b),
              proof: const Value('original'),
            ),
          );
      final old = await service.readDocument(episodeId);
      await (db.update(db.entityRelations)..where((t) => t.id.equals('proof')))
          .write(const EntityRelationsCompanion(proof: Value('updated')));
      await expectLater(
        save(old, old.merge(b)),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (e) => e.errorCode,
            'code',
            'stale_screenplay_edit',
          ),
        ),
      );
      expect((await service.readDocument(episodeId)).sceneOrder, [a, b]);
    },
  );

  test(
    'header-only save updates one element without rewriting scene statistics',
    () async {
      final old = await service.readDocument(episodeId);
      await db.customStatement('CREATE TEMP TABLE writes (table_name TEXT)');
      await db.customStatement(
        "CREATE TEMP TRIGGER track_scene AFTER UPDATE ON screenplay_scenes BEGIN INSERT INTO writes VALUES ('scene'); END",
      );
      await db.customStatement(
        "CREATE TEMP TRIGGER track_element AFTER UPDATE ON screenplay_scene_elements BEGIN INSERT INTO writes VALUES ('element'); END",
      );
      await save(
        old,
        old.copyWith(
          elements: [
            old.elements.first.copyWith(timeLabel: 'dawn'),
            ...old.elements.skip(1),
          ],
        ),
      );
      expect(
        (await db.customSelect('SELECT table_name FROM writes').get()).map(
          (r) => r.read<String>('table_name'),
        ),
        ['element'],
      );
    },
  );

  test(
    'a new scene inserted inside a partial document invalidates a structural save',
    () async {
      final old = await service.readDocument(episodeId, sceneIds: {a, b});
      final root = (await db.screenplayDao.getRoot())!;
      final inserted = await service.createScene(
        screenplayId: root.id,
        episodeId: episodeId,
      );
      final full = await service.readDocument(episodeId);
      await save(full, full.moveBefore(inserted, b));
      await expectLater(
        save(old, old.merge(b)),
        throwsA(
          isA<ScreenplayServiceException>().having(
            (e) => e.errorCode,
            'code',
            'stale_screenplay_edit',
          ),
        ),
      );
    },
  );
  test(
    'saved undo of a deleted partial document restores its episode anchors',
    () async {
      final original = await service.readDocument(episodeId, sceneIds: {a});
      final empty = await save(original, original.deleteScenes({a}));
      expect((await service.readDocument(episodeId)).sceneOrder, [b]);
      await save(empty, original);
      expect((await service.readDocument(episodeId)).sceneOrder, [a, b]);
    },
  );
}
