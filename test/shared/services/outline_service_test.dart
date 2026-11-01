// 职责: 验证 Outline Create/Update 边界、短 ID 碰撞、节拍身份与软删除恢复。
// 关联文件:
//   lib/shared/services/outline_service.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/models/outline.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/database/novel_content_daos/outline_dao.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/outline.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';

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

  Future<OutlineDraft> create({
    String title = '主线',
    String content = '',
    int startChapterNum = 1,
    List<OutlineBeatDraft> beats = const [],
  }) async {
    final id = await service.outlineService.createOutline(
      defaultTitle: title,
      content: content,
      startChapterNum: startChapterNum,
      beats: beats,
    );
    return (await service.outlineService.getByDocumentId(id))!;
  }

  test(
    'saveOutline is update-only and cannot create a missing identity',
    () async {
      final now = DateTime.now();
      final missing = OutlineDraft(
        documentId: 'legacy_missing',
        title: 'missing',
        createdAt: now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      );

      await expectLater(
        service.outlineService.saveOutline(missing),
        throwsArgumentError,
      );

      expect(await db.select(db.outlines).get(), isEmpty);
    },
  );

  test(
    'create uses short IDs and skips parent tombstones and same-batch beats',
    () async {
      final now = DateTime.now();
      await db.outlineDao.insertOutline(
        Outline(
          documentId: 'out_AAAAAA',
          title: 'deleted',
          content: '',
          status: outlineStatusPending,
          startChapterNum: 1,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
          deletedAt: now,
        ),
      );
      final candidates = {
        ShortEntityIdType.outline: ['out_AAAAAA', 'out_BBBBBB'],
        ShortEntityIdType.outlineBeat: ['obt_BBBBBB'],
      };
      service = NovelContentService(
        db,
        idBuilder: (type) => candidates[type]!.removeAt(0),
      );

      final id = await service.outlineService.createOutline(
        defaultTitle: '主线',
        beats: [
          OutlineBeatDraft(id: 'obt_AAAAAA', title: '甲', isNew: true),
          OutlineBeatDraft(id: 'obt_AAAAAA', title: '乙', isNew: true),
        ],
      );

      expect(id, 'out_BBBBBB');
      final created = (await service.outlineService.getByDocumentId(id))!;
      expect(created.beats.map((beat) => beat.id), [
        'obt_AAAAAA',
        'obt_BBBBBB',
      ]);
      expect(created.beats.every((beat) => !beat.isNew), isTrue);
      final tombstone = await db.outlineDao.getOutlineRowByDocumentId(
        'out_AAAAAA',
        includeDeleted: true,
      );
      expect(tombstone!.title, 'deleted');
    },
  );

  test(
    'update preserves identity, soft deletes omissions, and only restore revives tombstones',
    () async {
      final original = await create(
        beats: [
          service.outlineService.createBeatDraft(title: 'A', content: 'A'),
          service.outlineService.createBeatDraft(title: 'B', content: 'B'),
        ],
      );
      final first = original.beats.first;
      final second = original.beats.last;

      await service.outlineService.saveOutline(
        original.copyWith(beats: [second.copyWith(content: 'B2')]),
      );
      final rows = await db.outlineDao.getBeatRows(original.documentId);
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((row) => row.id == first.id).deletedAt,
        isNot(notDeletedSentinel),
      );
      expect(
        rows.singleWhere((row) => row.id == second.id).createdAt,
        second.createdAt,
      );

      await expectLater(
        service.outlineService.saveOutline(original),
        throwsArgumentError,
      );
      await service.outlineService.restoreOutline(original);
      final restored = (await service.outlineService.getByDocumentId(
        original.documentId,
      ))!;
      expect(restored.beats.map((beat) => beat.id), [first.id, second.id]);
    },
  );

  test(
    'collision updates queued draft copies and repeated saves retain identity',
    () async {
      final original = await create(
        beats: [OutlineBeatDraft(id: 'obt_AAAAAA', title: 'old', isNew: true)],
      );
      service = NovelContentService(db, idBuilder: (_) => 'obt_BBBBBB');
      final candidate = OutlineBeatDraft(
        id: 'obt_AAAAAA',
        title: 'new',
        isNew: true,
      );
      final queued = candidate.copyWith(content: 'typed while saving');
      await service.outlineService.saveOutline(
        original.copyWith(beats: [...original.beats, candidate]),
      );
      expect(candidate.id, 'obt_BBBBBB');
      expect(queued.id, 'obt_BBBBBB');
      expect(queued.isNew, isFalse);
      await service.outlineService.saveOutline(
        original.copyWith(beats: [...original.beats, queued]),
      );
      final rows = await db.outlineDao.getBeatRows(original.documentId);
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((row) => row.id == 'obt_BBBBBB').content,
        'typed while saving',
      );
      expect(rows.singleWhere((row) => row.id == 'obt_AAAAAA').title, 'old');
    },
  );

  test(
    'new beat intent is explicit and a missing retained ID is rejected',
    () async {
      final original = await create();
      final missing = OutlineBeatDraft(id: 'obt_MISSING', title: 'missing');

      await expectLater(
        service.outlineService.saveOutline(original.copyWith(beats: [missing])),
        throwsArgumentError,
      );
      final newBeat = service.outlineService.createBeatDraft(title: 'new');
      await service.outlineService.saveOutline(
        original.copyWith(beats: [newBeat]),
      );

      final stored = (await service.outlineService.getByDocumentId(
        original.documentId,
      ))!;
      expect(stored.beats.single.id, startsWith('obt_'));
      expect(stored.beats.single.isNew, isFalse);
    },
  );

  test('foreign beat identity rejects the parent update atomically', () async {
    final main = await create(
      title: '主线',
      beats: [service.outlineService.createBeatDraft(title: '主线拍')],
    );
    final other = await create(
      title: '支线',
      beats: [service.outlineService.createBeatDraft(title: '支线拍')],
    );

    await expectLater(
      service.outlineService.saveOutline(
        main.copyWith(title: '不应保存', beats: [other.beats.single]),
      ),
      throwsArgumentError,
    );

    expect(
      (await service.outlineService.getByDocumentId(main.documentId))!.title,
      '主线',
    );
  });

  test(
    'create normalizes chapter start and suffixes duplicate titles',
    () async {
      final first = await create(title: '主线', startChapterNum: 0);
      final second = await create(title: '主线');

      expect(first.startChapterNum, 1);
      expect(second.title, '主线 (2)');
    },
  );

  test(
    'importOutline creates a uniquely named outline with file content',
    () async {
      await create(title: '主线');

      final importedId = await service.outlineService.importOutline(
        title: '主线',
        content: '导入的总纲正文',
      );
      final imported = await service.outlineService.getByDocumentId(importedId);

      expect(imported!.title, '主线 (2)');
      expect(imported.content, '导入的总纲正文');
    },
  );

  test('create and save reject path-structural chars in title', () async {
    await expectLater(
      service.outlineService.createOutline(defaultTitle: 'Who?'),
      throwsArgumentError,
    );
    final outline = await create();
    await expectLater(
      service.outlineService.saveOutline(outline.copyWith(title: 'a/b')),
      throwsArgumentError,
    );
  });
}
