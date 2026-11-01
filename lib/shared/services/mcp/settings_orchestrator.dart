// 职责: 在同一数据库事务内更新 MCP 配置并防止并发编辑丢失。
// 关联文件:
//   lib/shared/models/mcp/config.dart
//   lib/shared/database/app_database.dart
//   lib/shared/providers/mcp_providers.dart

import '../../database/app_database.dart';
import '../../logger/app_logger.dart';
import '../../models/mcp/config.dart';
import '../../models/mcp/tool_descriptor.dart';

final _log = AppLogger.forModule('McpSettings');

class McpSettingsOrchestrator {
  Future<McpSettings> update({
    required AppDatabase database,
    required McpSettings Function(McpSettings current) change,
  }) async {
    String? payload;
    try {
      return await database.transaction(() async {
        final current = McpSettings.decode(
          await database.appSettingsDao.get(McpSettings.key),
        );
        final next = change(current);
        payload = next.encode();
        await database.appSettingsDao.set(
          key: McpSettings.key,
          value: payload!,
        );
        return next;
      });
    } catch (error, stack) {
      final diagnostic = error.toString();
      _log.error(
        '[DB] app_settings UPSERT id=mcp_servers failed',
        error: payload == null
            ? diagnostic
            : diagnostic.replaceAll(payload!, '[MCP configuration]'),
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<McpSettings> save({
    required AppDatabase database,
    required McpServerConfig config,
    required bool create,
    McpServerConfig? baseline,
  }) => update(
    database: database,
    change: (current) {
      final index = current.servers.indexWhere((s) => s.name == config.name);
      if (create && index >= 0) {
        throw McpServerNameConflict(config.name, config.name);
      }
      if (!create && index < 0) {
        throw StateError('MCP server no longer exists');
      }
      final servers = [...current.servers];
      if (index < 0) {
        servers.add(config);
      } else {
        servers[index] = mergeEditedConfig(
          current.servers[index],
          config,
          baseline,
        );
      }
      return McpSettings(servers);
    },
  );

  static McpServerConfig mergeEditedConfig(
    McpServerConfig current,
    McpServerConfig edited,
    McpServerConfig? baseline,
  ) {
    if (baseline == null) {
      return edited;
    }
    const tokenFields = {
      'accessToken',
      'refreshToken',
      'expiresAt',
      'issuer',
      'resource',
      'tokenEndpoint',
      'registeredClientId',
      'registeredClientSecret',
      'registeredAuthMethod',
    };
    Map<String, dynamic> editable(McpTransportConfig connection) {
      final json = connection.toJson();
      if (connection is McpHttpConfig) {
        json['oauth'] = {
          for (final entry in connection.oauth.entries)
            if (!tokenFields.contains(entry.key)) entry.key: entry.value,
        };
      }
      return json;
    }

    final original = canonicalMcpJson(editable(baseline.connection));
    if (canonicalMcpJson(editable(current.connection)) != original) {
      throw StateError(
        'MCP connection was edited elsewhere; reload before saving',
      );
    }
    final connection = edited.connection;
    if (connection is! McpHttpConfig) {
      return edited;
    }
    final keepTokens =
        canonicalMcpJson(editable(connection)) == original &&
        current.connection is McpHttpConfig;
    final latest = current.connection is McpHttpConfig
        ? (current.connection as McpHttpConfig).oauth
        : const <String, dynamic>{};
    final oauth = <String, dynamic>{
      for (final entry in connection.oauth.entries)
        if (!tokenFields.contains(entry.key)) entry.key: entry.value,
      if (keepTokens)
        for (final entry in latest.entries)
          if (tokenFields.contains(entry.key)) entry.key: entry.value,
    };
    return edited.copyWith(
      connection: McpHttpConfig(
        url: connection.url,
        authMode: connection.authMode,
        headers: connection.headers,
        bearerToken: connection.bearerToken,
        oauth: oauth,
      ),
    );
  }

  Future<McpSettings> delete({
    required AppDatabase database,
    required String name,
  }) => update(
    database: database,
    change: (current) {
      if (!current.servers.any((s) => s.name == name)) {
        throw StateError('MCP server not found');
      }
      return McpSettings(current.servers.where((s) => s.name != name));
    },
  );
}
