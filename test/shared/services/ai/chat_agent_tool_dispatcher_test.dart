// 职责: 验证主聊天子 agent 工具的同步兼容、后台接管、控制竞态与会话权限。
// 关联文件:
//   lib/shared/services/ai/chat_agent_tool_dispatcher.dart
//   lib/shared/services/ai/agent_message_mapping.dart
//   lib/shared/providers/spawn_agent_run_providers.dart
//   test/helpers/spawn_agent_runtime_fixture.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/providers/spawn_agent_run_providers.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/chat_agent_tool_dispatcher.dart';
import 'package:reveric/shared/services/ai/spawn_agent_handler.dart';
import 'package:reveric/shared/services/ai/tools.dart';

import '../../../helpers/spawn_agent_runtime_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SpawnAgentRuntimeFixture fixture;
  late SpawnAgentSessionRuns runs;
  late SpawnAgentSessionState state;
  late FakeAgentToolDispatcher inner;
  final startedRuns = <SpawnAgentRun>[];

  setUp(() async {
    fixture = SpawnAgentRuntimeFixture();
    await fixture.initialize();
    state = const SpawnAgentSessionState();
    startedRuns.clear();
    inner = FakeAgentToolDispatcher.withResults(
      results: {
        'Read': {'ok': true, 'content': 'existing tool'},
      },
    );
    runs = SpawnAgentSessionRuns(
      parentSessionId: 'parent',
      onChanged: (value) => state = value,
      onActivityStarted: startedRuns.add,
      onActivity: (_, _) {},
      onActivityFinished: (_) {},
    );
  });

  tearDown(() async {
    await runs.stopAll(source: 'test_cleanup');
    runs.dispose();
    await fixture.dispose();
  });

  ToolExecutionContext context({String sessionId = 'parent'}) =>
      ToolExecutionContext(
        sessionId: sessionId,
        sourceSessionId: 'parent',
        sourceTurnId: 'turn',
      );

  ChatAgentToolDispatcher dispatcher(ControlledSubAgent child) =>
      ChatAgentToolDispatcher(
        inner: inner,
        subAgents: runs,
        resumeSubAgent: (sessionId, message, callId, context) => runs.resume(
          handler: child.handler,
          sessionId: sessionId,
          message: message,
          callId: callId,
          context: context,
        ),
        startSubAgent: (input, callId, context, {required background}) =>
            runs.start(
              handler: child.handler,
              input: input,
              callId: callId,
              context: context,
              background: background,
            ),
      );

  Future<Map<String, dynamic>> spawn(
    ChatAgentToolDispatcher tools, {
    bool? background,
    String? sessionId,
    String callId = 'spawn',
  }) => tools.executeTool(
    name: spawnAgentToolName,
    input: {
      'agent': 'Writer',
      'name': 'Author',
      'task': 'Write the chapter.',
      'background': ?background,
      'session_id': ?sessionId,
    },
    callId: callId,
    context: context(),
  );

  test('background=false waits for final output without a notice', () async {
    final child = fixture.child();
    final tools = dispatcher(child);
    var returned = false;
    final result = spawn(tools, background: false)
      ..then((_) => returned = true);
    await child.requestEntered.future;
    expect(returned, isFalse);
    expect(state.runs.single.background, isFalse);
    child.finish('Final chapter');
    final completed = await result;
    expect(completed['output'], 'Final chapter');
    expect(completed['hint'], contains('SendAgentMessage'));
    expect(completed['hint'], contains('session_id'));
    expect(completed['context'], isA<Map>());
    await runs.waitForRun(startedRuns.single.runId);
    expect(state.pending, isEmpty);
    expect(child.releases, 1);
  });

  test(
    'Send resumes a completed foreground session in the background with its history',
    () async {
      final first = fixture.child();
      final result = spawn(dispatcher(first), background: false);
      await first.requestEntered.future;
      first.finish('Original chapter');
      final completed = await result;
      await runs.waitForRun(startedRuns.single.runId);
      final next = fixture.child();
      final resumed = await dispatcher(next).executeTool(
        name: sendAgentMessageToolName,
        input: {
          'session_id': completed['session_id'],
          'message': 'Correct the ending.',
        },
        callId: 'followup',
        context: context(),
      );
      expect(resumed['ok'], isTrue, reason: '$resumed');
      expect(resumed['accepted'], isTrue);
      expect(resumed['session_id'], completed['session_id']);
      expect(state.runs.single.background, isTrue);
      expect(state.runs.single.name, 'Author');
      expect(startedRuns.last.runId, isNot(startedRuns.first.runId));
      await next.requestEntered.future;
      expect(
        next.client.capturedStreamRequests.single.messages.map(
          (m) => m.content,
        ),
        containsAllInOrder([
          'Write the chapter.',
          'Original chapter',
          'Correct the ending.',
        ]),
      );
      next.finish('Corrected chapter');
      await runs.waitForRun(startedRuns.last.runId);
      expect(state.pending.single.result['output'], 'Corrected chapter');
      expect(state.pending.single.result['context'], isA<Map>());
      expect(state.pending.single.reminder, contains('Context:'));
    },
  );

  for (final background in [null, true]) {
    test(
      'background=$background waits for real startup and returns run identity with messaging guidance',
      () async {
        final child = fixture.child(blockInitialization: true);
        final tools = dispatcher(child);
        var returned = false;
        final result = spawn(tools, background: background)
          ..then((_) => returned = true);
        await child.initializationEntered.future;
        expect(returned, isFalse);
        expect(state.runs.single.status, SpawnAgentRunStatus.initializing);
        child.initializationRelease.complete();
        final started = await result;
        expect(started, {
          'ok': true,
          'status': 'running',
          'session_id': startedRuns.single.subSessionId,
          'run_id': startedRuns.single.runId,
          'hint':
              '子 agent 正在后台执行。如需在执行期间追加要求，使用 SendAgentMessage，沿用此 session_id。完成或失败后会自动通知。需要结果才能继续的步骤，请等待完成通知。',
        });
        expect(state.runs.single.background, isTrue);
        expect(child.releases, 0);
        child.finish('Saved chapter');
        await runs.waitForRun(started['run_id'] as String);
        expect(state.pending, hasLength(1));
        expect(state.pending.single.run.runId, started['run_id']);
        expect(state.pending.single.result['output'], 'Saved chapter');
        expect(
          state.pending.single.reminder,
          contains('type="subagent_completed"'),
        );
        expect(state.pending.single.reminder, contains('SendAgentMessage'));
        expect(state.pending.single.reminder, contains('沿用此 session_id'));
        expect(child.releases, 1);
        expect(inner.capturedCalls, isEmpty);
      },
    );
  }

  test(
    'parent finishes its reply while child runs and receives only one Spawn tool result',
    () async {
      final child = fixture.child();
      final tools = dispatcher(child);
      final parentClient = FakeProviderClient(
        responses: const [
          FakeProviderClientResponse.toolCalls([
            ToolCall(
              callId: 'spawn',
              toolName: spawnAgentToolName,
              arguments: {
                'agent': 'Writer',
                'name': 'Author',
                'task': 'Write chapter one.',
              },
            ),
          ]),
          FakeProviderClientResponse.text('Let us discuss chapter two.'),
        ],
      );
      final parent = FakeAgent.create(
        client: parentClient,
        toolManager: tools,
        allowedTools: [spawnAgentToolName],
      );
      await parent
          .process('Write and discuss', toolExecutionContext: context())
          .toList();
      expect(state.runs.single.status, SpawnAgentRunStatus.running);
      expect(child.releases, 0);
      final result = parentClient.capturedStreamRequests.last.messages
          .expand((message) => message.blocks)
          .whereType<ToolResultBlock>()
          .single;
      expect(result.toolCallId, 'spawn');
      expect(
        (result.content.single as TextBlock).text,
        contains('"status":"running"'),
      );
      child.finish('Chapter one is saved.');
      await runs.waitForRun(startedRuns.single.runId);
      expect(state.pending.single.result['output'], 'Chapter one is saved.');
      expect(parentClient.capturedStreamRequests, hasLength(2));
      expect(
        parent.contextManager.messages
            .expand((message) => message.blocks)
            .whereType<ToolResultBlock>(),
        hasLength(1),
      );
    },
  );

  test(
    'initialization failure returns an error without running or a notice',
    () async {
      final child = fixture.child(failInitialization: true);
      final result = await spawn(dispatcher(child), background: true);
      expect(result['ok'], isFalse);
      expect(result['error_code'], 'unavailable');
      expect(result.containsKey('status'), isFalse);
      expect(result.containsKey('hint'), isFalse);
      await runs.waitForRun(startedRuns.single.runId);
      expect(state.pending, isEmpty);
      expect(child.client.capturedStreamRequests, isEmpty);
    },
  );

  test(
    'accepted instruction reaches the next model request before completion',
    () async {
      final child = fixture.child();
      final tools = dispatcher(child);
      final started = await spawn(tools, background: true);
      await child.requestEntered.future;
      final result = await tools.executeTool(
        name: sendAgentMessageToolName,
        input: {
          'session_id': started['session_id'],
          'message': 'Keep the character alive.',
        },
        context: context(),
      );
      expect(result['ok'], isTrue);
      expect(result['accepted'], isTrue);
      expect(result['status'], 'accepted');
      expect(result.containsKey('output'), isFalse);
      expect(child.client.capturedStreamRequests, hasLength(1));
      child.finish();
      await runs.waitForRun(started['run_id'] as String);
      expect(child.client.capturedStreamRequests, hasLength(2));
      expect(
        child.client.capturedStreamRequests.last.messages.any(
          (message) => message.content == 'Keep the character alive.',
        ),
        isTrue,
      );
    },
  );

  test(
    'restored background acknowledgement can address the active child',
    () async {
      final child = fixture.child();
      final tools = dispatcher(child);
      final started = await spawn(tools, background: true);
      await child.requestEntered.future;
      final history = convertAiMessageToAgentMessagesForModel(
        AiMessage.assistant(
          id: 'parent_spawn',
          content: '',
          blocks: [
            AiToolCallBlock(
              id: 'spawn_block',
              callId: 'spawn',
              toolName: spawnAgentToolName,
              arguments: const {'background': true},
              status: AiToolCallStatus.success,
              result: started,
            ),
          ],
        ),
      );
      final resultBlock = history
          .expand((message) => message.blocks)
          .whereType<ToolResultBlock>()
          .single;
      final replay =
          jsonDecode((resultBlock.content.single as TextBlock).text) as Map;
      final sent = await tools.executeTool(
        name: sendAgentMessageToolName,
        input: {
          'session_id': replay['session_id'],
          'message': 'Review the chapter outline too.',
        },
        context: context(),
      );
      child.finish();
      await runs.waitForRun(started['run_id'] as String);
      expect(sent['accepted'], isTrue, reason: '$sent');
      expect(sent['run_id'], started['run_id']);
      expect(
        child.client.capturedStreamRequests.last.messages.any(
          (message) => message.content == 'Review the chapter outline too.',
        ),
        isTrue,
      );
    },
  );

  test(
    'running foreground child accepts steering without changing its mode',
    () async {
      final child = fixture.child();
      final tools = dispatcher(child);
      final completion = spawn(tools, background: false);
      await child.requestEntered.future;
      final run = startedRuns.single;
      final sent = await tools.executeTool(
        name: sendAgentMessageToolName,
        input: {'session_id': run.subSessionId, 'message': 'Keep the key.'},
        context: context(),
      );
      expect(sent['accepted'], isTrue);
      expect(sent['run_id'], run.runId);
      expect(state.runs.single.background, isFalse);
      child.finish();
      await completion;
      await runs.waitForRun(run.runId);
      expect(
        child.client.capturedStreamRequests.last.messages.map((m) => m.content),
        contains('Keep the key.'),
      );
      expect(state.pending, isEmpty);
    },
  );

  test('stopping rejects messages and cannot create a continuation', () async {
    final child = fixture.child();
    final tools = dispatcher(child);
    final started = await spawn(tools);
    runs.cancelRun(started['run_id'] as String);
    final result = await tools.executeTool(
      name: sendAgentMessageToolName,
      input: {'session_id': started['session_id'], 'message': 'Continue'},
      callId: 'late',
      context: context(),
    );
    expect(result['accepted'], isFalse);
    expect(result['error_code'], 'failed_precondition');
    expect(startedRuns, hasLength(1));
    child.finish();
    await runs.waitForRun(startedRuns.single.runId);
  });

  for (final operation in ['rollback', 'stop_all']) {
    test('$operation invalidates an in-flight continuation lookup', () async {
      final first = fixture.child();
      final started = await spawn(dispatcher(first));
      first.finish();
      await runs.waitForRun(startedRuns.single.runId);
      final next = fixture.child();
      final pending = dispatcher(next).executeTool(
        name: sendAgentMessageToolName,
        input: {'session_id': started['session_id'], 'message': 'Continue'},
        callId: 'next',
        context: context(),
      );
      if (operation == 'rollback') {
        runs.beginSessionMutation();
        runs.endSessionMutation();
      } else {
        await runs.stopAll(source: 'test');
      }
      final result = await pending;
      expect(result['error_code'], 'failed_precondition');
      expect(result['accepted'], isFalse);
      expect(next.initializationEntered.isCompleted, isFalse);
      expect(startedRuns, hasLength(1));
    });
  }

  test('concurrent followups never start two runs for one session', () async {
    final first = fixture.child();
    final started = await spawn(dispatcher(first));
    first.finish();
    await runs.waitForRun(startedRuns.single.runId);
    final next = fixture.child();
    final tools = dispatcher(next);
    final results = await Future.wait([
      for (final id in ['followup_1', 'followup_2'])
        tools.executeTool(
          name: sendAgentMessageToolName,
          input: {'session_id': started['session_id'], 'message': id},
          callId: id,
          context: context(),
        ),
    ]);
    expect(results.where((r) => r['accepted'] == true), hasLength(1));
    expect(
      results.where((r) => r['error_code'] == 'failed_precondition'),
      hasLength(1),
    );
    expect(state.runs, hasLength(1));
    next.finish();
    await runs.waitForRun(startedRuns.last.runId);
  });

  test(
    'message at persistence boundary is rejected and may resume after completion',
    () async {
      final child = fixture.child(blockSave: true);
      final tools = dispatcher(child);
      final started = await spawn(tools, background: true);
      child.finish();
      await child.saveEntered.future;
      final rejected = await tools.executeTool(
        name: sendAgentMessageToolName,
        input: {'session_id': started['session_id'], 'message': 'Too late'},
        context: context(),
      );
      expect(rejected['ok'], isFalse);
      expect(rejected['accepted'], isFalse);
      expect(rejected['error_code'], 'failed_precondition');
      child.saveRelease.complete();
      await runs.waitForRun(started['run_id'] as String);
      final next = fixture.child();
      final ended = await dispatcher(next).executeTool(
        name: sendAgentMessageToolName,
        input: {'session_id': started['session_id'], 'message': 'Ended'},
        callId: 'after_save',
        context: context(),
      );
      expect(ended['ok'], isTrue);
      expect(ended['session_id'], started['session_id']);
      next.finish();
      await runs.waitForRun(ended['run_id'] as String);
      expect(state.pending, hasLength(2));
    },
  );

  test(
    'stop confirms request while persistence finishes and revokes completion',
    () async {
      final child = fixture.child(blockSave: true);
      final tools = dispatcher(child);
      final started = await spawn(tools, background: true);
      await child.requestEntered.future;
      final stopped = await tools.executeTool(
        name: stopAgentToolName,
        input: {'session_id': started['session_id']},
        context: context(),
      );
      expect(stopped['ok'], isTrue);
      expect(stopped['accepted'], isTrue);
      expect(stopped['status'], 'stopping');
      expect(state.runs.single.status, SpawnAgentRunStatus.stopping);
      child.finish();
      await child.saveEntered.future;
      expect(state.runs.single.status, SpawnAgentRunStatus.stopping);
      expect(child.releases, 0);
      child.saveRelease.complete();
      await runs.waitForRun(started['run_id'] as String);
      expect(startedRuns.single.status, SpawnAgentRunStatus.cancelled);
      expect(state.runs, isEmpty);
      expect(state.pending, isEmpty);
      expect(child.releases, 1);
    },
  );

  test(
    'foreign sessions and child callers cannot control or spawn runs',
    () async {
      final child = fixture.child();
      final tools = dispatcher(child);
      final started = await spawn(tools, background: true);
      for (final name in [
        spawnAgentToolName,
        sendAgentMessageToolName,
        stopAgentToolName,
      ]) {
        for (final caller in [
          'other_parent',
          started['session_id'] as String,
        ]) {
          final result = await tools.executeTool(
            name: name,
            input: {
              'session_id': started['session_id'],
              'message': 'Forbidden',
            },
            context: context(sessionId: caller),
          );
          expect(result['error_code'], 'permission_denied');
        }
      }
      for (final name in [sendAgentMessageToolName, stopAgentToolName]) {
        final result = await tools.executeTool(
          name: name,
          input: {'session_id': 'some_other_session', 'message': 'Foreign'},
          context: context(),
        );
        expect(result['error_code'], 'not_found');
      }
      expect(startedRuns, hasLength(1));
      expect(child.client.cancelCallCount, 0);
      child.finish();
      await runs.waitForRun(started['run_id'] as String);
      expect(state.pending, hasLength(1));
    },
  );

  test(
    'Spawn rejects legacy reuse and Send continues the original session',
    () async {
      final child = fixture.child();
      final tools = dispatcher(child);
      final started = await spawn(tools, background: true);
      final duplicate = await spawn(
        tools,
        background: true,
        sessionId: started['session_id'] as String,
        callId: 'duplicate',
      );
      expect(duplicate['error_code'], 'invalid_argument');
      child.finish();
      await runs.waitForRun(started['run_id'] as String);
      final nextChild = fixture.child();
      final reused = await dispatcher(nextChild).executeTool(
        name: sendAgentMessageToolName,
        input: {
          'session_id': started['session_id'],
          'message': 'Revise the chapter.',
        },
        callId: 'next',
        context: context(),
      );
      expect(reused['session_id'], started['session_id']);
      expect(reused['run_id'], isNot(started['run_id']));
      nextChild.finish();
      await runs.waitForRun(reused['run_id'] as String);
      expect(state.pending, hasLength(2));
    },
  );

  test(
    'invalid parameters never start or control a run; other tools retain routing',
    () async {
      final tools = dispatcher(fixture.child());
      final invalid = await tools.executeTool(
        name: spawnAgentToolName,
        input: {'background': 'true'},
        context: context(),
      );
      expect(invalid['error_code'], 'invalid_argument');
      for (final name in [sendAgentMessageToolName, stopAgentToolName]) {
        final invalid = await tools.executeTool(
          name: name,
          input: {'session_id': 123, 'message': ''},
          context: context(),
        );
        expect(invalid['error_code'], 'invalid_argument');
      }
      expect(startedRuns, isEmpty);
      final caller = context();
      expect(
        await tools.executeTool(
          name: 'Read',
          input: {'path': '/chapters'},
          callId: 'read',
          emitEvents: false,
          context: caller,
        ),
        {'ok': true, 'content': 'existing tool'},
      );
      expect(inner.capturedCalls.single.context, same(caller));
      expect(inner.capturedCalls.single.emitEvents, isFalse);
      expect(tools.allToolNames(), inner.allToolNames());
      expect(tools.allToolDefs(), inner.allToolDefs());
      expect(
        tools.toolDefsForNames(['Read']),
        inner.toolDefsForNames(['Read']),
      );
    },
  );
  test(
    'Codemode registration follows chat-mode permission and rejects nesting',
    () async {
      final mainContext = ToolExecutionContext();
      var allowed = true;
      var calls = 0;
      final tools = ChatAgentToolDispatcher(
        inner: inner,
        subAgents: runs,
        resumeSubAgent: (sessionId, message, callId, context) =>
            throw StateError('unexpected subagent'),
        startSubAgent: (input, callId, context, {required background}) =>
            throw StateError('unexpected subagent'),
        codemodeAllowed: () => allowed,
        runCodemode: (input, callId, context) async {
          calls++;
          return {'ok': true};
        },
      );
      expect(tools.allToolNames(), contains('Codemode'));
      expect(
        tools.toolDefsForNames(['Codemode']).single.inputSchema['required'],
        ['code'],
      );
      expect(
        (await tools.executeTool(
          name: 'Codemode',
          input: {'code': 'return 1;'},
          callId: 'codemode',
          context: mainContext,
        ))['ok'],
        isTrue,
      );
      final nested = await tools.executeTool(
        name: 'Codemode',
        input: {'code': 'return 1;'},
        callId: 'nested',
        context: ToolExecutionContext(parentToolCallId: 'parent'),
      );
      expect(nested['error_code'], 'codemode_tool_forbidden');
      allowed = false;
      expect(tools.allToolNames(), isNot(contains('Codemode')));
      expect(tools.toolDefsForNames(['Codemode']), isEmpty);
      expect(
        (await tools.executeTool(
          name: 'Codemode',
          input: {'code': 'return 1;'},
          callId: 'codemode',
          context: mainContext,
        ))['error_code'],
        'codemode_tool_forbidden',
      );
      expect(calls, 1);
    },
  );
}
