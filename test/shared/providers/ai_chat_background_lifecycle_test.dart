// 职责: 验证子任务在无 UI 订阅、主请求停止或模型切换后仍按会话保活并正确收尾。
// 关联文件:
//   lib/shared/providers/ai_providers.dart
//   lib/shared/providers/spawn_agent_run_providers.dart
//   test/helpers/spawn_agent_runtime_fixture.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/providers/ai_mode_processing.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/ai/spawn_agent_handler.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/providers/spawn_agent_run_providers.dart';

import '../../helpers/spawn_agent_runtime_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'persisted hydration preserves a loaded session with a running tool',
    () {
      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWithValue(AiSettings.defaults()),
        ],
      );
      addTearDown(container.dispose);
      const sessionId = 'background_session';
      const callId = 'spawn_agent_call';
      final sessionProvider = aiChatSessionProvider(sessionId);
      final subscription = container.listen(sessionProvider, (_, _) {});
      addTearDown(subscription.close);
      final session = container.read(sessionProvider.notifier);

      session.loadSession(
        sessionId: sessionId,
        title: 'Persisted title',
        messages: [AiMessage.user(id: 'user_message', content: '开始')],
      );
      session.startStreamingMessage(messageId: 'running_assistant_message');
      session.upsertToolCallBlock(
        const AiToolCallBlock(
          id: 'spawn_agent_block',
          callId: callId,
          toolName: 'SpawnAgent',
          arguments: {'name': 'writer'},
          status: AiToolCallStatus.running,
        ),
      );

      // 模拟重进页面后从数据库读到的旧快照：它还没有后台中的 SpawnAgent。
      session.loadSessionIfUnloaded(
        sessionId: sessionId,
        title: 'Persisted title',
        messages: [AiMessage.user(id: 'user_message', content: '开始')],
      );

      final backgroundSession = container.read(sessionProvider);
      expect(backgroundSession.messages, hasLength(2));
      expect(
        backgroundSession.messages.last.blocks,
        contains(
          isA<AiToolCallBlock>()
              .having((block) => block.callId, 'callId', callId)
              .having(
                (block) => block.status,
                'status',
                AiToolCallStatus.running,
              ),
        ),
      );
    },
  );

  test('persisted hydration loads an unloaded session', () {
    final container = ProviderContainer(
      overrides: [aiSettingsProvider.overrideWithValue(AiSettings.defaults())],
    );
    addTearDown(container.dispose);
    const sessionId = 'unloaded_session';
    final sessionProvider = aiChatSessionProvider(sessionId);
    final subscription = container.listen(sessionProvider, (_, _) {});
    addTearDown(subscription.close);

    container
        .read(sessionProvider.notifier)
        .loadSessionIfUnloaded(
          sessionId: sessionId,
          title: 'Restored',
          messages: [AiMessage.user(id: 'persisted_user', content: '历史消息')],
        );

    final restored = container.read(sessionProvider);
    expect(restored.isLoaded, isTrue);
    expect(restored.messages.single.content, '历史消息');
  });

  group('child lifetime without UI watchers', () {
    late SpawnAgentRuntimeFixture fixture;
    late ProviderContainer container;
    final provider = aiChatRuntimeProvider('parent');

    setUp(() async {
      fixture = SpawnAgentRuntimeFixture();
      await fixture.initialize();
      container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWithValue(AiSettings.defaults()),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await fixture.dispose();
    });

    SpawnAgentRun start(
      AiChatRuntime runtime,
      ControlledSubAgent child, {
      bool background = true,
      String callId = 'child_call',
    }) => runtime.startSubAgent(
      handler: child.handler,
      input: const {'agent': 'Writer', 'name': 'Writer One', 'task': 'Write'},
      callId: callId,
      context: ToolExecutionContext(
        sessionId: child.handler.parentSessionId,
        sourceSessionId: child.handler.parentSessionId,
        sourceTurnId: 'turn_1',
      ),
      background: background,
    );

    test(
      'continuation lookup and execution retain runtime without UI watchers',
      () async {
        final first = fixture.child();
        final firstRun = start(
          container.read(provider.notifier),
          first,
          background: false,
        );
        await first.requestEntered.future;
        first.finish('Original text');
        await firstRun.result;
        await container.pump();
        final next = fixture.child(blockInitialization: true);
        final pending = container
            .read(provider.notifier)
            .resumeSubAgent(
              handler: next.handler,
              sessionId: firstRun.subSessionId,
              message: 'Revise the text.',
              callId: 'followup',
              context: ToolExecutionContext(
                sessionId: 'parent',
                sourceSessionId: 'parent',
                sourceTurnId: 'followup_turn',
              ),
            );
        await container.pump();
        final resumed = await pending;
        await next.initializationEntered.future;
        expect(container.exists(provider), isTrue);
        next.initializationRelease.complete();
        await next.requestEntered.future;
        next.finish('Revised text');
        expect((await resumed.result)['output'], 'Revised text');
        final runtime = container.read(provider.notifier);
        await runtime.subAgents.waitForRun(resumed.runId);
        expect(next.releases, 1);
        expect(
          runtime.subAgents.takeCompletion(resumed.runId)!.result['context'],
          isA<Map>(),
        );
        await container.pump();
        expect(container.exists(provider), isFalse);
      },
    );

    test(
      'processing includes children, pending completion and stopping cleanup',
      () async {
        final runtime = container.read(provider.notifier);
        final tracker = container.read(
          aiModeProcessingTrackerProvider.notifier,
        );
        tracker.setForegroundSession(
          mode: AiSessionMode.chat,
          sessionId: 'parent',
          foreground: true,
        );
        bool processing() => container.read(
          aiSessionProcessingProvider(
            mode: AiSessionMode.chat,
            sessionId: 'parent',
          ),
        );
        final parentRequest = runtime.startRequest();
        final child = fixture.child();
        final run = start(runtime, child);
        await child.requestEntered.future;
        runtime.markRequestIdle(parentRequest);
        expect(container.read(provider).isRequestInFlight, isFalse);
        expect(processing(), isTrue);
        child.finish();
        await runtime.subAgents.waitForRun(run.runId);
        expect(
          processing(),
          isTrue,
          reason: 'pending completion is still work',
        );
        runtime.subAgents.takeCompletion(run.runId);
        expect(processing(), isFalse);

        final stoppingChild = fixture.child(blockSave: true);
        final stoppingRun = start(runtime, stoppingChild, callId: 'stopping');
        await stoppingChild.requestEntered.future;
        final stopped = runtime.stopAll(source: AiChatCancelSource.exitPause);
        stoppingChild.finish();
        await stoppingChild.saveEntered.future;
        expect(
          processing(),
          isTrue,
          reason: 'pause exit waits for actual cleanup',
        );
        stoppingChild.saveRelease.complete();
        await stopped;
        expect(stoppingRun.status, SpawnAgentRunStatus.cancelled);
        expect(processing(), isFalse);
      },
    );

    test(
      'terminal card display preserves the original background tool result',
      () async {
        final runtime = container.read(provider.notifier);
        final session = container.read(
          aiChatSessionProvider('parent').notifier,
        );
        session.markLoaded();
        final child = fixture.child();
        final run = start(runtime, child);
        await child.requestEntered.future;
        final initial = {
          'ok': true,
          'status': 'running',
          'session_id': run.subSessionId,
          'run_id': run.runId,
        };
        session.startStreamingMessage(messageId: 'parent_reply');
        session.upsertToolCallBlock(
          AiToolCallBlock(
            id: 'block',
            callId: run.callId!,
            toolName: 'SpawnAgent',
            arguments: const {'background': true},
            status: AiToolCallStatus.success,
            result: initial,
          ),
        );
        child.finish('Saved chapter');
        await runtime.subAgents.waitForRun(run.runId);
        final block = session.findToolCallByCallId(run.callId!)!.$2;
        expect(block.result, initial);
        expect(block.metadata?['background_run']['status'], 'completed');
        expect(
          block.metadata?['background_run']['result']['output'],
          'Saved chapter',
        );
        runtime.subAgents.takeCompletion(run.runId);
      },
    );

    test(
      'command retains runtime and parent messages through completion consumption',
      () async {
        final runtime = container.read(provider.notifier);
        final session = container.read(
          aiChatSessionProvider('parent').notifier,
        );
        session.loadSession(
          sessionId: 'parent',
          title: 'live',
          messages: [AiMessage.user(id: 'turn_1', content: 'Write')],
        );
        final child = fixture.child(blockInitialization: true);
        final run = start(runtime, child);
        await child.initializationEntered.future;
        await container.pump();
        expect(container.read(provider.notifier), same(runtime));
        expect(
          container.read(aiChatSessionProvider('parent').notifier),
          same(session),
        );
        expect(container.read(provider).isEditing, isFalse);
        expect(container.read(provider).backgroundAgentCount, 1);
        child.initializationRelease.complete();
        await child.requestEntered.future;
        child.finish();
        await runtime.subAgents.waitForRun(run.runId);
        await container.pump();
        expect(child.releases, 1);
        expect(container.exists(provider), isTrue);
        expect(container.read(provider).backgroundAgentCount, 0);
        expect(
          container.read(provider).subAgents.pending.single.run.runId,
          run.runId,
        );
        expect(
          container.exists(spawnAgentActiveRunProvider('child_call')),
          isFalse,
        );
        runtime.subAgents.takeCompletion(run.runId);
        await container.pump();
        expect(container.exists(provider), isFalse);
        expect(container.exists(aiChatSessionProvider('parent')), isFalse);
        expect(container.read(provider).subAgents.pending, isEmpty);
      },
    );

    test(
      'sync command releases retention after history and resource cleanup',
      () async {
        final runtime = container.read(provider.notifier);
        final child = fixture.child(blockSave: true);
        final run = start(runtime, child, background: false);
        await child.requestEntered.future;
        child.finish('sync');
        await child.saveEntered.future;
        await container.pump();
        expect(container.exists(provider), isTrue);
        expect(child.releases, 0);
        child.saveRelease.complete();
        await runtime.subAgents.waitForRun(run.runId);
        expect((await run.result)['output'], 'sync');
        await container.pump();
        expect(child.releases, 1);
        expect(container.exists(provider), isFalse);
      },
    );

    test(
      'Stop Reply and model switch leave background child running',
      () async {
        final runtime = container.read(provider.notifier);
        final request = runtime.startRequest();
        final child = fixture.child();
        final run = start(runtime, child);
        await child.requestEntered.future;
        runtime.cancelRequest(request, source: AiChatCancelSource.stopButton);
        runtime.markRequestIdle(request, notifyOnComplete: false);
        runtime.cancel(source: AiChatCancelSource.modelSwitch);
        await container.pump();
        expect(run.status, SpawnAgentRunStatus.running);
        expect(container.read(provider).isRequestInFlight, isFalse);
        expect(container.read(provider).backgroundAgentCount, 1);
        final nextRequest = runtime.startRequest();
        runtime.cancelRequest(request);
        runtime.markRequestIdle(request, notifyOnComplete: false);
        expect(container.read(provider).isRequestInFlight, isTrue);
        child.finish();
        await runtime.subAgents.waitForRun(run.runId);
        expect(
          container.read(provider).subAgents.pending.single.run.runId,
          run.runId,
        );
        runtime.subAgents.takeCompletion(run.runId);
        runtime.markRequestIdle(nextRequest, notifyOnComplete: false);
        await container.pump();
        expect(container.exists(provider), isFalse);
      },
    );

    test(
      'Stop All waits for parent and child cleanup and leaves other sessions alone',
      () async {
        final runtime = container.read(provider.notifier);
        final request = runtime.startRequest();
        final child = fixture.child(blockSave: true);
        final run = start(runtime, child);
        await child.requestEntered.future;
        child.finish();
        await child.saveEntered.future;
        final otherRuntime = container.read(
          aiChatRuntimeProvider('other_parent').notifier,
        );
        final otherChild = fixture.child(parentSessionId: 'other_parent');
        final otherRun = start(otherRuntime, otherChild, callId: 'other_call');
        await otherChild.requestEntered.future;
        expect(runtime.subAgents.cancelRun(otherRun.runId), isFalse);
        expect(
          runtime.subAgents.sendMessage(otherRun.runId, 'not allowed'),
          isFalse,
        );
        expect(
          () => start(runtime, otherChild, callId: 'cross'),
          throwsStateError,
        );
        var finished = false;
        final stopped = runtime.stopAll().then((_) => finished = true);
        child.saveRelease.complete();
        await runtime.subAgents.waitForRun(run.runId);
        await container.pump();
        expect(finished, isFalse);
        expect(otherRun.status, SpawnAgentRunStatus.running);
        runtime.markRequestIdle(request, notifyOnComplete: false);
        await stopped;
        await container.pump();
        expect(container.exists(provider), isFalse);
        otherChild.finish();
        await otherRuntime.subAgents.waitForRun(otherRun.runId);
        expect(
          otherRuntime.subAgents.takeCompletion(otherRun.runId),
          isNotNull,
        );
        await container.pump();
        expect(
          container.exists(aiChatRuntimeProvider('other_parent')),
          isFalse,
        );
      },
    );

    test(
      'startup failure releases command retention without a completion notice',
      () async {
        final runtime = container.read(provider.notifier);
        final child = fixture.child(failInitialization: true);
        final run = start(runtime, child);
        await runtime.subAgents.waitForRun(run.runId);
        expect(await run.started, isFalse);
        await container.pump();
        expect(container.exists(provider), isFalse);
        expect(
          container.exists(spawnAgentActiveRunProvider('child_call')),
          isFalse,
        );
      },
    );

    test(
      'disposed runtime cleanup cannot release a replacement runtime or its activity',
      () async {
        final oldRuntime = container.read(provider.notifier);
        final oldRuns = oldRuntime.subAgents;
        final oldChild = fixture.child(blockSave: true);
        final oldRun = start(oldRuntime, oldChild);
        await oldChild.requestEntered.future;
        oldChild.finish('old');
        await oldChild.saveEntered.future;
        container.invalidate(provider);
        final replacement = container.read(provider.notifier);
        // Riverpod 复用 Notifier，重建的是本次 build 的会话运行记录。
        expect(replacement, same(oldRuntime));
        expect(replacement.subAgents, isNot(same(oldRuns)));
        final newChild = fixture.child();
        final newRun = start(replacement, newChild);
        await newChild.requestEntered.future;
        oldChild.saveRelease.complete();
        await oldRuns.waitForRun(oldRun.runId);
        await container.pump();
        expect(oldChild.releases, 1);
        expect(newChild.releases, 0);
        expect(container.read(provider.notifier), same(replacement));
        expect(
          container.read(provider).subAgents.runs.single.runId,
          newRun.runId,
        );
        expect(
          container.exists(spawnAgentActiveRunProvider('child_call')),
          isTrue,
        );
        newChild.finish('new');
        await replacement.subAgents.waitForRun(newRun.runId);
        expect(replacement.subAgents.takeCompletion(oldRun.runId), isNull);
        expect(replacement.subAgents.takeCompletion(newRun.runId), isNotNull);
        await container.pump();
        expect(container.exists(provider), isFalse);
        expect(
          container.exists(spawnAgentActiveRunProvider('child_call')),
          isFalse,
        );
      },
    );
  });
}
