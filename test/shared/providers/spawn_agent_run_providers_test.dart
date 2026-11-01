// 职责: 验证会话子运行的身份隔离、取消与通知边界，以及活动事件归约和清理。
// 关联文件:
//   lib/shared/providers/spawn_agent_run_providers.dart
//   lib/shared/agent/agent_run_state.dart
//   lib/shared/providers/ai_providers.dart
//   test/helpers/spawn_agent_runtime_fixture.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/providers/spawn_agent_run_providers.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/services/ai/spawn_agent_handler.dart';
import 'package:reveric/shared/services/ai/tools.dart';

import '../../helpers/spawn_agent_runtime_fixture.dart';

// 子会话消息要等 SpawnAgent 跑完才落库，运行中的第二行只能靠这份内存状态。
// 锁定三个契约：推理增量按段合并、工具事件按 callId 合并且立即可见、
// SpawnAgent 结束后状态归零交回 tool result。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const window = Duration(milliseconds: 100);
  const callId = 'spawn_call_1';

  test('merges consecutive thinking deltas into one block', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final notifier = container.read(
        spawnAgentActiveRunProvider(callId).notifier,
      );

      notifier.apply(const AgentThinkingDelta('先核对'));
      notifier.apply(const AgentThinkingDelta('人物设定'));
      async.elapse(window * 2);

      final run = container.read(spawnAgentActiveRunProvider(callId));
      expect(run, isNotNull);
      expect(run!.blocks.single, isA<AiThinkingBlock>());
      expect((run.blocks.single as AiThinkingBlock).text, '先核对人物设定');

      container.dispose();
    });
  });

  test('coalesces thinking notifications but publishes the last delta', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final notifier = container.read(
        spawnAgentActiveRunProvider(callId).notifier,
      );
      var notifications = 0;
      container.listen(
        spawnAgentActiveRunProvider(callId),
        (_, _) => notifications++,
      );

      for (var i = 0; i < 50; i++) {
        notifier.apply(AgentThinkingDelta('d$i '));
      }
      // 窗口内只有首个 delta 的通知，不会每 chunk 重建一次卡片行。
      expect(notifications, 1);

      // 窗口结束后补发，末次内容不丢。
      async.elapse(window + const Duration(milliseconds: 20));
      expect(notifications, 2);
      final run = container.read(spawnAgentActiveRunProvider(callId));
      expect(run!.accumulatedThinking, endsWith('d49 '));

      // 无新增量后不再产生空通知。
      async.elapse(window * 3);
      expect(notifications, 2);

      container.dispose();
    });
  });

  test('merges tool start and result by callId without waiting a window', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final notifier = container.read(
        spawnAgentActiveRunProvider(callId).notifier,
      );

      notifier.apply(
        const AgentToolCallStart(
          callId: 'nested_1',
          toolName: 'Read',
          arguments: {'path': '/chapters/chapter_12/content'},
        ),
      );
      // 工具事件低频且是第二行的主要信息，不经节流窗口即可读到。
      final running = container.read(spawnAgentActiveRunProvider(callId))!;
      final startBlock = running.blocks.single as AiToolCallBlock;
      expect(startBlock.toolName, 'Read');
      expect(startBlock.status, AiToolCallStatus.running);
      expect(startBlock.arguments['path'], '/chapters/chapter_12/content');

      notifier.apply(
        const AgentToolCallResult(callId: 'nested_1', toolName: 'Read'),
      );
      final settled = container.read(spawnAgentActiveRunProvider(callId))!;
      final resultBlock = settled.blocks.single as AiToolCallBlock;
      expect(resultBlock.status, AiToolCallStatus.success);
      // Result 事件不带 arguments，合并时必须保留 Start 的目标，第二行才有得显示。
      expect(resultBlock.arguments['path'], '/chapters/chapter_12/content');

      async.elapse(window * 2);
      container.dispose();
    });
  });

  test('clear drops the live state so the tool result takes over', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final notifier = container.read(
        spawnAgentActiveRunProvider(callId).notifier,
      );
      // 保持订阅，确保 clear 的是同一个 notifier 实例而不是被回收后新建的。
      container.listen(spawnAgentActiveRunProvider(callId), (_, _) {});

      notifier.apply(const AgentThinkingDelta('思考中'));
      async.elapse(window * 2);
      expect(container.read(spawnAgentActiveRunProvider(callId)), isNotNull);

      notifier.clear();
      expect(container.read(spawnAgentActiveRunProvider(callId)), isNull);

      // clear 之后遗留的窗口 timer 不得再把旧内容推回来。
      async.elapse(window * 3);
      expect(container.read(spawnAgentActiveRunProvider(callId)), isNull);

      container.dispose();
    });
  });

  test('keeps runs of different call ids independent', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      container
          .read(spawnAgentActiveRunProvider('spawn_a').notifier)
          .apply(const AgentThinkingDelta('A 在推理'));
      container
          .read(spawnAgentActiveRunProvider('spawn_b').notifier)
          .apply(const AgentThinkingDelta('B 在推理'));
      async.elapse(window * 2);

      expect(
        container
            .read(spawnAgentActiveRunProvider('spawn_a'))!
            .accumulatedThinking,
        'A 在推理',
      );
      expect(
        container
            .read(spawnAgentActiveRunProvider('spawn_b'))!
            .accumulatedThinking,
        'B 在推理',
      );

      container.dispose();
    });
  });

  test('old run events and cleanup cannot overwrite a new card run', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final activity = container.read(
      spawnAgentActiveRunProvider(callId).notifier,
    );
    activity.begin('R1');
    activity.apply(const AgentTextDelta('old'), runId: 'R1');
    activity.begin('R2');
    activity.apply(const AgentTextDelta('new'), runId: 'R2');
    activity.apply(const AgentTextDelta('late'), runId: 'R1');
    activity.clear(runId: 'R1');
    expect(
      container.read(spawnAgentActiveRunProvider(callId))!.accumulatedText,
      'new',
    );
    activity.clear(runId: 'R2');
  });

  group('session owned runs', () {
    late SpawnAgentRuntimeFixture fixture;
    late ProviderContainer container;
    late AiChatRuntime runtime;

    setUp(() async {
      fixture = SpawnAgentRuntimeFixture();
      await fixture.initialize();
      container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWithValue(AiSettings.defaults()),
        ],
      );
      container.listen(aiChatRuntimeProvider('parent'), (_, _) {});
      runtime = container.read(aiChatRuntimeProvider('parent').notifier);
    });

    tearDown(() async {
      container.dispose();
      await fixture.dispose();
    });

    SpawnAgentRun start(
      ControlledSubAgent child, {
      String turn = 'turn_1',
      String call = 'call_1',
      String? session,
      bool background = true,
    }) => runtime.startSubAgent(
      handler: child.handler,
      input: {'agent': 'Writer', 'name': 'Writer One', 'task': 'Write a scene'},
      resumeSessionId: session,
      callId: call,
      context: ToolExecutionContext(
        sessionId: 'parent',
        sourceSessionId: 'parent',
        sourceTurnId: turn,
      ),
      background: background,
    );

    SpawnAgentSessionState state() =>
        container.read(aiChatRuntimeProvider('parent')).subAgents;

    test(
      'accepted instruction reaches the next request and finished run rejects it',
      () async {
        final child = fixture.child();
        final run = start(child);
        await child.requestEntered.future;
        expect(
          runtime.subAgents.sendMessage(run.runId, 'Keep the character alive.'),
          isTrue,
        );
        child.finish();
        await runtime.subAgents.waitForRun(run.runId);
        expect(child.client.capturedStreamRequests, hasLength(2));
        final saved = await fixture.persistence.loadSessionMessages(
          sessionId: run.subSessionId,
          novelDatabase: fixture.novelDb,
        );
        expect(
          saved.messages.map((message) => message.content),
          contains('Keep the character alive.'),
        );
        expect(runtime.subAgents.sendMessage(run.runId, 'Too late'), isFalse);
      },
    );

    test('rollback revokes queued outcomes only for truncated turns', () async {
      final kept = fixture.child();
      final r1 = start(kept, turn: 'kept');
      final removed = fixture.child();
      final r2 = start(removed, call: 'call_2', turn: 'removed');
      await kept.requestEntered.future;
      await removed.requestEntered.future;
      removed.finish('removed');
      await runtime.subAgents.waitForRun(r2.runId);
      final cached = state().pending.single;
      expect(runtime.tryBeginSessionMutation(), isTrue);
      // 被保留的 run 在守卫期间继续执行并入队，只有消费受阻。
      kept.finish('kept');
      await runtime.subAgents.waitForRun(r1.runId);
      await runtime.subAgents.stopTurns({'removed'});
      expect(state().pending.single.run.runId, r1.runId);
      runtime.endSessionMutation();
      expect(runtime.subAgents.takeCompletion(cached.run.runId), isNull);
      expect(runtime.subAgents.takeCompletion(r1.runId), isNotNull);
    });

    test(
      'parent cancellation propagates only to synchronous children',
      () async {
        final parent = AgentCancellationController();
        final children = [fixture.child(), fixture.child()];
        final runs = [
          for (var i = 0; i < 2; i++)
            runtime.startSubAgent(
              handler: children[i].handler,
              input: const {
                'agent': 'Writer',
                'name': 'Writer One',
                'task': 'Write',
              },
              callId: 'cancel_$i',
              context: ToolExecutionContext(
                sessionId: 'parent',
                sourceSessionId: 'parent',
                sourceTurnId: 'turn_1',
                cancellationToken: parent.token,
              ),
              background: i == 1,
            ),
        ];
        for (final child in children) {
          await child.requestEntered.future;
        }
        parent.cancel();
        expect(runs[0].status, SpawnAgentRunStatus.stopping);
        expect(runs[1].status, SpawnAgentRunStatus.running);
        for (final child in children) {
          child.finish();
        }
        for (final run in runs) {
          await runtime.subAgents.waitForRun(run.runId);
        }
        expect((await runs[0].result)['cancelled'], isTrue);
        expect(state().pending.single.run.runId, runs[1].runId);
      },
    );

    test(
      'initializing session is reserved and single stop waits for cleanup',
      () async {
        final child = fixture.child(blockInitialization: true);
        final run = start(child);
        await child.initializationEntered.future;
        expect(state().runs.single.status, SpawnAgentRunStatus.initializing);
        expect(
          () => start(child, call: 'duplicate', session: run.subSessionId),
          throwsStateError,
        );

        final other = fixture.child();
        final otherRun = start(other, call: 'other');
        await other.requestEntered.future;
        expect(runtime.subAgents.cancelRun(run.runId), isTrue);
        var settled = false;
        final wait = runtime.subAgents
            .waitForRun(run.runId)
            .then((_) => settled = true);
        await container.pump();
        expect(settled, isFalse);
        expect(state().runs.first.status, SpawnAgentRunStatus.stopping);
        child.initializationRelease.complete();
        await wait;
        expect(child.client.capturedStreamRequests, isEmpty);
        expect(child.releases, 1);
        expect(state().runs.single.runId, otherRun.runId);
        other.finish();
        await runtime.subAgents.waitForRun(otherRun.runId);
        expect(state().pending.single.run.runId, otherRun.runId);
      },
    );

    test(
      'completion has independent identity, is consumed once, and sync has no notice',
      () async {
        final child = fixture.child();
        final run = start(child);
        await child.requestEntered.future;
        child.finish('first output');
        await runtime.subAgents.waitForRun(run.runId);
        final notice = state().pending.single;
        expect(notice.parentSessionId, 'parent');
        expect(notice.run.sourceTurnId, 'turn_1');
        expect(notice.messageId, isNot('turn_1'));
        expect(notice.result['output'], 'first output');
        expect(runtime.subAgents.takeCompletion(run.runId), same(notice));
        expect(runtime.subAgents.takeCompletion(run.runId), isNull);

        final sync = fixture.child();
        final syncRun = start(
          sync,
          call: 'sync',
          background: false,
          session: run.subSessionId,
        );
        await sync.requestEntered.future;
        sync.finish('sync output');
        expect((await syncRun.result)['output'], 'sync output');
        await runtime.subAgents.waitForRun(syncRun.runId);
        expect(syncRun.runId, isNot(run.runId));
        expect(state().pending, isEmpty);
      },
    );

    test(
      'older completion survives session reuse and old controls cannot stop new run',
      () async {
        final first = fixture.child();
        final r1 = start(first);
        await first.requestEntered.future;
        first.finish('R1');
        await runtime.subAgents.waitForRun(r1.runId);
        final second = fixture.child();
        final r2 = start(second, session: r1.subSessionId, call: 'call_2');
        await second.requestEntered.future;
        final old = runtime.subAgents.takeCompletion(r1.runId);
        expect(old!.result['output'], 'R1');
        expect(runtime.subAgents.cancelRun(r1.runId), isFalse);
        expect(runtime.subAgents.sendMessage(r1.runId, 'late'), isFalse);
        expect(runtime.subAgents.currentRunId(r1.subSessionId), r2.runId);
        expect(r2.status, SpawnAgentRunStatus.running);
        second.finish('R2');
        await runtime.subAgents.waitForRun(r2.runId);
        expect(state().pending.single.run.runId, r2.runId);
      },
    );

    test(
      'Stop All revokes completed and initializing runs before waiting',
      () async {
        final completed = fixture.child();
        final r1 = start(completed);
        await completed.requestEntered.future;
        completed.finish();
        await runtime.subAgents.waitForRun(r1.runId);
        final cached = state().pending.single;
        final initializing = fixture.child(blockInitialization: true);
        final r2 = start(initializing, call: 'call_2');
        await initializing.initializationEntered.future;
        final stopping = runtime.stopAll();
        expect(state().pending, isEmpty);
        expect(runtime.subAgents.takeCompletion(cached.run.runId), isNull);
        expect(() => start(initializing, call: 'new'), throwsStateError);
        expect(() => runtime.startRequest(), throwsStateError);
        initializing.initializationRelease.complete();
        await stopping;
        expect((await r2.result)['cancelled'], isTrue);
        expect(state().runs, isEmpty);
        expect(state().pending, isEmpty);
        expect(initializing.client.capturedStreamRequests, isEmpty);
      },
    );

    test(
      'rollback blocks initialization and delivery, retaining earlier turn results',
      () async {
        final older = fixture.child(blockInitialization: true);
        final r1 = start(older, turn: 'kept');
        final removed = fixture.child(blockInitialization: true);
        final r2 = start(removed, turn: 'removed', call: 'call_2');
        await older.initializationEntered.future;
        await removed.initializationEntered.future;
        expect(runtime.tryBeginSessionMutation(), isTrue);
        expect(() => start(older, call: 'blocked'), throwsStateError);
        final stopping = runtime.subAgents.stopTurns({'removed'});
        older.initializationRelease.complete();
        removed.initializationRelease.complete();
        await stopping;
        expect((await r2.result)['cancelled'], isTrue);
        expect(older.client.capturedStreamRequests, isEmpty);
        expect(state().runs.single.status, SpawnAgentRunStatus.initializing);
        runtime.endSessionMutation();
        await older.requestEntered.future;
        older.finish('preserved');
        await runtime.subAgents.waitForRun(r1.runId);
        final cached = state().pending.single;
        expect(runtime.tryBeginSessionMutation(), isTrue);
        expect(runtime.subAgents.takeCompletion(cached.run.runId), isNull);
        await runtime.subAgents.stopTurns({'removed'});
        expect(state().pending.single, same(cached));
        runtime.endSessionMutation();
        expect(runtime.subAgents.takeCompletion(r1.runId), same(cached));
        expect(runtime.subAgents.takeCompletion(r2.runId), isNull);
      },
    );

    test(
      'cancellation during persistence retains stopping until real finalization',
      () async {
        final child = fixture.child(blockSave: true);
        final run = start(child);
        await child.requestEntered.future;
        child.finish();
        await child.saveEntered.future;
        runtime.subAgents.cancelRun(run.runId);
        var ended = false;
        final stopped = runtime.subAgents
            .waitForRun(run.runId)
            .then((_) => ended = true);
        await container.pump();
        expect(ended, isFalse);
        expect(child.releases, 0);
        expect(state().runs.single.status, SpawnAgentRunStatus.stopping);
        child.saveRelease.complete();
        await stopped;
        expect(child.releases, 1);
        expect(state().pending, isEmpty);
        final persisted = await fixture.persistence.getSession(
          run.subSessionId,
        );
        expect(persisted!.metadata?['spawn_run_status'], 'cancelled');
      },
    );

    test(
      'failed child enqueues structured failure but failed startup does not notify',
      () async {
        final badInit = fixture.child(failInitialization: true);
        final failedStart = start(badInit);
        await runtime.subAgents.waitForRun(failedStart.runId);
        expect(await failedStart.started, isFalse);
        expect((await failedStart.result)['error_code'], 'unavailable');
        expect(state().pending, isEmpty);
        final child = fixture.child();
        final run = start(child, call: 'failed_run');
        await child.requestEntered.future;
        child.response.complete(
          FakeProviderClientResponse.events([
            StreamError('test request failure'),
          ]),
        );
        await runtime.subAgents.waitForRun(run.runId);
        expect(state().pending.single.result['ok'], isFalse);
        expect(state().pending.single.result['error_code'], isNotEmpty);
        expect(child.releases, 1);
      },
    );
  });
}
