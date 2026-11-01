// 职责: 提供 MCP 设置写入入口并协调已提交配置、连接及认证事务生命周期。
// 关联文件:
//   lib/shared/providers/mcp_providers.dart
//   lib/shared/services/mcp/settings_orchestrator.dart
//   lib/shared/services/mcp/runtime.dart
//   lib/shared/services/mcp/oauth/coordinator.dart
import 'dart:async';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import '../../database/app_database.dart';
import '../../models/mcp/config.dart';
import '../../models/mcp/tool_descriptor.dart';
import 'client_adapter.dart';
import 'diagnostics.dart';
import 'runtime.dart';
import 'settings_orchestrator.dart';
import 'oauth/callback.dart';
import 'oauth/coordinator.dart';
import 'oauth/metadata.dart';
import 'oauth/provider.dart';

class McpSettingsService {
  McpSettingsService(
    this.database, {
    required bool supportsStdio,
    McpConnector? connector,
    McpOAuthCallbacks? oauthCallbacks,
    Future<void> Function(Uri)? openBrowser,
  }) : callbacks = oauthCallbacks ?? McpOAuthCallbacks() {
    oauth = openBrowser == null
        ? McpOAuthCoordinator(database, callbacks)
        : McpOAuthCoordinator(database, callbacks, openBrowser: openBrowser);
    runtime = McpRuntime(
      connect: connector ?? _connect,
      supportsStdio: supportsStdio,
    );
    initialized = _initialize();
  }
  final AppDatabase database;
  final McpOAuthCallbacks callbacks;
  late final McpOAuthCoordinator oauth;
  late final McpRuntime runtime;
  late final Future<void> initialized;
  StreamSubscription<String?>? _settings;
  bool _active = false;
  final _sessions = <Object, McpSession>{};
  McpSession session(String? id) =>
      _sessions.putIfAbsent(id ?? Object(), () => McpSession(runtime));
  Object? get configurationError => runtime.configurationError;

  Future<void> _configure(String? raw) async {
    final loaded = McpSettingsLoad.decode(raw);
    runtime.configurationError = loaded.error;
    runtime.configurationErrors = loaded.errors;
    await runtime.configure(loaded.settings);
  }

  Future<void> _initialize() async {
    await _configure(await database.appSettingsDao.get(McpSettings.key));
    _settings = database.appSettingsDao.watch(McpSettings.key).listen((
      raw,
    ) async {
      await _configure(raw);
    });
    await callbacks.initialize();
  }

  Future<McpConnection> _connect(McpServerConfig config) async {
    final connection = config.connection;
    final usesOAuth =
        connection is McpHttpConfig && connection.authMode == McpAuthMode.oauth;
    try {
      return await McpClientAdapter.connect(
        config,
        authProvider: usesOAuth
            ? McpStoredTokenProvider(() => oauth.tokens(config))
            : null,
        refreshRejected: usesOAuth
            ? (accessToken) => oauth.refreshRejected(config, accessToken)
            : null,
      );
    } on sdk.UnauthorizedError {
      if (connection is McpHttpConfig &&
          (connection.authMode == McpAuthMode.oauth ||
              (connection.authMode == McpAuthMode.none &&
                  connection.headers.isEmpty))) {
        await McpOAuthMetadata.discover(Uri.parse(connection.url));
        throw const McpNeedsAuth();
      }
      rethrow;
    }
  }

  Future<void> activate() async {
    await initialized;
    _active = true;
  }

  Future<void> save(
    McpServerConfig config, {
    required bool create,
    McpServerConfig? baseline,
  }) async {
    await initialized;
    final existing = runtime.configs
        .where((s) => s.name == config.name)
        .firstOrNull;
    if (create && existing != null) {
      throw McpServerNameConflict(config.name, config.name);
    }
    final requested = existing == null
        ? config
        : McpSettingsOrchestrator.mergeEditedConfig(existing, config, baseline);
    if (existing != null &&
        (!requested.enabled ||
            canonicalMcpJson(existing.connection.toJson()) !=
                canonicalMcpJson(requested.connection.toJson()))) {
      oauth.invalidate(config.name);
      await runtime.disconnect(config.name);
    }
    try {
      final next = await McpSettingsOrchestrator().save(
        database: database,
        config: config,
        create: create,
        baseline: baseline,
      );
      await runtime.configure(next);
      if (config.enabled) {
        unawaited(runtime.startEnabled());
      }
    } catch (_) {
      await runtime.configure(
        McpSettings.decode(await database.appSettingsDao.get(McpSettings.key)),
      );
      if (_active) {
        unawaited(runtime.startEnabled());
      }
      rethrow;
    }
  }

  Future<void> importServers(List<McpServerConfig> servers) async {
    await initialized;
    final next = await McpSettingsOrchestrator().update(
      database: database,
      change: (current) => McpSettings([...current.servers, ...servers]),
    );
    await runtime.configure(next);
    unawaited(runtime.startEnabled());
  }

  Future<McpLogoutResult> delete(String name) async {
    await initialized;
    oauth.invalidate(name);
    await runtime.disconnect(name);
    final current = runtime.configs.where((s) => s.name == name).first;
    final revocation = await oauth.revoke(current);
    try {
      final next = await McpSettingsOrchestrator().delete(
        database: database,
        name: name,
      );
      await runtime.configure(next);
      return revocation;
    } catch (_) {
      await runtime.configure(
        McpSettings.decode(await database.appSettingsDao.get(McpSettings.key)),
      );
      if (_active) {
        unawaited(runtime.startEnabled());
      }
      rethrow;
    }
  }

  Future<void> login(String name) async {
    await initialized;
    await oauth.login(name);
    await runtime.configure(
      McpSettings.decode(await database.appSettingsDao.get(McpSettings.key)),
    );
    await runtime.ensureReady(name);
  }

  Future<McpLogoutResult> logout(String name) async {
    await initialized;
    await runtime.disconnect(name);
    try {
      final result = await oauth.logout(name);
      await runtime.configure(
        McpSettings.decode(await database.appSettingsDao.get(McpSettings.key)),
      );
      return result;
    } catch (_) {
      await runtime.configure(
        McpSettings.decode(await database.appSettingsDao.get(McpSettings.key)),
      );
      if (_active) {
        unawaited(runtime.startEnabled());
      }
      rethrow;
    }
  }

  Future<void> setForeground(bool foreground) async {
    await initialized;
    if (foreground) {
      await runtime.resume();
      if (_active) {
        if (_sessions.isEmpty) {
          await runtime.startEnabled();
        } else {
          await Future.wait([
            for (final session in _sessions.values)
              for (final config in runtime.configs)
                if (config.enabled &&
                    (runtime.supportsStdio ||
                        config.connection is McpHttpConfig) &&
                    session.failure(config.name) == null)
                  session
                      .ensureReady(config.name)
                      .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          ]);
        }
      }
    } else {
      await runtime.suspend();
    }
  }

  Future<void> close() async {
    await _settings?.cancel();
    _sessions.clear();
    await runtime.close();
    await oauth.close();
    await callbacks.close();
  }
}
