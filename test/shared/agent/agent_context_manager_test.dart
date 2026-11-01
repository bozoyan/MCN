// 职责: 验证上下文压缩在模型窗口使用到 80% 时触发，避免请求体先超过网关上限
// 关联文件:
//   lib/shared/agent/agent_context_manager.dart
//   lib/shared/models/models_catalog.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/services/ai/spawn_agent_handler.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/agent/token_estimator.dart';
import 'package:reveric/shared/models/models_catalog.dart';

void main() {
  test('unknown models use a 200K default context window', () {
    expect(defaultContextTokenLimit, 200000);
    expect(compactThresholdForContextLimit(defaultContextTokenLimit), 160000);
  });

  test('compacts DeepSeek V4 Flash at 80% of its 1M-token context window', () {
    final contextTokens = lookupCatalogLimit('deepseek-v4-flash')!.context!;

    expect(compactThresholdForContextLimit(contextTokens), 800000);
  });

  test(
    'blank compaction result preserves the complete context snapshot',
    () async {
      final manager = SmartAgentContextManager(compactThreshold: 1)
        ..setMessages([
          AgentMessage.user(id: 'old_user', content: 'old request'),
          AgentMessage.assistant(id: 'old_assistant', content: 'old answer'),
          AgentMessage.user(id: 'current_user', content: 'current request'),
        ])
        ..summarizer =
            ({required messages, previousSummary, cancellationToken}) async =>
                '   ';
      final before = manager.snapshot();

      await expectLater(
        manager.compact(taskText: 'current request'),
        throwsA(isA<StateError>()),
      );

      final after = manager.snapshot();
      expect(after.messages, before.messages);
      expect(after.summary, before.summary);
      expect(after.compactionCount, before.compactionCount);
      expect(manager.shouldCompact(systemPromptTokens: 0), isFalse);

      manager.resetTurnState();
      expect(manager.shouldCompact(systemPromptTokens: 0), isTrue);
    },
  );

  test(
    'summarizer exception preserves messages and compaction count',
    () async {
      final manager = SmartAgentContextManager(compactThreshold: 1)
        ..setMessages([
          AgentMessage.user(id: 'old_user', content: 'old request'),
          AgentMessage.assistant(id: 'old_assistant', content: 'old answer'),
          AgentMessage.user(id: 'current_user', content: 'current request'),
        ])
        ..summarizer =
            ({required messages, previousSummary, cancellationToken}) async {
              throw StateError('provider failed');
            };
      final before = manager.snapshot();

      await expectLater(
        manager.compact(taskText: 'current request'),
        throwsA(isA<StateError>()),
      );

      expect(manager.snapshot().messages, before.messages);
      expect(manager.snapshot().compactionCount, 0);
    },
  );

  test(
    'summarizer receives the full history including retained messages',
    () async {
      final history = [
        AgentMessage.user(
          id: 'very_old_user',
          content: List.filled(30, '旧').join(),
        ),
        AgentMessage.assistant(
          id: 'old_assistant',
          content: List.filled(30, '答').join(),
        ),
        AgentMessage.user(id: 'previous_user', content: '请保留这条用户原文'),
        AgentMessage.assistant(id: 'recent_assistant', content: '回应'),
        AgentMessage.user(id: 'current_user', content: '当前请求'),
      ];
      List<AgentMessage>? seenBySummarizer;
      final manager = SmartAgentContextManager(compactThreshold: 40)
        ..setMessages(history)
        ..summarizer =
            ({required messages, previousSummary, cancellationToken}) async {
              seenBySummarizer = messages;
              return '模型摘要';
            };

      await manager.compact(taskText: '当前请求');

      // Codex 式全量交接：摘要模型看到含保留段在内的完整历史。
      expect(
        seenBySummarizer!.map((message) => message.id),
        history.map((message) => message.id),
      );
      // 落回上下文的仍是摘要 + 保留段，历史总量确实被压缩。
      final rebuilt = await manager.buildMessages();
      expect(rebuilt.first.id, 'ctx_summary');
      expect(rebuilt.last.id, 'current_user');
      expect(rebuilt.length, lessThan(history.length + 1));
    },
  );

  test(
    'loaded supplement does not enter normal messages before compaction',
    () async {
      final manager = SmartAgentContextManager.fromSnapshot(
        snapshot: AgentContextSnapshot(
          summary: 'narrative summary',
          messages: [
            AgentMessage.user(id: 'retained_user', content: 'latest request'),
          ],
        ),
        summaryMaxChars: 8,
        contextSupplementProvider: () async => [
          AgentMessage.user(
            id: 'ctx_todos',
            content: '[当前结构化 Todo 真源]\n${List.filled(9000, 'x').join()}',
          ),
        ],
      );

      await manager.refreshContextSupplement();
      final supplement = manager.contextSupplementMessages;
      final messages = await manager.buildMessages();

      expect(identical(supplement, manager.contextSupplementMessages), isTrue);
      expect(messages.map((message) => message.id), [
        'ctx_summary',
        'retained_user',
      ]);
      expect(
        messages.map((message) => message.content).join('\n'),
        isNot(contains('[当前结构化 Todo 真源]')),
      );
      expect(
        manager.currentTokensEstimate(systemPromptTokens: 0),
        lessThan(2000),
      );
    },
  );

  test(
    'compaction appends compressed user messages before Todo context',
    () async {
      final manager =
          SmartAgentContextManager(
              compactThreshold: 40,
              contextSupplementProvider: () async => [
                AgentMessage.user(
                  id: 'ctx_todos',
                  content: '[当前结构化 Todo 真源]\n[]',
                ),
              ],
            )
            ..setMessages([
              AgentMessage.user(
                id: 'very_old_user',
                content: List.filled(30, '旧').join(),
              ),
              AgentMessage.assistant(
                id: 'old_assistant',
                content: List.filled(30, '答').join(),
              ),
              AgentMessage.user(id: 'previous_user', content: '请保留这条用户原文'),
              AgentMessage.user(
                id: 'runtime_remind',
                content: "<system-remind type='current_workspace_context' />",
              ),
              AgentMessage.assistant(id: 'recent_assistant', content: '回应'),
              AgentMessage.user(id: 'current_user', content: '当前请求'),
            ])
            ..summarizer =
                ({
                  required messages,
                  previousSummary,
                  cancellationToken,
                }) async =>
                    '模型摘要\n\n'
                    '[原始用户消息]\n'
                    '[{"id":"stale","content":"旧原文"}]\n\n'
                    '[当前结构化 Todo 真源]\n[]';

      await manager.compact(taskText: '当前请求');

      final messages = await manager.buildMessages();
      final summary = messages.first.content;
      final narrativeIndex = summary.indexOf('模型摘要');
      final originalIndex = summary.indexOf('[原始用户消息]');
      final todoIndex = summary.indexOf('[当前结构化 Todo 真源]');
      expect(narrativeIndex, greaterThanOrEqualTo(0));
      expect(originalIndex, greaterThan(narrativeIndex));
      expect(todoIndex, greaterThan(originalIndex));
      expect(summary, contains('请保留这条用户原文'));
      expect(summary, isNot(contains('旧原文')));
      expect(summary, isNot(contains("<system-remind type='")));
      expect(summary, isNot(contains('当前请求')));
      expect(messages.map((message) => message.id), [
        'ctx_summary',
        'current_user',
      ]);
    },
  );

  test(
    'keeps complete recent user messages within a 2048 token budget',
    () async {
      final excludedFourth = List.filled(3, '甲').join();
      final includedFirst = List.filled(682, '乙').join();
      final includedSecond = List.filled(682, '丙').join();
      final includedThird = List.filled(682, '丁').join();
      final manager = SmartAgentContextManager(compactThreshold: 1000)
        ..setMessages([
          AgentMessage.user(id: 'excluded_fourth', content: excludedFourth),
          AgentMessage.assistant(id: 'answer_0', content: ''),
          AgentMessage.user(id: 'included_first', content: includedFirst),
          AgentMessage.assistant(id: 'answer_1', content: ''),
          AgentMessage.user(id: 'included_second', content: includedSecond),
          AgentMessage.assistant(id: 'answer_2', content: ''),
          AgentMessage.user(id: 'included_third', content: includedThird),
          AgentMessage.assistant(id: 'answer_3', content: ''),
          AgentMessage.user(id: 'current_user', content: '当'),
        ])
        ..summarizer =
            ({required messages, previousSummary, cancellationToken}) async =>
                '模型摘要';

      await manager.compact(taskText: '当');

      final summary = (await manager.buildMessages()).first.content;
      expect(summary, isNot(contains(excludedFourth)));
      expect(summary, contains(includedFirst));
      expect(summary, contains(includedSecond));
      expect(summary, contains(includedThird));
      expect(summary, isNot(contains('已截断')));
      expect(
        summary.indexOf(includedFirst),
        lessThan(summary.indexOf(includedSecond)),
      );
      expect(
        summary.indexOf(includedSecond),
        lessThan(summary.indexOf(includedThird)),
      );
      expect(
        estimateTextTokens(includedFirst) +
            estimateTextTokens(includedSecond) +
            estimateTextTokens(includedThird),
        2046,
      );
    },
  );

  test('usage baseline stays active with supplement provider and includes '
      'the generated assistant message', () {
    const usage = AiUsage(inputTokens: 120);
    const assistant = AgentMessage(
      id: 'assistant_with_usage',
      role: AgentMessageRole.assistant,
      content: '回答正文',
      blocks: [
        ThinkingBlock('思考内容'),
        ToolCallBlock(
          callId: 'call_1',
          toolName: 'TodoWrite',
          arguments: {'todos': '更新任务'},
        ),
      ],
      usage: usage,
    );
    const toolResult = AgentMessage(
      id: 'tool_result',
      role: AgentMessageRole.user,
      type: AgentMessageType.tool_result,
      blocks: [
        ToolResultBlock(
          toolCallId: 'call_1',
          toolName: 'TodoWrite',
          content: [TextBlock('任务已更新')],
        ),
      ],
    );
    final manager = SmartAgentContextManager.fromSnapshot(
      snapshot: const AgentContextSnapshot(
        summary: '压缩摘要',
        messages: [
          AgentMessage(
            id: 'user_before_usage',
            role: AgentMessageRole.user,
            content: '此前输入',
          ),
          assistant,
          toolResult,
        ],
      ),
      contextSupplementProvider: () async => const [],
    );

    expect(
      manager.currentTokensEstimate(systemPromptTokens: 999),
      usage.inputTokens + estimateAgentMessagesTokens([assistant, toolResult]),
    );
  });

  test('compaction reports tokens on the same basis as the trigger and '
      'records where it happened', () async {
    final history = [
      AgentMessage.user(id: 'old_user', content: List.filled(60, '旧').join()),
      AgentMessage.assistant(
        id: 'old_assistant',
        content: List.filled(60, '答').join(),
      ),
      AgentMessage.user(id: 'current_user', content: '当前请求'),
      AgentMessage.assistant(
        id: 'current_step',
        content: '第一步',
        usage: const AiUsage(inputTokens: 5000),
      ),
    ];
    final manager = SmartAgentContextManager(compactThreshold: 100)
      ..setMessages(history)
      ..summarizer =
          ({required messages, previousSummary, cancellationToken}) async =>
              '摘要';
    final triggerTokens = manager.currentTokensEstimate(
      systemPromptTokens: 300,
    );

    final outcome = await manager.compact(
      taskText: '当前请求',
      systemPromptTokens: 300,
    );

    // 触发基线来自上次真实 usage（含 system prompt 与工具定义），卡片要用同一口径。
    expect(outcome.tokensBefore, triggerTokens);
    final retained = manager.messages;
    final summary = manager.snapshot().summary!;
    expect(
      outcome.tokensBefore - outcome.tokensAfterEstimate,
      estimateAgentMessagesTokens(history) -
          estimateAgentMessagesTokens(retained) -
          estimateTextTokens(summary),
    );

    manager.addMessages([
      AgentMessage.assistant(id: 'after_compaction', content: '第二步'),
    ]);
    expect(manager.snapshot().lastCompactionMessageCount, retained.length);
  });
}
