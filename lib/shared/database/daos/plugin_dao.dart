// 职责: 按插件身份持久化登记、启停与隔离的键值数据。
// 关联文件:
//   lib/shared/database/app_database.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../logger/app_logger.dart';
part 'plugin_dao.drift.dart';

final _log = AppLogger.forModule('PluginDao');

@DriftAccessor(tables: [PluginRegistry, PluginStorage, PluginSecrets])
class PluginDao extends DatabaseAccessor<AppDatabase> with _$PluginDaoMixin {
  PluginDao(super.db);
  Future<PluginRegistryData?> getPlugin(String pluginId) =>
      (select(pluginRegistry)..where(
            (t) =>
                t.pluginId.equals(pluginId) &
                t.deletedAt.equals(notDeletedSentinel),
          ))
          .getSingleOrNull();
  Future<T> _write<T>(
    String pluginId,
    String table,
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (error, stack) {
      _log.error(
        '[DB] $table $operation plugin=$pluginId',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> register({
    required String pluginId,
    required String version,
    required String source,
    required String packagePath,
    required bool defaultEnabled,
  }) => _write(pluginId, 'plugin_registry', 'UPSERT', () async {
    if (!['bundled', 'local'].contains(source)) {
      throw ArgumentError.value(source, 'source');
    }
    await transaction(() async {
      final existing = await getPlugin(pluginId);
      await into(pluginRegistry).insertOnConflictUpdate(
        PluginRegistryCompanion.insert(
          pluginId: pluginId,
          version: version,
          source: source,
          packagePath: packagePath,
          enabled: existing?.enabled ?? defaultEnabled,
          createdAt: existing == null
              ? const Value.absent()
              : Value(existing.createdAt),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  });
  Future<void> setEnabled(String pluginId, bool enabled) =>
      _write(pluginId, 'plugin_registry', 'UPDATE', () async {
        final count =
            await (update(pluginRegistry)..where(
                  (t) =>
                      t.pluginId.equals(pluginId) &
                      t.deletedAt.equals(notDeletedSentinel),
                ))
                .write(
                  PluginRegistryCompanion(
                    enabled: Value(enabled),
                    updatedAt: Value(DateTime.now()),
                  ),
                );
        if (count != 1) {
          throw StateError('Unknown plugin: $pluginId');
        }
      });
  Future<String?> getStorage(String pluginId, String key) async =>
      (await (select(pluginStorage)
                ..where((t) => t.pluginId.equals(pluginId) & t.key.equals(key)))
              .getSingleOrNull())
          ?.value;
  Future<void> setStorage(String pluginId, String key, String value) =>
      _write(pluginId, 'plugin_storage', 'UPSERT', () async {
        await into(pluginStorage).insertOnConflictUpdate(
          PluginStorageCompanion.insert(
            pluginId: pluginId,
            key: key,
            value: value,
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
  Future<String?> getSecret(String pluginId, String key) async =>
      (await (select(pluginSecrets)
                ..where((t) => t.pluginId.equals(pluginId) & t.key.equals(key)))
              .getSingleOrNull())
          ?.value;
  Future<List<String>> secretValues(String pluginId) async =>
      (await (select(
            pluginSecrets,
          )..where((t) => t.pluginId.equals(pluginId))).get())
          .map((r) => r.value)
          .toList();
  Future<void> setSecret(String pluginId, String key, String value) =>
      _write(pluginId, 'plugin_secrets', 'UPSERT', () async {
        await into(pluginSecrets).insertOnConflictUpdate(
          PluginSecretsCompanion.insert(
            pluginId: pluginId,
            key: key,
            value: value,
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
}
