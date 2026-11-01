// 职责: 共享 MCP 连接并发布目录状态，按配置代次和聊天会话隔离失败。
// 关联文件:
//   lib/shared/services/mcp/client_adapter.dart
//   lib/shared/models/mcp/config.dart
//   lib/shared/providers/mcp_providers.dart

import 'dart:async';
import '../../models/mcp/config.dart';
import '../../models/mcp/tool_descriptor.dart';
import 'client_adapter.dart';
import 'diagnostics.dart';

enum McpConnectionStatus {
  disabled,
  disconnected,
  connecting,
  ready,
  needs_auth,
  error,
}

typedef McpConnector = Future<McpConnection> Function(McpServerConfig config);

class McpConnectionState {
  McpConnectionState({
    required this.server,
    required this.status,
    this.description,
    this.instructions,
    List<Map<String, dynamic>> tools = const [],
    this.error,
    this.failureKind,
  }) : tools = List.unmodifiable(
         tools.map((tool) => Map<String, dynamic>.unmodifiable(tool)),
       );
  final String server;
  final McpConnectionStatus status;
  final String? description;
  final String? instructions;
  final List<Map<String, dynamic>> tools;
  final String? error;
  final McpFailureKind? failureKind;
}

class McpRuntime {
  McpRuntime({required this.connect, this.supportsStdio = true});
  final McpConnector connect;
  final bool supportsStdio;
  final _updates =
      StreamController<Map<String, McpConnectionState>>.broadcast();
  final _entries = <String, _Entry>{};
  final _slots = <Completer<void>>[];
  int _connecting = 0;
  bool _closed = false;
  bool _suspended = false;
  int _lifecycleGeneration = 0;
  Stream<Map<String, McpConnectionState>> get changes => _updates.stream;
  Map<String, McpConnectionState> get states => Map.unmodifiable({
    for (final entry in _entries.entries) entry.key: entry.value.state,
  });
  List<McpServerConfig> get configs =>
      List.unmodifiable(_entries.values.map((e) => e.config));

  String? serverDescription(String name) => _entries[name]?.description;

  Map<String, String> configurationErrors = const {};
  String? configurationError;

  final knownTools = <String, McpToolDescriptor>{};
  Map<String, McpToolDescriptor> get tools {
    final ready = [
      for (final state in states.values)
        if (state.status == McpConnectionStatus.ready)
          for (final definition in state.tools)
            (server: state.server, definition: definition),
    ];
    // 替换字符后撞名的工具全部加 hash，谁保留原名就不取决于服务器和工具的顺序。
    final owners = <String, Set<String>>{};
    for (final tool in ready) {
      final raw = tool.definition['name'] as String;
      owners
          .putIfAbsent(mcpToolName(tool.server, raw), () => {})
          .add('${tool.server}\u0000$raw');
    }
    final result = <String, McpToolDescriptor>{};
    for (final tool in ready) {
      final name = mcpToolName(
        tool.server,
        tool.definition['name'] as String,
        isTaken: (name) => (owners[name]?.length ?? 0) > 1,
      );
      result[name] = McpToolDescriptor(
        server: tool.server,
        name: name,
        definition: tool.definition,
      );
    }
    return Map.unmodifiable(result);
  }

  Future<void> configure(McpSettings settings) async {
    if (_closed) {
      throw StateError('MCP runtime closed');
    }
    final closing = <Future<void>>[];
    final names = settings.servers.map((s) => s.name).toSet();
    for (final name in _entries.keys.toList()) {
      if (!names.contains(name)) {
        closing.add(_retire(_entries.remove(name)!));
      }
    }
    for (final config in settings.servers) {
      final previous = _entries[config.name];
      if (previous != null &&
          !previous.retired &&
          _connectionKey(previous.config) == _connectionKey(config)) {
        previous.config = config;
      } else {
        if (previous != null) {
          closing.add(_retire(previous));
        }
        _entries[config.name] =
            _Entry(
                config,
                _available(config)
                    ? McpConnectionStatus.disconnected
                    : McpConnectionStatus.disabled,
              )
              ..description =
                  previous != null &&
                      _targetKey(previous.config) == _targetKey(config)
                  ? previous.description
                  : null;
      }
    }
    _publish();
    await Future.wait(closing);
  }

