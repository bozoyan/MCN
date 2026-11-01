// 职责: 测试 NovelContentService — 章节树混排移动等服务层编排逻辑
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/chapter.dart

import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  group('NovelContentService', () {
    test(
      'moveSiblingToPosition reorders mixed root volume and chapter nodes',
      () async {
        final now = DateTime.now();
        await db.chapterDao.insert(
          ChaptersCompanion.insert(
            id: 'vol_1',
            type: nodeTypeVolume,
            parentId: const Value(null),
            siblingOrder: 1,
            title: const Value('第一卷'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await db.chapterDao.insert(
          ChaptersCompanion.insert(
            id: 'ch_1',
            type: nodeTypeChapter,
            parentId: const Value(null),
            siblingOrder: 2,
            title: const Value('根章节'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await db.chapterDao.insert(
          ChaptersCompanion.insert(
            id: 'extra_1',
            type: nodeTypeExtra,
            parentId: const Value(null),
            siblingOrder: 3,
            title: const Value('番外'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        await service.moveSiblingToPosition('extra_1', 1);

        final roots = await db.chapterDao.getSiblings(null);
        expect(roots.map((node) => node.id), ['extra_1', 'vol_1', 'ch_1']);
        expect(roots.map((node) => node.siblingOrder), [1, 2, 3]);
      },
    );

    test(
      'createItem/updateItem reject path-structural chars in title',
      () async {
        await expectLater(
          service.createItem(type: 'skill', title: 'Who?'),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          service.createItem(type: 'skill', title: 'a/b'),
          throwsA(isA<ArgumentError>()),
        );

        final id = await service.createItem(type: 'skill', title: '原名');
        await expectLater(
          service.updateItem(entryId: id, title: '改成?什么', content: ''),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
