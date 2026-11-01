// 职责: 阅读进度数据访问对象 — 负责 ReadingProgress 的持久化读写
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/providers/reading_progress_providers.dart

import 'package:drift/drift.dart';

import '../app_database.dart';

part 'reading_progress_dao.drift.dart';

@DriftAccessor(tables: [ReadingProgress])
class ReadingProgressDao extends DatabaseAccessor<AppDatabase>
    with _$ReadingProgressDaoMixin {
  ReadingProgressDao(super.db);

  Future<ReadingProgressData?> getByNovelId(String novelId) async {
    return await (select(
      readingProgress,
    )..where((t) => t.novelId.equals(novelId))).getSingleOrNull();
  }

  Stream<ReadingProgressData?> watchByNovelId(String novelId) {
    return (select(
      readingProgress,
    )..where((t) => t.novelId.equals(novelId))).watchSingleOrNull();
  }

  Future<void> upsert(ReadingProgressCompanion companion) async {
    await into(readingProgress).insertOnConflictUpdate(companion);
  }

  Future<void> deleteByNovelId(String novelId) async {
    await (delete(
      readingProgress,
    )..where((t) => t.novelId.equals(novelId))).go();
  }
}
