// 职责: 测试压缩摘要插入位置 — retained 从尾部对齐，避免插到 overflow / 向导流程里
// 关联文件:
//   lib/shared/services/ai/context_message_matcher.dart
//   lib/shared/services/ai/agent_message_mapping.dart
//   lib/shared/agent/message.dart
//   lib/shared/models/ai_chat_models.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/context_message_matcher.dart';

void main() {
  group('sameContextMessage', () {
    test('matches tool_result by tool_call_id, not by type alone', () {
      final setupResult = _uiToolResult(
        id: 'ui_setup',
        callId: 'call_setup',
        content: '{"ok":true,"content":"<agent_skill>创作向导</agent_skill>"}',
      );
      final writeResult = _agentToolResult(
        id: 'agent_write',
        callId: 'call_write',
        content: '{"ok":true,"path":"/profile/title"}',
      );

      expect(sameContextMessage(setupResult, writeResult), isFalse);
      expect(
        sameContextMessage(
          _uiToolResult(
            id: 'ui_write',
            callId: 'call_write',
            content: '{"ok":true,"path":"/profile/title"}',
          ),
          writeResult,
        ),
        isTrue,
      );
    });
  });

  group('resolveCompactionInsertIndex', () {
    test(
      'does not insert before an earlier tool_result with a different call id',
      () {
        final uiMessages = [
          AiMessage.user(id: 'kickoff', content: '倾向于写一篇大女主倾向的长篇文'),
          AiMessage.assistant(id: 'load_setup', content: '加载创作向导'),
          _uiToolResult(
            id: 'setup_skill',
            callId: 'call_setup',
            content: '{"ok":true,"content":"<agent_skill>创作向导</agent_skill>"}',
          ),
          AiMessage.user(id: 'later_user', content: '继续写第 15 章'),
          AiMessage.assistant(id: 'write_ch15', content: '写入第 15 章'),
          _uiToolResult(
            id: 'write_result',
            callId: 'call_write',
            content: '{"edited":true}',
          ),
        ];
        final retained = [
          AgentMessage.user(id: 'agent_later_user', content: '继续写第 15 章'),
          AgentMessage.assistant(id: 'agent_write_ch15', content: '写入第 15 章'),
          _agentToolResult(
            id: 'agent_write',
            callId: 'call_write',
            content: '{"edited":true}',
          ),
        ];

        expect(
          resolveCompactionInsertIndex(
            uiMessages: uiMessages,
            retainedMessages: retained,
            sessionId: 'sess',
          ),
          uiMessages.indexWhere((message) => message.id == 'later_user'),
        );
      },
    );

    test(
      'aligns duplicate user text to the retained suffix, not the first hit',
      () {
        final uiMessages = [
          AiMessage.user(id: 'kickoff', content: '开书'),
          AiMessage.assistant(id: 'setup', content: '开始向导'),
          AiMessage.user(id: 'continue_early', content: '继续'),
          AiMessage.assistant(id: 'mid', content: '写到第 4 章'),
          AiMessage.user(id: 'continue_late', content: '继续'),
          AiMessage.assistant(id: 'recent', content: '写第 15 章'),
        ];
        final retained = [
          AgentMessage.user(id: 'agent_continue', content: '继续'),
          AgentMessage.assistant(id: 'agent_recent', content: '写第 15 章'),
        ];

        expect(
          resolveCompactionInsertIndex(
            uiMessages: uiMessages,
            retainedMessages: retained,
            sessionId: 'sess',
          ),
          uiMessages.indexWhere((message) => message.id == 'continue_late'),
        );
      },
    );

    test('does not match an empty wizard assistant as the retained cut', () {
      final uiMessages = [
        AiMessage.user(id: 'kickoff', content: '开书'),
        AiMessage.assistant(id: 'setup_call', content: ''),
        _uiToolResult(
          id: 'setup_skill',
          callId: 'call_setup',
          content: '{"ok":true}',
        ),
        AiMessage.user(id: 'later_user', content: '现在整理吧'),
        AiMessage.assistant(id: 'recent_call', content: ''),
        _uiToolResult(
          id: 'recent_result',
          callId: 'call_recent',
          content: '{"ok":true}',
        ),
      ];
      final retained = [
        AgentMessage.user(id: 'agent_later', content: '现在整理吧'),
        AgentMessage.assistant(id: 'agent_recent_call', content: ''),
        _agentToolResult(
          id: 'agent_recent',
          callId: 'call_recent',
          content: '{"ok":true}',
        ),
      ];

      expect(
        resolveCompactionInsertIndex(
          uiMessages: uiMessages,
          retainedMessages: retained,
          sessionId: 'sess',
        ),
        uiMessages.indexWhere((message) => message.id == 'later_user'),
      );
    });

    test('replay window after insert drops overflow including setup skill', () {
      final uiMessages = [
        AiMessage.user(id: 'kickoff', content: '倾向于写一篇大女主倾向的长篇文'),
        AiMessage.assistant(id: 'load_setup', content: '加载创作向导'),
        _uiToolResult(
          id: 'setup_skill',
          callId: 'call_setup',
          content: '{"ok":true,"content":"<agent_skill>创作向导</agent_skill>"}',
        ),
        AiMessage.user(id: 'continue_early', content: '继续'),
        AiMessage.assistant(id: 'mid', content: '写到第 4 章'),
        AiMessage.user(id: 'continue_late', content: '继续'),
        AiMessage.assistant(id: 'recent', content: '写第 15 章'),
      ];
      final retained = [
        AgentMessage.user(id: 'agent_continue', content: '继续'),
        AgentMessage.assistant(id: 'agent_recent', content: '写第 15 章'),
      ];
      final placement = resolveCompactSummaryPlacement(
        uiMessages: uiMessages,
        retainedMessages: retained,
        sessionId: 'sess',
      );
      expect(placement, isNotNull);
      expect(placement!.replayFromMessageId, 'continue_late');
      final persisted = [...uiMessages]
        ..insert(
          placement.insertIndex,
          AiMessage.user(
            id: compactSummaryMessageId('sess', 1),
            content: '已完成：初始化引导',
            type: AiMessageType.compact_summary,
            metadata: buildCompactSummaryMetadata(
              compactionCount: 1,
              replayFromMessageId: placement.replayFromMessageId,
            ),
          ),
        );
      final replay = messagesSinceLatestCompact(persisted);

      expect(replay.map((message) => message.id), [
        compactSummaryMessageId('sess', 1),
        'continue_late',
        'recent',
      ]);
      expect(replay.any((message) => message.id == 'setup_skill'), isFalse);
      expect(replay.any((message) => message.id == 'load_setup'), isFalse);
    });
  });

  group('resolveCompactSummaryPlacement', () {
    test('uses the shared user message id, not the first matching text', () {
      final uiMessages = [
        AiMessage.user(id: 'kickoff', content: '开书'),
        AiMessage.assistant(id: 'setup', content: '开始向导'),
        AiMessage.user(id: 'continue_early', content: '继续'),
        AiMessage.assistant(id: 'mid', content: '写到第 4 章'),
        AiMessage.user(id: 'continue_late', content: '继续'),
        AiMessage.assistant(id: 'recent', content: '写第 15 章'),
      ];
      final retained = [
        AgentMessage.user(id: 'continue_late', content: '继续'),
        AgentMessage.assistant(id: 'asst_recent', content: '写第 15 章'),
      ];

      final placement = resolveCompactSummaryPlacement(
        uiMessages: uiMessages,
        retainedMessages: retained,
        sessionId: 'sess',
      );

      expect(placement?.replayFromMessageId, 'continue_late');
      expect(
        placement?.insertIndex,
        uiMessages.indexWhere((message) => message.id == 'continue_late'),
      );
    });

    test(
      'ignores a colliding id with a different role and falls back to content',
      () {
        final uiMessages = [
          AiMessage.user(id: 'continue_early', content: '继续'),
          AiMessage.assistant(id: 'mid', content: '写到第 4 章'),
          AiMessage.assistant(id: 'continue_late', content: '写第 15 章'),
        ];
        final retained = [
          AgentMessage.user(id: 'continue_late', content: '继续'),
          AgentMessage.assistant(id: 'asst_recent', content: '写第 15 章'),
        ];

        final placement = resolveCompactSummaryPlacement(
          uiMessages: uiMessages,
          retainedMessages: retained,
          sessionId: 'sess',
        );

        expect(placement?.replayFromMessageId, 'continue_early');
        expect(
          placement?.insertIndex,
          uiMessages.indexWhere((message) => message.id == 'continue_early'),
        );
      },
    );

    test('ignores a colliding id when only one side is a tool_result', () {
      final uiMessages = [AiMessage.user(id: 'tool_1', content: 'hello')];
      final retained = [
        _agentToolResult(
          id: 'tool_1',
          callId: 'call_write',
          content: '{"edited":true}',
        ),
      ];

      expect(
        resolveCompactSummaryPlacement(
          uiMessages: uiMessages,
          retainedMessages: retained,
          sessionId: 'sess',
        ),
        isNull,
      );
    });

    test('skips compaction restate messages that are not in the UI list', () {
      final uiMessages = [
        AiMessage.user(id: 'continue_early', content: '继续'),
        AiMessage.assistant(id: 'mid', content: '写到第 4 章'),
        AiMessage.user(id: 'continue_late', content: '继续'),
        AiMessage.assistant(id: 'recent', content: '写第 15 章'),
      ];
      final retained = [
        AgentMessage.user(id: 'ctx_restate_1', content: '[用户当前指令原文] 继续'),
        AgentMessage.user(id: 'continue_late', content: '继续'),
        AgentMessage.assistant(id: 'asst_recent', content: '写第 15 章'),
      ];

      expect(
        resolveCompactSummaryPlacement(
          uiMessages: uiMessages,
          retainedMessages: retained,
          sessionId: 'sess',
        )?.replayFromMessageId,
        'continue_late',
      );
    });

    test(
      'inserts a mid-turn summary before the streaming tail, so rolling back '
      'the turn drops it',
      () {
        final uiMessages = [
          AiMessage.user(id: 'old_user', content: '重写第一集'),
          AiMessage.assistant(id: 'old_answer', content: '已重写'),
          AiMessage.user(id: 'current_user', content: '开始准备画布'),
          AiMessage.assistant(id: 'step_before', content: '补全了 22 个节点'),
          AiMessage.assistant(id: 'streaming', content: '', isStreaming: true),
        ];
        final retained = [
          AgentMessage.user(id: 'current_user', content: '开始准备画布'),
          AgentMessage.assistant(id: 'asst_step', content: '补全了 22 个节点'),
        ];

        final placement = resolveCompactSummaryPlacement(
          uiMessages: uiMessages,
          retainedMessages: retained,
          sessionId: 'sess',
          compactedMessageCount: retained.length,
        )!;

        expect(placement.replayFromMessageId, 'current_user');
        expect(placement.insertIndex, 4);

        final withSummary = [...uiMessages]
          ..insert(
            placement.insertIndex,
            AiMessage.user(
              id: 'ctx_summary_sess_1',
              content: '已补全 22 个节点',
              type: AiMessageType.compact_summary,
              metadata: buildCompactSummaryMetadata(
                compactionCount: 1,
                replayFromMessageId: placement.replayFromMessageId,
              ),
            ),
          );
        final rolledBack = withSummary.sublist(
          0,
          withSummary.indexWhere((message) => message.id == 'current_user'),
        );
        expect(
          rolledBack.any(
            (message) => message.type == AiMessageType.compact_summary,
          ),
          isFalse,
          reason: 'The summary describes work done in the rolled-back turn.',
        );
      },
    );

    test(
      'inserts before the first message produced after compaction when '
      'persisted later',
      () {
        final uiMessages = [
          AiMessage.user(id: 'old_user', content: '重写第一集'),
          AiMessage.user(id: 'current_user', content: '开始准备画布'),
          AiMessage.assistant(id: 'step_before', content: '补全了 22 个节点'),
          AiMessage.assistant(id: 'step_after', content: '整理布局'),
          AiMessage.assistant(id: 'final', content: '画布已整理完成'),
        ];
        final retained = [
          AgentMessage.user(id: 'current_user', content: '开始准备画布'),
          AgentMessage.assistant(id: 'asst_before', content: '补全了 22 个节点'),
          AgentMessage.assistant(id: 'asst_after', content: '整理布局'),
          AgentMessage.assistant(id: 'asst_final', content: '画布已整理完成'),
        ];

        final placement = resolveCompactSummaryPlacement(
          uiMessages: uiMessages,
          retainedMessages: retained,
          sessionId: 'sess',
          compactedMessageCount: 2,
        );

        expect(placement?.replayFromMessageId, 'current_user');
        expect(
          placement?.insertIndex,
          uiMessages.indexWhere((message) => message.id == 'step_after'),
        );
      },
    );
  });
}

AiMessage _uiToolResult({
  required String id,
  required String callId,
  required String content,
}) {
  return AiMessage.user(
    id: id,
    content: content,
    type: AiMessageType.tool_result,
    metadata: {'tool_call_id': callId},
  );
}

AgentMessage _agentToolResult({
  required String id,
  required String callId,
  required String content,
}) {
  return AgentMessage(
    id: id,
    role: AgentMessageRole.user,
    type: AgentMessageType.tool_result,
    blocks: [
      ToolResultBlock(
        toolCallId: callId,
        toolName: 'Write',
        content: [TextBlock(content)],
      ),
    ],
  );
}
