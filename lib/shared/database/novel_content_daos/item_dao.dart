// 职责: 物品数据访问对象 — 封装所有物品相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';

part 'item_dao.drift.dart';

@DriftAccessor(tables: [Items])
class ItemDao extends DatabaseAccessor<NovelContentDatabase>
    with _$ItemDaoMixin {
  ItemDao(super.db);

  Future<List<Item>> getByType(String type) {
    return (select(items)
          ..where(
            (table) =>
                table.type.equals(type) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .get();
  }

  Future<Item?> getById(String id) {
    return (select(items)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Future<List<Item>> getByIds(Set<String> ids) {
    if (ids.isEmpty) return Future.value([]);
    return (select(items)..where(
          (table) =>
              table.id.isIn(ids) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .get();
  }

  Future<Item?> getByTypeAndTitle(String type, String title) {
    return (select(items)..where(
          (table) =>
              table.type.equals(type) &
              table.title.equals(title) &
              table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Stream<List<Item>> watchByType(String type) {
    return (select(items)
          ..where(
            (table) =>
                table.type.equals(type) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([(table) => OrderingTerm(expression: table.sortOrder)]))
        .watch();
  }

  Future<void> upsert(Item item) async {
    await into(items).insertOnConflictUpdate(item);
  }

  Future<int> softDelete(String id) {
    return (update(items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> restore(String id) {
    return (update(items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(deletedAt: Value(notDeletedSentinel)),
    );
  }

  Future<void> updatePhotos(String id, List<SubjectPhoto> photos) async {
    await (update(items)..where((t) => t.id.equals(id))).write(
      ItemsCompanion(photos: Value(photos), updatedAt: Value(DateTime.now())),
    );
  }

  Future<int> hardDelete(String id) {
    return (delete(items)..where((t) => t.id.equals(id))).go();
  }
}
