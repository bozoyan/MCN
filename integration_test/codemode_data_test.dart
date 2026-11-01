// 职责: 通过真实 FJS、Agent、数据工具和 Run 验证临时数据变更、归属及回退。
// 关联文件:
//   lib/shared/services/ai/codemode/orchestrator.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/working_overlay.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/agent/agent.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_nested_tool_call.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/ai/codemode/orchestrator.dart';
import 'package:reveric/shared/services/ai/codemode/scheduler.dart';
import 'package:reveric/shared/services/ai/codemode/tool.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('data tools and Run preserve changes and source turn through FJS', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final app = AppDatabase.forTest(NativeDatabase.memory());
      final content = NovelContentService(db);
      final overlay = WorkingOverlayService(
        db,
        content,
        novelActionsService: NovelActionsService(app),
      );
      final tools = AiToolManager(content, workingOverlayService: overlay)
        ..registerAllTools();
      final dispatcher = _Dispatcher(tools);
      try {
        final disposable = await content.createItem(
          type: 'skill',
          title: 'Disposable',
          content: 'temporary',
        );
        final code =
            '''
const created = await tools.Create({path:'skills', fields:{title:'Fixture',content:'first clue'}});
const path = 'skills/' + created.id + '/content';
await tools.Write({path, value:'second clue'});
await tools.Edit({path, old_text:'second', new_text:'third'});
await tools.Replace({path:'skills', pattern:'clue', replacement:'evidence', dry_run:false});
const read = await tools.Read({path});
const glob = await tools.Glob({pattern:'skills/*/content'});
const grep = await tools.Grep({path:'skills', pattern:'evidence', output_mode:'files_with_matches'});
const graph = await tools.GraphSearch({type:'skill', id:created.id});
const removal = await tools.Remove({path:'skills/$disposable'});
const help = await tools.Run({command:'help'});
if (!help.output.includes('agent-rules:')) throw new Error('Missing Run help');
await tools.Run({command:'agent-rules', subcommand:'create', options:{name:'Code rule',content:'Keep the viewpoint stable.'}});
const rules = await tools.Run({command:'agent-rules', subcommand:'list'});
if (!rules.rules.some(rule => rule.name === 'Code rule')) throw new Error('Run write not visible');
try { await tools.Run({command:'account', subcommand:'login'}); throw new Error('Login must be blocked'); }
catch (error) { if (error.error_code !== 'permission_denied') throw error; }
return {id:created.id, value:read.value, matches:glob.matches, grep:grep.text, relations:graph.total_relations, removed:removal.removed};
''';
        final agent = FakeAgent.create(
          toolManager: dispatcher,
          responses: [
            FakeProviderClientResponse.toolCalls([
              ToolCall(
                callId: 'parent',
                toolName: 'Codemode',
                arguments: {'code': code},
              ),
            ]),
            FakeProviderClientResponse.text('done'),
          ],
        );
        dispatcher.agent = agent;
        final events = await agent
            .process(
              'fixture',
              toolExecutionContext: ToolExecutionContext(
                sessionId: 'fixture-session',
                sourceSessionId: 'fixture-session',
                sourceTurnId: 'fixture-turn',
              ),
            )
            .toList();
        final result =
            events.whereType<AgentToolCallResult>().single.output as Map;
        expect(result['ok'], isTrue, reason: '$result');
        expect(result['call_count'], 13);
        expect(result['completed_count'], 12);
        expect(result['failed_count'], 1);
        expect(
          (result['completed_operations'] as List).any(
            (item) => item['command'] == 'agent-rules create',
          ),
          isTrue,
        );
        final value = result['return_value'] as Map;
        expect(value['value'], 'third evidence');
        expect(value['removed'], isTrue);
        expect(value['matches'], contains('skills/${value['id']}/content'));
        expect(value['grep'], contains('skills/${value['id']}/content'));
        final changes = await db.workingChangeDao.getAll();
        expect(changes, isNotEmpty);
        expect(
          changes.every(
            (c) =>
                c.sourceSessionId == 'fixture-session' &&
                c.sourceTurnId == 'fixture-turn',
          ),
          isTrue,
          reason: changes
              .map(
                (c) =>
                    '${c.toolName}: ${c.sourceSessionId}/${c.sourceTurnId} ${c.resourcePath}',
              )
              .join('\n'),
        );
        expect(await content.getItemById(disposable), isNull);
        final replacement = changes.firstWhere(
          (c) => c.newText == 'third evidence',
        );
        final records = dispatcher.records['parent']!;
        for (final name in ['Create', 'Write', 'Edit', 'Replace']) {
          final record = records.values.singleWhere((r) => r.toolName == name);
          expect(record.workingChangeId, isNotNull, reason: name);
          expect(changes.map((c) => c.id), contains(record.workingChangeId));
          expect(record.workingChangeScope!.sourceSessionId, 'fixture-session');
          expect(record.workingChangeScope!.sourceTurnId, 'fixture-turn');
        }
        final write = records.values.singleWhere((r) => r.toolName == 'Write');
        expect(write.workingChangeId, replacement.id);
        expect(replacement.oldText, 'first clue');
        expect(replacement.newText, 'third evidence');
        await overlay.rollbackChange(replacement.id);
        expect(
          (await content.getItemById(value['id'] as String))!.content,
          'first clue',
        );
        expect((result['completed_operations'] as List).length, 6);
        final failedAgent = FakeAgent.create(
          toolManager: dispatcher,
          responses: [
            FakeProviderClientResponse.toolCalls([
              ToolCall(
                callId: 'failed-parent',
                toolName: 'Codemode',
                arguments: {
                  'code':
                      "await tools.Write({path:'skills/${value['id']}/content',value:'committed before script failure'}); throw new Error('stop');",
                },
              ),
            ]),
            FakeProviderClientResponse.text('done'),
          ],
        );
        dispatcher.agent = failedAgent;
        final failedEvents = await failedAgent
            .process(
              'fixture',
              toolExecutionContext: ToolExecutionContext(
                sessionId: 'fixture-session',
                sourceSessionId: 'fixture-session',
                sourceTurnId: 'failed-turn',
              ),
            )
            .toList();
        final failedResult =
            failedEvents.whereType<AgentToolCallResult>().single.output as Map;
        expect(failedResult['ok'], isFalse);
        final retained = dispatcher.records['failed-parent']!.values
            .where((r) => r.workingChangeId != null)
            .last;
        final committed = await overlay.getWorkingChangeById(
          retained.workingChangeId!,
        );
        expect(committed!.newText, 'committed before script failure');
        expect(retained.workingChangeScope!.sourceTurnId, 'failed-turn');
        expect(
          (failedResult['completed_operations'] as List)
              .single['working_change_id'],
          committed.id,
        );
      } finally {
        tools.dispose();
        dispatcher.scheduler.dispose();
        await db.close();
        await app.close();
      }
    });
  });
}

class _Dispatcher implements AgentToolDispatcher {
  _Dispatcher(this.tools);
  final AiToolManager tools;
  final scheduler = CodemodeScheduler(maxActive: 2);
  final records = <String, Map<String, AiNestedToolCall>>{};
  late Agent agent;
  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) {
    if (name == 'Codemode') {
      final parentRecords = records[callId!] = {};
      return CodemodeOrchestrator().execute(
        input: input,
        context: context!,
        parentToolCallId: callId,
        tools: tools,
        runTool: (call, context) => agent.runToolCall(call, context: context),
        onRecord: (record) => parentRecords[record.callId] = record,
        scheduler: scheduler,
        isAllowed: () => true,
        allowedToolNames: tools.allToolNames,
      );
    }
    return tools.executeTool(
      name: name,
      input: input,
      callId: callId,
      emitEvents: emitEvents,
      context: context,
    );
  }

  @override
  List<String> allToolNames() => [...tools.allToolNames(), 'Codemode'];
  @override
  List<ToolDef> allToolDefs() => [...tools.allToolDefs(), codemodeToolDef];
  @override
  List<ToolDef> toolDefsForNames(List<String> names) =>
      allToolDefs().where((tool) => names.contains(tool.name)).toList();
}
