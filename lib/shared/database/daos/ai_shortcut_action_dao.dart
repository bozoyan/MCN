// 职责: AI 快捷方式 DAO — 全局快捷方式的增删改查与排序。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/providers/ai_shortcut_action_providers.dart

import 'package:drift/drift.dart';

import '../app_database.dart';

part 'ai_shortcut_action_dao.drift.dart';

@DriftAccessor(tables: [AiShortcutActions])
class AiShortcutActionDao extends DatabaseAccessor<AppDatabase>
    with _$AiShortcutActionDaoMixin {
  AiShortcutActionDao(super.db);

  Future<List<AiShortcutAction>> getAll() {
    return (select(aiShortcutActions)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
          ]))
        .get();
  }

  Stream<List<AiShortcutAction>> watchAll() {
    return (select(aiShortcutActions)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
          ]))
        .watch();
  }

  Future<AiShortcutAction?> getById(String id) {
    return (select(
      aiShortcutActions,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<AiShortcutAction?> getByBuiltinId(String builtinId) {
    return (select(aiShortcutActions)
          ..where((table) => table.builtinId.equals(builtinId))
          ..where((table) => table.deletedAt.equals(notDeletedSentinel)))
        .getSingleOrNull();
  }

  Future<void> upsert(AiShortcutAction action) async {
    await into(aiShortcutActions).insertOnConflictUpdate(action);
  }

  Future<int> softDelete(String id) {
    return (update(
      aiShortcutActions,
    )..where((table) => table.id.equals(id))).write(
      AiShortcutActionsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> reorder(List<String> ids) async {
    await transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (update(
          aiShortcutActions,
        )..where((table) => table.id.equals(ids[i]))).write(
          AiShortcutActionsCompanion(
            sortOrder: Value(i),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }
}
