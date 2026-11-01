// 职责: 伏笔数据访问对象 — 封装所有伏笔相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';

part 'foreshadowing_dao.drift.dart';

@DriftAccessor(tables: [Foreshadowings])
class ForeshadowingDao extends DatabaseAccessor<NovelContentDatabase>
    with _$ForeshadowingDaoMixin {
  ForeshadowingDao(super.db);

  Future<List<Foreshadowing>> getAll() {
    return (select(foreshadowings)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Future<List<Foreshadowing>> getByStatus(String status) {
    return (select(foreshadowings)
          ..where(
            (table) =>
                table.status.equals(status) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Future<Foreshadowing?> getById(String id) {
    return (select(foreshadowings)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Stream<List<Foreshadowing>> watchAll() {
    return (select(foreshadowings)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .watch();
  }

  Stream<List<Foreshadowing>> watchByStatus(String status) {
    return (select(foreshadowings)
          ..where(
            (table) =>
                table.status.equals(status) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .watch();
  }

  Future<void> upsert(Foreshadowing foreshadowing) async {
    await into(
      foreshadowings,
    ).insertOnConflictUpdate(foreshadowing.copyWith(updatedAt: DateTime.now()));
  }

  Future<int> softDelete(String id) {
    return (update(foreshadowings)..where((t) => t.id.equals(id))).write(
      ForeshadowingsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> restore(String id) {
    return (update(foreshadowings)..where((t) => t.id.equals(id))).write(
      ForeshadowingsCompanion(
        deletedAt: Value(notDeletedSentinel),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> hardDelete(String id) {
    return (delete(foreshadowings)..where((t) => t.id.equals(id))).go();
  }
}
