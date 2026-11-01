// 职责: 应用设置数据访问对象 — 封装所有应用设置相关的数据库操作
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/providers/app_settings_providers.dart

import 'package:drift/drift.dart';

import '../app_database.dart';

part 'app_settings_dao.drift.dart';

@DriftAccessor(tables: [AppSettings])
class AppSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$AppSettingsDaoMixin {
  AppSettingsDao(super.db);

  Future<String?> get(String key) async {
    final row = await (select(
      appSettings,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<Map<String, String>> getAll() async {
    final rows = await select(appSettings).get();
    return {for (final row in rows) row.key: row.value};
  }

  Stream<String?> watch(String key) {
    return (select(appSettings)..where((table) => table.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  Future<void> set({required String key, required String value}) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: Value(value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> remove(String key) async {
    await (delete(appSettings)..where((table) => table.key.equals(key))).go();
  }

  Future<bool> has(String key) async {
    final row = await (select(
      appSettings,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row != null;
  }
}
