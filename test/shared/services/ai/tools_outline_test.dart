// 职责: 测试 AI 大纲工具的 working change 接受、拒绝与节拍排序语义
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_outline.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/models/outline.dart

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/outline.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import '../../../helpers/working_change_test_helper.dart';

void main() {
  late NovelContentDatabase db;
  late AppDatabase appDb;
  late NovelContentService contentService;
  late WorkingOverlayService overlay;
  late AiToolManager toolManager;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDb = AppDatabase.forTest(NativeDatabase.memory());
    contentService = NovelContentService(db);
    overlay = WorkingOverlayService(
      db,
      contentService,
      novelActionsService: NovelActionsService(appDb),
    );
    toolManager = AiToolManager(contentService, workingOverlayService: overlay)
      ..registerAllTools();
  });

  tearDown(() async {
    await db.close();
    await appDb.close();
  });

  Future<OutlineDraft> seedOutline({
    String title = '主线',
    String content = '旧总览',
    int startChapterNum = 1,
    List<OutlineBeatDraft>? beats,
  }) async {
    final createdId = await contentService.outlineService.createOutline(
      defaultTitle: title,
      content: content,
      status: outlineStatusPending,
      startChapterNum: startChapterNum,
      beats: beats ?? const <OutlineBeatDraft>[],
    );
    return (await contentService.outlineService.getByDocumentId(createdId))!;
  }

  OutlineBeatDraft beat(String title, String content) {
    return contentService.outlineService.createBeatDraft(
      title: title,
      content: content,
    );
  }

  Future<String> firstBeatId([String title = '主线']) async =>
      (await contentService.outlineService.getByTitle(title))!.beats.first.id;

  Future<void> accept(String changeId) async {
    final commitId = await overlay.commitWorkingChanges(
      [changeId],
      source: workingChangeSourceAi,
      message: 'test.accept_ai_outline_change',
    );
    expect(commitId, isNotNull);
  }

  test(
    'Create beat collision returns persisted identity and canonical working snapshot',
    () async {
      final original = await seedOutline(beats: [beat('Existing', 'keep')]);
      final occupiedId = original.beats.single.id;
      final candidates = [occupiedId, 'obt_FINAL1'];
      final content = NovelContentService(
        db,
        idBuilder: (_) => candidates.removeAt(0),
      );
      final collisionOverlay = WorkingOverlayService(
        db,
        content,
        novelActionsService: NovelActionsService(appDb),
      );
      final manager = AiToolManager(
        content,
        workingOverlayService: collisionOverlay,
      )..registerAllTools();
      final result = await manager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines/主线/beats',
          'fields': {'title': 'New', 'content': 'new body'},
        },
      );
      expect(result['ok'], isTrue, reason: '$result');
      expect(result['id'], 'obt_FINAL1');
      final stored = (await content.outlineService.getByDocumentId(
        original.documentId,
      ))!;
      expect(stored.beats.map((beat) => beat.id), [occupiedId, 'obt_FINAL1']);
      final changes = await db.select(db.workingChanges).get();
      final snapshot = decodeTimelineJson(changes.single.newText!);
      expect(snapshot.map((beat) => beat.id), [occupiedId, 'obt_FINAL1']);
      expect(snapshot.every((beat) => !beat.isNew), isTrue);
    },
  );

  test(
    'beat field guidance excludes parent fields and leaves runtime errors alone',
    () async {
      await seedOutline(beats: [beat('A', '原文')]);
      for (final field in ['status', 'chapter_count']) {
        final result = await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'outlines/主线/beats/${await firstBeatId()}/$field',
            'old_text': '1',
            'new_text': '2',
          },
        );
        expect(result['error_code'], 'unsupported');
        expect(result['hint'], contains('chapter_count'));
        expect(result['hint'], contains('title, content'));
        expect(result.toString(), isNot(contains('start_chapter_num')));
        expect(result['hint'], contains('Read /_schema/outlines'));
      }
      final readonly = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/beats/${await firstBeatId()}/id',
          'old_text': 'a',
          'new_text': 'b',
        },
      );
      expect(readonly['error_code'], 'permission_denied');
      final missed = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/beats/${await firstBeatId()}/content',
          'old_text': '不存在',
          'new_text': '修改',
        },
      );
      expect(missed['ok'], isFalse);
      expect(missed.toString(), isNot(contains('/_schema')));
      expect(missed.containsKey('validation_errors'), isFalse);
    },
  );

  test(
    'old numeric beat paths fail with ID listing guidance before loading data',
    () async {
      for (final scenario in <(String, Map<String, dynamic>)>[
        ('Read', {}),
        ('Write', {'value': 'x'}),
        ('Edit', {'old_text': 'x', 'new_text': 'y'}),
        ('Remove', {'force': true}),
      ]) {
        final result = await toolManager.executeTool(
          name: scenario.$1,
          input: {'path': 'outlines/main/beats/0', ...scenario.$2},
        );
        expect(result['error_code'], 'invalid_argument');
        expect(result['hint'], contains('Read /_schema/outlines'));
      }
      expect(await db.select(db.workingChanges).get(), isEmpty);
    },
  );

  group('stable beat identities', () {
    Future<List<Object?>> snapshot() async => [
      (await db.select(db.outlines).get()).map((r) => r.toJson()).toList(),
      (await db.select(db.outlineBeats).get()).map((r) => r.toJson()).toList(),
      (await db.select(db.workingChanges).get())
          .map((r) => r.toJson())
          .toList(),
    ];

    test(
      'mixed IDs reorder/update/create/delete; repeat is no-op and ID path survives insertion',
      () async {
        final original = await seedOutline(
          beats: [beat('A', 'a'), beat('B', 'b'), beat('C', 'c')],
        );
        final b = original.beats[1];
        final bPath = 'outlines/主线/beats/${b.id}';
        final write = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线/beats',
            'value': [
              {
                'id': b.id,
                'title': 'B2',
                'content': 'b2',
                'chapter_count': '2.5',
              },
              {'title': 'new', 'content': 'new'},
              {'id': original.beats.first.id, 'title': 'A', 'content': 'a'},
            ],
          },
        );
        expect(write['updated'], true, reason: '$write');
        final current = (await contentService.outlineService.getByTitle('主线'))!;
        expect(current.beats.map((b) => b.title), ['B2', 'new', 'A']);
        expect(current.beats.first.id, b.id);
        expect(current.beats.first.createdAt, b.createdAt);
        expect(current.beats.first.chapterCount, 3);
        expect(
          (await db.select(db.outlineBeats).get())
              .singleWhere((r) => r.id == original.beats.last.id)
              .deletedAt,
          isNot(notDeletedSentinel),
        );
        final listing = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'outlines/主线/beats'},
        );
        final entries = (listing['entries'] as List)
            .cast<Map<String, dynamic>>();
        final before = await snapshot();
        final repeated = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线/beats',
            'value': [
              for (final entry in entries)
                Map<String, dynamic>.from(entry)..remove('path'),
            ],
          },
        );
        expect(repeated['updated'], false, reason: '$repeated');
        expect(await snapshot(), before);
        await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines/主线/beats',
            'fields': {'title': 'insert', 'index': 0},
          },
        );
        final located = await toolManager.executeTool(
          name: 'Read',
          input: {'path': bPath},
        );
        expect(located['id'], b.id);
        expect(located['title'], 'B2');
        expect(located['index'], 1);
        final cleared = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'outlines/主线/beats', 'value': []},
        );
        expect(cleared['updated'], true);
        expect(
          (await contentService.outlineService.getByTitle('主线'))!.beats,
          isEmpty,
        );
        expect(
          (await db.select(db.outlineBeats).get()).every(
            (r) => r.deletedAt != notDeletedSentinel,
          ),
          true,
        );
      },
    );

    test(
      'every invalid list is rejected atomically including foreign tombstones',
      () async {
        final original = await seedOutline(
          beats: [beat('A', 'a'), beat('deleted', 'd')],
        );
        final foreign = await seedOutline(
          title: 'other',
          beats: [beat('foreign', 'f')],
        );
        await contentService.outlineService.saveOutline(
          original.copyWith(beats: [original.beats.first]),
        );
        final a = original.beats.first.id;
        final deleted = original.beats.last.id;
        final foreignId = foreign.beats.single.id;
        for (final id in [
          null,
          '',
          '   ',
          1,
          false,
          'missing',
          deleted,
          foreignId,
        ]) {
          final before = await snapshot();
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {
              'path': 'outlines/主线/beats',
              'value': [
                {'id': a, 'title': 'changed'},
                {'title': 'new'},
                {'id': id},
              ],
            },
          );
          expect(result['error_code'], 'invalid_argument', reason: '$result');
          expect(await snapshot(), before);
        }
        for (final value in [
          [
            {'id': a},
            {'id': a},
          ],
          [false],
          [
            {'title': 'new'},
            null,
          ],
        ]) {
          final before = await snapshot();
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {'path': 'outlines/主线/beats', 'value': value},
          );
          expect(result['error_code'], 'invalid_argument', reason: '$result');
          expect(await snapshot(), before);
        }
        await contentService.outlineService.saveOutline(
          foreign.copyWith(beats: []),
        );
        final before = await snapshot();
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线/beats',
            'value': [
              {'id': foreignId},
            ],
          },
        );
        expect(result['error_code'], 'invalid_argument');
        expect(await snapshot(), before);
        // 新建 outline 的 beat 不能认领已有 id：id 被跳过，建出来的是全新 beat，
        // 原 outline 一个 beat 都不掉。
        final createdWithBeats = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines',
            'fields': {
              'title': 'new',
              'beats': [
                {'id': a},
              ],
            },
          },
        );
        expect(createdWithBeats['ok'], isTrue, reason: '$createdWithBeats');
        expect(createdWithBeats['ignored_fields'], ['beats[0].id']);
        expect(
          (await contentService.outlineService.getByTitle(
            'new',
          ))!.beats.single.id,
          isNot(a),
        );
        expect(
          (await contentService.outlineService.getByTitle(
            '主线',
          ))!.beats.first.id,
          a,
        );
        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines/主线/beats',
            'fields': {'id': a, 'title': 'new'},
          },
        );
        expect(created['ok'], isTrue, reason: '$created');
        expect(created['ignored_fields'], ['id']);
        expect(created['id'], isNot(a));
        final afterCreate = (await contentService.outlineService.getByTitle(
          '主线',
        ))!;
        expect(afterCreate.beats.first.id, a);
        expect(afterCreate.beats.first.title, original.beats.first.title);
        expect(afterCreate.beats.last.id, created['id']);
      },
    );
  });

  // turn 回退以工作变更自身的 oldText 为目标，不读提交记录，碰不到这里篡改的历史。
  for (final rollbackMode in ['active', 'single', 'lines', 'commit']) {
    final committed = rollbackMode != 'active';
    test(
      'invalid historical beat ownership leaves all data and history untouched, mode=$rollbackMode',
      () async {
        final original = await seedOutline(beats: [beat('A', 'a')]);
        final other = await seedOutline(
          title: 'other',
          beats: [beat('B', 'b')],
        );
        await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线/beats',
            'value': [
              {'title': 'new'},
            ],
          },
        );
        final changeId = await onlyActiveWorkingChangeId(db);
        final corrupt = original
            .copyWith(beats: [original.beats.single, other.beats.single])
            .encodeTimelineJson();
        String? commitId;
        if (committed) {
          commitId = await overlay.commitWorkingChanges(
            [changeId],
            source: workingChangeSourceAi,
            message: 'test',
          );
          await (db.update(db.changeCommitItems)
                ..where((r) => r.workingChangeId.equals(changeId)))
              .write(ChangeCommitItemsCompanion(oldText: Value(corrupt)));
        } else {
          await (db.update(db.workingChanges)
                ..where((r) => r.id.equals(changeId)))
              .write(WorkingChangesCompanion(oldText: Value(corrupt)));
        }
        Future<List<Object?>> snapshot() async => [
          (await db.select(db.outlines).get()).map((r) => r.toJson()).toList(),
          (await db.select(db.outlineBeats).get())
              .map((r) => r.toJson())
              .toList(),
          (await db.select(db.workingChanges).get())
              .map((r) => r.toJson())
              .toList(),
          (await db.select(db.changeCommits).get())
              .map((r) => r.toJson())
              .toList(),
          (await db.select(db.changeCommitItems).get())
              .map((r) => r.toJson())
              .toList(),
        ];
        final before = await snapshot();
        // 拒绝工作变更与整提交回滚不中止：坏的历史目标按 skipped 跳过，数据原样；
        // 单条与按行回滚仍直接报错。
        switch (rollbackMode) {
          case 'lines':
            await expectLater(
              overlay.rollbackChangeLines(changeId, {'d:1', 'i:1'}),
              throwsArgumentError,
            );
          case 'single':
            await expectLater(
              overlay.rollbackChange(changeId),
              throwsArgumentError,
            );
          case 'commit':
            expect(
              await overlay.rollbackCommit(commitId: commitId!),
              RestoreResourceResult.skipped,
            );
          default:
            expect(
              await overlay.rejectWorkingChange(changeId),
              RollbackChangeResult.skipped,
            );
        }
        expect(await snapshot(), before);
      },
    );
  }

  group('Remove beat', () {
    Future<Map<String, dynamic>> remove(String path, {bool force = false}) =>
        toolManager.executeTool(
          name: 'Remove',
          input: {'path': path, 'force': force},
        );

    test('missing beat returns not_found with the locate hint', () async {
      await seedOutline(beats: [beat('A', 'a')]);

      final result = await remove('outlines/主线/beats/ghost');

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'not_found');
      expect(result['hint'], contains('outlines/主线/beats'));
    });

    test(
      'current-work absolute Remove serializes both target and parent and rejects other works',
      () async {
        final original = await seedOutline(
          beats: [beat('A', 'a'), beat('B', 'b')],
        );
        final manager = AiToolManager(
          contentService,
          workingOverlayService: overlay,
          workId: 'current',
        )..registerAllTools();
        addTearDown(manager.dispose);
        final id = original.beats.first.id;
        final denied = await manager.executeTool(
          name: 'Remove',
          input: {'path': '/works/other/outlines/主线/beats/$id', 'force': true},
        );
        expect(denied['ok'], false);
        expect(
          (await contentService.outlineService.getByTitle('主线'))!.beats,
          hasLength(2),
        );
        final path = '/works/current/outlines/主线/beats/$id';
        final removed = await manager.executeTool(
          name: 'Remove',
          input: {'path': path},
        );
        expect(removed['path'], path);
        expect(removed['parent_path'], '/works/current/outlines/主线/beats');
        expect(removed['work_id'], 'current');
        expect(removed['removed'], true);
      },
    );

    for (final count in [1, 3]) {
      for (final removeLast in [false, true]) {
        test(
          'soft deletes count=$count last=$removeLast and keeps stable siblings',
          () async {
            final original = await seedOutline(
              startChapterNum: 4,
              beats: [
                for (var i = 0; i < count; i++)
                  beat('beat $i', 'body $i').copyWith(chapterCount: 2),
              ],
            );
            final index = removeLast ? count - 1 : count ~/ 2;
            final removed = original.beats[index];
            final path = 'outlines/主线/beats/${removed.id}';
            final result = await remove(path);
            expect(result['removed'], true, reason: '$result');
            expect(result['path'], path);
            expect(result['id'], removed.id);
            expect(result['parent_path'], 'outlines/主线/beats');
            expect(result['beat_count'], count - 1);
            final current = (await contentService.outlineService.getByTitle(
              '主线',
            ))!;
            final expected = original.beats
                .where((b) => b.id != removed.id)
                .toList();
            expect(current.startChapterNum, 4);
            expect(current.beats.map((b) => b.id), expected.map((b) => b.id));
            expect(
              current.beats.map((b) => b.content),
              expected.map((b) => b.content),
            );
            expect(
              current.beats.map((b) => b.sortOrder),
              List.generate(count - 1, (i) => i),
            );
            expect(current.beats.map((b) => b.chapterCount), everyElement(2));
            final tombstone = await (db.select(
              db.outlineBeats,
            )..where((r) => r.id.equals(removed.id))).getSingle();
            expect(tombstone.deletedAt, isNot(notDeletedSentinel));
            final change = (await overlay.getWorkingChanges()).single;
            expect(change.toolName, 'Remove');
            expect(change.field, 'beats');
            expect(
              outlineBeatsHaveSameContent(
                decodeTimelineJson(change.oldText!),
                original.beats,
              ),
              true,
            );
            final snapshot = (await db.select(db.workingChanges).get())
                .map((r) => r.toJson())
                .toList();
            expect((await remove(path))['error_code'], 'not_found');
            expect((await remove(path, force: true))['missing'], true);
            expect(
              (await db.select(db.workingChanges).get())
                  .map((r) => r.toJson())
                  .toList(),
              snapshot,
            );
          },
        );
      }
    }

    test(
      'uses prior Edit/Create changes and rejects illegal or foreign targets',
      () async {
        final original = await seedOutline(
          beats: [beat('A', 'original'), beat('B', 'keep')],
        );
        final other = await seedOutline(
          title: '0',
          beats: [beat('Other', 'other')],
        );
        final a = original.beats.first.id;
        await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'outlines/主线/beats/$a/content',
            'old_text': 'original',
            'new_text': 'edited',
          },
        );
        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines/主线/beats',
            'fields': {'title': 'C', 'content': 'created'},
          },
        );
        final newId = created['id'];
        await remove('outlines/主线/beats/${original.beats.last.id}');
        final current = (await contentService.outlineService.getByTitle('主线'))!;
        expect(current.beats.map((b) => b.id), [a, newId]);
        expect(current.beats.map((b) => b.content), ['edited', 'created']);
        final change = (await overlay.getWorkingChanges()).single;
        expect(change.toolName, 'Remove');
        expect(decodeTimelineJson(change.newText!).map((b) => b.id), [
          a,
          newId,
        ]);
        expect(
          outlineBeatsHaveSameContent(
            decodeTimelineJson(change.oldText!),
            original.beats,
          ),
          true,
        );
        for (final path in [
          'outlines/主线/beats',
          'outlines/主线/beats/0',
          'outlines/主线/beats/$a/content',
        ]) {
          expect(
            (await remove(path, force: true))['error_code'],
            'invalid_argument',
            reason: path,
          );
        }
        final foreignPath = 'outlines/主线/beats/${other.beats.single.id}';
        expect((await remove(foreignPath))['error_code'], 'not_found');
        expect((await remove(foreignPath, force: true))['missing'], true);
        expect(
          (await contentService.outlineService.getByTitle(
            '0',
          ))!.encodeTimelineJson(),
          other.encodeTimelineJson(),
        );
        await overlay.rollbackChange(change.id);
        final restored = (await contentService.outlineService.getByTitle(
          '主线',
        ))!;
        expect(
          outlineBeatsHaveSameContent(restored.beats, original.beats),
          true,
        );
        expect(
          (await db.select(db.outlineBeats).get())
              .where((b) => b.id == newId)
              .single
              .deletedAt,
          isNot(notDeletedSentinel),
        );
      },
    );

    for (final committed in [false, true]) {
      test(
        'already restored beat content ignores timestamp differences committed=$committed',
        () async {
          final before = await seedOutline(
            beats: [beat('A', 'a'), beat('B', 'b')],
          );
          await remove('outlines/主线/beats/${before.beats.last.id}');
          final change = (await overlay.getWorkingChanges()).single;
          if (committed) {
            await accept(change.id);
          }
          await Future<void>.delayed(const Duration(milliseconds: 3));
          await contentService.outlineService.restoreOutline(before);
          final beatRows = (await db.select(db.outlineBeats).get())
              .map((r) => r.toJson())
              .toList();
          final commits = (await db.select(db.changeCommits).get())
              .map((r) => r.toJson())
              .toList();
          expect(
            await overlay.rollbackChange(change.id),
            RollbackChangeResult.rolledBack,
          );
          expect(
            (await db.select(db.outlineBeats).get())
                .map((r) => r.toJson())
                .toList(),
            beatRows,
          );
          expect(
            (await db.select(db.changeCommits).get())
                .map((r) => r.toJson())
                .toList(),
            commits,
          );
        },
      );
    }

    for (final mode in ['active', 'single', 'turn', 'lines', 'commit']) {
      test(
        '$mode restores IDs and history across timestamps and later edits',
        () async {
          final original = await seedOutline(
            beats: [beat('A', 'a'), beat('B', 'b'), beat('C', 'c')],
          );
          final middle = original.beats[1];
          await remove('outlines/主线/beats/${middle.id}');
          final change = (await overlay.getWorkingChanges()).single;
          await (db.update(
            db.workingChanges,
          )..where((r) => r.id.equals(change.id))).write(
            const WorkingChangesCompanion(sourceTurnId: Value('remove-turn')),
          );
          String? commitId;
          if (mode != 'active') {
            await Future<void>.delayed(const Duration(milliseconds: 3));
            commitId = await overlay.commitWorkingChanges(
              [change.id],
              source: workingChangeSourceAi,
              message: 'accept',
            );
          }
          final after = (await contentService.outlineService.getByTitle('主线'))!;
          await Future<void>.delayed(const Duration(milliseconds: 3));
          await contentService.outlineService.saveOutline(
            after.copyWith(
              content: 'outside field retained',
              beats: after.beats.reversed
                  .map((b) => b.copyWith(content: 'later ${b.content}'))
                  .toList(),
            ),
          );
          Future<void> rollback() async {
            switch (mode) {
              case 'turn':
                await overlay.rollbackTurn(turnId: 'remove-turn');
              case 'commit':
                await overlay.rollbackCommit(commitId: commitId!);
              case 'lines':
                await overlay.rollbackChangeLines(change.id, {'d:1', 'i:1'});
              default:
                await overlay.rollbackChange(change.id);
            }
          }

          await rollback();
          final restored = (await contentService.outlineService.getByTitle(
            '主线',
          ))!;
          expect(
            outlineBeatsHaveSameContent(restored.beats, original.beats),
            true,
          );
          expect(
            restored.beats.map((b) => b.createdAt),
            original.beats.map((b) => b.createdAt),
          );
          expect(restored.content, 'outside field retained');
          expect(
            (await db.workingChangeDao.getById(change.id))!.status,
            workingChangeStatusRejected,
          );
          final beforeRepeat = [
            (await db.select(db.outlineBeats).get())
                .map((r) => r.toJson())
                .toList(),
            (await db.select(db.workingChanges).get())
                .map((r) => r.toJson())
                .toList(),
            (await db.select(db.changeCommits).get())
                .map((r) => r.toJson())
                .toList(),
          ];
          await rollback();
          expect([
            (await db.select(db.outlineBeats).get())
                .map((r) => r.toJson())
                .toList(),
            (await db.select(db.workingChanges).get())
                .map((r) => r.toJson())
                .toList(),
            (await db.select(db.changeCommits).get())
                .map((r) => r.toJson())
                .toList(),
          ], beforeRepeat);
        },
      );
    }
  });

  group('shared resource target', () {
    test('deep outline paths fail before every read or mutation', () async {
      await seedOutline(title: 'a', beats: [beat('A', '原文')]);
      await seedOutline(title: 'b', beats: [beat('B', '原文')]);
      Future<List<Object?>> snapshot() async => [
        (await db.select(db.outlines).get())
            .map((row) => row.toJson())
            .toList(),
        (await db.select(db.outlineBeats).get())
            .map((row) => row.toJson())
            .toList(),
        (await db.select(db.workingChanges).get())
            .map((row) => row.toJson())
            .toList(),
      ];
      final before = await snapshot();
      for (final path in [
        'outlines/a/b',
        'outlines/a/b/status',
        'outlines/a/b/beats',
        'outlines/a/beats/no_index/unknown',
      ]) {
        for (final call in <(String, Map<String, dynamic>)>[
          ('Read', {'path': path}),
          ('Write', {'path': path, 'value': outlineStatusFinished}),
          ('Edit', {'path': path, 'old_text': '原文', 'new_text': '修改'}),
          (
            'Create',
            {
              'path': path,
              'fields': {'title': '新拍'},
            },
          ),
          ('Remove', {'path': path, 'force': true}),
          ('Glob', {'path': path, 'pattern': '**'}),
          ('Grep', {'path': path, 'pattern': '原文'}),
          (
            'Replace',
            {
              'path': path,
              'pattern': '原文',
              'replacement': '修改',
              'dry_run': false,
            },
          ),
        ]) {
          final result = await toolManager.executeTool(
            name: call.$1,
            input: call.$2,
          );
          expect(
            result['error_code'],
            'invalid_argument',
            reason: '${call.$1} $path: $result',
          );
          expect(
            await snapshot(),
            before,
            reason: '${call.$1} $path changed data',
          );
        }
      }
    });

    for (final title in ['beats', 'title', 'content', '0']) {
      test(
        'reserved title $title has normal outline and beat operations',
        () async {
          await seedOutline(title: title, beats: [beat('第一拍', '原文')]);
          final base = 'outlines/$title';
          Future<Map<String, dynamic>> call(
            String name,
            Map<String, dynamic> input,
          ) => toolManager.executeTool(name: name, input: input);
          expect(
            (await call('Read', {'path': '$base/content'}))['value'],
            '旧总览',
          );
          expect(
            (await call('Edit', {
              'path': '$base/content',
              'old_text': '旧',
              'new_text': '新',
            }))['edited'],
            true,
          );
          expect(
            (await call('Write', {
              'path': '$base/status',
              'value': outlineStatusFinished,
            }))['updated'],
            true,
          );
          expect(
            (await call('Read', {
              'path': '$base/beats/${await firstBeatId(title)}/content',
            }))['value'],
            '原文',
          );
          expect(
            (await call('Edit', {
              'path': '$base/beats/${await firstBeatId(title)}/content',
              'old_text': '原文',
              'new_text': '拍正文',
            }))['edited'],
            true,
          );
          expect(
            (await call('Write', {
              'path': '$base/beats/${await firstBeatId(title)}/chapter_count',
              'value': '3',
            }))['updated'],
            true,
          );
          expect(
            (await call('Read', {
              'path': '$base/beats/${await firstBeatId(title)}/chapter_count',
            }))['value'],
            3,
          );
          final created = await call('Create', {
            'path': '$base/beats',
            'fields': {'title': '第二拍'},
          });
          expect(created['created'], true, reason: '$created');
          final listing = await call('Read', {'path': '$base/beats'});
          for (final entry in listing['entries'] as List) {
            expect(
              (await call('Read', {'path': entry['path']}))['id'],
              entry['id'],
            );
          }
          final grep = await call('Grep', {'path': base, 'pattern': '拍正文'});
          expect(
            grep.toString(),
            contains('$base/beats/${await firstBeatId(title)}/content'),
          );
          final replace = await call('Replace', {
            'path': base,
            'pattern': '拍正文',
            'replacement': '替换正文',
            'dry_run': false,
          });
          expect(replace['error'], isNull, reason: '$replace');
          expect(
            (await call('Read', {
              'path': '$base/beats/${await firstBeatId(title)}/content',
            }))['value'],
            '替换正文',
          );
          expect(
            (await call('Remove', {
              'path': '$base/beats/${await firstBeatId(title)}',
              'force': true,
            }))['removed'],
            true,
          );
          final write = await call('Write', {
            'path': '$base/beats',
            'value': [
              {'title': '覆盖拍', 'content': '覆盖正文'},
            ],
          });
          expect(write['updated'], true, reason: '$write');
          expect((await call('Remove', {'path': base}))['removed'], true);
        },
      );
    }
  });

  group('CreateOutline', () {
    test('outline details and listings expose the stored id', () async {
      final outline = await seedOutline();
      final listing = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines'},
      );
      final entry = (listing['entries'] as List).single;
      expect(entry['id'], outline.documentId);
      final detail = await toolManager.executeTool(
        name: 'Read',
        input: {'path': entry['path']},
      );
      expect(detail['id'], outline.documentId);
      expect(detail['title'], outline.title);
      final createdBeat = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': '${entry['path']}/beats',
          'fields': {'title': '新拍'},
        },
      );
      final beatRead = await toolManager.executeTool(
        name: 'Read',
        input: {'path': createdBeat['path']},
      );
      expect(createdBeat['id'], isA<String>());
      expect(beatRead['id'], createdBeat['id']);
    });

    test('Create failure on outlines carries the field contract', () async {
      // 字段契约只在失败时按路径返回，不再常驻 _links.create。
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {'content': '缺标题'},
        },
      );

      expect(result['ok'], isFalse);
      final contract = result['input_contract'] as Map<String, dynamic>;
      expect(contract['allowed_fields'], [
        'title',
        'content',
        'status',
        'start_chapter_num',
        'beats',
      ]);
      expect(contract['required_fields'], ['title']);
      expect(result.containsKey('_schemas'), isFalse);
    });

    test('unified Create creates an outline from /outlines', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {
            'title': 'AI 大纲',
            'content': '临时内容',
            'beats': [
              {'title': '第一拍', 'content': '确认时间线和身份', 'chapter_count': 2},
            ],
          },
        },
      );

      expect(result['created'], isTrue);
      expect(result['path'], 'outlines/AI 大纲');
      expect(result.containsKey('_links'), isFalse);
      expect(result.containsKey('working_change_id'), isFalse);
      final change = await onlyActiveWorkingChange(db);
      expect(change.toolName, 'Create');
    });

    test('Create rejects path separators in title with a hint', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {'title': '伏笔/节奏清单'},
        },
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
      expect(result['hint'], contains('replace "/" with "-"'));
      expect(result.containsKey('exception_type'), isFalse);
      expect(await contentService.outlineService.getAll(), isEmpty);
    });

    test('Write replaces outline content like other collections', () async {
      final outline = await seedOutline();

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'outlines/主线/content', 'value': '新总览'},
      );

      expect(result['ok'], isNot(isFalse));
      expect(result['updated'], isTrue);
      await accept(await onlyActiveWorkingChangeId(db));
      final stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.content, '新总览');
    });

    test('unified Create suffixes a duplicate outline title', () async {
      await seedOutline(title: 'AI 大纲');

      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {'title': 'AI 大纲', 'content': '第二份大纲'},
        },
      );

      expect(result['created'], isTrue);
      expect(result['path'], 'outlines/AI 大纲 (2)');
      final stored = await contentService.outlineService.getByDocumentId(
        result['id'] as String,
      );
      expect(stored!.title, 'AI 大纲 (2)');
    });

    test('unified Create persists start_chapter_num', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {'title': '感情线', 'start_chapter_num': 12},
        },
      );

      final stored = await contentService.outlineService.getByDocumentId(
        result['id'] as String,
      );
      expect(stored!.startChapterNum, 12);
    });

    test('unified Create rejects invalid start_chapter_num', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {'title': '感情线', 'start_chapter_num': 0},
        },
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
    });

    test(
      'Create trims outer whitespace and preserves internal indentation in outline content',
      () async {
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines',
            'fields': {'title': '缩进大纲', 'content': '　　总览第一行'},
          },
        );

        expect(result['created'], isTrue);
        final stored = await contentService.outlineService.getByDocumentId(
          result['id'] as String,
        );
        expect(stored!.content, '　　总览第一行'.trim());
      },
    );

    test('creates structured beats from beats field', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {
            'title': 'AI 大纲',
            'content': '临时内容',
            'beats': [
              {'title': '第一拍', 'content': '确认时间线和身份', 'chapter_count': 2},
              {'title': '第二拍', 'content': '寻找盟友', 'chapterCount': 3},
            ],
          },
        },
      );

      final outlineId = result['id'] as String;
      final stored = await contentService.outlineService.getByDocumentId(
        outlineId,
      );

      expect(stored, isNotNull);
      expect(stored!.beats.map((item) => item.title), ['第一拍', '第二拍']);
      expect(stored.beats.map((item) => item.chapterCount), [2, 3]);
    });

    test(
      'Create trims outer whitespace and preserves internal indentation in outline beat content',
      () async {
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines',
            'fields': {
              'title': '节拍缩进',
              'beats': [
                {'title': '第一拍', 'content': '　　确认线索'},
              ],
            },
          },
        );

        expect(result['created'], isTrue);
        final stored = await contentService.outlineService.getByDocumentId(
          result['id'] as String,
        );
        expect(stored!.beats.single.content, '　　确认线索'.trim());
      },
    );

    test('reject removes the staged structured outline', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {'title': 'AI 大纲', 'content': '临时内容'},
        },
      );

      final outlineId = result['id'] as String;
      expect(
        await contentService.outlineService.getByDocumentId(outlineId),
        isNotNull,
      );

      await overlay.rejectWorkingChange(await onlyActiveWorkingChangeId(db));

      expect(
        await contentService.outlineService.getByDocumentId(outlineId),
        isNull,
      );
    });
  });

  group('EditOutline', () {
    test(
      'unified Create appends a beat through outlines/{name}/beats',
      () async {
        await seedOutline();

        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines/主线/beats',
            'fields': {'title': '第一拍', 'content': '节拍内容', 'chapter_count': 2},
          },
        );

        expect(result['created'], isTrue);
        expect(result['path'], 'outlines/主线/beats/${await firstBeatId()}');
        expect(result.containsKey('_links'), isFalse);
        final stored = await contentService.outlineService.getByTitle('主线');
        expect(stored!.beats.single.content, '节拍内容');
      },
    );

    test(
      'unified Create trims outer whitespace in appended beat content',
      () async {
        await seedOutline();

        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines/主线/beats',
            'fields': {'title': '第一拍', 'content': '　　节拍内容'},
          },
        );

        expect(result['created'], isTrue);
        final stored = await contentService.outlineService.getByTitle('主线');
        expect(stored!.beats.single.content, '　　节拍内容'.trim());
      },
    );

    test('read can access outline beat content by index path', () async {
      await seedOutline(beats: [beat('第一拍', '节拍内容')]);

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/beats/${await firstBeatId()}/content'},
      );

      expect(
        result['path'],
        'outlines/主线/beats/${await firstBeatId()}/content',
      );
      expect(result['value'], '节拍内容');
    });

    test('read exposes the supported outline beat fields', () async {
      await seedOutline(
        beats: [
          contentService.outlineService.createBeatDraft(
            title: '第一拍',
            content: '节拍内容',
            chapterCount: 3,
          ),
        ],
      );

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/beats/${await firstBeatId()}'},
      );

      expect(result['index'], 0);
      expect(result['id'], isA<String>().having((id) => id, 'id', isNotEmpty));
      expect(result['title'], '第一拍');
      expect(result['content'], '节拍内容');
      expect(result['status'], outlineStatusPending);
      expect(result['chapter_count'], 3);
      expect(result.containsKey('sort_order'), isFalse);
    });

    test(
      'Create failure on outlines/{name}/beats carries the field contract',
      () async {
        await seedOutline();

        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines/主线/beats',
            'fields': {'content': '缺标题'},
          },
        );

        expect(result['ok'], isFalse);
        final contract = result['input_contract'] as Map<String, dynamic>;
        expect(contract['input'], {
          'path': 'outlines/主线/beats',
          'fields': <String, dynamic>{},
        });
        expect(contract['allowed_fields'], [
          'title',
          'content',
          'status',
          'chapter_count',
          'index',
        ]);
        expect(contract['required_fields'], ['title']);
        expect(result.containsKey('_schemas'), isFalse);
      },
    );

    test('read can access outline beat id by index path', () async {
      await seedOutline(beats: [beat('第一拍', '节拍内容')]);

      final beatResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/beats/${await firstBeatId()}'},
      );
      final idResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/beats/${await firstBeatId()}/id'},
      );

      expect(idResult['path'], 'outlines/主线/beats/${await firstBeatId()}/id');
      expect(idResult['value'], beatResult['id']);
    });

    test('read can access outline beat chapter count by index path', () async {
      await seedOutline(
        beats: [
          contentService.outlineService.createBeatDraft(
            title: '第一拍',
            content: '节拍内容',
            chapterCount: 3,
          ),
        ],
      );

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {
          'path': 'outlines/主线/beats/${await firstBeatId()}/chapter_count',
        },
      );

      expect(
        result['path'],
        'outlines/主线/beats/${await firstBeatId()}/chapter_count',
      );
      expect(result['value'], 3);
    });

    test('read rejects unsupported outline top-level fields', () async {
      await seedOutline(beats: [beat('第一拍', '节拍内容')]);

      final tagsResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/tags'},
      );
      final chapterCountResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/chapter_count'},
      );

      expect(tagsResult['error_code'], 'invalid_argument');
      expect(chapterCountResult['error_code'], 'invalid_argument');
    });

    test('read exposes outline start chapter number', () async {
      await seedOutline(startChapterNum: 12);

      final detailResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线'},
      );
      final fieldResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/start_chapter_num'},
      );

      expect(detailResult['start_chapter_num'], 12);
      expect(fieldResult['path'], 'outlines/主线/start_chapter_num');
      expect(fieldResult['value'], 12);
    });

    test('read rejects an ID missing from its parent', () async {
      await seedOutline(beats: [beat('第一拍', '节拍内容')]);

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/beats/o'},
      );

      expect(result['error_code'], 'not_found');
    });

    test('empty content can be initialized with empty old_text', () async {
      final outline = await seedOutline(content: '');

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/content',
          'old_text': '',
          'new_text': '新大纲内容',
          'all': true,
        },
      );

      expect(result['edited'], isTrue);
      expect(result['match_count'], 1);

      var stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.content, '新大纲内容');

      await accept(await onlyActiveWorkingChangeId(db));

      stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.content, '新大纲内容');
    });

    test('empty old_text is still rejected for non-empty content', () async {
      await seedOutline(content: '已有内容');

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/content',
          'old_text': '',
          'new_text': '新大纲内容',
          'all': true,
        },
      );

      expect(result['error'], 'old_text must not be empty');
    });

    test(
      'content edit writes raw outline content and preserves beats on accept',
      () async {
        final outline = await seedOutline(
          content: '旧总览',
          beats: [beat('第一拍', '旧节拍内容')],
        );

        await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'outlines/主线/content',
            'old_text': '旧总览',
            'new_text': '新总览',
          },
        );

        var stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.content, '新总览');
        expect(stored.beats.single.content, '旧节拍内容');

        final readResult = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'outlines/主线/content'},
        );
        expect(readResult['value'], contains('新总览'));

        await accept(await onlyActiveWorkingChangeId(db));

        stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.content, '新总览');
        expect(stored.beats.single.content, '旧节拍内容');
      },
    );

    test('beat path edit applies immediately and accept records it', () async {
      final outline = await seedOutline(beats: [beat('第一拍', '旧节拍内容')]);

      await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/beats/${await firstBeatId()}/content',
          'old_text': '旧节拍内容',
          'new_text': '新节拍内容',
        },
      );

      var stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.single.content, '新节拍内容');

      await accept(await onlyActiveWorkingChangeId(db));

      stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.single.content, '新节拍内容');
    });

    test('beats path replaces the whole beat list immediately', () async {
      final outline = await seedOutline(beats: [beat('旧拍', '旧内容')]);

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'outlines/主线/beats',
          'value': [
            {'title': '穿越降临', 'content': '确认时间线和身份，适应新环境', 'chapter_count': 10},
            {'title': '找到盟友', 'content': '遇见苏瑶，组建初始团队', 'chapter_count': 20},
          ],
        },
      );

      expect(result['updated'], isTrue);
      expect(result['beat_count'], 2);
      expect(result['previous_beat_count'], 1);

      var stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.map((item) => item.title), ['穿越降临', '找到盟友']);

      final readBeforeAccept = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'outlines/主线/beats'},
      );
      final entries = readBeforeAccept['entries'] as List;
      expect(entries.map((item) => item['title']), ['穿越降临', '找到盟友']);

      await accept(await onlyActiveWorkingChangeId(db));

      stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.map((item) => item.title), ['穿越降临', '找到盟友']);
      expect(stored.beats.map((item) => item.chapterCount), [10, 20]);
    });

    test('empty value clears existing beats explicitly', () async {
      final outline = await seedOutline(beats: [beat('旧拍', '旧内容')]);

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'outlines/主线/beats', 'value': <dynamic>[]},
      );

      expect(result['updated'], isTrue);
      expect(result['beat_count'], 0);
      expect(result['previous_beat_count'], 1);

      await accept(await onlyActiveWorkingChangeId(db));

      final stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats, isEmpty);
    });

    test('beats write rejects missing value argument', () async {
      await seedOutline(beats: [beat('旧拍', '旧内容')]);

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'outlines/主线/beats'},
      );

      expect(result['error_code'], 'invalid_argument');
      expect(result['error'], 'Missing beats in fields.');
    });

    test('Edit on the beats listing points at Write', () async {
      await seedOutline(beats: [beat('旧拍', '旧内容')]);

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/beats',
          'old_text': '旧内容',
          'new_text': '新内容',
        },
      );

      expect(result['error_code'], 'unsupported');
      expect(result['error'], contains('Write on outlines/主线/beats'));

      final stored = await contentService.outlineService.getByTitle('主线');
      expect(stored!.beats.single.content, '旧内容');
    });
  });

  group('WriteOutlineScalar', () {
    test(
      'Write outline resource rolls back the first write when the second fails',
      () async {
        final outline = await seedOutline();
        final failingOverlay = _FailingOutlineOverlay(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        );
        final manager = AiToolManager(
          contentService,
          workingOverlayService: failingOverlay,
        )..registerAllTools();
        addTearDown(manager.dispose);
        await expectLater(
          manager.executeTool(
            name: 'Write',
            input: {
              'path': 'outlines/主线',
              'fields': {'status': 'finished', 'start_chapter_num': 12},
            },
          ),
          throwsStateError,
        );
        expect(failingOverlay.completedFields, ['status']);
        final stored = (await contentService.outlineService.getByTitle('主线'))!;
        expect(stored.status, outline.status);
        expect(stored.startChapterNum, outline.startChapterNum);
        expect(stored.updatedAt, outline.updatedAt);
        expect(await db.workingChangeDao.getAll(), isEmpty);
      },
    );

    for (final prefix in ['', '/works/current/']) {
      test(
        'Write outline resource $prefix updates both fields and rolls back the commit',
        () async {
          final outline = await seedOutline(beats: [beat('A', '正文')]);
          final scoped = AiToolManager(
            contentService,
            workingOverlayService: overlay,
            workId: 'current',
          )..registerAllTools();
          addTearDown(scoped.dispose);
          final input = {
            'path': '${prefix}outlines/主线',
            'fields': {'status': 'finished', 'start_chapter_num': 12},
          };
          final result = await scoped.executeTool(name: 'Write', input: input);
          expect(result['ok'], isTrue);
          expect(result['path'], input['path']);
          expect(result['updated'], isTrue);
          final stored = (await contentService.outlineService.getByTitle(
            '主线',
          ))!;
          expect(stored.status, 'finished');
          expect(stored.startChapterNum, 12);
          expect(stored.content, outline.content);
          expect(stored.encodeTimelineJson(), outline.encodeTimelineJson());
          final changes = await db.workingChangeDao.getAll();
          expect(changes, hasLength(2));
          expect(
            changes.map((c) => c.field),
            unorderedEquals(['status', 'start_chapter_num']),
          );
          final unchanged = await scoped.executeTool(
            name: 'Write',
            input: input,
          );
          expect(unchanged['updated'], isFalse);
          expect(await db.workingChangeDao.getAll(), hasLength(2));
          final commitId = await overlay.commitWorkingChanges(
            changes.map((c) => c.id).toList(),
            source: workingChangeSourceAi,
            message: 'outline patch',
          );
          expect(commitId, isNotNull);
          await overlay.rollbackCommit(commitId: commitId!);
          final restored = (await contentService.outlineService.getByTitle(
            '主线',
          ))!;
          expect(restored.status, outline.status);
          expect(restored.startChapterNum, outline.startChapterNum);
          expect(restored.encodeTimelineJson(), outline.encodeTimelineJson());
        },
      );
    }

    test(
      'Write outline resource rejects invalid patches and preserves omitted fields',
      () async {
        final outline = await seedOutline();
        for (final fields in <Map<String, dynamic>>[
          {'status': 'finished', 'start_chapter_num': 0},
          {'status': 'invalid', 'start_chapter_num': 12},
          {},
        ]) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {'path': 'outlines/主线', 'fields': fields},
          );
          expect(result['ok'], isFalse);
          final stored = (await contentService.outlineService.getByTitle(
            '主线',
          ))!;
          expect(stored.status, outline.status);
          expect(stored.startChapterNum, outline.startChapterNum);
          expect(stored.content, outline.content);
          expect(await db.workingChangeDao.getAll(), isEmpty);
        }
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线',
            'fields': {'start_chapter_num': '8.6'},
          },
        );
        expect(result['ok'], isTrue);
        final stored = (await contentService.outlineService.getByTitle('主线'))!;
        expect(stored.status, outline.status);
        expect(stored.startChapterNum, 9);
        expect((await onlyActiveWorkingChange(db)).field, 'start_chapter_num');
        for (final ignored in ['beats']) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {
              'path': 'outlines/主线',
              'fields': {'status': 'finished', ignored: '不可覆盖'},
            },
          );
          expect(result['ok'], isTrue, reason: '$result');
          expect(result['ignored_fields'], [ignored]);
          final stored = (await contentService.outlineService.getByTitle(
            '主线',
          ))!;
          expect(stored.status, 'finished');
          expect(stored.content, outline.content);
          expect(stored.encodeTimelineJson(), outline.encodeTimelineJson());
        }
      },
    );

    test(
      'Write beat resource respects outline ownership and current-work absolute paths',
      () async {
        final outline = await seedOutline(beats: [beat('A', '正文')]);
        final foreign = await seedOutline(
          title: '另一纲',
          beats: [beat('B', '其他正文')],
        );
        final scoped = AiToolManager(
          contentService,
          workingOverlayService: overlay,
          workId: 'current',
        )..registerAllTools();
        addTearDown(scoped.dispose);
        for (final call in [
          ('outlines/主线/beats/${foreign.beats.single.id}', 'not_found'),
          (
            '/works/other/outlines/主线/beats/${outline.beats.single.id}',
            'permission_denied',
          ),
        ]) {
          final rejected = await scoped.executeTool(
            name: 'Write',
            input: {
              'path': call.$1,
              'fields': {'status': 'finished', 'chapter_count': 5},
            },
          );
          expect(rejected['ok'], isFalse);
          expect(rejected['error_code'], call.$2);
          expect(await db.workingChangeDao.getAll(), isEmpty);
        }
        final path =
            '/works/current/outlines/主线/beats/${outline.beats.single.id}';
        final created = await scoped.executeTool(
          name: 'Write',
          input: {
            'path': path,
            'fields': {'status': 'finished', 'chapter_count': 5},
          },
        );
        expect(created['ok'], isTrue);
        expect(created['path'], path);
        final saved = (await contentService.outlineService.getByTitle('主线'))!;
        expect(saved.beats.single.status, 'finished');
        expect(saved.beats.single.chapterCount, 5);
        final other = (await contentService.outlineService.getByTitle('另一纲'))!;
        expect(other.beats.single.toJson(), foreign.beats.single.toJson());
      },
    );

    test(
      'Write beat resource updates fields together and supports no-op and rollback',
      () async {
        final outline = await seedOutline(
          beats: [beat('A', '正文 A'), beat('B', '正文 B')],
        );
        final target = outline.beats.first;
        final path = 'outlines/主线/beats/${target.id}';
        final input = {
          'path': path,
          'fields': {'status': 'finished', 'chapter_count': 5},
        };

        final result = await toolManager.executeTool(
          name: 'Write',
          input: input,
        );
        expect(result['ok'], isTrue);
        expect(result['path'], path);
        expect(result['updated'], isTrue);
        final stored = (await contentService.outlineService.getByTitle('主线'))!;
        expect(stored.beats.first.id, target.id);
        expect(stored.beats.first.status, 'finished');
        expect(stored.beats.first.chapterCount, 5);
        expect(stored.beats.first.content, target.content);
        expect(stored.beats.last.toJson(), outline.beats.last.toJson());
        final change = await onlyActiveWorkingChange(db);
        expect(change.resourcePath, 'outlines/${outline.documentId}/beats');
        expect(await db.workingChangeDao.getAll(), hasLength(1));

        final unchanged = await toolManager.executeTool(
          name: 'Write',
          input: input,
        );
        expect(unchanged['updated'], isFalse);
        expect(await db.workingChangeDao.getAll(), hasLength(1));
        await overlay.rejectWorkingChange(change.id);
        final restored = (await contentService.outlineService.getByTitle(
          '主线',
        ))!;
        expect(
          restored.beats.map((b) => b.toJson()),
          outline.beats.map((b) => b.toJson()),
        );
      },
    );

    test(
      'Write beat resource validates the entire patch before changing data',
      () async {
        final outline = await seedOutline(beats: [beat('A', '原文')]);
        final path = 'outlines/主线/beats/${outline.beats.first.id}';
        for (final fields in <Map<String, dynamic>>[
          {'status': 'finished', 'chapter_count': 0},
          {'status': 'invalid', 'chapter_count': 5},
          {},
        ]) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {'path': path, 'fields': fields},
          );
          expect(result['ok'], isFalse);
          final stored = (await contentService.outlineService.getByTitle(
            '主线',
          ))!;
          expect(stored.beats.single.toJson(), outline.beats.single.toJson());
          expect(await db.workingChangeDao.getAll(), isEmpty);
        }
        final partial = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': path,
            'fields': {'chapter_count': '5.2'},
          },
        );
        expect(partial['ok'], isTrue);
        final stored = (await contentService.outlineService.getByTitle('主线'))!;
        expect(stored.beats.single.chapterCount, 5);
        expect(stored.beats.single.status, outline.beats.single.status);
        final withIgnored = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': path,
            'fields': {
              'status': 'finished',
              'content': '不能覆盖',
              'id': 'another-beat',
            },
          },
        );
        expect(withIgnored['ok'], isTrue, reason: '$withIgnored');
        expect(withIgnored['ignored_fields'], ['content', 'id']);
        final updated = (await contentService.outlineService.getByTitle('主线'))!;
        expect(updated.beats.single.status, 'finished');
        expect(updated.beats.single.id, outline.beats.single.id);
        expect(updated.beats.single.content, outline.beats.single.content);
      },
    );

    test(
      'Write updates beat status immediately and accept records it',
      () async {
        final outline = await seedOutline(beats: [beat('第一拍', '内容')]);

        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线/beats/${await firstBeatId()}/status',
            'value': outlineStatusInProgress,
          },
        );

        expect(result['updated'], isTrue);
        expect(
          result['path'],
          'outlines/主线/beats/${await firstBeatId()}/status',
        );

        var stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.beats.single.status, outlineStatusInProgress);

        await accept(await onlyActiveWorkingChangeId(db));

        stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.beats.single.status, outlineStatusInProgress);
      },
    );

    test(
      'Write updates beat chapter_count immediately and accept records it',
      () async {
        final outline = await seedOutline(beats: [beat('第一拍', '内容')]);

        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线/beats/${await firstBeatId()}/chapter_count',
            'value': 5,
          },
        );

        expect(result['updated'], isTrue);

        var stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.beats.single.chapterCount, 5);

        await accept(await onlyActiveWorkingChangeId(db));

        stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.beats.single.chapterCount, 5);
      },
    );

    test(
      'Write updates outline document status immediately and accept records it',
      () async {
        final outline = await seedOutline();

        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'outlines/主线/status',
            'value': outlineStatusInProgress,
          },
        );

        expect(result['updated'], isTrue);
        expect(result['path'], 'outlines/主线/status');

        var stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.status, outlineStatusInProgress);

        await accept(await onlyActiveWorkingChangeId(db));

        stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.status, outlineStatusInProgress);
      },
    );

    test(
      'Write updates outline start_chapter_num immediately and accept records it',
      () async {
        final outline = await seedOutline();

        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'outlines/主线/start_chapter_num', 'value': 12},
        );

        expect(result['updated'], isTrue);
        expect(result['path'], 'outlines/主线/start_chapter_num');

        var stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.startChapterNum, 12);

        await accept(await onlyActiveWorkingChangeId(db));

        stored = await contentService.outlineService.getByDocumentId(
          outline.documentId,
        );
        expect(stored!.startChapterNum, 12);
      },
    );

    test('Write rejects invalid outline start_chapter_num', () async {
      await seedOutline();

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'outlines/主线/start_chapter_num', 'value': 0},
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
    });

    test('Write rejects invalid beat status', () async {
      await seedOutline(beats: [beat('第一拍', '内容')]);

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'outlines/主线/beats/${await firstBeatId()}/status',
          'value': 'not_a_status',
        },
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
    });
  });

  group('EditOutlineRedirects', () {
    test('Edit beat status redirects to Write', () async {
      await seedOutline(beats: [beat('第一拍', '内容')]);

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/beats/${await firstBeatId()}/status',
          'old_text': 'pending',
          'new_text': 'in_progress',
        },
      );

      expect(result['error_code'], 'unsupported');
      expect(result['path'], 'outlines/主线/beats/${await firstBeatId()}/status');
    });

    test('Edit outline status path redirects to Write', () async {
      await seedOutline();

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/status',
          'old_text': 'pending',
          'new_text': 'in_progress',
        },
      );

      expect(result['error_code'], 'unsupported');
      expect(result['path'], 'outlines/主线/status');
    });

    test('Edit outline start chapter path redirects to Write', () async {
      await seedOutline();

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/start_chapter_num',
          'old_text': '1',
          'new_text': '12',
        },
      );

      expect(result['error_code'], 'unsupported');
      expect(result['path'], 'outlines/主线/start_chapter_num');
    });
  });

  group('CreateBeat', () {
    test('index inserts the beat immediately and accept records it', () async {
      final outline = await seedOutline(beats: [beat('A', ''), beat('C', '')]);

      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines/主线/beats',
          'fields': {'title': 'B', 'content': 'B 内容', 'index': 1},
        },
      );

      expect(result['beat_index'], 1);
      var stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.map((item) => item.title), ['A', 'B', 'C']);
      // 插入后 sortOrder 必须重新编号成连续下标，不能留下重复值。
      expect(stored.beats.map((item) => item.sortOrder), [0, 1, 2]);

      await accept(await onlyActiveWorkingChangeId(db));

      stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.map((item) => item.title), ['A', 'B', 'C']);
      expect(stored.beats.map((item) => item.sortOrder), [0, 1, 2]);
    });
  });

  group('EditBeat', () {
    test('reject leaves the existing beat unchanged', () async {
      final outline = await seedOutline(beats: [beat('旧标题', '旧内容')]);

      await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'outlines/主线/beats/${await firstBeatId()}/title',
          'old_text': '旧标题',
          'new_text': '新标题',
        },
      );

      var stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.single.title, '新标题');

      await overlay.rejectWorkingChange(await onlyActiveWorkingChangeId(db));

      stored = await contentService.outlineService.getByDocumentId(
        outline.documentId,
      );
      expect(stored!.beats.single.title, '旧标题');
    });
  });
}

class _FailingOutlineOverlay extends WorkingOverlayService {
  _FailingOutlineOverlay(
    super.db,
    super.service, {
    required super.novelActionsService,
  });

  final completedFields = <String?>[];

  @override
  Future<WorkingChange> stageTextChange({
    required String resourcePath,
    required String resourceType,
    required String? resourceId,
    required String? field,
    required String? oldText,
    required String newText,
    required String source,
    String? sourceSessionId,
    String? sourceTurnId,
    String? toolName,
    String? summary,
    String? expectedCurrentText,
    bool restoreHistory = false,
  }) async {
    if (field == 'start_chapter_num') {
      throw StateError('injected second outline field failure');
    }
    final result = await super.stageTextChange(
      resourcePath: resourcePath,
      resourceType: resourceType,
      resourceId: resourceId,
      field: field,
      oldText: oldText,
      newText: newText,
      source: source,
      sourceSessionId: sourceSessionId,
      sourceTurnId: sourceTurnId,
      toolName: toolName,
      summary: summary,
      expectedCurrentText: expectedCurrentText,
      restoreHistory: restoreHistory,
    );
    completedFields.add(field);
    return result;
  }
}
