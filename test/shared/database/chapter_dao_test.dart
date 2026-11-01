// 职责: 测试 ChapterDao 和 chapters VIEW — CRUD、树操作、VIEW 计算列
// 关联文件:
//   lib/shared/database/novel_content_daos/chapter_dao.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/chapter.dart

import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_daos/chapter_dao.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/chapter_comment.dart';

void main() {
  late NovelContentDatabase db;
  late ChapterDao dao;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    dao = db.chapterDao;
  });

  tearDown(() async {
    await db.close();
  });

  group('ChapterDao', () {
    test(
      'id lookup filters by actual node types without changing unfiltered callers',
      () async {
        for (final type in [nodeTypeChapter, nodeTypeExtra, nodeTypeVolume]) {
          await dao.insert(
            ChaptersCompanion.insert(id: type, type: type, siblingOrder: 1),
          );
        }
        const chapterTypes = {nodeTypeChapter, nodeTypeExtra};
        expect(
          (await dao.getById(nodeTypeChapter, types: chapterTypes))!.type,
          nodeTypeChapter,
        );
        expect(
          (await dao.getById(nodeTypeExtra, types: chapterTypes))!.type,
          nodeTypeExtra,
        );
        expect(await dao.getById(nodeTypeVolume, types: chapterTypes), isNull);
        expect(
          (await dao.getById(nodeTypeVolume, types: {nodeTypeVolume}))!.type,
          nodeTypeVolume,
        );
        expect(
          await dao.getById(nodeTypeChapter, types: {nodeTypeVolume}),
          isNull,
        );
        expect(await dao.getById(nodeTypeChapter, types: {}), isNull);
        expect(await dao.getById('missing', types: chapterTypes), isNull);
        expect((await dao.getById(nodeTypeVolume))!.type, nodeTypeVolume);
        await dao.softDelete(nodeTypeChapter);
        expect(await dao.getById(nodeTypeChapter, types: chapterTypes), isNull);
      },
    );

    test(
      'last edited picks the most recently updated chapter with text',
      () async {
        Future<void> add(String id, int order, int words, DateTime at) =>
            dao.insert(
              ChaptersCompanion.insert(
                id: id,
                type: nodeTypeChapter,
                siblingOrder: order,
                content: Value('$id body'),
                wordCount: Value(words),
                updatedAt: Value(at),
              ),
            );
        // 「上次写到」按最后改动，而不是章号最大的那章；空章不算写过。
        await add('early', 1, 120, DateTime(2026, 1, 3));
        await add('late', 2, 80, DateTime(2026, 1, 1));
        await add('empty', 3, 0, DateTime(2026, 1, 5));
        expect((await dao.watchLastEdited().first)!.id, 'early');
        expect((await dao.watchLastWritten().first)!.id, 'late');
      },
    );

    test('insert and read a root-level chapter', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('第一章'),
          outline: const Value('outline'),
          content: const Value('content'),
          wordCount: const Value(100),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final all = await dao.getAll();
      expect(all.length, 1);
      expect(all.first.id, 'ch_1');
      expect(all.first.title, '第一章');
      expect(all.first.type, nodeTypeChapter);
      expect(all.first.siblingOrder, 1);
      expect(all.first.chapterNum, 1);
      expect(all.first.volumeNum, isNull);
      expect(all.first.volumeChapterNum, isNull);
    });

    test(
      'tree keeps metadata light while content lookup includes chronicler fields',
      () async {
        await dao.insert(
          ChaptersCompanion.insert(
            id: 'ch_1',
            type: nodeTypeChapter,
            parentId: const Value(null),
            siblingOrder: 1,
            title: const Value('第一章'),
            brief: const Value('本章摘要'),
            events: const Value([
              {'title': '密室交易', 'summary': '换回卖身契'},
            ]),
            comments: Value([
              ChapterComment(
                id: 'comment_1',
                start: 0,
                end: 2,
                quote: '本章',
                content: '这里再压一压',
                createdAt: DateTime.fromMillisecondsSinceEpoch(1000000000000),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(1000000000000),
              ),
            ]),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

        final treeChapter = (await dao.getTree()).single;
        expect(treeChapter.brief, isEmpty);
        expect(treeChapter.events, isNull);

        final detailChapter = await dao.watchContentById('ch_1').first;
        expect(detailChapter?.brief, '本章摘要');
        expect(detailChapter?.events, [
          {'title': '密室交易', 'summary': '换回卖身契'},
        ]);
        // 批注列曾漏在 watchContentById 的手写列清单外，编辑器因此读不到已存批注。
        expect(detailChapter?.comments?.single.content, '这里再压一压');
      },
    );

    test('watchAll emits after inserting a chapter node', () async {
      final queue = StreamIterator(dao.watchAll());
      addTearDown(queue.cancel);

      expect(await queue.moveNext(), isTrue);
      expect(queue.current, isEmpty);

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('第一章'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await queue.moveNext().timeout(const Duration(seconds: 1));
      final next = queue.current;
      expect(next.map((chapter) => chapter.id), contains('ch_1'));
    });

    test('insert and read a volume', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('第一卷'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final all = await dao.getAll();
      expect(all.length, 1);
      expect(all.first.isVolume, isTrue);
      expect(all.first.isChapter, isFalse);
      expect(all.first.chapterNum, isNull);
      expect(all.first.volumeNum, 1);
    });

    test('chapters under a volume get correct volume_chapter_num', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('第一卷'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value('vol_1'),
          siblingOrder: 1,
          title: const Value('第一章'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'extra_1',
          type: nodeTypeExtra,
          parentId: const Value('vol_1'),
          siblingOrder: 2,
          title: const Value('番外'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_2',
          type: nodeTypeChapter,
          parentId: const Value('vol_1'),
          siblingOrder: 3,
          title: const Value('第二章'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final all = await dao.getAll();
      expect(all.length, 4);

      final vol = all.firstWhere((c) => c.id == 'vol_1');
      expect(vol.volumeNum, 1);
      expect(vol.chapterNum, isNull);

      final ch1 = all.firstWhere((c) => c.id == 'ch_1');
      expect(ch1.volumeNum, isNull);
      expect(ch1.chapterNum, 1);
      expect(ch1.volumeChapterNum, 1);

      final extra = all.firstWhere((c) => c.id == 'extra_1');
      expect(extra.isChapter, isTrue);
      expect(extra.isExtra, isTrue);
      expect(extra.chapterNum, isNull);
      expect(extra.volumeChapterNum, isNull);

      final ch2 = all.firstWhere((c) => c.id == 'ch_2');
      expect(ch2.volumeNum, isNull);
      expect(ch2.chapterNum, 2);
      expect(ch2.volumeChapterNum, 2);
    });

    test('order: root chapters sorted by sibling_order', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_2',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 2,
          title: const Value('第二章'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('第一章'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final all = await dao.getAll();
      expect(all.length, 2);
      expect(all[0].id, 'ch_1');
      expect(all[1].id, 'ch_2');
    });

    test('soft delete excludes from VIEW', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.softDelete('ch_1');

      final all = await dao.getAll();
      expect(all, isEmpty);
    });

    test('move chapter into a volume', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.moveToVolume('ch_1', 'vol_1');
      final ch = await dao.getById('ch_1');
      expect(ch, isNotNull);
      expect(ch!.parentId, 'vol_1');
      expect(ch.siblingOrder, 1);
    });

    test('move chapter out of a volume', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value('vol_1'),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.moveOutOfVolume('ch_1');
      final ch = await dao.getById('ch_1');
      expect(ch, isNotNull);
      expect(ch!.parentId, isNull);
    });

    test('extra type node is not numbered as chapter', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'extra_1',
          type: nodeTypeExtra,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('番外'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final all = await dao.getAll();
      expect(all.length, 1);
      expect(all.first.isChapter, isTrue);
      expect(all.first.isExtra, isTrue);
      expect(all.first.isNumberedChapter, isFalse);
      expect(all.first.chapterNum, isNull);
    });

    test('getPrevious returns previous chapter', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'extra_1',
          type: nodeTypeExtra,
          parentId: const Value(null),
          siblingOrder: 2,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_2',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 3,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final prev = await dao.getPrevious('ch_2');
      expect(prev, isNotNull);
      expect(prev!.id, 'ch_1');
    });

    test('upsert updates existing row', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('旧标题'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.upsert(
        ChapterData(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: null,
          siblingOrder: 1,
          title: '新标题',
          outline: '',
          brief: '',
          content: '',
          wordCount: 0,
          stat: chapterStatDraft,
          embeddingSyncStatus: chapterEmbeddingSyncStatusPending,
          embeddingSyncedAt: null,
          embeddingSyncModelId: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          deletedAt: notDeletedSentinel,
        ),
      );

      final ch = await dao.getById('ch_1');
      expect(ch, isNotNull);
      expect(ch!.title, '新标题');
    });

    test('hardDelete removes from table', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.hardDelete('ch_1');
      final all = await dao.getAll();
      expect(all, isEmpty);
    });

    test('getListStats aggregates chapter count and word count', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          wordCount: const Value(120),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'extra_1',
          type: nodeTypeExtra,
          parentId: const Value(null),
          siblingOrder: 2,
          wordCount: const Value(30),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final stats = await dao.getListStats();
      expect(stats.chapterCount, 2);
      expect(stats.totalWordCount, 150);
    });

    test('nextSiblingOrderAtRoot returns correct values', () async {
      final first = await dao.nextSiblingOrderAtRoot();
      expect(first, 1);

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: first,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final second = await dao.nextSiblingOrderAtRoot();
      expect(second, 2);
    });

    test('nextSiblingOrderInVolume returns correct values', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final first = await dao.nextSiblingOrderInVolume('vol_1');
      expect(first, 1);

      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value('vol_1'),
          siblingOrder: first,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final second = await dao.nextSiblingOrderInVolume('vol_1');
      expect(second, 2);
    });
  });

  group('Chapter model', () {
    test('displayTitle for volumes', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          title: const Value('测试卷'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final vol = await dao.getById('vol_1');
      expect(vol, isNotNull);
      expect(vol!.displayTitle, '第 1 卷 · 测试卷');
    });

    test('displayTitle for chapters without title', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final ch = await dao.getById('ch_1');
      expect(ch, isNotNull);
      expect(ch!.displayTitle, '第 1 章');
    });

    test('isVolume getter', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'vol_1',
          type: nodeTypeVolume,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final vol = await dao.getById('vol_1');
      expect(vol!.isVolume, isTrue);
      expect(vol.isChapter, isFalse);
    });

    test('isChapter getter', () async {
      await dao.insert(
        ChaptersCompanion.insert(
          id: 'ch_1',
          type: nodeTypeChapter,
          parentId: const Value(null),
          siblingOrder: 1,
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final ch = await dao.getById('ch_1');
      expect(ch!.isChapter, isTrue);
      expect(ch.isVolume, isFalse);
    });

    test(
      'repairOrphanChapterParents moves chapters with missing volume to root',
      () async {
        await dao.insert(
          ChaptersCompanion.insert(
            id: 'ch_orphan',
            type: nodeTypeChapter,
            parentId: const Value('missing_vol'),
            siblingOrder: 1,
            title: const Value('孤儿章'),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

        await dao.repairOrphanChapterParents();

        final chapter = await dao.getById('ch_orphan');
        expect(chapter, isNotNull);
        expect(chapter!.parentId, isNull);
        expect(chapter.siblingOrder, 1);
      },
    );
  });
}
