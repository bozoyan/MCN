import 'package:drift/drift.dart';

import '../../logger/app_logger.dart';
import '../app_database.dart';

part 'global_agent_dao.drift.dart';

final _log = AppLogger.forModule('DB');

@DriftAccessor(tables: [Agents])
class GlobalAgentDao extends DatabaseAccessor<AppDatabase>
    with _$GlobalAgentDaoMixin {
  GlobalAgentDao(super.db);

  Future<GlobalAgent?> getBySlug(String slug) async {
    final rows =
        await (select(agents)..where(
              (table) =>
                  table.slug.equals(slug) &
                  table.deletedAt.equals(notDeletedSentinel),
            ))
            .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<GlobalAgent>> getAll() async {
    final rows =
        await (select(agents)
              ..where((table) => table.deletedAt.equals(notDeletedSentinel))
              ..orderBy([
                (table) => OrderingTerm(
                  expression: table.sortOrder,
                  mode: OrderingMode.asc,
                ),
              ]))
            .get();
    return rows;
  }

  Stream<List<GlobalAgent>> watchAll() {
    return (select(agents)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
          ]))
        .watch();
  }

  Future<List<GlobalAgent>> getByScope(String scope, {String? novelId}) async {
    final rows =
        await (select(agents)
              ..where((table) {
                final scopeFilter = table.scope.equals(scope);
                if (novelId != null) {
                  return scopeFilter & table.novelId.equals(novelId);
                }
                return scopeFilter;
              })
              ..where((table) => table.deletedAt.equals(notDeletedSentinel))
              ..orderBy([
                (table) => OrderingTerm(
                  expression: table.sortOrder,
                  mode: OrderingMode.asc,
                ),
              ]))
            .get();
    return rows;
  }

  Stream<List<GlobalAgent>> watchByScope(String scope, {String? novelId}) {
    return (select(agents)
          ..where((table) {
            final scopeFilter = table.scope.equals(scope);
            if (novelId != null) {
              return scopeFilter & table.novelId.equals(novelId);
            }
            return scopeFilter;
          })
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
          ]))
        .watch();
  }

  Future<void> upsert(GlobalAgent agent) async {
    try {
      // 权限来自代码策略；保留旧列数据，不再覆盖历史值。
      await into(agents).insertOnConflictUpdate(
        agent
            .toCompanion(false)
            .copyWith(allowedToolNames: const Value.absent()),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] agents UPSERT id=${agent.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<int> softDelete(String id, {DateTime? deletedAt}) async {
    final now = deletedAt ?? DateTime.now();
    try {
      return await (update(agents)..where((table) => table.id.equals(id)))
          .write(AgentsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    } catch (error, stackTrace) {
      _log.error(
        '[agents][UPDATE] failed softDelete id=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<int> hardDelete(String id) {
    return (delete(agents)..where((table) => table.id.equals(id))).go();
  }

  Future<void> reorder(List<String> ids) async {
    await transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (update(agents)..where((table) => table.id.equals(ids[i]))).write(
          AgentsCompanion(sortOrder: Value(i)),
        );
      }
    });
  }
}
