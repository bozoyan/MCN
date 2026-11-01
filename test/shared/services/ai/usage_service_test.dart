// 职责: 验证 UsageService 的来源归一化、入口分类与父子会话聚合语义。
// 关联文件:
//   lib/shared/services/ai/usage_service.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/providers/usage_query_providers.dart
//   lib/shared/database/app_database.dart

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/providers/usage_query_providers.dart';
import 'package:reveric/shared/services/ai/usage_service.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';

void main() {
  late AppDatabase database;
  late AiSessionPersistenceService persistence;
  late UsageService usage;

  setUp(() async {
    database = AppDatabase.forTest(NativeDatabase.memory());
    persistence = AiSessionPersistenceService(database, 'novel_1');
    usage = UsageService(appDatabase: database);

    await persistence.createActiveSession(
      id: 'parent',
      title: 'Parent session',
      provider: 'provider_main',
      model: 'model_main',
      mode: AiSessionMode.chat.value,
      agentSlug: 'orchestrator',
    );
    await persistence.createActiveSession(
      id: 'child',
      title: 'Reviewer',
      provider: 'provider_sub',
      model: 'model_sub',
      mode: AiSessionMode.chat.value,
      agentSlug: 'reviewer',
      parentId: 'parent',
    );
  });

  tearDown(() => database.close());

  test('calendar month filter stays stable across rebuild timestamps', () {
    final firstBuild = UsageFilter.calendarMonth(DateTime(2026, 8, 1, 9, 30));
    final laterBuild = UsageFilter.calendarMonth(DateTime(2026, 8, 31, 23, 30));

    expect(laterBuild, firstBuild);
    expect(laterBuild.hashCode, firstBuild.hashCode);
    expect(
      topUsageSessionsProvider(laterBuild),
      topUsageSessionsProvider(firstBuild),
    );
    expect(firstBuild.startDate, DateTime(2026, 8));
    expect(firstBuild.endDate, DateTime(2026, 8, 31, 23, 59, 59));
  });

  test(
    'sorts sessions by conversation time by default and supports usage sort',
    () async {
      await persistence.createActiveSession(
        id: 'recent',
        title: 'Recent session',
        provider: 'provider_main',
        model: 'model_main',
        mode: AiSessionMode.chat.value,
        agentSlug: 'orchestrator',
      );
      await database
          .into(database.aiUsages)
          .insert(
            AiUsagesCompanion.insert(
              id: 'usage_parent',
              providerId: 'provider_main',
              model: 'model_main',

              sessionId: const Value('parent'),
              inputTokens: const Value(100),
              outputTokens: const Value(20),
              createdAt: Value(DateTime(2026, 8, 2, 10)),
            ),
          );
      await database
          .into(database.aiUsages)
          .insert(
            AiUsagesCompanion.insert(
              id: 'usage_recent',
              providerId: 'provider_main',
              model: 'model_main',

              sessionId: const Value('recent'),
              inputTokens: const Value(10),
              outputTokens: const Value(10),
              createdAt: Value(DateTime(2026, 8, 3, 10)),
            ),
          );

      final byTime = await usage.getTopSessions(
        UsageFilter.calendarMonth(DateTime(2026, 8, 4)),
      );
      final byUsage = await usage.getTopSessions(
        UsageFilter.calendarMonth(
          DateTime(2026, 8, 4),
          sessionSort: UsageSessionSort.total_tokens_descending,
        ),
      );

      expect(byTime.map((session) => session.id), ['recent', 'parent']);
      expect(byUsage.map((session) => session.id), ['parent', 'recent']);
    },
  );

  test('groups usage rows by their exact source value', () async {
    await usage.recordUsage(
      providerId: 'provider_main',
      model: 'model_main',
      usage: const AiUsage(inputTokens: 100, outputTokens: 20),
      sessionId: 'parent',
      source: UsageSources.chat,
    );
    await usage.recordUsage(
      providerId: 'provider_main',
      model: 'model_main',
      usage: const AiUsage(inputTokens: 50, outputTokens: 10),
      sessionId: 'parent',
      source: UsageSources.roleplay,
    );

    final sources = await usage.getSourceUsage(const UsageFilter());

    expect(
      sources.map((item) => item.source),
      containsAll([UsageSources.chat, UsageSources.roleplay]),
    );
    expect(
      sources
          .singleWhere((item) => item.source == UsageSources.chat)
          .totalTokens,
      120,
    );
  });

  test('merges Assistant and Chat usage into one session list', () async {
    await database
        .into(database.assistantSessions)
        .insert(
          AssistantSessionsCompanion.insert(
            id: 'assistant_1',
            chatId: 'writer@example.com',
            channelType: 'wechat',
            provider: const Value('provider_assistant'),
            model: const Value('model_assistant'),
          ),
        );
    await persistence.createActiveSession(
      id: 'chat_session',
      title: 'Polish draft / Rewrite',
      provider: 'provider_chat',
      model: 'model_chat',
      mode: AiSessionMode.chat.value,
      agentSlug: 'chat_writer',
    );
    await usage.recordUsage(
      providerId: 'provider_assistant',
      model: 'model_assistant',
      usage: const AiUsage(inputTokens: 30, outputTokens: 10),
      sessionId: 'assistant_1',
      source: UsageSources.assistant,
    );
    await usage.recordUsage(
      providerId: 'provider_chat',
      model: 'model_chat',
      usage: const AiUsage(inputTokens: 80, outputTokens: 20),
      sessionId: 'chat_session',
      source: UsageSources.chat,
    );

    final sessions = await usage.getTopSessions(const UsageFilter());
    final sources = await usage.getSourceUsage(const UsageFilter());
    final dailySources = await usage.getDailySourceUsage(const UsageFilter());
    final assistantDetail = await usage.getSessionDetail('assistant_1');

    expect(
      sessions.map((session) => session.id),
      containsAll(<String>['assistant_1', 'chat_session']),
    );
    expect(
      sessions.singleWhere((session) => session.id == 'assistant_1').title,
      'writer@example.com',
    );
    expect(
      sessions.singleWhere((session) => session.id == 'assistant_1').mode,
      UsageSources.assistant,
    );
    expect(
      sessions.singleWhere((session) => session.id == 'chat_session').title,
      'Polish draft / Rewrite',
    );
    expect(
      sessions.singleWhere((session) => session.id == 'chat_session').mode,
      UsageSources.chat,
    );
    expect(
      sources.map((item) => item.source),
      containsAll([UsageSources.assistant, UsageSources.chat]),
    );
    expect(dailySources, hasLength(1));
    expect(dailySources.single.tokensBySource[UsageSources.assistant], 40);
    expect(dailySources.single.tokensBySource[UsageSources.chat], 100);
    expect(assistantDetail?.session.title, 'writer@example.com');
    expect(assistantDetail?.session.provider, 'provider_assistant');
    expect(assistantDetail?.session.model, 'model_assistant');
    expect(assistantDetail?.session.mode, UsageSources.assistant);
  });

  test(
    'attributes child usage, keeps run detail, and excludes cache from display totals',
    () async {
      await usage.recordUsage(
        providerId: 'provider_main',
        model: 'model_main',
        usage: const AiUsage(inputTokens: 100, outputTokens: 20),
        sessionId: 'parent',
        source: UsageSources.chat,
      );
      await usage.recordUsage(
        providerId: 'provider_sub',
        model: 'model_sub',
        usage: const AiUsage(
          inputTokens: 80,
          outputTokens: 10,
          cacheReadTokens: 30,
        ),
        sessionId: 'child',
        source: UsageSources.chat,
        runId: 'run_1',
        runLabel: 'Review chapter 1',
      );

      final sessions = await usage.getTopSessions(const UsageFilter());
      final detail = await usage.getSessionDetail('parent');
      final meter = await usage.watchSessionMeter('parent').first;
      final daily = await usage.getDailyUsage(const UsageFilter());

      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'parent');
      expect(sessions.single.totalTokens, 180);
      expect(detail, isNotNull);
      expect(detail!.mainTokens, 120);
      expect(detail.tokens.totalCacheReadTokens, 30);
      expect(detail.tokens.totalTokens, 180);
      expect(daily.single.cacheReadTokens, 30);
      expect(daily.single.totalTokens, 180);
      expect(detail.subagents, hasLength(1));
      expect(detail.subagents.single.sessionId, 'child');
      expect(detail.subagents.single.displayName, 'Reviewer');
      expect(detail.subagents.single.provider, 'provider_sub');
      expect(detail.subagents.single.model, 'model_sub');
      expect(detail.subagents.single.totalTokens, 60);
      expect(detail.subagents.single.runs, hasLength(1));
      expect(detail.subagents.single.runs.single.id, 'run_1');
      expect(detail.subagents.single.runs.single.label, 'Review chapter 1');
      expect(meter?.totalTokens, 180);
      expect(meter?.contextInputTokens, 100);
      expect(meter?.model, 'model_main');
    },
  );
}
