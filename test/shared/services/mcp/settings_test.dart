// 职责: 验证 MCP 配置写入与运行中编辑保留各会话调用事实及其他服务。
// 关联文件:
//   lib/shared/services/mcp/settings_service.dart
//   lib/shared/services/mcp/tool_dispatcher.dart
//   lib/shared/services/mcp/settings_orchestrator.dart
//   lib/shared/models/mcp/config.dart
import 'dart:async';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/services/mcp/settings_orchestrator.dart';
import 'package:reveric/shared/services/mcp/settings_service.dart';
import 'package:reveric/shared/services/mcp/tool_dispatcher.dart';
import 'package:reveric/shared/models/mcp/call_result.dart';
import 'runtime_test.dart' show FakeConnection;

class PendingConnection extends FakeConnection {
  int calls = 0;
  final pending = <Completer<Map<String, dynamic>>>[];
  final bothStarted = Completer<void>();
  @override
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments, {
    sdk.AbortSignal? signal,
    void Function(sdk.Progress)? onProgress,
  }) async {
    calls++;
    if (arguments['wait'] == true) {
      final result = Completer<Map<String, dynamic>>();
      pending.add(result);
      if (pending.length == 2) {
        bothStarted.complete();
      }
      return result.future;
    }
    return {
      'content': [
        {'type': 'text', 'text': 'saved'},
      ],
    };
  }

  @override
  Future<void> close() async {
    for (final result in pending) {
      if (!result.isCompleted) {
        result.completeError(StateError('Connection closed after sending'));
      }
    }
    await super.close();
  }
}

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTest(NativeDatabase.memory());
  });
  tearDown(() => db.close());
  McpServerConfig config(String name) => McpServerConfig(
    name: name,
    enabled: true,
    connection: McpStdioConfig(command: 'test', env: {'SECRET': 'credential'}),
  );
  test(
    'valid OAuth survives disable and failed-save rollback without login',
    () async {
      final service = McpSettingsService(
        db,
        supportsStdio: true,
        connector: (_) async => FakeConnection(),
      );
      try {
        await service.initialized;
        final original = McpServerConfig(
          name: 'oauth',
          enabled: true,
          connection: McpHttpConfig(
            url: 'https://example.test',
            authMode: McpAuthMode.oauth,
            oauth: {
              'accessToken': 'valid',
              'issuer': 'https://example.test',
              'resource': 'https://example.test',
              'expiresAt': '2099-01-01T00:00:00Z',
            },
          ),
        );
        await service.save(original, create: true);
        await db.customStatement('PRAGMA query_only = ON');
        await expectLater(
          service.save(original.copyWith(enabled: false), create: false),
          throwsA(anything),
        );
        await db.customStatement('PRAGMA query_only = OFF');
        expect((await service.oauth.tokens(original))!.accessToken, 'valid');
        await service.save(original.copyWith(enabled: false), create: false);
        await service.save(original, create: false);
        expect((await service.oauth.tokens(original))!.accessToken, 'valid');
      } finally {
        await service.close();
      }
    },
  );
  for (final action in ['delete', 'disable', 'connection', 'authentication']) {
    test(
      'in-flight sessions preserve call facts across $action',
      () async {
        final connections = <String, List<PendingConnection>>{};
        final service = McpSettingsService(
          db,
          supportsStdio: true,
          connector: (config) async {
            final connection = PendingConnection();
            connections.putIfAbsent(config.name, () => []).add(connection);
            return connection;
          },
        );
        try {
          await service.initialized;
          final original = config('notes');
          await service.save(original, create: true);
          await service.save(config('other'), create: true);
          await service.runtime.ensureReady('notes');
          await service.runtime.ensureReady('other');
          final old = connections['notes']!.single;
          final unaffected = connections['other']!.single;
          final dispatcher = McpToolDispatcher(service.runtime);
          final succeeded = await dispatcher.call('mcp__notes__search', {});
          final a = dispatcher.call('mcp__notes__search', {'wait': true});
          final b = dispatcher.call('mcp__notes__search', {'wait': true});
          await old.bothStarted.future;
          if (action == 'delete') {
            await service.delete('notes');
          } else {
            final edited = switch (action) {
              'disable' => original.copyWith(enabled: false),
              'connection' => original.copyWith(
                connection: McpStdioConfig(
                  command: 'new-command',
                  env: {'SECRET': 'credential'},
                ),
              ),
              _ => original.copyWith(
                connection: McpStdioConfig(
                  command: 'test',
                  env: {'SECRET': 'new-credential'},
                ),
              ),
            };
            await service.save(edited, create: false, baseline: original);
          }
          expect(succeeded.executionState, McpExecutionState.succeeded);
          expect((await a).executionState, McpExecutionState.unknown);
          expect((await b).executionState, McpExecutionState.unknown);
          expect(old.closed, true);
          expect(old.calls, 3);
          final next = await dispatcher.call('mcp__notes__search', {});
          if (action == 'delete' || action == 'disable') {
            expect(next.executionState, McpExecutionState.not_started);
            expect(connections['notes'], hasLength(1));
          } else {
            expect(next.executionState, McpExecutionState.succeeded);
            expect(connections['notes'], hasLength(2));
            expect(connections['notes']!.last.calls, 1);
          }
          expect(
            (await dispatcher.call('mcp__other__search', {})).executionState,
            McpExecutionState.succeeded,
          );
          expect(unaffected.closed, false);
          expect(connections['other'], hasLength(1));
        } finally {
          await service.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
  test(
    'saving an older editor snapshot preserves newly refreshed OAuth tokens',
    () async {
      final operations = McpSettingsOrchestrator();
      final baseline = McpServerConfig(
        name: 'notes',
        enabled: true,
        connection: McpHttpConfig(
          url: 'https://example.test',
          authMode: McpAuthMode.oauth,
          oauth: {
            'clientId': 'client',
            'accessToken': 'old',
            'refreshToken': 'old-refresh',
          },
        ),
      );
      await operations.save(database: db, config: baseline, create: true);
      await operations.update(
        database: db,
        change: (_) => McpSettings([
          baseline.copyWith(
            connection: McpHttpConfig(
              url: 'https://example.test',
              authMode: McpAuthMode.oauth,
              oauth: {
                'clientId': 'client',
                'accessToken': 'new',
                'refreshToken': 'new-refresh',
              },
            ),
          ),
        ]),
      );
      final updated = await operations.save(
        database: db,
        config: baseline.copyWith(description: 'New purpose'),
        create: false,
        baseline: baseline,
      );
      final saved = updated.servers.single;
      expect(saved.description, 'New purpose');
      expect((saved.connection as McpHttpConfig).oauth['accessToken'], 'new');
      expect(
        (saved.connection as McpHttpConfig).oauth['refreshToken'],
        'new-refresh',
      );
    },
  );
  test('concurrent edits preserve every service', () async {
    await Future.wait([
      for (final name in ['one', 'two', 'three'])
        McpSettingsOrchestrator().save(
          database: db,
          config: config(name),
          create: true,
        ),
    ]);
    final saved = McpSettings.decode(
      await db.appSettingsDao.get(McpSettings.key),
    );
    expect(
      saved.servers.map((s) => s.name),
      containsAll(['one', 'two', 'three']),
    );
  });
  test('collision does not replace persisted configuration', () async {
    final operations = McpSettingsOrchestrator();
    await operations.save(
      database: db,
      config: config('docs-api'),
      create: true,
    );
    final before = await db.appSettingsDao.get(McpSettings.key);
    await expectLater(
      operations.save(database: db, config: config('docs_api'), create: true),
      throwsFormatException,
    );
    expect(await db.appSettingsDao.get(McpSettings.key), before);
  });
  test('deleted server name can be created and imported again', () async {
    final service = McpSettingsService(
      db,
      supportsStdio: true,
      connector: (_) async => FakeConnection(),
    );
    try {
      await service.initialized;
      await service.save(config('github'), create: true);
      await service.save(config('other'), create: true);
      await service.delete('github');
      expect(
        McpSettings.decode(
          await db.appSettingsDao.get(McpSettings.key),
        ).servers.map((s) => s.name),
        ['other'],
      );
      await service.save(config('github'), create: true);
      await service.delete('github');
      await service.importServers([config('github')]);
      expect(
        McpSettings.decode(
          await db.appSettingsDao.get(McpSettings.key),
        ).servers.map((s) => s.name),
        ['other', 'github'],
      );
    } finally {
      await service.close();
    }
  });
  test(
    'name conflicts report both names and leave storage untouched',
    () async {
      final service = McpSettingsService(
        db,
        supportsStdio: true,
        connector: (_) async => FakeConnection(),
      );
      try {
        await service.initialized;
        await service.save(config('docs-api'), create: true);
        final before = await db.appSettingsDao.get(McpSettings.key);
        await expectLater(
          service.save(config('docs-api'), create: true),
          throwsA(
            isA<McpServerNameConflict>()
                .having((e) => e.name, 'name', 'docs-api')
                .having((e) => e.existing, 'existing', 'docs-api'),
          ),
        );
        await expectLater(
          service.importServers([config('docs_api')]),
          throwsA(
            isA<McpServerNameConflict>()
                .having((e) => e.name, 'name', 'docs_api')
                .having((e) => e.existing, 'existing', 'docs-api'),
          ),
        );
        expect(await db.appSettingsDao.get(McpSettings.key), before);
      } finally {
        await service.close();
      }
    },
  );
}
