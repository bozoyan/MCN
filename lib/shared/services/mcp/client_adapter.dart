// 职责: 将 MCP SDK 的连接、分页目录和请求取消接入应用协议边界。
// 关联文件:
//   lib/shared/models/mcp/config.dart
//   lib/shared/services/mcp/runtime.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:http/http.dart' as http;
// The public conditional export omits stderr from its web stub; this native-only adapter needs the bounded diagnostic stream.
// ignore: implementation_imports
import 'package:mcp_dart/src/client/stdio.dart' as native;
// ignore: implementation_imports
import 'package:mcp_dart/src/shared/stdio.dart'
    show StdioMessageTooLargeException;
import '../../models/mcp/config.dart';
import 'diagnostics.dart';

abstract interface class McpConnection {
  set onToolsChanged(Future<void> Function()? callback);
  set onClosed(void Function()? callback);
  String? get description;
  String? get instructions;
  Future<List<Map<String, dynamic>>> listTools();
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments, {
    sdk.AbortSignal? signal,
    void Function(sdk.Progress)? onProgress,
  });
  Future<void> close();
}

class McpClientAdapter implements McpConnection {
  McpClientAdapter._(
    this.config,
    this.client,
    this.transport,
    this._refreshRejected,
  ) {
    client.onclose = () => _onClosed?.call();
    client.onerror = (error) {
      if (error is StdioMessageTooLargeException) {
        _oversizedAt = DateTime.now();
      }
    };
    client.setNotificationHandler<sdk.JsonRpcToolListChangedNotification>(
      'notifications/tools/list_changed',
      (_) async {
        await _onToolsChanged?.call();
      },
      (_, meta) => sdk.JsonRpcToolListChangedNotification(meta: meta),
    );
  }
  Future<void> Function()? _onToolsChanged;
  void Function()? _onClosed;
  bool _closed = false;
  DateTime? _oversizedAt;
  sdk.McpSubscription? _changes;
  StreamSubscription<sdk.JsonRpcNotification>? _changeDrain;
  @override
  set onToolsChanged(Future<void> Function()? callback) =>
      _onToolsChanged = callback;
  @override
  set onClosed(void Function()? callback) => _onClosed = callback;
  final McpServerConfig config;
  final sdk.McpClient client;
  final sdk.Transport transport;
  final Future<void> Function(String accessToken)? _refreshRejected;

  static Future<String>? _macosPath;

