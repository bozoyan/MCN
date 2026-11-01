// 职责: 地点数据访问对象 — 封装所有地点相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';

part 'location_dao.drift.dart';

@DriftAccessor(tables: [Locations])
class LocationDao extends DatabaseAccessor<NovelContentDatabase>
    with _$LocationDaoMixin {
  LocationDao(super.db);

  Future<List<Location>> getAll() {
    return (select(locations)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Future<Location?> getById(String id) {
    return (select(locations)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Stream<List<Location>> watchAll() {
    return (select(locations)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .watch();
  }

  Future<void> upsert(Location location) async {
    await into(locations).insertOnConflictUpdate(location);
  }

  Future<int> softDelete(String id) {
    return (update(locations)..where((t) => t.id.equals(id))).write(
      LocationsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> restore(String id) {
    return (update(locations)..where((t) => t.id.equals(id))).write(
      LocationsCompanion(deletedAt: Value(notDeletedSentinel)),
    );
  }

  Future<int> hardDelete(String id) {
    return (delete(locations)..where((t) => t.id.equals(id))).go();
  }
}