  bool _available(McpServerConfig config) =>
      config.enabled && (supportsStdio || config.connection is McpHttpConfig);
  String _targetKey(McpServerConfig config) => canonicalMcpJson(
    config.connection is McpHttpConfig
        ? (config.connection as McpHttpConfig).connectionIdentity()
        : config.connection.toJson(),
  );
  String _connectionKey(McpServerConfig config) => canonicalMcpJson({
    'connection': _targetKey(config),
    'enabled': config.enabled,
    'connectTimeout': config.connectTimeoutSeconds,
    'callTimeout': config.callTimeoutSeconds,
  });
  void _publish() {
    if (!_closed) {
      knownTools.addAll(tools);
      _updates.add(states);
    }
  }

  Future<McpConnection> ensureReady(String name) {
    final entry = _entries[name];
    if (_closed ||
        _suspended ||
        entry == null ||
        !_available(entry.config) ||
        entry.retired) {
      return Future.error(StateError('MCP server unavailable'));
    }
    if (entry.state.status == McpConnectionStatus.needs_auth) {
      return Future.error(const McpNeedsAuth());
    }
    if (entry.connection != null) {
      return Future.value(entry.connection);
    }
    return entry.initializing ??= _initialize(entry);
  }

  Future<void> startEnabled() async {
    await Future.wait([
      for (final entry in _entries.values)
        if (_available(entry.config)) _start(entry.config.name),
    ]);
  }

  Future<void> _start(String name) async {
    try {
      await ensureReady(name);
    } catch (_) {
      // 初始化失败已写入状态；后台启动不能让一个服务阻断其他服务。
    }
  }

  Future<void> _acquire(Duration timeout) async {
    if (_connecting >= 4) {
      final waiter = Completer<void>();
      _slots.add(waiter);
      try {
        await waiter.future.timeout(timeout);
      } catch (_) {
        if (!_slots.remove(waiter)) {
          _release();
        }
        rethrow;
      }
    } else {
      _connecting++;
    }
  }

  void _release() {
    if (_slots.isNotEmpty) {
      _slots.removeAt(0).complete();
    } else {
      _connecting--;
    }
  }

  bool _current(_Entry entry) =>
      !_closed &&
      !_suspended &&
      !entry.retired &&
      identical(_entries[entry.config.name], entry);

