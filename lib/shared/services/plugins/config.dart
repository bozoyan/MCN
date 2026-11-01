// 职责: 读取插件配置并在事务内校验和保存普通字段及凭据变更；清空必填凭据时同时关闭插件。
// 关联文件:
//   lib/shared/database/daos/plugin_dao.dart
//   lib/shared/models/plugin/manifest.dart
//   lib/shared/models/plugin/setting_field.dart
//   lib/shared/services/plugins/host.dart
import 'dart:convert';
import '../../database/daos/plugin_dao.dart';
import '../../logger/app_logger.dart';
import '../../models/plugin/manifest.dart';
import '../../models/plugin/setting_field.dart';

final _log = AppLogger.forModule('PluginConfig');

/// 普通配置与已保存凭据的名称；不向界面返回凭据原文。
typedef PluginConfig = ({
  Map<String, Object?> values,
  Set<String> savedSecrets,
});

Future<Object?> readPluginSetting(
  PluginDao dao,
  String pluginId,
  PluginSettingField field,
) async {
  final stored = await dao.getStorage(pluginId, 'settings.${field.key}');
  return stored == null ? field.defaultValue : jsonDecode(stored);
}

Future<String?> readPluginSecret(
  PluginDao dao,
  String pluginId,
  String key,
) async {
  final value = await dao.getSecret(pluginId, key);
  // 空值表示已清除，保留记录及其身份，不引入硬删除路径。
  return value == null || value.isEmpty ? null : value;
}

Future<PluginConfig> readPluginConfig(
  PluginDao dao,
  PluginManifest manifest,
) async {
  final values = <String, Object?>{};
  final savedSecrets = <String>{};
  for (final field in manifest.settings) {
    if (field.isSecret) {
      if (await readPluginSecret(dao, manifest.id, field.key) != null) {
        savedSecrets.add(field.key);
      }
    } else {
      values[field.key] = await readPluginSetting(dao, manifest.id, field);
    }
  }
  return (values: values, savedSecrets: savedSecrets);
}

class PluginConfigOrchestrator {
  /// 返回 true 表示本次清空了必填凭据，且已在同一事务内关闭插件。
  Future<bool> save({
    required PluginDao dao,
    required PluginManifest manifest,
    required Map<String, Object?> settings,
    required Map<String, String?> secrets,
  }) async {
    final fields = {for (final field in manifest.settings) field.key: field};
    for (final key in settings.keys) {
      if (fields[key] == null || fields[key]!.isSecret) {
        throw FormatException('Unknown setting: $key');
      }
    }
    for (final key in secrets.keys) {
      if (fields[key]?.isSecret != true) {
        throw FormatException('Unknown secret: $key');
      }
    }
    bool cleared(PluginSettingField field) =>
        field.isSecret &&
        secrets.containsKey(field.key) &&
        secrets[field.key] == null;
    try {
      return await dao.transaction(() async {
        for (final field in manifest.settings) {
          // 显式清空的凭据允许保存；必填凭据缺失时改为关闭插件。
          if (cleared(field)) {
            continue;
          }
          final value = field.isSecret
              ? (secrets.containsKey(field.key)
                    ? secrets[field.key]
                    : await readPluginSecret(dao, manifest.id, field.key))
              : settings[field.key];
          final issue = validatePluginSettingValue(field, value);
          if (issue != null) {
            throw FormatException(
              'Invalid setting ${field.key}: ${issue.name}',
            );
          }
        }
        for (final entry in settings.entries) {
          await dao.setStorage(
            manifest.id,
            'settings.${entry.key}',
            jsonEncode(entry.value),
          );
        }
        for (final entry in secrets.entries) {
          await dao.setSecret(manifest.id, entry.key, entry.value ?? '');
        }
        if (!manifest.settings.any(
              (field) => field.required && cleared(field),
            ) ||
            (await dao.getPlugin(manifest.id))?.enabled != true) {
          return false;
        }
        await dao.setEnabled(manifest.id, false);
        return true;
      });
    } catch (error, stack) {
      _log.error(
        '[DB] plugin_storage/plugin_secrets/plugin_registry UPSERT plugin=${manifest.id}',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
