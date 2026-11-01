// 职责: 验证后台任务列表的本地化、窄屏布局、停止收尾与工具历史展示。
// 关联文件:
//   lib/shared/widgets/ai/chat/background_agents.dart
//   lib/shared/widgets/ai/tools/spawn_agent_display.dart
//   lib/shared/providers/ai_providers.dart
//   test/helpers/spawn_agent_runtime_fixture.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/ai_mode_processing.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/providers/spawn_agent_run_providers.dart';
import 'package:reveric/shared/services/ai/spawn_agent_handler.dart';
import 'package:reveric/shared/services/ai/chat_agent_tool_dispatcher.dart';
import 'package:reveric/shared/services/ai/chat_session_controller.dart';
import 'package:reveric/shared/services/ai/chat_turn_runner.dart';
import 'package:reveric/shared/services/ai/chat_prompt_builder.dart';
import 'package:reveric/shared/services/ai/prompts/ai_prompt_service.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/background_agents.dart';
import 'package:reveric/shared/widgets/ai/tool_activity_group.dart';
import 'package:reveric/shared/widgets/ai/tools/spawn_agent_activity_line.dart';
import 'package:reveric/shared/widgets/ai/tools/spawn_agent_display.dart';
import 'package:reveric/shared/widgets/ai/tools/spawn_agent_tool_card_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/spawn_agent_runtime_fixture.dart';
import '../../../helpers/novel_fixture.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
    testWidgets(
      'Stop All only stops background agents (${locale.toLanguageTag()})',
      (tester) async {
        late SpawnAgentRuntimeFixture fixture;
        late ProviderContainer container;
        late AiChatRuntime runtime;
        late ControlledSubAgent synchronous;
        late ControlledSubAgent background;
        late ControlledSubAgent initializing;
        late SpawnAgentRun backgroundRun;
        late SpawnAgentRun initializingRun;
        late Future<List<AgentEvent>> parentWork;
        final parentClient = FakeProviderClient(
          responses: const [
            FakeProviderClientResponse.toolCalls([
              ToolCall(
                callId: 'sync',
                toolName: 'SpawnAgent',
                arguments: {
                  'agent': 'Writer',
                  'name': 'Synchronous author',
                  'task': 'Write',
                  'background': false,
                },
              ),
            ]),
            FakeProviderClientResponse.text('Parent continued'),
          ],
        );
        await tester.runAsync(() async {
          fixture = SpawnAgentRuntimeFixture();
          await fixture.initialize();
          container = ProviderContainer(
            overrides: [
              aiSettingsProvider.overrideWithValue(AiSettings.defaults()),
              mergedSubAgentsProvider.overrideWithValue(const []),
            ],
          );
          container.listen(aiChatRuntimeProvider('parent'), (_, _) {});
          runtime = container.read(aiChatRuntimeProvider('parent').notifier);
          synchronous = fixture.child();
          background = fixture.child(blockSave: true);
          initializing = fixture.child(blockInitialization: true);
          final dispatcher = ChatAgentToolDispatcher(
            inner: FakeAgentToolDispatcher(),
            subAgents: runtime.subAgents,
            resumeSubAgent: (sessionId, message, callId, context) =>
                runtime.resumeSubAgent(
                  handler: synchronous.handler,
                  sessionId: sessionId,
                  message: message,
                  callId: callId,
                  context: context,
                ),
            startSubAgent: (input, callId, context, {required background}) =>
                runtime.startSubAgent(
                  handler: synchronous.handler,
                  input: input,
                  callId: callId,
                  context: context,
                  background: background,
                ),
          );
          final parent = FakeAgent.create(
            client: parentClient,
            toolManager: dispatcher,
            allowedTools: ['SpawnAgent'],
          );
          runtime.agent = parent;
          final request = runtime.startRequest();
          parentWork = parent
              .process(
                'Write',
                toolExecutionContext: ToolExecutionContext(
                  sessionId: 'parent',
                  sourceSessionId: 'parent',
                  sourceTurnId: 'turn',
                ),
              )
              .toList()
              .whenComplete(() => runtime.markRequestIdle(request));
          await synchronous.requestEntered.future;
          SpawnAgentRun start(ControlledSubAgent child, String name) =>
              runtime.startSubAgent(
                handler: child.handler,
                input: {'agent': 'Writer', 'name': name, 'task': 'Write'},
                callId: name,
                context: ToolExecutionContext(
                  sessionId: 'parent',
                  sourceSessionId: 'parent',
                  sourceTurnId: 'turn',
                ),
                background: true,
              );
          backgroundRun = start(background, 'Background author');
          initializingRun = start(initializing, 'Initializing author');
          await background.requestEntered.future;
          await initializing.initializationEntered.future;
        });
        try {
          await tester.pumpWidget(
            _wrap(
              container,
              locale,
              const BackgroundAgents(sessionId: 'parent'),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('background_agents_stop_all')),
          );
          await tester.pump();
          expect(backgroundRun.status, SpawnAgentRunStatus.stopping);
          expect(initializingRun.status, SpawnAgentRunStatus.stopping);
          expect(background.client.cancelCallCount, 1);
          expect(synchronous.client.cancelCallCount, 0);
          expect(parentClient.cancelCallCount, 0);
          expect(
            container.read(aiChatRuntimeProvider('parent')).isRequestInFlight,
            isTrue,
          );
          await tester.runAsync(() async {
            synchronous.finish('Synchronous result');
            final events = await parentWork;
            expect(
              events.whereType<AgentDone>().single.finalText,
              'Parent continued',
            );
            expect(events.whereType<AgentCancelled>(), isEmpty);
            background.finish();
            await background.saveEntered.future;
          });
          // 主回复已经完成，后台取消仍等待各自的初始化和持久化收尾。
          expect(background.releases, 0);
          expect(backgroundRun.status, SpawnAgentRunStatus.stopping);
          await tester.runAsync(() async {
            initializing.initializationRelease.complete();
            background.saveRelease.complete();
            await runtime.subAgents.waitForRun(backgroundRun.runId);
            await runtime.subAgents.waitForRun(initializingRun.runId);
          });
          await tester.pumpAndSettle();
          expect(backgroundRun.status, SpawnAgentRunStatus.cancelled);
          expect(initializingRun.status, SpawnAgentRunStatus.cancelled);
          expect(background.releases, 1);
          expect(initializing.releases, 1);
          expect(initializing.client.capturedStreamRequests, isEmpty);
          expect(
            container.read(aiChatRuntimeProvider('parent')).subAgents.pending,
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            for (final child in [synchronous, background, initializing]) {
              if (!child.response.isCompleted) {
                child.finish();
              }
              if (!child.initializationRelease.isCompleted) {
                child.initializationRelease.complete();
              }
              if (!child.saveRelease.isCompleted) {
                child.saveRelease.complete();
              }
            }
            await parentWork;
            await runtime.subAgents.stopAll(source: 'test_cleanup');
            container.dispose();
            await fixture.dispose();
          });
        }
      },
    );

    testWidgets(
      'list shows live jobs and waits for pause cleanup (${locale.toLanguageTag()})',
      (tester) async {
        late SpawnAgentRuntimeFixture fixture;
        late ProviderContainer container;
        late AiChatRuntime runtime;
        late ControlledSubAgent first;
        late ControlledSubAgent second;
        late SpawnAgentRun firstRun;
        late SpawnAgentRun secondRun;
        await tester.runAsync(() async {
          fixture = SpawnAgentRuntimeFixture();
          await fixture.initialize();
          container = ProviderContainer(
            overrides: [
              aiSettingsProvider.overrideWithValue(AiSettings.defaults()),
              mergedSubAgentsProvider.overrideWithValue(const []),
            ],
          );
          container
              .read(aiModeProcessingTrackerProvider.notifier)
              .setForegroundSession(
                mode: AiSessionMode.chat,
                sessionId: 'parent',
                foreground: true,
              );
          runtime = container.read(aiChatRuntimeProvider('parent').notifier);
          SpawnAgentRun start(ControlledSubAgent child, String name) =>
              runtime.startSubAgent(
                handler: child.handler,
                input: {
                  'agent': 'Writer',
                  'name': name,
                  'task': 'Write the chapter without changing the protagonist.',
                },
                callId: name,
                context: ToolExecutionContext(
                  sessionId: 'parent',
                  sourceSessionId: 'parent',
                  sourceTurnId: 'turn',
                ),
                background: true,
              );
          first = fixture.child(blockSave: true);
          second = fixture.child();
          firstRun = start(first, 'First author');
          secondRun = start(second, 'Second author');
          await Future.wait([
            first.requestEntered.future,
            second.requestEntered.future,
          ]);
        });
        await tester.binding.setSurfaceSize(
          Size(locale.languageCode == 'en' ? 360 : 320, 700),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            container,
            locale,
            const BackgroundAgents(
              sessionId: 'parent',
              novelId: 'novel',
              databasePath: 'test',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('First author'), findsOneWidget);
        expect(find.text('Second author'), findsOneWidget);
        final summaryTitle = locale.languageCode == 'en'
            ? '2 background tasks'
            : '2 个后台任务';
        expect(find.textContaining(summaryTitle), findsOneWidget);
        expect(
          container.read(aiChatRuntimeProvider('parent')).isRequestInFlight,
          isFalse,
        );
        // 「全部停止」只在展开且有多个在跑时出现。
        expect(
          find.byKey(const ValueKey('background_agents_stop_all')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // 点标题而不是整行中心：行中心此刻压在「全部停止」上，那是破坏性动作。
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('background_agents_toggle')),
            matching: find.text(summaryTitle),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(summaryTitle));
        await tester.pumpAndSettle();
        expect(find.text('First author'), findsNothing);
        await tester.tap(find.text(summaryTitle));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('background_agent_stop_${firstRun.runId}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(locale.languageCode == 'en' ? 'Stopping…' : '正在停止…'),
          findsOneWidget,
        );
        expect(secondRun.status, SpawnAgentRunStatus.running);
        await tester.runAsync(() async {
          first.finish();
          await first.saveEntered.future;
        });
        await tester.pumpAndSettle();
        expect(find.text('First author'), findsOneWidget);
        await tester.runAsync(() async {
          first.saveRelease.complete();
          await runtime.subAgents.waitForRun(firstRun.runId);
        });
        await tester.pumpAndSettle();
        // 结束的任务不立刻消失：先留一条回执，6 秒后才移出。
        expect(find.text('First author'), findsOneWidget);
        expect(
          find.text(locale.languageCode == 'en' ? 'Cancelled' : '已取消'),
          findsOneWidget,
        );
        expect(find.text('Second author'), findsOneWidget);
        // 只剩一个在跑，「全部停止」已收起，停止入口回到该行自己。
        expect(
          find.byKey(const ValueKey('background_agents_stop_all')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(ValueKey('background_agent_stop_${secondRun.runId}')),
        );
        await tester.pump();
        expect(secondRun.status, SpawnAgentRunStatus.stopping);
        await tester.runAsync(() async {
          second.finish();
          await runtime.subAgents.waitForRun(secondRun.runId);
        });
        await tester.pumpAndSettle();
        expect(find.text('Second author'), findsOneWidget);
        // 回执过期后整条 bar 收回，不留占位。
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpAndSettle();
        expect(find.text('First author'), findsNothing);
        expect(find.text('Second author'), findsNothing);
        expect(
          find.byKey(const ValueKey('background_agents_toggle')),
          findsNothing,
        );
        expect(
          container.read(aiChatRuntimeProvider('parent')).subAgents.pending,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          container.dispose();
          await fixture.dispose();
        });
      },
    );
  }

  testWidgets(
    'Stop Reply during real startup leaves the child card live then terminal without rewriting cancellation',
    (tester) async {
      late SpawnAgentRuntimeFixture fixture;
      late ProviderContainer container;
      late ControlledSubAgent child;
      late AiChatRuntime runtime;
      late AiChatSession session;
      late Map<String, dynamic> cancelledResult;
      late List<ToolResultBlock> originalModelResults;
      late AgentToolDispatcher parentDispatcher;
      await tester.runAsync(() async {
        fixture = SpawnAgentRuntimeFixture();
        await fixture.initialize();
        container = ProviderContainer(
          overrides: [
            aiSettingsProvider.overrideWithValue(AiSettings.defaults()),
            appDebugModeProvider.overrideWithValue(false),
            mergedSubAgentsProvider.overrideWithValue(const []),
          ],
        );
        container.listen(aiChatRuntimeProvider('parent'), (_, _) {});
        container.listen(aiChatSessionProvider('parent'), (_, _) {});
        container
            .read(aiModeProcessingTrackerProvider.notifier)
            .setForegroundSession(
              mode: AiSessionMode.chat,
              sessionId: 'parent',
              foreground: true,
            );
        session = container.read(aiChatSessionProvider('parent').notifier);
        session.markLoaded();
        session.addUserMessage('Write', id: 'origin');
        runtime = container.read(aiChatRuntimeProvider('parent').notifier);
        child = fixture.child(blockInitialization: true);
        parentDispatcher = ChatAgentToolDispatcher(
          inner: FakeAgentToolDispatcher(),
          subAgents: runtime.subAgents,
          resumeSubAgent: (sessionId, message, callId, context) =>
              runtime.resumeSubAgent(
                handler: child.handler,
                sessionId: sessionId,
                message: message,
                callId: callId,
                context: context,
              ),
          startSubAgent: (input, callId, context, {required background}) =>
              runtime.startSubAgent(
                handler: child.handler,
                input: input,
                callId: callId,
                context: context,
                background: background,
              ),
        );
        final parent = FakeAgent.create(
          toolManager: parentDispatcher,
          allowedTools: ['SpawnAgent'],
          responses: const [
            FakeProviderClientResponse.toolCalls([
              ToolCall(
                callId: 'stopped_startup',
                toolName: 'SpawnAgent',
                arguments: {
                  'agent': 'Writer',
                  'name': 'Author',
                  'task': 'Write',
                },
              ),
            ]),
          ],
        );
        runtime.agent = parent;
        final controller = ChatSessionController(
          container: container,
          scope: ChatScope(
            activeSessionId: 'parent',
            novel: buildTestNovel(),
            databasePath: null,
            workspaceSection: NovelWorkspaceSection.novel_description,
          ),
          host: ChatHost(
            clearComposer: () {},
            focusComposer: () {},
            openModelSelector: () {},
            resetScroll: () {},
            isMounted: () => true,
          ),
          store: DefaultChatComposerStore(),
          promptBuilder: ChatPromptBuilder(),
          availableSubAgents: const [],
          aiPromptService: AiPromptService(),
          promptContext: const AiSessionContext(),
        );
        final request = runtime.startRequest();
        final work =
            ChatTurnRunner(
                  container: container,
                  novel: buildTestNovel(),
                  databasePath: null,
                  aiPromptService: AiPromptService(),
                  promptContext: const AiSessionContext(),
                )
                .runTurn(
                  'Write',
                  requestId: request,
                  sessionId: 'parent',
                  userMessageId: 'origin',
                )
                .whenComplete(() => runtime.markRequestIdle(request));
        await child.initializationEntered.future;
        controller.cancel('parent', source: AiChatCancelSource.stopButton);
        final cancelled = session.findToolCallByCallId('stopped_startup')!.$2;
        expect(cancelled.status, AiToolCallStatus.cancelled);
        expect(cancelled.result?['status'], isNot('running'));
        cancelledResult = Map<String, dynamic>.from(cancelled.result!);
        child.initializationRelease.complete();
        await child.requestEntered.future;
        await work;
        originalModelResults = parent.contextManager.messages
            .expand((m) => m.blocks)
            .whereType<ToolResultBlock>()
            .toList();
        addTearDown(() {
          expect(
            parent.contextManager.messages
                .expand((m) => m.blocks)
                .whereType<ToolResultBlock>()
                .toList(),
            originalModelResults,
          );
        });
      });
      try {
        await tester.pumpWidget(
          _wrap(
            container,
            const Locale('en'),
            Consumer(
              builder: (context, ref, _) {
                final messages = ref
                    .watch(aiChatSessionProvider('parent'))
                    .messages;
                final block = messages
                    .expand((m) => m.blocks)
                    .whereType<AiToolCallBlock>()
                    .singleWhere((b) => b.callId == 'stopped_startup');
                return AiToolActivityGroup(blocks: [block]);
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        expect(find.text('Running…'), findsOneWidget);
        expect(find.text('Cancelled'), findsNothing);
        expect(
          session.findToolCallByCallId('stopped_startup')!.$2.result,
          cancelledResult,
        );
        await tester.runAsync(() async {
          child.finish('Child completed after Stop Reply');
          final run = container
              .read(aiChatRuntimeProvider('parent'))
              .subAgents
              .runs
              .single;
          await runtime.subAgents.waitForRun(run.runId);
        });
        await tester.pumpAndSettle();
        expect(find.text('Child completed after Stop Reply'), findsOneWidget);
        expect(find.text('Cancelled'), findsNothing);
        expect(
          session.findToolCallByCallId('stopped_startup')!.$2.result,
          cancelledResult,
        );
        expect(child.releases, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          if (!child.response.isCompleted) {
            child.finish();
          }
          await runtime.subAgents.stopAll(source: 'test_cleanup');
          container.dispose();
          await fixture.dispose();
        });
      }
    },
  );

  testWidgets(
    'live detail reveals current output without claiming completion',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final activity = container.read(
        spawnAgentActiveRunProvider('live_detail').notifier,
      );
      activity.begin('live_run');
      activity.apply(
        const AgentTextDelta('Draft in progress, still being written.'),
        runId: 'live_run',
      );
      await tester.pumpWidget(
        _wrap(
          container,
          const Locale('en'),
          const SpawnAgentDetailButton(
            block: AiToolCallBlock(
              id: 'live',
              callId: 'live_detail',
              toolName: 'SpawnAgent',
              arguments: {'agent': 'Writer', 'name': 'Author'},
              status: AiToolCallStatus.running,
              result: {'session_id': 'child'},
            ),
            novelId: 'novel',
            databasePath: 'memory',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Current output'), findsOneWidget);
      expect(find.text('Final Output'), findsNothing);
      expect(
        find.textContaining('Draft in progress', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      activity.clear(runId: 'live_run');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'history never treats a persisted running receipt as live execution',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDebugModeProvider.overrideWithValue(true),
          mergedSubAgentsProvider.overrideWithValue(const []),
        ],
      );
      addTearDown(container.dispose);
      final original = AiToolCallBlock(
        id: 'receipt',
        callId: 'history',
        toolName: 'SpawnAgent',
        arguments: const {'background': true},
        status: AiToolCallStatus.success,
        result: const {
          'ok': true,
          'status': 'running',
          'run_id': 'old_run',
          'session_id': 'child',
        },
      );
      Widget line(AiToolCallBlock block) => Consumer(
        builder: (context, ref, _) =>
            SpawnAgentActivityLine(block: spawnAgentDisplayBlock(ref, block)),
      );
      await tester.pumpWidget(
        _wrap(container, const Locale('en'), line(original)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not running'), findsOneWidget);
      expect(find.text('Running…'), findsNothing);
      final completed = original.copyWith(
        metadata: const {
          'background_run': {
            'run_id': 'old_run',
            'status': 'completed',
            'result': {'ok': true, 'output': 'Saved chapter\nFull details'},
          },
        },
      );
      await tester.pumpWidget(
        _wrap(container, const Locale('en'), line(completed)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved chapter'), findsOneWidget);
      expect(completed.result, original.result);
      await tester.pumpWidget(
        _wrap(
          container,
          const Locale('en'),
          AiToolActivityGroup(blocks: [original]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not running'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Widget _wrap(ProviderContainer container, Locale locale, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: locale,
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData().copyWith(
              platform: locale.languageCode == 'en'
                  ? TargetPlatform.macOS
                  : TargetPlatform.iOS,
            ),
            builder: (context, child) =>
                RevericTheme(data: RevericThemeData.reveric, child: child!),
            home: Scaffold(
              body: Align(alignment: Alignment.bottomCenter, child: child),
            ),
          ),
        ),
      ),
    );