  // GUI launches do not read shell profiles. Resolve PATH once, then start
  // servers directly so shell startup output never enters the MCP stream.
  static Future<String> _readMacosPath() async {
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    final process = await Process.start(shell, [
      '-ilc',
      r'''printf '\0%s\0' "$PATH"''',
    ]);
    try {
      final output = await Future.wait<Object>([
        process.stdout.transform(utf8.decoder).join(),
        process.stderr.transform(utf8.decoder).join(),
        process.exitCode,
      ]).timeout(const Duration(seconds: 5));
      final fields = (output[0] as String).split('\x00');
      if (output[2] != 0 || fields.length < 3 || fields[1].isEmpty) {
        throw ProcessException(
          shell,
          const ['-ilc'],
          'Could not read login shell PATH: ${output[1]}',
          output[2] as int,
        );
      }
      return fields[1];
    } finally {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// [refreshRejected] replaces an OAuth access token the server rejected
  /// with HTTP 401. Each connect or request then retries once; a second
  /// rejection requires signing in again.
  static Future<McpClientAdapter> connect(
    McpServerConfig config, {
    sdk.OAuthClientProvider? authProvider,
    sdk.OAuthUriValidator? oauthUriValidator,
    Future<void> Function(String accessToken)? refreshRejected,
  }) async {
    try {
      return await _connect(
        config,
        authProvider: authProvider,
        oauthUriValidator: oauthUriValidator,
        refreshRejected: refreshRejected,
        refreshOnRejection: true,
      );
    } on _RefreshedAfterRejection {
      return _connect(
        config,
        authProvider: authProvider,
        oauthUriValidator: oauthUriValidator,
        refreshRejected: refreshRejected,
        refreshOnRejection: false,
      );
    }
  }

  static Future<McpClientAdapter> _connect(
    McpServerConfig config, {
    required sdk.OAuthClientProvider? authProvider,
    required sdk.OAuthUriValidator? oauthUriValidator,
    required Future<void> Function(String accessToken)? refreshRejected,
    required bool refreshOnRejection,
  }) async {
    if (!config.enabled) {
      throw StateError('MCP server is disabled');
    }
    // SDK raw logging can include remote payloads; diagnostics travel through the adapter.
    sdk.silenceMcpLogs();
    final client = sdk.McpClient(
      const sdk.Implementation(name: 'Reveric', version: '1'),
      options: sdk.McpClientOptions(
        capabilities: const sdk.ClientCapabilities(),
      ),
    );
    final sdk.Transport transport;
    switch (config.connection) {
      case McpStdioConfig connection:
        if (Platform.isAndroid) {
          throw UnsupportedError('MCP stdio is desktop only');
        }
        if (connection.cwd != null &&
            !await Directory(connection.cwd!).exists()) {
          throw const McpConfigurationFailure(
            McpFailureKind.working_directory,
            'MCP working directory does not exist',
          );
        }
        transport = _DiagnosticStdioTransport(
          native.StdioServerParameters(
            command: connection.command,
            args: connection.args,
            workingDirectory: connection.cwd,
            environment: {
              if (Platform.isMacOS && !connection.env.containsKey('PATH'))
                'PATH': await (_macosPath ??= _readMacosPath()),
              ...connection.env,
            },
            stderrMode: ProcessStartMode.normal,
          ),
        );
      case McpHttpConfig connection:
        if (connection.authMode == McpAuthMode.bearer &&
            (connection.bearerToken?.isEmpty ?? true)) {
          throw const FormatException('Bearer token is required');
        }
        final monitored = _HttpStatusClient(
          http.Client(),
          Uri.parse(connection.url),
        );
        transport = http.runWithClient(
          () => sdk.StreamableHttpClientTransport(
            Uri.parse(connection.url),
            opts: sdk.StreamableHttpClientTransportOptions(
              authProvider: authProvider,
              oauthUriValidator: oauthUriValidator,
              requestInit: {
                'headers': {
                  ...connection.headers,
                  if (connection.authMode == McpAuthMode.bearer &&
                      connection.bearerToken != null)
                    'Authorization': 'Bearer ${connection.bearerToken}',
                },
              },
            ),
          ),
          () => monitored,
        );
    }
    final exchange = _HttpExchange();
    try {
      return await runZoned(() async {
        await client
            .connect(transport)
            .timeout(Duration(seconds: config.connectTimeoutSeconds));
        final adapter = McpClientAdapter._(
          config,
          client,
          transport,
          refreshRejected,
        );
        await adapter._subscribeToToolChanges();
        return adapter;
      }, zoneValues: {_HttpExchange.zoneKey: exchange});
    } catch (error) {
      await client.close();
      if (exchange.lastStatus == 401) {
        final rejected = exchange.lastBearer;
        if (refreshOnRejection && refreshRejected != null && rejected != null) {
          await refreshRejected(rejected);
          throw const _RefreshedAfterRejection();
        }
        throw sdk.UnauthorizedError(error.toString());
      }
      if (transport is _DiagnosticStdioTransport &&
          transport.diagnostic.isNotEmpty) {
        throw McpCommandException(error, transport.diagnostic);
      }
      rethrow;
    }
  }

  Future<void> _subscribeToToolChanges() async {
    final version = client.getProtocolVersion();
    if (version == null ||
        !sdk.isStatelessProtocolVersion(version) ||
        client.getServerCapabilities()?.tools?.listChanged != true) {
      return;
    }
    final changes = client.listenSubscriptions(
      const sdk.SubscriptionsListenRequest(
        notifications: sdk.SubscriptionFilter(toolsListChanged: true),
      ),
    );
    _changes = changes;
    // The SDK also sends accepted notifications through the registered handler.
    // Drain its subscription stream without dispatching a second refresh.
    _changeDrain = changes.notifications.listen(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (!_closed) {
          unawaited(close());
        }
      },
    );
    unawaited(
      changes.done.then<void>(
        (_) {
          if (!_closed) {
            unawaited(close());
          }
        },
        onError: (Object _, StackTrace _) {
          if (!_closed) {
            unawaited(close());
          }
        },
      ),
    );
    final acknowledged = await changes.acknowledged.timeout(
      Duration(seconds: config.connectTimeoutSeconds),
    );
    if (acknowledged.notifications.toolsListChanged != true) {
      throw StateError('MCP server rejected tool-change subscription');
    }
  }

  @override
  String? get description => client.getServerVersion()?.description;
  @override
  String? get instructions => client.getInstructions();
  @override
  Future<List<Map<String, dynamic>>> listTools() async {
    final tools = <Map<String, dynamic>>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final pageCursor = cursor;
      final page = await _authorized(
        () => client.listTools(
          params: sdk.ListToolsRequest(cursor: pageCursor),
          options: sdk.RequestOptions(
            timeout: Duration(seconds: config.connectTimeoutSeconds),
          ),
        ),
      );
      tools.addAll(page.tools.map((tool) => tool.toJson()));
      cursor = page.nextCursor;
      if (cursor != null && !cursors.add(cursor)) {
        throw StateError('MCP repeated pagination cursor');
      }
    } while (cursor != null);
    return tools;
  }

