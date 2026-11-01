// 职责: 验证 Agent Council 总结检查点与追加轮次的状态语义
// 关联文件:
//   lib/shared/models/agent_council_models.dart
//   lib/shared/models/ai_run_failure.dart
//   lib/shared/providers/agent_council_providers.dart
//   lib/shared/services/ai/agent_council_orchestrator.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:reveric/shared/agent/agent_run_state.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/agent_council_models.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/ai_run_failure.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/providers/agent_council_providers.dart';
import 'package:reveric/shared/providers/ai_mode_processing.dart';
import 'package:reveric/shared/providers/trace_providers.dart';
import 'package:reveric/shared/services/ai/agent_council_orchestrator.dart';
import 'package:reveric/shared/services/ai/chat.dart';
import 'package:reveric/shared/services/ai/mode_run_resources.dart';
import 'package:reveric/shared/services/ai/usage_service.dart';
import 'package:reveric/shared/providers/usage_query_providers.dart';
import 'package:reveric/shared/services/ai/trace_reporter_service.dart';

class _FakeAiClient extends AiClient {
  _FakeAiClient()
    : super(aiProviderBuiltinDefaults.first, chatModel: 'test-model');
}

class _SuccessfulSummaryOrchestrator extends AgentCouncilOrchestrator {
  _SuccessfulSummaryOrchestrator(this.summary);

  final CouncilSummary summary;

  @override
  Future<CouncilSummary> generateSummary({
    required AgentCouncilSession session,
    required AiClient aiService,
    String Function(String)? t,
    TraceReporterService? traceReporter,
    UsageService? usageService,
  }) async {
    return summary;
  }
}

class _DelayedRoundOrchestrator extends AgentCouncilOrchestrator {
  final started = Completer<void>();
  final release = Completer<void>();
  AgentCouncilSession? received;

  @override
  Future<AgentCouncilSession> runRound({
    required AgentCouncilSession session,
    required AiClient aiService,
    required AiSessionContext context,
    AgentCouncilConfig config = const AgentCouncilConfig(),
    CouncilMessageCallback? onMessageGenerated,
    CouncilPhaseCallback? onPhaseChanged,
    CouncilAiServiceResolver? aiServiceResolver,
    String Function(String)? t,
    CouncilTextDeltaCallback? onTextDelta,
    CouncilThinkingDeltaCallback? onThinkingDelta,
    CouncilToolCallCallback? onToolCall,
    TraceReporterService? traceReporter,
    UsageService? usageService,
    String? speakerId,
  }) async {
    received = session;
    started.complete();
    await release.future;
    final completed = session.copyWith(phase: CouncilPhase.completed);
    onPhaseChanged?.call(completed);
    return completed;
  }
}

class _DelayedSummaryOrchestrator extends AgentCouncilOrchestrator {
  _DelayedSummaryOrchestrator(this.summary);

  final CouncilSummary summary;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<CouncilSummary> generateSummary({
    required AgentCouncilSession session,
    required AiClient aiService,
    String Function(String)? t,
    TraceReporterService? traceReporter,
    UsageService? usageService,
  }) async {
    started.complete();
    await release.future;
    return summary;
  }
}

