// 职责: 验证共享初始化、配置代次与连接并发上限。
// 关联文件:
//   lib/shared/services/mcp/runtime.dart
//   lib/shared/services/mcp/client_adapter.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'package:reveric/shared/services/mcp/client_adapter.dart';

class FakeConnection implements McpConnection {
  bool closed = false;
  @override
  Future<void> Function()? onToolsChanged;
  @override
  void Function()? onClosed;
  @override
  String? get description => 'Notes';
  @override
  String? get instructions => null;
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    {
      'name': 'search',
      'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  ];
  @override
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments, {
    sdk.AbortSignal? signal,
    void Function(sdk.Progress)? onProgress,
  }) async => {};
}

class ChangingConnection extends FakeConnection {
  final firstPage = Completer<void>();
  final started = Completer<void>();
  int lists = 0;
  @override
  Future<List<Map<String, dynamic>>> listTools() async {
    lists++;
    if (lists == 1) {
      started.complete();
      await firstPage.future;
    }
    return [
      {
        'name': lists == 1 ? 'old' : 'new',
        'inputSchema': {'type': 'object'},
      },
    ];
  }
}

class SlowConnection extends FakeConnection {
  @override
  Future<List<Map<String, dynamic>>> listTools() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return super.listTools();
  }
}

class DelayedCloseConnection extends FakeConnection {
  final closing = Completer<void>();
  final releaseClose = Completer<void>();
  @override
  Future<void> close() async {
    if (!closing.isCompleted) {
      closing.complete();
    }
    await releaseClose.future;
    await super.close();
    onClosed?.call();
  }
}

