// 职责: 验证关系生命周期、并发保护、当前摘要查询和图谱展开行为。
// 关联文件:
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/services/ai/tools_graph.dart

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reveric/shared/models/entity_relation_history.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/entity_relations_service.dart';

void main() {
  late NovelContentDatabase db;
  late EntityRelationsService service;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = EntityRelationsService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('lifecycle', () {
    var tick = DateTime.utc(2026, 9, 24, 10);
    Future<String> create({String? chapterId}) => service.createRelation(
      sourceType: 'character',
      sourceId: 'a',
      targetType: 'character',
      targetId: 'b',
      relationType: 'friend',
      proof: '初始完整依据',
      chapterId: chapterId,
    );
    Future<EntityRelation> read(String id) async =>
        (await service.getRelationById(id))!;
    Matcher code(String value) => throwsA(
      isA<RelationServiceException>().having((e) => e.code, 'code', value),
    );
    setUp(() {
      tick = DateTime.utc(2026, 9, 24, 10);
      service = EntityRelationsService(db, clock: () => tick);
    });
    test(
      'new baseline shares row time; friend enemy friend ended active retain identity and evidence',
      () async {
        final chapter = await NovelContentService(
          db,
        ).createChapter(siblingOrder: 1, title: '证据');
        final id = await create(chapterId: chapter);
        final initial = await read(id);
        expect(
          initial.changeLogs.single.recordedAt.isAtSameMomentAs(
            initial.createdAt,
          ),
          isTrue,
        );
        expect(initial.updatedAt, initial.createdAt);
        for (final state in [
          ('enemy', 'active'),
          ('friend', 'active'),
          ('friend', 'ended'),
          ('friend', 'active'),
        ]) {
          tick = tick.add(const Duration(seconds: 1));
          final result = await service.recordChange(
            id: id,
            relationType: state.$1,
            status: state.$2,
            proof: '依据 $state',
            reason: '原因 $state',
          );
          expect(result.relation.id, id);
          expect(result.historyAppended, isTrue);
          expect(result.relation.chapterId, isNull);
        }
        final row = await read(id);
        expect(row.changeLogs, hasLength(5));
        expect(row.changeLogs.first.chapterId, chapter);
        expect(row.changeLogs.first.proof, '初始完整依据');
      },
    );
    test(
      'legacy correction stays empty and first change freezes corrected old updated_at exactly once',
      () async {
        await db
            .into(db.entityRelations)
            .insert(
              EntityRelationsCompanion.insert(
                id: 'legacy',
                sourceType: 'character',
                sourceId: 'a',
                targetType: 'character',
                targetId: 'b',
                relationType: 'enemy',
                createdAt: Value(DateTime.utc(2000)),
                updatedAt: Value(DateTime.utc(2001)),
              ),
            );
        await service.correctCurrentFields(
          id: 'legacy',
          relationType: 'friend',
        );
        final corrected = await read('legacy');
        expect(corrected.changeLogs, isEmpty);
        tick = tick.add(const Duration(seconds: 30));
        await service.recordChange(
          id: 'legacy',
          relationType: 'enemy',
          proof: 'p',
          reason: 'r',
        );
        var row = await read('legacy');
        expect(
          row.changeLogs.first.recordedAt.isAtSameMomentAs(corrected.updatedAt),
          isTrue,
        );
        expect(row.changeLogs.first.relationType, 'friend');
        expect(row.changeLogs.last.recordedAt, tick);
        final baseline = row.changeLogs.first.id;
        await service.recordChange(
          id: 'legacy',
          relationType: 'friend',
          proof: 'p2',
          reason: 'r2',
        );
        row = await read('legacy');
        expect(row.changeLogs, hasLength(3));
        expect(row.changeLogs.first.id, baseline);
      },
    );
    test(
      'first legacy change uses original updated_at, never created_at or migration time',
      () async {
        await db
            .into(db.entityRelations)
            .insert(
              EntityRelationsCompanion.insert(
                id: 'unmodified-legacy',
                sourceType: 'character',
                sourceId: 'a',
                targetType: 'character',
                targetId: 'b',
                relationType: 'friend',
                createdAt: Value(DateTime.utc(2000)),
                updatedAt: Value(DateTime.utc(2001)),
              ),
            );
        final result = await service.recordChange(
          id: 'unmodified-legacy',
          relationType: 'enemy',
          proof: 'p',
          reason: 'r',
        );
        expect(result.relation.changeLogs.first.recordedAt, DateTime.utc(2001));
        expect(result.relation.changeLogs.last.recordedAt, tick);
      },
    );
    test(
      'concurrent distinct writes serialize; concurrent retries append only once',
      () async {
        final id = await create();
        await Future.wait([
          service.recordChange(
            id: id,
            relationType: 'enemy',
            proof: 'p1',
            reason: 'r1',
          ),
          service.recordChange(
            id: id,
            relationType: 'lover',
            proof: 'p2',
            reason: 'r2',
          ),
        ]);
        var row = await read(id);
        expect(row.changeLogs.map((s) => s.proof).toSet(), {
          '初始完整依据',
          'p1',
          'p2',
        });
        expect(row.relationType, row.changeLogs.last.relationType);
        final replies = await Future.wait(
          List.generate(
            2,
            (_) => service.recordChange(
              id: id,
              relationType: 'friend',
              proof: 'same',
              reason: 'same',
            ),
          ),
        );
        expect(replies.where((r) => r.changed), hasLength(1));
        row = await read(id);
        expect(row.changeLogs, hasLength(4));
      },
    );
    test('stale form cannot overwrite a same-snapshot correction', () async {
      final id = await create();
      final expected = await read(id);
      // Keep the clock fixed: field comparison must protect same-tick edits.
      await service.correctCurrentFields(id: id, proof: 'external correction');
      final current = await read(id);
      final stored =
          (await db
                  .customSelect(
                    'SELECT * FROM entity_relations WHERE id = ?',
                    variables: [Variable(id)],
                  )
                  .getSingle())
              .data;
      expect(current.updatedAt, expected.updatedAt);
      expect(current.changeLogs.single.id, expected.changeLogs.single.id);
      await expectLater(
        service.correctCurrentFields(
          id: id,
          proof: 'stale correction',
          expected: expected,
        ),
        code('relation_changed'),
      );
      await expectLater(
        service.recordChange(
          id: id,
          relationType: 'enemy',
          proof: 'stale change',
          reason: 'stale reason',
          expected: expected,
        ),
        code('relation_changed'),
      );
      expect(
        (await db
                .customSelect(
                  'SELECT * FROM entity_relations WHERE id = ?',
                  variables: [Variable(id)],
                )
                .getSingle())
            .data,
        stored,
      );
      final confirmed = await service.recordChange(
        id: id,
        relationType: 'enemy',
        proof: 'confirmed change',
        reason: 'confirmed reason',
        expected: current,
      );
      expect(confirmed.relation.changeLogs, hasLength(2));
      expect(confirmed.relation.changeLogs.first.proof, 'external correction');
    });
    test('two forms based on one state commit only one change', () async {
      final id = await create();
      final expected = await read(id);
      Future<Object> save(String type) async {
        try {
          return await service.recordChange(
            id: id,
            relationType: type,
            proof: 'proof $type',
            reason: 'reason $type',
            expected: expected,
          );
        } on RelationServiceException catch (error) {
          return error;
        }
      }

      final results = await Future.wait([save('enemy'), save('lover')]);
      expect(results.whereType<RelationMutationResult>(), hasLength(1));
      expect(
        results.whereType<RelationServiceException>().single.code,
        'relation_changed',
      );
      final current = await read(id);
      expect(current.changeLogs, hasLength(2));
      expect(current.relationType, current.changeLogs.last.relationType);
      expect(current.proof, current.changeLogs.last.proof);
    });
    test(
      'correction preserves metadata, earlier snapshots, omitted evidence and count',
      () async {
        final chapter = await NovelContentService(
          db,
        ).createChapter(siblingOrder: 1, title: '证据');
        final id = await create(chapterId: chapter);
        await service.recordChange(
          id: id,
          relationType: 'enemy',
          proof: '新依据',
          reason: '反目',
          chapterId: chapter,
        );
        final before = await read(id);
        final result = await service.correctCurrentFields(
          id: id,
          relationType: 'lover',
          status: 'ended',
          proof: '修正依据',
        );
        final after = result.relation;
        expect(result.historyAppended, isFalse);
        expect(after.changeLogs.length, before.changeLogs.length);
        expect(
          after.changeLogs.first.toJson(),
          before.changeLogs.first.toJson(),
        );
        final old = before.changeLogs.last;
        final latest = after.changeLogs.last;
        expect(
          (latest.id, latest.kind, latest.reason, latest.recordedAt),
          (old.id, old.kind, old.reason, old.recordedAt),
        );
        expect(
          (
            latest.relationType,
            latest.status.name,
            latest.proof,
            latest.chapterId,
          ),
          ('lover', 'ended', '修正依据', chapter),
        );
        expect(after.chapterId, chapter);
      },
    );
    test(
      'remove latest restores evidence; middle removal preserves current; stale confirmation cannot revert',
      () async {
        final chapter = await NovelContentService(
          db,
        ).createChapter(siblingOrder: 1, title: '证据');
        final id = await create(chapterId: chapter);
        final first = await service.recordChange(
          id: id,
          relationType: 'enemy',
          proof: 'p1',
          reason: 'r1',
        );
        final second = await service.recordChange(
          id: id,
          relationType: 'lover',
          proof: 'p2',
          reason: 'r2',
        );
        await expectLater(
          service.removeChange(
            id: id,
            snapshotId: first.changeId!,
            expected: first.relation,
          ),
          code('relation_changed'),
        );
        final removed = await service.removeChange(
          id: id,
          snapshotId: first.changeId!,
        );
        expect(removed.currentChanged, isFalse);
        expect(removed.relation.relationType, 'lover');
        expect(removed.relation.changeLogs.map((s) => s.toJson()), [
          second.relation.changeLogs.first.toJson(),
          second.relation.changeLogs.last.toJson(),
        ]);
        expect(second.relation.changeLogs, hasLength(3));
        expect(
          removed.relation.changeLogs.map((s) => s.id),
          isNot(contains(first.changeId)),
        );
        final restored = await service.removeChange(
          id: id,
          snapshotId: second.changeId!,
        );
        expect(restored.currentChanged, isTrue);
        expect(
          (
            restored.relation.relationType,
            restored.relation.proof,
            restored.relation.chapterId,
          ),
          ('friend', '初始完整依据', chapter),
        );
        await expectLater(
          service.removeChange(
            id: id,
            snapshotId: restored.relation.changeLogs.first.id,
            force: true,
          ),
          code('initial_snapshot_not_removable'),
        );
        expect(
          (await service.removeChange(
            id: id,
            snapshotId: second.changeId!,
            force: true,
          )).changed,
          isFalse,
        );
        await expectLater(
          service.removeChange(id: id, snapshotId: second.changeId!),
          code('not_found'),
        );
      },
    );
    for (final correction in [false, true]) {
      test(
        'remove confirmation rejects unchanged latest ID after ${correction ? 'correction' : 'predecessor removal'}, including force',
        () async {
          final id = await create();
          final middle = await service.recordChange(
            id: id,
            relationType: 'enemy',
            proof: 'middle',
            reason: 'middle',
          );
          final latest = await service.recordChange(
            id: id,
            relationType: 'lover',
            proof: 'latest',
            reason: 'latest',
          );
          final expected = await read(id);
          if (correction) {
            await service.correctCurrentFields(
              id: id,
              proof: 'corrected latest',
            );
          } else {
            await service.removeChange(id: id, snapshotId: middle.changeId!);
          }
          final current = await read(id);
          expect(current.updatedAt, expected.updatedAt);
          expect(current.changeLogs.last.id, expected.changeLogs.last.id);
          final stored =
              (await db
                      .customSelect(
                        'SELECT * FROM entity_relations WHERE id = ?',
                        variables: [Variable(id)],
                      )
                      .getSingle())
                  .data;
          for (final force in [false, true]) {
            await expectLater(
              service.removeChange(
                id: id,
                snapshotId: latest.changeId!,
                expected: expected,
                force: force,
              ),
              code('relation_changed'),
            );
            expect(
              (await db
                      .customSelect(
                        'SELECT * FROM entity_relations WHERE id = ?',
                        variables: [Variable(id)],
                      )
                      .getSingle())
                  .data,
              stored,
            );
          }
          final refreshed = await service.removeChange(
            id: id,
            snapshotId: latest.changeId!,
            expected: current,
          );
          expect(
            refreshed.relation.relationType,
            correction ? 'enemy' : 'friend',
          );
        },
      );
    }
    test('volume is not valid chapter evidence', () async {
      final volume = await NovelContentService(db).createVolume(title: '卷一');
      await expectLater(create(chapterId: volume), code('invalid_chapter_ref'));
    });
    test(
      'deleted chapter reference remains in history and cannot be restored',
      () async {
        final content = NovelContentService(db);
        final chapter = await content.createChapter(
          siblingOrder: 1,
          title: '证据',
        );
        final id = await create(chapterId: chapter);
        await content.deleteChapter(chapter);
        var row = await read(id);
        expect(row.chapterId, isNull);
        expect(row.changeLogs.first.chapterId, chapter);
        final change = await service.recordChange(
          id: id,
          relationType: 'enemy',
          proof: 'new',
          reason: 'new',
        );
        await service.removeChange(id: id, snapshotId: change.changeId!);
        row = await read(id);
        expect(row.chapterId, isNull);
        expect(row.changeLogs.single.chapterId, chapter);
        expect(row.proof, '初始完整依据');
      },
    );
    test(
      'invalid mutation and enclosing transaction failure leave current and history intact',
      () async {
        final id = await create();
        final before =
            (await db
                    .customSelect('SELECT * FROM entity_relations')
                    .getSingle())
                .data;
        await expectLater(
          service.recordChange(
            id: id,
            relationType: 'unknown',
            proof: 'p',
            reason: 'r',
          ),
          code('invalid_relation_type'),
        );
        await expectLater(
          service.recordChange(
            id: id,
            status: 'unknown',
            proof: 'p',
            reason: 'r',
          ),
          code('invalid_relation_status'),
        );
        await expectLater(
          service.recordChange(id: id, proof: '', reason: 'r'),
          code('missing_required_fields'),
        );
        await expectLater(
          service.recordChange(
            id: id,
            proof: 'p',
            reason: 'r',
            chapterId: 'foreign',
          ),
          code('invalid_chapter_ref'),
        );
        await expectLater(
          service.correctCurrentFields(id: id, proof: ' '),
          code('missing_required_fields'),
        );
        expect(
          (await db.customSelect('SELECT * FROM entity_relations').getSingle())
              .data,
          before,
        );
        final changed = await service.recordChange(
          id: id,
          relationType: 'enemy',
          proof: 'p',
          reason: 'r',
        );
        final beforeRemoval =
            (await db
                    .customSelect('SELECT * FROM entity_relations')
                    .getSingle())
                .data;
        await expectLater(
          db.transaction(() async {
            await service.removeChange(id: id, snapshotId: changed.changeId!);
            throw StateError('abort surrounding transaction');
          }),
          throwsStateError,
        );
        expect(
          (await db.customSelect('SELECT * FROM entity_relations').getSingle())
              .data,
          beforeRemoval,
        );
      },
    );
    test(
      'hard delete removes row and inline history; deleted IDs cannot be updated',
      () async {
        final id = await create();
        await service.recordChange(
          id: id,
          status: 'ended',
          proof: 'p',
          reason: 'r',
        );
        expect((await read(id)).status, 'ended');
        await service.deleteRelation(id);
        expect(await service.getRelationById(id), isNull);
        expect(
          await db.customSelect('SELECT * FROM entity_relations').get(),
          isEmpty,
        );
        await expectLater(
          service.recordChange(id: id, proof: 'p', reason: 'r'),
          code('not_found'),
        );
      },
    );
    test(
      'corrupt history fails explicitly and is not replaced on write',
      () async {
        final id = await create();
        await db.customStatement(
          "UPDATE entity_relations SET change_logs = '{}' WHERE id = ?",
          [id],
        );
        await expectLater(
          service.recordChange(id: id, proof: 'p', reason: 'r'),
          code('invalid_relation_history'),
        );
        expect(
          (await db
                  .customSelect('SELECT change_logs FROM entity_relations')
                  .getSingle())
              .data['change_logs'],
          '{}',
        );
      },
    );
  });

  group('summary scopes', () {
    test(
      'ended is discoverable while graph traversal cannot cross it',
      () async {
        final ab = await service.createRelation(
          sourceType: 'character',
          sourceId: 'a',
          targetType: 'character',
          targetId: 'b',
          relationType: 'friend',
        );
        await service.createRelation(
          sourceType: 'character',
          sourceId: 'b',
          targetType: 'character',
          targetId: 'c',
          relationType: 'friend',
        );
        await service.recordChange(
          id: ab,
          status: 'ended',
          proof: 'ended',
          reason: 'ended',
        );
        expect(
          await service.getRelationsForEntity(
            entityType: 'character',
            entityId: 'a',
          ),
          hasLength(1),
        );
        expect(
          await service
              .watchRelationSummaries(entityType: 'character', entityId: 'a')
              .first,
          hasLength(1),
        );
        expect(
          await service.getRelationsForPair(
            sourceType: 'character',
            sourceId: 'b',
            targetType: 'character',
            targetId: 'a',
          ),
          hasLength(1),
        );
        expect(
          await service.getRelationsBetween(
            sourceType: 'character',
            sourceId: 'b',
            targetType: 'character',
            targetId: 'a',
          ),
          isEmpty,
        );
        expect(
          (await service.graphSearch(
            entityType: 'character',
            entityId: 'a',
            depth: 2,
          )).totalRelations,
          0,
        );
        expect(
          (await service.getCharacterNetwork('a')).values.expand((v) => v),
          isEmpty,
        );
        await service.recordChange(
          id: ab,
          status: 'active',
          proof: 'restored',
          reason: 'restored',
        );
        expect(
          (await service.graphSearch(
            entityType: 'character',
            entityId: 'a',
            depth: 2,
          )).totalRelations,
          2,
        );
      },
    );
    test(
      'summary lists and graph do not decode history even when damaged',
      () async {
        final id = await service.createRelation(
          sourceType: 'character',
          sourceId: 'a',
          targetType: 'character',
          targetId: 'b',
          relationType: 'friend',
        );
        await db.customStatement(
          "UPDATE entity_relations SET change_logs = '{}' WHERE id = ?",
          [id],
        );
        expect((await service.queryRelationSummaries()).single.id, id);
        expect((await service.watchRelationSummaries().first).single.id, id);
        expect((await service.getRelationSummaryById(id))!.proof, '');
        expect(
          (await service.getRelationSummaryById(id))!.toJson().keys,
          isNot(contains('changeLogs')),
        );
        expect(
          (await service.graphSearch(
            entityType: 'character',
            entityId: 'a',
          )).totalRelations,
          1,
        );
        await expectLater(service.getRelationById(id), throwsFormatException);
        await service.deleteRelation(id);
        expect(await service.queryRelationSummaries(), isEmpty);
        expect(
          (await service.graphSearch(
            entityType: 'character',
            entityId: 'a',
          )).totalRelations,
          0,
        );
      },
    );
    test('current faction and skill helpers exclude ended records', () async {
      for (final pair in [('faction', 'member'), ('skill', 'mastered')]) {
        await service.createRelation(
          sourceType: 'character',
          sourceId: 'a',
          targetType: pair.$1,
          targetId: 'target',
          relationType: pair.$2,
          status: 'ended',
        );
        await service.createRelation(
          sourceType: 'character',
          sourceId: 'b',
          targetType: pair.$1,
          targetId: 'target',
          relationType: pair.$2,
        );
      }
      expect((await service.getFactionMembers('target')).single.sourceId, 'b');
      expect((await service.getSkillLearners('target')).single.sourceId, 'b');
      expect((await service.queryRelationSummaries()).length, 4);
    });
  });

  group('graphSearch', () {
    test('returns empty result for entity with no relations', () async {
      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_no_relations',
      );

      expect(result.startEntityType, entityTypeCharacter);
      expect(result.startEntityId, 'char_no_relations');
      expect(result.layers, isEmpty);
      expect(result.totalRelations, 0);
    });

    test('returns direct relations at depth 1', () async {
      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_a',
        targetType: entityTypeCharacter,
        targetId: 'char_b',
        relationType: characterRelationFriend,
      );

      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_a',
        depth: 1,
      );

      expect(result.layers.length, 1);
      expect(result.layers.first.depth, 1);
      expect(result.layers.first.relations.length, 1);
      expect(result.totalRelations, 1);

      final relation = result.layers.first.relations.first;
      expect(relation.sourceId, 'char_a');
      expect(relation.targetId, 'char_b');
      expect(relation.relationType, characterRelationFriend);
    });

    test('returns relations from both source and target directions', () async {
      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_a',
        targetType: entityTypeCharacter,
        targetId: 'char_b',
        relationType: characterRelationFriend,
      );

      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_c',
        targetType: entityTypeCharacter,
        targetId: 'char_a',
        relationType: characterRelationEnemy,
      );

      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_a',
        depth: 1,
      );

      expect(result.layers.length, 1);
      expect(result.layers.first.relations.length, 2);
      expect(result.totalRelations, 2);
    });

    test('returns second degree relations at depth 2', () async {
      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_a',
        targetType: entityTypeCharacter,
        targetId: 'char_b',
        relationType: characterRelationFriend,
      );

      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_b',
        targetType: entityTypeCharacter,
        targetId: 'char_c',
        relationType: characterRelationFriend,
      );

      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_a',
        depth: 2,
      );

      expect(result.layers.length, 2);
      expect(result.layers[0].depth, 1);
      expect(result.layers[0].relations.length, 1);
      expect(result.layers[1].depth, 2);
      expect(result.layers[1].relations.length, 1);
      expect(result.totalRelations, 2);
    });

    test('filters by relation_type when specified', () async {
      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_a',
        targetType: entityTypeCharacter,
        targetId: 'char_b',
        relationType: characterRelationFriend,
      );

      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_a',
        targetType: entityTypeCharacter,
        targetId: 'char_c',
        relationType: characterRelationEnemy,
      );

      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_a',
        relationType: characterRelationFriend,
        depth: 1,
      );

      expect(result.layers.length, 1);
      expect(result.layers.first.relations.length, 1);
      expect(
        result.layers.first.relations.first.relationType,
        characterRelationFriend,
      );
    });

    test('avoids cycles in the graph', () async {
      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_a',
        targetType: entityTypeCharacter,
        targetId: 'char_b',
        relationType: characterRelationFriend,
      );

      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_b',
        targetType: entityTypeCharacter,
        targetId: 'char_a',
        relationType: characterRelationFriend,
      );

      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_a',
        depth: 3,
      );

      expect(result.layers.length, 1);
      expect(result.layers.first.relations.length, 2);
      expect(result.totalRelations, 2);
    });

    test('handles cross-entity-type relations', () async {
      await service.createRelation(
        sourceType: entityTypeCharacter,
        sourceId: 'char_a',
        targetType: entityTypeFaction,
        targetId: 'faction_x',
        relationType: characterFactionMember,
      );

      await service.createRelation(
        sourceType: entityTypeFaction,
        sourceId: 'faction_x',
        targetType: entityTypeFaction,
        targetId: 'faction_y',
        relationType: factionFactionAlly,
      );

      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_a',
        depth: 2,
      );

      expect(result.layers.length, 2);
      expect(result.layers[0].relations.length, 1);
      expect(result.layers[1].relations.length, 1);
      expect(result.totalRelations, 2);
    });

    test('respects maximum depth of 5', () async {
      for (var i = 0; i < 6; i++) {
        await service.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: 'char_$i',
          targetType: entityTypeCharacter,
          targetId: 'char_${i + 1}',
          relationType: characterRelationFriend,
        );
      }

      final result = await service.graphSearch(
        entityType: entityTypeCharacter,
        entityId: 'char_0',
        depth: 10,
      );

      expect(result.layers.length, lessThanOrEqualTo(5));
    });
  });

  group('queryRelationSummaries', () {
    test(
      'filters by multiple query parameters in the database query',
      () async {
        await db
            .into(db.chapters)
            .insert(
              ChaptersCompanion.insert(
                id: 'chapter_1',
                type: 'chapter',
                siblingOrder: 1,
                title: const Value('One'),
              ),
            );
        await db
            .into(db.chapters)
            .insert(
              ChaptersCompanion.insert(
                id: 'chapter_2',
                type: 'chapter',
                siblingOrder: 2,
                title: const Value('Two'),
              ),
            );
        final firstId = await service.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: 'char_a',
          targetType: entityTypeCharacter,
          targetId: 'char_b',
          relationType: characterRelationFriend,
          chapterId: 'chapter_1',
        );
        await service.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: 'char_a',
          targetType: entityTypeCharacter,
          targetId: 'char_c',
          relationType: characterRelationEnemy,
          chapterId: 'chapter_1',
        );
        await service.createRelation(
          sourceType: entityTypeCharacter,
          sourceId: 'char_a',
          targetType: entityTypeCharacter,
          targetId: 'char_b',
          relationType: characterRelationEnemy,
          chapterId: 'chapter_2',
        );

        final result = await service.queryRelationSummaries(
          sourceType: entityTypeCharacter,
          sourceId: 'char_a',
          targetId: 'char_b',
          relationType: characterRelationFriend,
          chapterId: 'chapter_1',
        );

        expect(result.map((relation) => relation.id), [firstId]);
      },
    );
  });

  group('GraphSearchLayer', () {
    test('stores depth and relations', () {
      final layer = GraphSearchLayer(depth: 2, relations: []);

      expect(layer.depth, 2);
      expect(layer.relations, isEmpty);
    });
  });

  group('GraphSearchResult', () {
    test('calculates total relations correctly', () {
      final result = GraphSearchResult(
        startEntityType: entityTypeCharacter,
        startEntityId: 'char_a',
        layers: [
          GraphSearchLayer(depth: 1, relations: [MockEntityRelation()]),
          GraphSearchLayer(
            depth: 2,
            relations: [MockEntityRelation(), MockEntityRelation()],
          ),
        ],
        totalRelations: 3,
      );

      expect(result.startEntityType, entityTypeCharacter);
      expect(result.startEntityId, 'char_a');
      expect(result.layers.length, 2);
      expect(result.totalRelations, 3);
    });
  });
}

class MockEntityRelation extends RelationSummary {
  MockEntityRelation()
    : super(
        id: 'mock',
        sourceType: entityTypeCharacter,
        sourceId: 'mock_source',
        targetType: entityTypeCharacter,
        targetId: 'mock_target',
        relationType: characterRelationFriend,
        proof: '',
        status: 'active',
        sortOrder: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}