  Future<McpConnection> _initialize(_Entry entry) async {
    var acquired = false;
    McpConnection? connection;
    final attempt = ++entry.attempt;
    final watch = Stopwatch()..start();
    Duration remaining() {
      final duration =
          Duration(seconds: entry.config.connectTimeoutSeconds) - watch.elapsed;
      if (duration <= Duration.zero) {
        throw TimeoutException('MCP initialization deadline exceeded');
      }
      return duration;
    }

    try {
      await _acquire(remaining());
      acquired = true;
      if (!_current(entry)) {
        throw StateError('MCP configuration changed');
      }
      entry.state = McpConnectionState(
        server: entry.config.name,
        status: McpConnectionStatus.connecting,
      );
      _publish();
      final pending = connect(entry.config);
      // 超时后的迟到连接也必须关闭，不能泄漏本地进程。
      var abandoned = false;
      pending.then((lateConnection) {
        if (abandoned) {
          unawaited(lateConnection.close());
        }
      }, onError: (Object _, StackTrace _) {});
      try {
        connection = await pending.timeout(remaining());
      } catch (_) {
        abandoned = true;
        rethrow;
      }
      if (!_current(entry)) {
        throw StateError('MCP configuration changed');
      }
      final activeConnection = connection;
      var disconnected = false;
      connection.onClosed = () {
        disconnected = true;
        if (_current(entry) && entry.attempt == attempt) {
          entry.connection = null;
          entry.state = McpConnectionState(
            server: entry.config.name,
            status: McpConnectionStatus.disconnected,
          );
          _publish();
        }
      };
      connection.onToolsChanged = () async {
        if (!_current(entry) || entry.attempt != attempt) {
          return;
        }
        if (entry.connection == null) {
          entry.refreshRequested = true;
          return;
        }
        await _refresh(entry, activeConnection);
      };
      var tools = await connection.listTools().timeout(remaining());
      while (entry.refreshRequested) {
        entry.refreshRequested = false;
        tools = await connection.listTools().timeout(remaining());
      }
      if (!_current(entry)) {
        throw StateError('MCP configuration changed');
      }
      if (disconnected) {
        throw StateError('MCP connection closed during discovery');
      }
      entry.connection = connection;
      entry.description = connection.description;
      entry.state = McpConnectionState(
        server: entry.config.name,
        status: McpConnectionStatus.ready,
        description: connection.description,
        instructions: connection.instructions,
        tools: tools,
      );
      _publish();
      return connection;
    } catch (error) {
      await connection?.close();
      if (_current(entry)) {
        entry.state = McpConnectionState(
          server: entry.config.name,
          status: error is McpNeedsAuth
              ? McpConnectionStatus.needs_auth
              : McpConnectionStatus.error,
          failureKind: mcpFailureKind(
            error is McpCommandException ? error.cause : error,
          ),
          error: mcpDiagnostic(error, entry.config),
        );
        _publish();
      }
      rethrow;
    } finally {
      entry.initializing = null;
      if (acquired) {
        _release();
      }
    }
  }

  Future<void> _refresh(_Entry entry, McpConnection connection) async {
    entry.refreshRequested = true;
    if (entry.refreshing) {
      return;
    }
    entry.refreshing = true;
    try {
      while (entry.refreshRequested && _current(entry)) {
        entry.refreshRequested = false;
        final tools = await connection.listTools().timeout(
          Duration(seconds: entry.config.connectTimeoutSeconds),
        );
        if (_current(entry) && identical(entry.connection, connection)) {
          entry.state = McpConnectionState(
            server: entry.config.name,
            status: McpConnectionStatus.ready,
            description: connection.description,
            instructions: connection.instructions,
            tools: tools,
          );
          _publish();
        }
      }
    } catch (error) {
      if (_current(entry) && identical(entry.connection, connection)) {
        entry.connection = null;
        await connection.close();
        entry.state = McpConnectionState(
          server: entry.config.name,
          status: error is McpNeedsAuth
              ? McpConnectionStatus.needs_auth
              : McpConnectionStatus.error,
          failureKind: mcpFailureKind(
            error is McpCommandException ? error.cause : error,
          ),
          error: mcpDiagnostic(error, entry.config),
        );
        _publish();
      }
    } finally {
      entry.refreshing = false;
    }
  }

  Future<void> requireAuthentication(String name) async {
    final entry = _entries[name];
    if (entry == null || entry.retired) {
      return;
    }
    final connection = entry.connection;
    entry.connection = null;
    await connection?.close();
    if (_current(entry)) {
      entry.state = McpConnectionState(
        server: name,
        status: McpConnectionStatus.needs_auth,
        error: const McpNeedsAuth().toString(),
      );
      _publish();
    }
  }

  Future<McpConnection> retry(String name) async {
    final entry = _entries[name];
    if (entry != null && !entry.retired && entry.connection == null) {
      entry.state = McpConnectionState(
        server: name,
        status: McpConnectionStatus.disconnected,
      );
    }
    return ensureReady(name);
  }

  Future<void> disconnect(String name) async {
    final entry = _entries[name];
    if (entry == null) {
      return;
    }
    final closing = _retire(entry);
    entry.state = McpConnectionState(
      server: name,
      status: McpConnectionStatus.disconnected,
    );
    _publish();
    await closing;
  }