void main() {
  McpServerConfig config(String name) => McpServerConfig(
    name: name,
    enabled: true,
    connection: McpHttpConfig(url: 'https://example.test/mcp'),
  );
  test('late suspend close cannot erase resumed directory', () async {
    final old = DelayedCloseConnection();
    final current = FakeConnection();
    var count = 0;
    final runtime = McpRuntime(
      connect: (_) async => count++ == 0 ? old : current,
    );
    addTearDown(runtime.close);
    await runtime.configure(McpSettings([config('notes')]));
    await runtime.ensureReady('notes');
    final suspend = runtime.suspend();
    await old.closing.future;
    await runtime.resume();
    await runtime.ensureReady('notes');
    old.releaseClose.complete();
    await suspend;
    expect(runtime.states['notes']!.status, McpConnectionStatus.ready);
    expect(runtime.tools, isNotEmpty);
    expect(await runtime.ensureReady('notes'), same(current));
    expect(current.closed, false);
    expect(old.closed, true);
  });
  test('OAuth token rotation keeps the live tool connection', () async {
    final connection = FakeConnection();
    final runtime = McpRuntime(connect: (_) async => connection);
    addTearDown(runtime.close);
    McpServerConfig oauth(String token) => McpServerConfig(
      name: 'notes',
      enabled: true,
      connection: McpHttpConfig(
        url: 'https://example.test',
        authMode: McpAuthMode.oauth,
        oauth: {
          'clientId': 'client',
          'accessToken': token,
          'refreshToken': 'refresh-$token',
          'expiresAt': '2030-01-01T00:00:00Z',
        },
      ),
    );
    await runtime.configure(McpSettings([oauth('old')]));
    await runtime.ensureReady('notes');
    await runtime.configure(McpSettings([oauth('new')]));
    expect(connection.closed, false);
    expect(await runtime.ensureReady('notes'), same(connection));
  });
  for (final changedAuth in [
    {'clientId': 'other', 'accessToken': 'token'},
    {
      'clientId': 'client',
      'accessToken': 'token',
      'issuer': 'https://other.test',
    },
    {'clientId': 'client'},
  ]) {
    test(
      'OAuth identity change retires the tool connection: $changedAuth',
      () async {
        final connection = FakeConnection();
        final runtime = McpRuntime(connect: (_) async => connection);
        addTearDown(runtime.close);
        McpServerConfig config(Map<String, dynamic> auth) => McpServerConfig(
          name: 'notes',
          enabled: true,
          connection: McpHttpConfig(
            url: 'https://example.test',
            authMode: McpAuthMode.oauth,
            oauth: auth,
          ),
        );
        await runtime.configure(
          McpSettings([
            config({'clientId': 'client', 'accessToken': 'token'}),
          ]),
        );
        await runtime.ensureReady('notes');
        await runtime.configure(McpSettings([config(changedAuth)]));
        expect(connection.closed, true);
        expect(
          runtime.states['notes']!.status,
          McpConnectionStatus.disconnected,
        );
      },
    );
  }
  test('tool changes during first discovery are not lost', () async {
    final connection = ChangingConnection();
    final runtime = McpRuntime(connect: (_) async => connection);
    addTearDown(runtime.close);
    await runtime.configure(McpSettings([config('notes')]));
    final ready = runtime.ensureReady('notes');
    await connection.started.future;
    await connection.onToolsChanged!.call();
    connection.firstPage.complete();
    await ready;
    expect(connection.lists, 2);
    expect(runtime.states['notes']!.tools.single['name'], 'new');
  });
  test('connection and initial discovery share one total deadline', () async {
    final connection = SlowConnection();
    final runtime = McpRuntime(
      connect: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return connection;
      },
    );
    addTearDown(runtime.close);
    await runtime.configure(
      McpSettings([
        McpServerConfig(
          name: 'notes',
          enabled: true,
          connectTimeoutSeconds: 1,
          connection: McpHttpConfig(url: 'https://example.test'),
        ),
      ]),
    );
    await expectLater(
      runtime.ensureReady('notes'),
      throwsA(isA<TimeoutException>()),
    );
    expect(connection.closed, true);
  });
  test(
    'concurrent sessions initialize once and description changes retain connection',
    () async {
      final gate = Completer<McpConnection>();
      var count = 0;
      final runtime = McpRuntime(
        connect: (_) {
          count++;
          return gate.future;
        },
      );
      addTearDown(runtime.close);
      await runtime.configure(McpSettings([config('notes')]));
      final a = runtime.ensureReady('notes');
      final b = runtime.ensureReady('notes');
      final connection = FakeConnection();
      gate.complete(connection);
      expect(await a, same(await b));
      expect(count, 1);
      await runtime.configure(
        McpSettings([
          config(
            'notes',
          ).copyWith(description: 'New purpose', exposure: McpExposure.direct),
        ]),
      );
      expect(await runtime.ensureReady('notes'), same(connection));
      expect(connection.closed, false);
    },
  );
  test('late initialization after disable cannot republish tools', () async {
    final gate = Completer<McpConnection>();
    final started = Completer<void>();
    final runtime = McpRuntime(
      connect: (_) {
        started.complete();
        return gate.future;
      },
    );
    addTearDown(runtime.close);
    await runtime.configure(McpSettings([config('notes')]));
    final pending = runtime.ensureReady('notes');
    final expectation = expectLater(pending, throwsStateError);
    await started.future;
    await runtime.configure(
      McpSettings([config('notes').copyWith(enabled: false)]),
    );
    final connection = FakeConnection();
    gate.complete(connection);
    await expectation;
    expect(connection.closed, true);
    expect(runtime.states['notes']!.status, McpConnectionStatus.disabled);
    expect(runtime.states['notes']!.tools, isEmpty);
  });
  test(
    'background initialization permits at most four concurrent connections',
    () async {
      var active = 0;
      var maximum = 0;
      final runtime = McpRuntime(
        connect: (_) async {
          active++;
          if (active > maximum) {
            maximum = active;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return FakeConnection();
        },
      );
      addTearDown(runtime.close);
      await runtime.configure(
        McpSettings([for (var n = 0; n < 9; n++) config('s$n')]),
      );
      await runtime.startEnabled();
      expect(maximum, 4);
      expect(
        runtime.states.values.every(
          (s) => s.status == McpConnectionStatus.ready,
        ),
        true,
      );
    },
  );
}
