// 职责: 验证 AI chat session/runtime family 按 sessionId 隔离状态
// 关联文件:
//   lib/shared/providers/ai_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'dart:async';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';

ProviderContainer _chatTestContainer() {
  return ProviderContainer(
    overrides: [aiSettingsProvider.overrideWithValue(AiSettings.defaults())],
  );
}

void main() {
  group('AI chat family providers', () {
    test(
      'operation retains an unread runtime until completion is consumed',
      () async {
        final container = _chatTestContainer();
        addTearDown(container.dispose);
        final provider = aiChatRuntimeProvider('operation_owner');
        final runtime = container.read(provider.notifier);
        final finish = Completer<Map<String, dynamic>>();
        final entered = Completer<void>();
        final context = ToolExecutionContext(
          sessionId: 'operation_owner',
          sourceTurnId: 'turn',
        );
        final receipt = await runtime.operations.start(
          context: context,
          callId: 'call',
          workId: 'work',
          kind: 'editing.preview',
          targetPath: '/editings/one',
          toolName: 'Run',
          background: true,
          execute: (_) {
            entered.complete();
            return finish.future;
          },
          verifyTarget: () async {},
        );
        await entered.future;
        await container.pump();
        expect(container.exists(provider), true);
        final request = runtime.startRequest();
        runtime.cancelRequest(request);
        runtime.markRequestIdle(request, notifyOnComplete: false);
        expect(
          runtime.operations.read(
            receipt['run_id'] as String,
            context,
          )['status'],
          'running',
        );
        finish.complete({'ok': true});
        await runtime.operations.wait(receipt['run_id'] as String, context);
        await container.pump();
        expect(container.exists(provider), true);
        runtime.operations.takeCompletion(receipt['run_id'] as String);
        await container.pump();
        expect(container.exists(provider), false);
      },
    );

    test(
      'operation notification waits for persistence and delivers once after active turn',
      () async {
        final container = _chatTestContainer();
        addTearDown(container.dispose);
        final provider = aiChatRuntimeProvider('owner');
        final runtime = container.read(provider.notifier);
        final saving = Completer<void>();
        final saved = Completer<void>();
        final delivered = Completer<void>();
        runtime.persistOperation = (_) async {
          saving.complete();
          await saved.future;
        };
        var deliveries = 0;
        runtime.configureCompletionDelivery((turn) async {
          expect(turn, 'turn');
          deliveries++;
          final notices = runtime.operations.state.pending;
          for (final notice in notices) {
            runtime.operations.takeCompletion(notice.record.runId);
          }
          delivered.complete();
          return true;
        });
        final request = runtime.startRequest();
        await runtime.operations.start(
          context: ToolExecutionContext(
            sessionId: 'owner',
            sourceTurnId: 'turn',
          ),
          callId: 'call',
          workId: 'work',
          kind: 'editing.preview',
          targetPath: '/editings/one',
          toolName: 'Run',
          background: true,
          execute: (_) async => {'ok': true},
          verifyTarget: () async {},
        );
        await saving.future;
        await container.pump();
        expect(container.exists(provider), true);
        expect(runtime.operations.state.pending, isEmpty);
        saved.complete();
        await Future<void>.delayed(Duration.zero);
        expect(deliveries, 0);
        runtime.markRequestIdle(request);
        await delivered.future;
        await container.pump();
        expect(deliveries, 1);
        expect(container.exists(provider), false);
      },
    );

    test(
      'cancelled runtime survives without listeners until turn cleanup',
      () async {
        final container = _chatTestContainer();
        addTearDown(container.dispose);
        final provider = aiChatRuntimeProvider('cancel_cleanup');
        final runtime = container.read(provider.notifier);
        final request = runtime.startRequest();
        runtime.cancelRequest(request);
        await container.pump();
        expect(container.exists(provider), isTrue);
        expect(container.read(provider.notifier), same(runtime));
        runtime.cancelRequest(request);
        runtime.markRequestIdle(request, notifyOnComplete: false);
        await container.pump();
        expect(container.exists(provider), isFalse);
      },
    );

    test(
      'newer turn finishing does not dispose an older cancelled turn',
      () async {
        final container = _chatTestContainer();
        addTearDown(container.dispose);
        final provider = aiChatRuntimeProvider('overlapping_cleanup');
        final runtime = container.read(provider.notifier);
        final first = runtime.startRequest();
        runtime.cancelRequest(first);
        final second = runtime.startRequest();
        runtime.markRequestIdle(second, notifyOnComplete: false);
        await container.pump();
        expect(container.exists(provider), isTrue);
        runtime.markRequestIdle(first, notifyOnComplete: false);
        await container.pump();
        expect(container.exists(provider), isFalse);
      },
    );

    test('late cancellation cleanup cannot cancel the next request', () async {
      final container = _chatTestContainer();
      addTearDown(container.dispose);
      final provider = aiChatRuntimeProvider('late_cancel');
      final runtime = container.read(provider.notifier);
      final first = runtime.startRequest();
      runtime.cancelRequest(first);
      final second = runtime.startRequest();
      runtime.cancelRequest(first);
      expect(container.read(provider).isRequestInFlight, isTrue);
      runtime.markRequestIdle(first, notifyOnComplete: false);
      expect(container.read(provider).isRequestInFlight, isTrue);
      runtime.markRequestIdle(second, notifyOnComplete: false);
      await container.pump();
      expect(container.exists(provider), isFalse);
    });

    test(
      'model switch preserves IDs until cancelled requests finish',
      () async {
        final container = _chatTestContainer();
        addTearDown(container.dispose);
        final provider = aiChatRuntimeProvider('switch_cleanup');
        final runtime = container.read(provider.notifier);
        final first = runtime.startRequest();
        final completion = runtime.waitForRequestCompletion(first);
        runtime.cancel(source: AiChatCancelSource.modelSwitch);
        final second = runtime.startRequest();
        expect(second, greaterThan(first));
        runtime.markRequestIdle(first, notifyOnComplete: false);
        await completion.timeout(const Duration(seconds: 1));
        expect(container.read(provider).isRequestInFlight, isTrue);
        runtime.markRequestIdle(second, notifyOnComplete: false);
        await container.pump();
        expect(container.exists(provider), isFalse);
      },
    );

    test(
      'history mutation owns retention independently of cancellation',
      () async {
        final container = _chatTestContainer();
        addTearDown(container.dispose);
        final provider = aiChatRuntimeProvider('mutation_cleanup');
        final runtime = container.read(provider.notifier);
        expect(runtime.tryBeginSessionMutation(), isTrue);
        runtime.cancel(source: AiChatCancelSource.modelSwitch);
        await container.pump();
        expect(container.exists(provider), isTrue);
        expect(runtime.tryBeginSessionMutation(), isFalse);
        runtime.endSessionMutation();
        await container.pump();
        expect(container.exists(provider), isFalse);
      },
    );

    test('family state is not marked loaded until explicitly restored', () {
      final container = _chatTestContainer();
      addTearDown(container.dispose);

      final initial = container.read(aiChatSessionProvider('session_a'));
      expect(initial.sessionId, 'session_a');
      expect(initial.isLoaded, isFalse);

      container
          .read(aiChatSessionProvider('session_a').notifier)
          .loadSession(
            sessionId: 'session_a',
            title: 'Restored',
            messages: const [],
          );

      final loaded = container.read(aiChatSessionProvider('session_a'));
      expect(loaded.sessionId, 'session_a');
      expect(loaded.isLoaded, isTrue);
    });

    test('session state is isolated per session id', () {
      final container = _chatTestContainer();
      addTearDown(container.dispose);

      container
          .read(aiChatSessionProvider('session_a').notifier)
          .addUserMessage('from A');
      container
          .read(aiChatSessionProvider('session_b').notifier)
          .addUserMessage('from B');

      final sessionA = container.read(aiChatSessionProvider('session_a'));
      final sessionB = container.read(aiChatSessionProvider('session_b'));

      expect(sessionA.sessionId, 'session_a');
      expect(sessionA.messages.single.content, 'from A');
      expect(sessionB.sessionId, 'session_b');
      expect(sessionB.messages.single.content, 'from B');
    });

    test('signature-only thinking is kept on the active streaming message', () {
      final container = _chatTestContainer();
      addTearDown(container.dispose);

      final notifier = container.read(
        aiChatSessionProvider('session_signature').notifier,
      );
      notifier.startStreamingMessage();
      notifier.setActiveThinkingSignature('sig123');

      final message = container
          .read(aiChatSessionProvider('session_signature'))
          .messages
          .single;
      final thinking = message.blocks.single as AiThinkingBlock;
      expect(thinking.text, isEmpty);
      expect(thinking.signature, 'sig123');
    });

    test('signature-only completed assistant is removed as invisible', () {
      final container = _chatTestContainer();
      addTearDown(container.dispose);

      final notifier = container.read(
        aiChatSessionProvider('session_signature_cleanup').notifier,
      );
      notifier.startStreamingMessage();
      notifier.setActiveThinkingSignature('sig123');
      notifier.endStreamingMessage();
      notifier.removeLastAssistantMessageIfInvisible();

      expect(
        container
            .read(aiChatSessionProvider('session_signature_cleanup'))
            .messages,
        isEmpty,
      );
    });

    test(
      'new session materialization is single-flight and retryable',
      () async {
        const novelId = 'novel_materialize';
        const signal = '__new__materialize';
        final gate = Completer<String>();
        var createCount = 0;

        Future<String> create() {
          createCount += 1;
          return gate.future;
        }

        final first = materializeAiChatNewSession(
          novelId: novelId,
          signal: signal,
          create: create,
        );
        final second = materializeAiChatNewSession(
          novelId: novelId,
          signal: signal,
          create: create,
        );
        expect(createCount, 1);

        gate.complete('ai_session_materialized');
        expect(await first, 'ai_session_materialized');
        expect(await second, 'ai_session_materialized');
        expect(
          resolveAiChatNewSessionId(novelId: novelId, activeId: signal),
          'ai_session_materialized',
        );
        releaseAiChatNewSessionId(novelId: novelId, signal: signal);

        var failedCreateCount = 0;
        Future<String> failOnce() async {
          failedCreateCount += 1;
          if (failedCreateCount == 1) {
            throw StateError('create failed');
          }
          return 'ai_session_retry';
        }

        await expectLater(
          materializeAiChatNewSession(
            novelId: novelId,
            signal: '__new__retryable',
            create: failOnce,
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          await materializeAiChatNewSession(
            novelId: novelId,
            signal: '__new__retryable',
            create: failOnce,
          ),
          'ai_session_retry',
        );
        expect(failedCreateCount, 2);
        releaseAiChatNewSessionId(novelId: novelId, signal: '__new__retryable');
      },
    );

    test('the same temporary signal is isolated across novels', () async {
      const signal = '__new__same_signal_across_novels';
      var novelACreateCount = 0;
      var novelBCreateCount = 0;

      final sessionA = await materializeAiChatNewSession(
        novelId: 'novel_signal_a',
        signal: signal,
        create: () async {
          novelACreateCount += 1;
          return 'session_signal_a';
        },
      );
      final sessionB = await materializeAiChatNewSession(
        novelId: 'novel_signal_b',
        signal: signal,
        create: () async {
          novelBCreateCount += 1;
          return 'session_signal_b';
        },
      );

      expect(sessionA, 'session_signal_a');
      expect(sessionB, 'session_signal_b');
      expect(novelACreateCount, 1);
      expect(novelBCreateCount, 1);
      releaseAiChatNewSessionId(novelId: 'novel_signal_a', signal: signal);
      releaseAiChatNewSessionId(novelId: 'novel_signal_b', signal: signal);
    });

    test(
      'runtime request state and cancellation are isolated per session id',
      () {
        final container = _chatTestContainer();
        addTearDown(container.dispose);

        final runtimeA = container.read(
          aiChatRuntimeProvider('session_a').notifier,
        );
        final runtimeB = container.read(
          aiChatRuntimeProvider('session_b').notifier,
        );

        final requestA = runtimeA.startRequest();
        final requestB = runtimeB.startRequest();
        runtimeA.cancelRequest(requestA, source: AiChatCancelSource.stopButton);

        final stateA = container.read(aiChatRuntimeProvider('session_a'));
        final stateB = container.read(aiChatRuntimeProvider('session_b'));

        expect(stateA.isRequestInFlight, isFalse);
        expect(stateA.requestSequence, requestA);
        expect(stateB.isRequestInFlight, isTrue);
        expect(stateB.requestSequence, requestB);
        expect(runtimeA.lastCancellationSource, 'stop_button');

        runtimeA.startRequest();
        expect(runtimeA.lastCancellationSource, isNull);
      },
    );

    test(
      'cancelling detaches a still-processing agent before the next send',
      () async {
        final container = _chatTestContainer();
        addTearDown(container.dispose);

        final agent = FakeAgent.create(
          responses: const [
            FakeProviderClientResponse.text(
              'delayed response',
              eventDelay: Duration(seconds: 1),
            ),
          ],
        );
        final subscription = agent.process('initial request').listen((_) {});
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        expect(agent.isProcessing, isTrue);

        final runtime = container.read(
          aiChatRuntimeProvider('session_a').notifier,
        );
        runtime.agent = agent;
        final requestId = runtime.startRequest();

        runtime.cancelRequest(requestId);

        // 底层取消是异步的，旧 Agent 此刻仍可能在收尾；runtime 必须不再复用它。
        expect(agent.isProcessing, isTrue);
        expect(runtime.agent, isNull);
      },
    );

    test(
      'effectiveAiChatSessionId resolves __new__ signal after registration',
      () {
        const novelId = 'novel_effective_new';
        const signal = '__new__test_signal';
        registerAiChatNewSessionId(
          novelId: novelId,
          signal: signal,
          sessionId: 'ai_session_real',
        );

        expect(
          effectiveAiChatSessionId(novelId: novelId, activeId: signal),
          'ai_session_real',
        );
        releaseAiChatNewSessionId(novelId: novelId, signal: signal);
      },
    );

    test(
      'effectiveAiChatSessionId passes unregistered __new__ signal to panel',
      () {
        const novelId = 'novel_effective_pending';
        const signal = '__new__pending';

        expect(
          effectiveAiChatSessionId(novelId: novelId, activeId: signal),
          signal,
        );
      },
    );

    test(
      'effectiveAiChatSessionId passes __handoff_draft__ signal to panel',
      () {
        const novelId = 'novel_effective_handoff_pending';
        const signal = '__handoff_draft__src_writer';

        expect(
          effectiveAiChatSessionId(novelId: novelId, activeId: signal),
          signal,
        );
      },
    );

    test(
      'effectiveAiChatSessionId resolves registered __handoff_draft__ signal',
      () {
        const novelId = 'novel_effective_handoff';
        const signal = '__handoff_draft__cover_1_orchestrator';
        const sessionId = 'ai_session_cover';

        registerAiChatNewSessionId(
          novelId: novelId,
          signal: signal,
          sessionId: sessionId,
        );

        expect(
          effectiveAiChatSessionId(novelId: novelId, activeId: signal),
          sessionId,
        );
        releaseAiChatNewSessionId(novelId: novelId, signal: signal);
      },
    );

    test('temporary chat session ids include new and handoff signals', () {
      expect(isTemporaryAiChatSessionId('__new__pending'), isTrue);
      expect(
        isTemporaryAiChatSessionId('__handoff_draft__source_writer'),
        isTrue,
      );
      expect(isTemporaryAiChatSessionId('ai_session_real'), isFalse);
      expect(isTemporaryAiChatSessionId('__persisted_parent'), isFalse);
      expect(isTemporaryAiChatSessionId(null), isFalse);
    });

    test(
      'clearActiveStreamingMessage clears partial content and keeps bubble',
      () {
        final container = _chatTestContainer();
        addTearDown(container.dispose);

        final notifier = container.read(
          aiChatSessionProvider('sess_clear').notifier,
        );
        notifier.loadSession(
          sessionId: 'sess_clear',
          title: 'Test',
          messages: const [],
        );

        notifier.startStreamingMessage();
        notifier.appendTextDelta('partial text');

        final beforeState = container.read(aiChatSessionProvider('sess_clear'));
        final beforeId = beforeState.messages.single.id;
        final beforeTimestamp = beforeState.messages.single.timestamp;

        notifier.clearActiveStreamingMessage();

        final state = container.read(aiChatSessionProvider('sess_clear'));
        final msg = state.messages.single;
        expect(msg.id, beforeId);
        expect(msg.timestamp, beforeTimestamp);
        expect(msg.isStreaming, isTrue);
        expect(msg.content, '');
        expect(msg.blocks, isEmpty);
      },
    );

    test(
      'clearActiveStreamingMessage is no-op when no active streaming message',
      () {
        final container = _chatTestContainer();
        addTearDown(container.dispose);

        final notifier = container.read(
          aiChatSessionProvider('sess_noop').notifier,
        );
        notifier.loadSession(
          sessionId: 'sess_noop',
          title: 'Test',
          messages: const [],
        );

        expect(() => notifier.clearActiveStreamingMessage(), returnsNormally);
      },
    );

    test('failed turn marks pending tools as error instead of cancelled', () {
      final container = _chatTestContainer();
      addTearDown(container.dispose);

      final notifier = container.read(
        aiChatSessionProvider('sess_failed_tool').notifier,
      );
      notifier.loadSession(
        sessionId: 'sess_failed_tool',
        title: 'Test',
        messages: const [],
      );
      notifier.startStreamingMessage();
      notifier.upsertToolCallBlock(
        const AiToolCallBlock(
          id: 'block_edit',
          callId: 'edit_1',
          toolName: 'Edit',
          arguments: {},
          requestId: 7,
          status: AiToolCallStatus.running,
        ),
      );

      notifier.failPendingToolCallsForRequest(
        7,
        errorCode: 'turn_failed',
        errorMessage: 'Request failed',
      );

      final block = container
          .read(aiChatSessionProvider('sess_failed_tool'))
          .messages
          .single
          .blocks
          .whereType<AiToolCallBlock>()
          .single;
      expect(block.status, AiToolCallStatus.error);
      expect(block.result?['error_code'], 'turn_failed');
      expect(block.result?['cancelled'], isNull);
    });
  });
}