  Future<void> suspend() async {
    _suspended = true;
    final generation = ++_lifecycleGeneration;
    final entries = _entries.values.toList();
    await Future.wait(entries.map(_retire));
    if (generation != _lifecycleGeneration || !_suspended || _closed) {
      return;
    }
    for (final entry in entries) {
      entry.state = McpConnectionState(
        server: entry.config.name,
        status: _available(entry.config)
            ? McpConnectionStatus.disconnected
            : McpConnectionStatus.disabled,
      );
    }
    _publish();
  }

  Future<void> resume() async {
    if (!_suspended) {
      return;
    }
    _lifecycleGeneration++;
    final settings = McpSettings(configs);
    final descriptions = {
      for (final entry in _entries.entries) entry.key: entry.value.description,
    };
    _entries.clear();
    _suspended = false;
    await configure(settings);
    for (final entry in _entries.entries) {
      entry.value.description = descriptions[entry.key];
    }
  }

  Future<void> _retire(_Entry entry) async {
    entry.retired = true;
    final connection = entry.connection;
    entry.connection = null;
    await connection?.close();
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_entries.values.map(_retire));
    await _updates.close();
  }
}

class _Entry {
  _Entry(this.config, McpConnectionStatus status)
    : state = McpConnectionState(server: config.name, status: status);
  McpServerConfig config;
  McpConnectionState state;
  String? description;
  McpConnection? connection;
  Future<McpConnection>? initializing;
  int attempt = 0;
  bool retired = false;
  bool refreshing = false;
  bool refreshRequested = false;
}

/// Remembers unavailable servers for one chat session, independently of shared
/// transports and other sessions' connection attempts.
class McpSession {
  McpSession(this.runtime);
  final McpRuntime runtime;
  final failures = <String, McpSessionFailure>{};
  McpSessionFailure? configurationFailure;

  void captureConfigurationErrors() {
    if (runtime.configurationError case final error?) {
      configurationFailure ??= McpSessionFailure(
        'mcp_configuration_error',
        error,
      );
    }
    for (final entry in runtime.configurationErrors.entries) {
      failures.putIfAbsent(
        entry.key,
        () => McpSessionFailure(
          'mcp_configuration_error',
          entry.value,
          server: entry.key,
        ),
      );
    }
  }

  McpSessionFailure? failure(String server) {
    captureConfigurationErrors();
    return configurationFailure ?? failures[server];
  }

  McpSessionFailure? toolFailure(String name) {
    captureConfigurationErrors();
    if (configurationFailure != null) {
      return configurationFailure;
    }
    final known = runtime.knownTools[name];
    if (known != null) {
      return failures[known.server];
    }
    final servers =
        {...runtime.configs.map((s) => s.name), ...failures.keys}.toList()
          ..sort(
            (a, b) =>
                mcpToolName(b, '').length.compareTo(mcpToolName(a, '').length),
          );
    for (final server in servers) {
      if (name.startsWith(mcpToolName(server, ''))) {
        return failures[server];
      }
    }
    return null;
  }

  Map<String, McpToolDescriptor> get tools => {
    for (final entry in runtime.tools.entries)
      if (failure(entry.value.server) == null) entry.key: entry.value,
  };

  Future<McpConnection> ensureReady(String server) async {
    final previous = failure(server);
    if (previous != null) {
      throw previous;
    }
    try {
      return await runtime.ensureReady(server);
    } catch (error) {
      final state = runtime.states[server];
      final failure = McpSessionFailure(
        error is McpNeedsAuth
            ? 'mcp_needs_auth'
            : error is TimeoutException
            ? 'mcp_timeout'
            : 'mcp_connection_failed',
        state?.error ?? error.toString(),
        server: server,
      );
      failures.putIfAbsent(server, () => failure);
      throw failures[server]!;
    }
  }
}

class McpSessionFailure implements Exception {
  const McpSessionFailure(this.code, this.message, {this.server});
  final String code;
  final String message;
  final String? server;
  @override
  String toString() => server == null ? message : '$server: $message';
}