class _FakeTraceReporterService implements TraceReporterService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 7, 29);

  CouncilRound completedRound(int number) {
    return CouncilRound(
      roundNumber: number,
      messages: [
        CouncilMessage(
          id: 'message_$number',
          participantId: 'agent',
          participantName: 'Agent',
          content: 'Round $number',
          timestamp: now.add(Duration(minutes: number)),
          round: number,
        ),
      ],
      isComplete: true,
    );
  }

  AgentCouncilSession completedSession() {
    return AgentCouncilSession(
      id: 'session',
      novelId: 'novel',
      topic: 'Topic',
      participants: const [
        CouncilParticipant(
          id: 'agent',
          name: 'Agent',
          description: '',
          prompt: '',
        ),
      ],
      rounds: [completedRound(1), completedRound(2), completedRound(3)],
      summary: CouncilSummary(
        content: 'Summary through round 3',
        coveredThroughMessageId: 'message_3',
        timestamp: now.add(const Duration(minutes: 4)),
        coveredThroughRound: 3,
      ),
      phase: CouncilPhase.completed,
      createdAt: now,
      updatedAt: now,
    );
  }

  for (final disposeContainer in [false, true]) {
    test(
      'pending initialization releases its client on ${disposeContainer ? 'container disposal' : 'cancel'}',
      () async {
        final pendingClient = Completer<AiModeOwnedClient>();
        final container = ProviderContainer(
          overrides: [
            aiModeClientFactoryProvider.overrideWithValue(
              (_) => pendingClient.future,
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(
          agentCouncilSessionProvider('session').notifier,
        );
        final future = notifier.startCouncil(
          novelId: 'novel',
          topic: 'Topic',
          participants: const [],
          selection: AiModeRunSelection(
            model: const AiModelOption(
              providerId: 'custom',
              providerDisplayName: 'Test',
              model: 'test',
              kind: AiModelKind.chat,
            ),
          ),
          context: const AiSessionContext(),
        );
        final rejected = expectLater(
          future,
          throwsA(isA<AiModeRunCancelled>()),
        );
        if (disposeContainer) {
          container.dispose();
        } else {
          notifier.cancel();
        }
        var released = 0;
        pendingClient.complete(
          AiModeOwnedClient(_FakeAiClient(), () => released++),
        );
        await rejected;
        expect(released, 1);
      },
    );
  }

  test(
    'regeneration mutates history only after client initialization succeeds',
    () async {
      var unavailable = true;
      final container = ProviderContainer(
        overrides: [
          aiModeClientFactoryProvider.overrideWithValue((_) async {
            if (unavailable) {
              throw const AiModeClientUnavailable();
            }
            return AiModeOwnedClient(_FakeAiClient(), () {});
          }),
          traceReporterServiceProvider.overrideWithValue(
            _FakeTraceReporterService(),
          ),
          usageServiceProvider.overrideWith((ref) => _UnusedUsage()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        agentCouncilSessionProvider('session').notifier,
      );
      notifier.setSession(completedSession());
      final selection = AiModeRunSelection(
        model: const AiModelOption(
          providerId: 'custom',
          providerDisplayName: 'Test',
          model: 'test',
          kind: AiModelKind.chat,
        ),
      );
      await expectLater(
        notifier.runAdditionalRound(
          selection: selection,
          context: const AiSessionContext(),
          rewindFromMessageId: 'message_2',
        ),
        throwsA(isA<AiModeClientUnavailable>()),
      );
      expect(
        container.read(agentCouncilSessionProvider('session'))!.rounds,
        hasLength(3),
      );
      unavailable = false;
      final orchestrator = _DelayedRoundOrchestrator();
      container
              .read(agentCouncilRuntimeProvider('session').notifier)
              .orchestrator =
          orchestrator;
      final running = notifier.runAdditionalRound(
        selection: selection,
        context: const AiSessionContext(),
        rewindFromMessageId: 'message_2',
      );
      await orchestrator.started.future;
      expect(orchestrator.received!.rounds, hasLength(1));
      expect(orchestrator.received!.summary, isNull);
      orchestrator.release.complete();
      await running;
    },
  );

  group('Agent Council summary checkpoint', () {
    test(
      'adding user input preserves the old summary before the new round',
      () {
        final container = ProviderContainer(
          overrides: [
            aiModeClientFactoryProvider.overrideWithValue(
              (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
            ),
          ],
        );
        addTearDown(container.dispose);
        final provider = agentCouncilSessionProvider('session');
        final notifier = container.read(provider.notifier);
        notifier.setSession(completedSession());

        notifier.addUserMessage('Please discuss one more concern');

        final session = container.read(provider)!;
        expect(session.summary?.coveredThroughRound, 3);
        expect(session.rounds.last.roundNumber, 4);
        expect(session.rounds.last.isComplete, isFalse);
        expect(session.nextDiscussionRoundNumber, 4);
        expect(session.hasOutdatedSummary, isTrue);
        expect(session.canUpdateSummary, isFalse);
      },
    );

    test('a completed last round starts the next numbered round', () {
      final session = completedSession();

      expect(session.nextDiscussionRoundNumber, 4);
      expect(session.hasOutdatedSummary, isFalse);
      expect(session.canUpdateSummary, isFalse);
    });

    test(
      'persisted hydration cannot overwrite a council running in background',
      () {
        final container = ProviderContainer(
          overrides: [
            aiModeClientFactoryProvider.overrideWithValue(
              (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
            ),
          ],
        );
        addTearDown(container.dispose);
        const sessionId = 'session';
        final provider = agentCouncilSessionProvider(sessionId);
        final notifier = container.read(provider.notifier);
        final liveSession = completedSession().copyWith(
          title: 'Live title',
          phase: CouncilPhase.discussing,
        );
        const liveRun = AgentRunState(
          agentId: 'agent',
          agentName: 'Agent',
          round: 3,
          accumulatedText: 'Live run detail',
          isComplete: true,
        );
        notifier.setSession(liveSession);
        notifier.restoreRunHistory(const {'live_message': liveRun});
        container
            .read(agentCouncilRuntimeProvider(sessionId).notifier)
            .setProcessing(true);

        final didRestore = notifier.restorePersistedSessionIfAbsent(
          session: completedSession().copyWith(
            title: 'Stale title',
            rounds: [completedRound(1)],
            phase: CouncilPhase.discussing,
          ),
          runHistory: const {
            'stale_message': AgentRunState(
              agentId: 'agent',
              agentName: 'Agent',
              round: 1,
              accumulatedText: 'Stale run detail',
              isComplete: true,
            ),
          },
        );

        expect(didRestore, isFalse);
        expect(container.read(provider), same(liveSession));
        final preservedHistory = container.read(
          agentCouncilRunHistoryStoreProvider(sessionId),
        );
        expect(preservedHistory.keys, ['live_message']);
        expect(
          preservedHistory['live_message']?.accumulatedText,
          liveRun.accumulatedText,
        );
        expect(preservedHistory['live_message']?.round, liveRun.round);
      },
    );

    test('persisted hydration initializes an absent council session', () {
      final container = ProviderContainer(
        overrides: [
          aiModeClientFactoryProvider.overrideWithValue(
            (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
          ),
        ],
      );
      addTearDown(container.dispose);
      const sessionId = 'restored_session';
      final provider = agentCouncilSessionProvider(sessionId);
      final notifier = container.read(provider.notifier);
      final persistedSession = completedSession().copyWith(id: sessionId);
      const persistedRun = AgentRunState(
        agentId: 'agent',
        agentName: 'Agent',
        round: 1,
        accumulatedText: 'Persisted run detail',
        isComplete: true,
      );

      final didRestore = notifier.restorePersistedSessionIfAbsent(
        session: persistedSession,
        runHistory: const {'persisted_message': persistedRun},
      );

      expect(didRestore, isTrue);
      expect(container.read(provider), same(persistedSession));
      final restoredHistory = container.read(
        agentCouncilRunHistoryStoreProvider(sessionId),
      );
      expect(restoredHistory.keys, ['persisted_message']);
      expect(
        restoredHistory['persisted_message']?.accumulatedText,
        persistedRun.accumulatedText,
      );
      expect(restoredHistory['persisted_message']?.round, persistedRun.round);
    });

    test('a completed newer round allows the summary to be updated', () {
      final session = completedSession().copyWith(
        rounds: [...completedSession().rounds, completedRound(4)],
      );

      expect(session.hasOutdatedSummary, isTrue);
      expect(session.canUpdateSummary, isTrue);
    });

    test('a solo speech appended to the summarized round outdates it', () {
      final summarized = completedSession().copyWith(
        summary: CouncilSummary(
          content: 'Summary through message_3',
          timestamp: now.add(const Duration(minutes: 4)),
          coveredThroughRound: 3,
          coveredThroughMessageId: 'message_3',
        ),
      );
      expect(summarized.hasOutdatedSummary, isFalse);

      final lastRound = summarized.rounds.last;
      final appended = summarized.copyWith(
        rounds: [
          ...summarized.rounds.take(2),
          lastRound.copyWith(
            messages: [
              ...lastRound.messages,
              CouncilMessage(
                id: 'solo',
                participantId: 'agent',
                participantName: 'Agent',
                content: 'One more thought',
                timestamp: now.add(const Duration(minutes: 5)),
                round: 3,
              ),
            ],
          ),
        ],
      );

      // 轮次没变，只能靠覆盖到的消息判断过期。
      expect(appended.currentRoundNumber, 3);
      expect(appended.hasOutdatedSummary, isTrue);
      expect(appended.canUpdateSummary, isTrue);
    });

    test('a legacy summary with unknown coverage can be refreshed', () {
      final session = completedSession().copyWith(
        summary: CouncilSummary(
          content: 'Legacy summary',
          timestamp: now,
          coveredThroughRound: 0,
        ),
      );

      expect(session.hasOutdatedSummary, isTrue);
      expect(session.canUpdateSummary, isTrue);
    });

    test('summary coverage survives JSON and legacy JSON remains readable', () {
      final summary = completedSession().summary!;

      expect(CouncilSummary.fromJson(summary.toJson()).coveredThroughRound, 3);
      final withMessage = CouncilSummary(
        content: summary.content,
        timestamp: summary.timestamp,
        coveredThroughRound: 3,
        coveredThroughMessageId: 'message_3',
      );
      expect(
        CouncilSummary.fromJson(withMessage.toJson()).coveredThroughMessageId,
        'message_3',
      );
      expect(
        CouncilSummary.fromJson({
          'content': 'Legacy summary',
          'timestamp': now.toIso8601String(),
        }).coveredThroughRound,
        0,
      );
      expect(
        CouncilSummary.fromJson({
          'content': 'Legacy summary',
          'timestamp': now.toIso8601String(),
        }).coveredThroughMessageId,
        isNull,
      );
    });

    test('run error survives JSON and is cleared before retry', () {
      final failed = completedSession().copyWith(
        phase: CouncilPhase.error,
        failure: const AiRunFailure.http(statusCode: 402, providerId: 'custom'),
      );

      final restored = AgentCouncilSession.fromJson(
        jsonDecode(jsonEncode(failed.toJson())) as Map<String, dynamic>,
      );

      expect(restored.phase, CouncilPhase.error);
      expect(
        restored.failure,
        const AiRunFailure.http(statusCode: 402, providerId: 'custom'),
      );
      expect(restored.copyWith(clearFailure: true).failure, isNull);
    });

    test('successful summary generation clears the previous failure', () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          aiModeClientFactoryProvider.overrideWithValue(
            (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
          ),
          traceReporterServiceProvider.overrideWithValue(
            _FakeTraceReporterService(),
          ),
          usageServiceProvider.overrideWithValue(
            UsageService(appDatabase: database),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = agentCouncilSessionProvider('session');
      final notifier = container.read(provider.notifier);
      container
          .read(aiModeProcessingTrackerProvider.notifier)
          .setForegroundSession(
            mode: AiSessionMode.council,
            sessionId: 'session',
            foreground: true,
          );
      notifier.setSession(
        completedSession().copyWith(
          phase: CouncilPhase.error,
          failure: const AiRunFailure.http(
            statusCode: 503,
            providerId: 'custom',
          ),
        ),
      );
      final newSummary = CouncilSummary(
        content: 'Regenerated summary',
        timestamp: now.add(const Duration(minutes: 5)),
        coveredThroughRound: 3,
      );
      container
          .read(agentCouncilRuntimeProvider('session').notifier)
          .orchestrator = _SuccessfulSummaryOrchestrator(
        newSummary,
      );

      final outcome = await notifier.generateSummary(
        context: const AiSessionContext(),
        selection: AiModeRunSelection(
          model: const AiModelOption(
            providerId: 'custom',
            providerDisplayName: 'Test',
            model: 'test-model',
            kind: AiModelKind.chat,
          ),
        ),
      );

      final session = container.read(provider)!;
      expect(outcome?.sessionId, 'session');
      expect(outcome?.phase, CouncilPhase.completed);
      expect(session.phase, CouncilPhase.completed);
      expect(session.summary?.content, 'Regenerated summary');
      expect(session.failure, isNull);
    });

    test('an interjection during summary generation is kept', () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          aiModeClientFactoryProvider.overrideWithValue(
            (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
          ),
          traceReporterServiceProvider.overrideWithValue(
            _FakeTraceReporterService(),
          ),
          usageServiceProvider.overrideWithValue(
            UsageService(appDatabase: database),
          ),
        ],
      );
      addTearDown(container.dispose);
      const sessionId = 'session';
      final provider = agentCouncilSessionProvider(sessionId);
      final notifier = container.read(provider.notifier);
      notifier.setSession(completedSession().copyWith(clearSummary: true));
      container
          .read(aiModeProcessingTrackerProvider.notifier)
          .setForegroundSession(
            mode: AiSessionMode.council,
            sessionId: sessionId,
            foreground: true,
          );
      final orchestrator = _DelayedSummaryOrchestrator(
        CouncilSummary(
          content: 'Summary',
          timestamp: now.add(const Duration(minutes: 5)),
          coveredThroughRound: 3,
          coveredThroughMessageId: 'message_3',
        ),
      );
      container
              .read(agentCouncilRuntimeProvider(sessionId).notifier)
              .orchestrator =
          orchestrator;

      final run = notifier.generateSummary(
        selection: AiModeRunSelection(
          model: const AiModelOption(
            providerId: 'custom',
            providerDisplayName: 'Test',
            model: 'test-model',
            kind: AiModelKind.chat,
          ),
        ),
        context: const AiSessionContext(),
      );
      await orchestrator.started.future;
      notifier.addUserMessage('总结前再补一句');
      orchestrator.release.complete();
      await run;

      final session = container.read(provider)!;
      expect(session.summary?.content, 'Summary');
      expect(
        session.rounds
            .expand((r) => r.messages)
            .where((m) => m.isUser)
            .single
            .content,
        '总结前再补一句',
      );
      // 插话没进这次总结，总结要能标记为过期。
      expect(session.hasOutdatedSummary, isTrue);
      expect(notifier.pendingUserMessageIds, isEmpty);
    });

    test(
      'late round completion cannot overwrite a cancelled session',
      () async {
        final database = AppDatabase.forTest(NativeDatabase.memory());
        addTearDown(database.close);
        final container = ProviderContainer(
          overrides: [
            aiModeClientFactoryProvider.overrideWithValue(
              (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
            ),
            traceReporterServiceProvider.overrideWithValue(
              _FakeTraceReporterService(),
            ),
            usageServiceProvider.overrideWithValue(
              UsageService(appDatabase: database),
            ),
          ],
        );
        addTearDown(container.dispose);
        const sessionId = 'session';
        final provider = agentCouncilSessionProvider(sessionId);
        final notifier = container.read(provider.notifier);
        notifier.setSession(completedSession());
        container
            .read(aiModeProcessingTrackerProvider.notifier)
            .setForegroundSession(
              mode: AiSessionMode.council,
              sessionId: sessionId,
              foreground: true,
            );
        final orchestrator = _DelayedRoundOrchestrator();
        container
                .read(agentCouncilRuntimeProvider(sessionId).notifier)
                .orchestrator =
            orchestrator;

        final run = notifier.runAdditionalRound(
          selection: AiModeRunSelection(
            model: const AiModelOption(
              providerId: 'custom',
              providerDisplayName: 'Test',
              model: 'test-model',
              kind: AiModelKind.chat,
            ),
          ),
          context: const AiSessionContext(),
        );
        await orchestrator.started.future;
        notifier.cancel();
        orchestrator.release.complete();
        final outcome = await run;

        final session = container.read(provider)!;
        expect(outcome?.sessionId, sessionId);
        expect(outcome?.phase, CouncilPhase.cancelled);
        expect(session.phase, CouncilPhase.cancelled);
        expect(session.failure, isNull);
      },
    );
  });

  group('Agent Council moderation', () {
    test(
      'an interjection during a run stays visible and is kept after it',
      () async {
        final database = AppDatabase.forTest(NativeDatabase.memory());
        addTearDown(database.close);
        final container = ProviderContainer(
          overrides: [
            aiModeClientFactoryProvider.overrideWithValue(
              (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
            ),
            traceReporterServiceProvider.overrideWithValue(
              _FakeTraceReporterService(),
            ),
            usageServiceProvider.overrideWithValue(
              UsageService(appDatabase: database),
            ),
          ],
        );
        addTearDown(container.dispose);
        const sessionId = 'session';
        final provider = agentCouncilSessionProvider(sessionId);
        final notifier = container.read(provider.notifier);
        notifier.setSession(completedSession());
        container
            .read(aiModeProcessingTrackerProvider.notifier)
            .setForegroundSession(
              mode: AiSessionMode.council,
              sessionId: sessionId,
              foreground: true,
            );
        final orchestrator = _DelayedRoundOrchestrator();
        container
                .read(agentCouncilRuntimeProvider(sessionId).notifier)
                .orchestrator =
            orchestrator;

        final run = notifier.runAdditionalRound(
          selection: AiModeRunSelection(
            model: const AiModelOption(
              providerId: 'custom',
              providerDisplayName: 'Test',
              model: 'test-model',
              kind: AiModelKind.chat,
            ),
          ),
          context: const AiSessionContext(),
        );
        await orchestrator.started.future;
        notifier.addUserMessage('先回答角色动机');

        // 编排器尚未并入时界面已经能看到这条插话，编号落在正在进行的一轮。
        final during = container.read(provider)!;
        expect(during.rounds.last.messages.last.content, '先回答角色动机');
        expect(during.rounds.last.roundNumber, 4);

        orchestrator.release.complete();
        await run;

        // 这次运行没有人再发言，插话在收尾时落定，不会被编排器快照冲掉。
        final after = container.read(provider)!;
        expect(
          after.rounds.expand((r) => r.messages).where((m) => m.isUser),
          hasLength(1),
        );
      },
    );

    test('rewinding into a summarized round drops the stale summary', () {
      final container = ProviderContainer(
        overrides: [
          aiModeClientFactoryProvider.overrideWithValue(
            (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = agentCouncilSessionProvider('session');
      final notifier = container.read(provider.notifier);
      notifier.setSession(completedSession());

      notifier.rewindTo('message_2', inclusive: false);

      final session = container.read(provider)!;
      expect(session.rounds.map((r) => r.roundNumber), [1, 2]);
      expect(session.summary, isNull);
    });

    test('removing a message after the summary keeps the summary', () {
      final container = ProviderContainer(
        overrides: [
          aiModeClientFactoryProvider.overrideWithValue(
            (_) async => AiModeOwnedClient(_FakeAiClient(), () {}),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = agentCouncilSessionProvider('session');
      final notifier = container.read(provider.notifier);
      notifier.setSession(completedSession());
      notifier.addUserMessage('补充一句');
      final userMessage = container.read(provider)!.rounds.last.messages.single;

      notifier.removeMessage(userMessage.id);

      final session = container.read(provider)!;
      expect(session.rounds.map((r) => r.roundNumber), [1, 2, 3]);
      expect(session.summary?.coveredThroughRound, 3);
    });
  });
}

class _UnusedUsage implements UsageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
