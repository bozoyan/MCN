// 职责: 测试 ReadingProgressDao — 验证 upsert、查询、删除和 stream 监听
// 关联文件:
//   lib/shared/database/daos/reading_progress_dao.dart
//   lib/shared/database/app_database.dart

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTest(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('ReadingProgressDao', () {
    test('upsert creates progress', () async {
      final now = DateTime.now();
      await db.readingProgressDao.upsert(
        ReadingProgressCompanion(
          novelId: Value('novel_1'),
          chapterId: Value('ch1'),
          scrollOffset: const Value(42.0),
          lastReadAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final result = await db.readingProgressDao.getByNovelId('novel_1');
      expect(result, isNotNull);
      expect(result!.chapterId, 'ch1');
      expect(result.scrollOffset, 42.0);
      expect(result.lastReadAt, isNotNull);
    });

    test('upsert updates existing progress', () async {
      final now = DateTime.now();
      await db.readingProgressDao.upsert(
        ReadingProgressCompanion(
          novelId: Value('novel_1'),
          chapterId: Value('ch1'),
          scrollOffset: const Value(10.0),
          updatedAt: Value(now),
        ),
      );

      await db.readingProgressDao.upsert(
        ReadingProgressCompanion(
          novelId: Value('novel_1'),
          chapterId: Value('ch2'),
          scrollOffset: const Value(20.0),
          updatedAt: Value(now),
        ),
      );

      final result = await db.readingProgressDao.getByNovelId('novel_1');
      expect(result, isNotNull);
      expect(result!.chapterId, 'ch2');
      expect(result.scrollOffset, 20.0);
    });

    test('getByNovelId returns null for unknown novel', () async {
      final result = await db.readingProgressDao.getByNovelId('unknown');
      expect(result, isNull);
    });

    test('deleteByNovelId removes progress', () async {
      final now = DateTime.now();
      await db.readingProgressDao.upsert(
        ReadingProgressCompanion(
          novelId: Value('novel_1'),
          chapterId: Value('ch1'),
          scrollOffset: const Value(0),
          updatedAt: Value(now),
        ),
      );

      await db.readingProgressDao.deleteByNovelId('novel_1');

      final result = await db.readingProgressDao.getByNovelId('novel_1');
      expect(result, isNull);
    });

    test('watchByNovelId emits on upsert', () async {
      final now = DateTime.now();
      final stream = db.readingProgressDao.watchByNovelId('novel_1');

      await db.readingProgressDao.upsert(
        ReadingProgressCompanion(
          novelId: Value('novel_1'),
          chapterId: Value('ch1'),
          scrollOffset: const Value(0),
          updatedAt: Value(now),
        ),
      );

      final result = await stream.first;
      expect(result, isNotNull);
      expect(result!.chapterId, 'ch1');
    });
  });
}