  @override
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments, {
    sdk.AbortSignal? signal,
    void Function(sdk.Progress)? onProgress,
  }) async {
    final startedAt = DateTime.now();
    try {
      return (await _authorized(
        () => client.callTool(
          sdk.CallToolRequest(name: name, arguments: arguments),
          options: sdk.RequestOptions(
            signal: signal,
            onprogress: onProgress,
            timeout: Duration(seconds: config.callTimeoutSeconds),
            maxTotalTimeout: Duration(seconds: config.callTimeoutSeconds),
          ),
        ),
      )).toJson();
    } catch (error) {
      if (_oversizedAt != null && !_oversizedAt!.isBefore(startedAt)) {
        throw const McpResponseUnavailable();
      }
      final active = transport;
      if (active is _DiagnosticStdioTransport && active.diagnostic.isNotEmpty) {
        throw McpCommandException(error, active.diagnostic);
      }
      rethrow;
    }
  }

  /// Runs one request and attributes an HTTP 401/403 answer to it. Such a
  /// request never ran, so an OAuth request may be retried once after the
  /// rejected token is refreshed.
  Future<T> _authorized<T>(Future<T> Function() request) async {
    final exchange = _HttpExchange();
    try {
      return await runZoned(
        request,
        zoneValues: {_HttpExchange.zoneKey: exchange},
      );
    } catch (error) {
      final status = exchange.rejectedStatus;
      if (status == null) {
        rethrow;
      }
      final refresh = _refreshRejected;
      if (refresh == null) {
        throw McpCredentialsRejected(status, error);
      }
      final rejected = exchange.lastBearer;
      if (status != 401 || rejected == null) {
        throw const McpNeedsAuth(requestRejected: true);
      }
      try {
        await refresh(rejected);
      } on McpNeedsAuth {
        throw const McpNeedsAuth(requestRejected: true);
      } catch (refreshError) {
        throw McpCredentialsRejected(status, refreshError);
      }
    }
    final retry = _HttpExchange();
    try {
      return await runZoned(
        request,
        zoneValues: {_HttpExchange.zoneKey: retry},
      );
    } catch (error) {
      if (retry.rejectedStatus == null) {
        rethrow;
      }
      throw const McpNeedsAuth(requestRejected: true);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _changes?.cancel();
    await _changeDrain?.cancel();
    await client.close();
  }
}

class McpCommandException implements Exception {
  const McpCommandException(this.cause, this.diagnostic);
  final Object cause;
  final String diagnostic;
  @override
  String toString() => '$cause\nstderr: $diagnostic';
}

class _DiagnosticStdioTransport extends native.StdioClientTransport {
  _DiagnosticStdioTransport(super.parameters);
  final _stderr = <int>[];
  StreamSubscription<List<int>>? _diagnostics;
  String get diagnostic => utf8.decode(_stderr, allowMalformed: true);
  @override
  Future<void> start() async {
    await super.start();
    _diagnostics = super.stderr?.listen((bytes) {
      _stderr.addAll(bytes);
      if (_stderr.length > 8192) {
        _stderr.removeRange(0, _stderr.length - 8192);
      }
    });
  }

  @override
  Future<void> close() async {
    await super.close();
    await _diagnostics?.cancel();
  }
}

class McpResponseUnavailable implements Exception {
  const McpResponseUnavailable();
  @override
  String toString() =>
      'MCP response exceeded the transport message limit before it could be decoded.';
}

class _RefreshedAfterRejection implements Exception {
  const _RefreshedAfterRejection();
}

// Endpoint POST outcomes of one MCP operation, kept independently of SDK or
// server error text. Scoped by zone because concurrent requests share one
// connection and HTTP client.
class _HttpExchange {
  static final zoneKey = Object();
  int? lastStatus;
  String? lastBearer;
  bool accepted = false;

  void record(http.BaseRequest request, int status) {
    lastStatus = status;
    final authorization = request.headers['authorization'];
    lastBearer = authorization != null && authorization.startsWith('Bearer ')
        ? authorization.substring('Bearer '.length)
        : null;
    if (status >= 200 && status < 300) {
      accepted = true;
    }
  }

  /// A 401/403 counts as a rejection only while no request of the operation
  /// was accepted; after that the server may already have run it.
  int? get rejectedStatus =>
      !accepted && (lastStatus == 401 || lastStatus == 403) ? lastStatus : null;
}

class _HttpStatusClient extends http.BaseClient {
  _HttpStatusClient(this.inner, this.endpoint);
  final http.Client inner;
  final Uri endpoint;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    final exchange = Zone.current[_HttpExchange.zoneKey];
    if (exchange is _HttpExchange &&
        request.method == 'POST' &&
        request.url == endpoint) {
      exchange.record(request, response.statusCode);
    }
    return response;
  }

  @override
  void close() => inner.close();
}
