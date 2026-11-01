// 职责: 用真实 FJS 与 Agent hooks 验证 Run、direct 和脚本统一调用 MCP。
// 关联文件:
//   lib/shared/services/ai/mcp/agent_dispatcher.dart
//   lib/shared/services/ai/codemode/orchestrator.dart
//   lib/shared/services/mcp/tool_dispatcher.dart
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import '../test/shared/services/mcp/adapter_test.dart' show reply;
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/agent/agent.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/models/ai_nested_tool_call.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/ai/mcp/agent_dispatcher.dart';
import 'package:reveric/shared/services/ai/codemode/orchestrator.dart';
import 'package:reveric/shared/services/ai/codemode/scheduler.dart';
import 'package:reveric/shared/services/mcp/settings_service.dart';
import 'package:reveric/shared/services/mcp/settings_orchestrator.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import '../test/shared/services/mcp/execution_test.dart'
    show ExecutionConnection;
import '../test/shared/services/ai/mcp/agent_scope_test.dart' show CountHook;

class EvaluationConnection extends ExecutionConnection {
  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    ...await super.listTools(),
    {
      'name': 'search',
      'description': 'Search notes 查找笔记',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
    },
  ];
  @override
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments, {
    sdk.AbortSignal? signal,
    void Function(sdk.Progress)? onProgress,
  }) async {
    if (name == 'search') {
      calls++;
      return {
        'content': [],
        'structuredContent': {
          'notes': [
            {'id': 'one', 'text': 'first note'},
            {'id': 'two', 'text': 'selected note'},
            {'id': 'three', 'text': 'third note'},
          ],
        },
      };
    }
    return super.callTool(
      name,
      arguments,
      signal: signal,
      onProgress: onProgress,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'MCP discovery and all three execution entries retain one external effect per call',
    (tester) async {
      await tester.runAsync(() async {
        final app = AppDatabase.forTest(NativeDatabase.memory());
        final db = NovelContentDatabase.forTest(NativeDatabase.memory());
        final content = NovelContentService(db);
        final inner = AiToolManager(
          content,
          workingOverlayService: WorkingOverlayService(
            db,
            content,
            novelActionsService: NovelActionsService(app),
          ),
        )..registerAllTools();
        final connection = EvaluationConnection();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          if (request.method != 'POST') {
            request.response.statusCode = 405;
            await request.response.close();
            return;
          }
          final rpc =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          Map<String, dynamic>? response;
          if (rpc['method'] == 'tools/list') {
            response = {
              'jsonrpc': '2.0',
              'id': rpc['id'],
              'result': {
                'tools': await connection.listTools(),
                'resultType': 'complete',
                'ttlMs': 0,
                'cacheScope': 'private',
              },
            };
          } else if (rpc['method'] == 'tools/call') {
            request.response.bufferOutput = false;
            final params = rpc['params'] as Map;
            final token = (params['_meta'] as Map?)?['progressToken'];
            expect(token, isNotNull);
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.write(
              'event: message\ndata: ${jsonEncode({
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': {'progressToken': token, 'progress': 1, 'total': 2, 'message': 'fixture progress'},
              })}\n\n',
            );
            await request.response.flush();
            final result = await connection.callTool(
              params['name'] as String,
              Map<String, dynamic>.from(params['arguments'] as Map),
            );
            request.response.write(
              'event: message\ndata: ${jsonEncode({
                'jsonrpc': '2.0',
                'id': rpc['id'],
                'result': {...result, 'resultType': 'complete'},
              })}\n\n',
            );
            await request.response.close();
            return;
          } else {
            response = reply(rpc, modern: true);
          }
          if (response == null) {
            request.response.statusCode = 202;
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(response));
          }
          await request.response.close();
        });
        await McpSettingsOrchestrator().save(
          database: app,
          create: true,
          config: McpServerConfig(
            name: 'notes',
            enabled: true,
            connection: McpHttpConfig(
              url: 'http://127.0.0.1:${server.port}/mcp',
            ),
          ),
        );
        final service = McpSettingsService(app, supportsStdio: true);
        final scheduler = CodemodeScheduler(maxActive: 1);
        try {
          await service.activate();
          await service.runtime.ensureReady('notes');
          final tools = McpAgentToolDispatcher(
            inner: inner,
            runTools: inner,
            service: service,
            isEnabled: () => true,
          );
          final hooks = CountHook();
          final agent = Agent.custom(
            id: 'mcp-fixture',
            systemPrompt: 'fixture',
            client: FakeProviderClient(),
            config: const AgentConfig(),
            toolManager: tools,
            hooks: [hooks],
          );
          final progress = <Map<String, dynamic>>[];
          final context = ToolExecutionContext(
            lifecycleObserver: ToolLifecycleObserver(onProgress: progress.add),
            sessionId: 'session',
            sourceSessionId: 'session',
            sourceTurnId: 'turn',
          );
          final direct = await agent.runToolCall(
            const ToolCall(
              callId: 'direct',
              toolName: 'mcp__notes__write',
              arguments: {'number': 1},
            ),
            context: context,
          );
          final run = await agent.runToolCall(
            const ToolCall(
              callId: 'run',
              toolName: 'Run',
              arguments: {
                'command': 'mcp',
                'subcommand': 'call',
                'options': {
                  'name': 'mcp__notes__write',
                  'arguments': {'number': 1},
                },
              },
            ),
            context: context,
          );
          expect(progress, hasLength(2));
          expect(
            progress.every((item) => item['message'] == 'fixture progress'),
            true,
          );
          expect(direct['executionState'], 'succeeded');
          expect(run['executionState'], 'succeeded');
          final records = <AiNestedToolCall>[];
          final script = await CodemodeOrchestrator().execute(
            input: {
              'code': r'''
const servers = await listMcpServers();
if (servers.servers[0].name !== 'notes') throw new Error('service missing');
const found = await searchTool('write', {mcpServer:'notes'});
const name = found.tools[0].name;
const definition = await describeTool(name);
const notes = await tools.mcp__notes__search({query:'character notes'});
const created = await tools.Create({path:'skills',fields:{title:'MCP fixture',content:''}});
await tools.Write({path:'skills/' + created.id + '/content',value:notes.structuredContent.notes[1].text});
const result = await tools[name]({number:1});
text(result.executionState);
try { await tools[name]({number:0}); throw new Error('invalid input accepted'); }
catch (error) { text(error.result.executionState); }
text(created.id);
''',
            },
            context: context,
            parentToolCallId: 'script',
            tools: tools,
            catalog: tools.catalog,
            runTool: (call, context) =>
                agent.runToolCall(call, context: context),
            onRecord: records.add,
            scheduler: scheduler,
            isAllowed: () => true,
            allowedToolNames: () => ['Run', 'Create', 'Write'],
          );
          expect(script['ok'], true, reason: '$script');
          final output = script['output'] as List;
          expect(output.take(2), ['succeeded', 'not_started']);
          expect(
            (await content.getItemById(output[2] as String))!.content,
            'selected note',
          );
          expect(output.toString(), isNot(contains('inputSchema')));
          expect(
            records.where(
              (record) =>
                  record.status == AiNestedToolStatus.running &&
                  record.resultPreview.contains('fixture progress'),
            ),
            hasLength(2),
          );
          expect(connection.calls, 4);
          expect(hooks.before, 7);
          expect(hooks.after, 7);
          final latest = {for (final record in records) record.callId: record};
          expect(
            latest.values.where((record) => record.source == 'mcp'),
            hasLength(3),
          );
          expect(
            latest.values.every(
              (record) =>
                  record.parentCallId == 'script' &&
                  record.sourceSessionId == 'session',
            ),
            true,
          );
          expect(
            latest.values
                .firstWhere((record) => record.source == 'mcp')
                .effectStatus,
            AiToolEffectStatus.unknown,
          );
        } finally {
          scheduler.dispose();
          await service.close();
          await server.close(force: true);
          await db.close();
          await app.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
