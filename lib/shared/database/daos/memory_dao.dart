// 职责: Memory 数据访问对象 — 封装所有 Memory 相关的数据库操作，含分类查询、统计、批量操作
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/services/ai/memory_service.dart
//   lib/shared/providers/memory_providers.dart

import 'package:drift/drift.dart';

import '../app_database.dart';

part 'memory_dao.drift.dart';

@DriftAccessor(tables: [Memories])
class MemoryDao extends DatabaseAccessor<AppDatabase> with _$MemoryDaoMixin {
  MemoryDao(super.db);

  Future<List<Memory>> getAll() async {
    return (select(memories)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
            (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  Stream<List<Memory>> watchAll() {
    return (select(memories)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
            (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Stream<List<Memory>> watchGlobal() {
    return (select(memories)
          ..where(
            (table) =>
                table.novelId.isNull() &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
            (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Stream<List<Memory>> watchByNovelId(String novelId) {
    return (select(memories)
          ..where(
            (table) =>
                table.novelId.equals(novelId) &
                table.deletedAt.equals(notDeletedSentinel),
          )
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
            (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Future<List<Memory>> getCoreMemories({String? novelId}) async {
    final query = select(memories)
      ..where(
        (table) =>
            table.priority.equals(memoryPriorityCore) &
            table.enabled.equals(true) &
            table.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.sortOrder, mode: OrderingMode.asc),
        (table) =>
            OrderingTerm(expression: table.createdAt, mode: OrderingMode.desc),
      ]);

    if (novelId != null) {
      query.where(
        (table) => table.novelId.equals(novelId) | table.novelId.isNull(),
      );
    } else {
      query.where((table) => table.novelId.isNull());
    }

    return query.get();
  }

  Future<List<Memory>> getMemoriesForPrompt({String? novelId}) async {
    final query = select(memories)
      ..where(
        (table) =>
            table.enabled.equals(true) &
            table.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.sortOrder, mode: OrderingMode.asc),
        (table) =>
            OrderingTerm(expression: table.createdAt, mode: OrderingMode.desc),
      ]);

    if (novelId != null) {
      query.where(
        (table) => table.novelId.equals(novelId) | table.novelId.isNull(),
      );
    } else {
      query.where((table) => table.novelId.isNull());
    }

    return query.get();
  }

  Future<List<Memory>> getByCategory({
    required String category,
    String? novelId,
  }) async {
    final query = select(memories)
      ..where(
        (table) =>
            table.category.equals(category) &
            table.enabled.equals(true) &
            table.deletedAt.isNull(),
      )
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.sortOrder, mode: OrderingMode.asc),
        (table) =>
            OrderingTerm(expression: table.createdAt, mode: OrderingMode.desc),
      ]);

    if (novelId != null) {
      query.where(
        (table) => table.novelId.equals(novelId) | table.novelId.isNull(),
      );
    } else {
      query.where((table) => table.novelId.isNull());
    }

    return query.get();
  }

  Future<int> count({String? novelId, bool enabledOnly = true}) async {
    final query = selectOnly(memories)
      ..addColumns([memories.id.count()]);

    if (enabledOnly) {
      query.where(memories.enabled.equals(true));
    }
    query.where(memories.deletedAt.isNull());

    if (novelId != null) {
      query.where(
        memories.novelId.equals(novelId) | memories.novelId.isNull(),
      );
    } else {
      query.where(memories.novelId.isNull());
    }

    final row = await query.getSingle();
    return row.read(memories.id.count()) ?? 0;
  }

  Future<int> countByCategory({
    required String category,
    String? novelId,
  }) async {
    final query = selectOnly(memories)
      ..addColumns([memories.id.count()]);
    query.where(memories.category.equals(category));
    query.where(memories.enabled.equals(true));
    query.where(memories.deletedAt.isNull());

    if (novelId != null) {
      query.where(
        memories.novelId.equals(novelId) | memories.novelId.isNull(),
      );
    } else {
      query.where(memories.novelId.isNull());
    }

    final row = await query.getSingle();
    return row.read(memories.id.count()) ?? 0;
  }

  Future<Memory?> get(String id) async {
    return (select(memories)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Future<String> create({
    required String id,
    required String category,
    required String content,
    String? novelId,
    String priority = memoryPriorityContext,
    String source = memorySourceManual,
    String? sourceSessionId,
    bool enabled = true,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now();
    await into(memories).insert(
      MemoriesCompanion.insert(
        id: id,
        novelId: Value(novelId),
        category: category,
        priority: Value(priority),
        content: content,
        source: Value(source),
        sourceSessionId: Value(sourceSessionId),
        enabled: Value(enabled),
        sortOrder: Value(sortOrder),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  Future<void> upsert(MemoriesCompanion companion) async {
    await into(memories).insertOnConflictUpdate(companion);
  }

  Future<int> updateContent({
    required String id,
    required String content,
    String? category,
    String? priority,
    bool? enabled,
    int? sortOrder,
  }) {
    return (update(memories)..where((table) => table.id.equals(id))).write(
      MemoriesCompanion(
        content: Value(content),
        category: category != null ? Value(category) : const Value.absent(),
        priority: priority != null ? Value(priority) : const Value.absent(),
        enabled: enabled != null ? Value(enabled) : const Value.absent(),
        sortOrder: sortOrder != null ? Value(sortOrder) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> softDelete(String id) async {
    return (update(memories)..where((table) => table.id.equals(id))).write(
      MemoriesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> hardDelete(String id) async {
    return (delete(memories)..where((table) => table.id.equals(id))).go();
  }

  Future<void> reorder(List<String> ids) async {
    await transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (update(memories)..where((table) => table.id.equals(ids[i])))
            .write(MemoriesCompanion(sortOrder: Value(i)));
      }
    });
  }

  Future<int> batchSoftDelete(List<String> ids) async {
    if (ids.isEmpty) return 0;
    return transaction(() async {
      var count = 0;
      final now = DateTime.now();
      for (final id in ids) {
        count += await (update(memories)
              ..where((table) => table.id.equals(id) & table.deletedAt.isNull()))
            .write(
          MemoriesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
      return count;
    });
  }
}
