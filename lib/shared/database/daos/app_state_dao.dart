// 职责: 应用状态数据访问对象 — 封装所有应用状态相关的数据库操作
// 关联文件:
//   lib/shared/database/app_database.dart

import 'package:drift/drift.dart';

import '../app_database.dart';

part 'app_state_dao.drift.dart';

@DriftAccessor(tables: [AppStates])
class AppStateDao extends DatabaseAccessor<AppDatabase>
    with _$AppStateDaoMixin {
  AppStateDao(super.db);

  Future<String?> get(String key) async {
    final row = await (select(
      appStates,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set({required String key, required String value}) async {
    final now = DateTime.now();
    await into(appStates).insertOnConflictUpdate(
      AppStatesCompanion.insert(
        key: key,
        value: Value(value),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> remove(String key) async {
    await (delete(appStates)..where((table) => table.key.equals(key))).go();
  }

  Future<bool> has(String key) async {
    final row = await (select(
      appStates,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row != null;
  }

  /// 获取所有 key 以 [prefix] 开头的记录。
  Future<Map<String, String>> getAllByPrefix(String prefix) async {
    final rows = await (select(
      appStates,
    )..where((table) => table.key.like('$prefix%'))).get();
    return {for (final row in rows) row.key: row.value};
  }
}
