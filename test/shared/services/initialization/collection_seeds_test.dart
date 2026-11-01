// 职责: 验证默认集合的事务初始化、保护边界和失败重试。
// 关联文件:
//   lib/shared/services/initialization/collection_seeds.dart
//   lib/shared/services/app_initialization.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/services/initialization/collection_seeds.dart';

void main() {
  late AppDatabase db;
  const names = {
    'all': 'All',
    'in_progress': 'In progress',
    'finished': 'Finished',
  };
  setUp(() => db = AppDatabase.forTest(NativeDatabase.memory()));
  tearDown(() => db.close());
  test(
    'three seeds, one protected record; retries preserve renamed and deleted defaults',
    () async {
      await seedCollections(db, names: names);
      final rows = await db.select(db.novelCollections).get();
      expect(rows.length, 3);
      expect(rows.where((c) => c.builtin).single.id, 'collection:all');
      await db.novelCollectionDao.rename('collection:in_progress', 'Custom');
      await db.novelCollectionDao.softDelete('collection:finished');
      await seedCollections(db, names: names);
      expect((await db.select(db.novelCollections).get()).length, 3);
      final active = await db.novelCollectionDao.watchDefinitions().first;
      expect(active.length, 2);
      expect(active.singleWhere((c) => !c.builtin).name, 'Custom');
      await expectLater(
        db.novelCollectionDao.rename('collection:all', 'New'),
        throwsStateError,
      );
      await expectLater(
        db.novelCollectionDao.softDelete('collection:all'),
        throwsStateError,
      );
      await expectLater(
        db.novelCollectionDao.setMembership(
          'collection:all',
          [],
          included: false,
        ),
        throwsStateError,
      );
    },
  );
  test('failure rolls back all seeds and can retry', () async {
    await expectLater(
      seedCollections(db, names: {'all': 'All'}),
      throwsStateError,
    );
    expect(await db.select(db.novelCollections).get(), isEmpty);
    await seedCollections(db, names: names);
    expect((await db.select(db.novelCollections).get()).length, 3);
  });
  test('corrupt builtin is reported and never rewritten', () async {
    await db
        .into(db.novelCollections)
        .insert(
          NovelCollectionsCompanion.insert(
            id: 'collection:all',
            name: 'Bad',
            builtin: const Value(true),
          ),
        );
    await expectLater(seedCollections(db, names: names), throwsFormatException);
    expect((await db.select(db.novelCollections).get()).single.name, 'Bad');
  });
}
