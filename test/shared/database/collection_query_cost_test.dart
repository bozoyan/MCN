// 职责: 记录一百个集合和一万部轻量作品的批量计数成本与查询计划。
// 关联文件:
//   lib/shared/database/queries/collection_filter.dart
//   lib/shared/database/daos/novel_collection_dao.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/queries/collection_filter.dart';
import 'package:reveric/shared/models/collections/filter.dart';

void main() {
  test('100 collection counts aggregate 10000 works in one SQL batch', () async {
    final db = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    await db.batch((batch) {
      batch.insertAll(db.novels, [
        for (var i = 0; i < 10000; i++)
          NovelsCompanion.insert(
            id: '$i',
            title: 'Work $i',
            description: '',
            wordCount: Value(i),
            tags: Value(i.isEven ? ['科幻'] : []),
          ),
      ]);
      batch.insertAll(db.novelCollections, [
        for (var i = 0; i < 100; i++)
          NovelCollectionsCompanion.insert(
            id: 'rule:$i',
            name: 'Rule $i',
            filterMode: const Value('rule'),
            filter: Value(
              CollectionFilter.fromRoot(
                CollectionCompare('novel.word_count', 'gte', i * 100),
              ),
            ),
          ),
      ]);
    });
    final definitions = await db.novelCollectionDao.watchDefinitions().first;
    final timer = Stopwatch()..start();
    final counts = await db.novelCollectionDao.counts(definitions);
    timer.stop();
    expect(counts.length, 100);
    expect(counts['rule:0'], 10000);
    expect(counts['rule:99'], 100);
    final predicate = const CollectionFilterCompiler().forCollection(
      definitions.first,
    );
    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT COUNT(*) FROM novels n WHERE ${predicate.sql}',
          variables: predicate.variables,
        )
        .get();
    // ignore: avoid_print
    print(
      'COLLECTION_COST collections=100 works=10000 count_sql_batches=1 elapsed_ms=${timer.elapsedMilliseconds} plan=${plan.map((r) => r.data).toList()}',
    );
  });
}
