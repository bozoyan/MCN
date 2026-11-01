// 职责: 验证嵌套调用有界落库、旧记录兼容及模型历史不重放子调用。
// 关联文件:
//   lib/shared/models/ai_nested_tool_call.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/services/ai/agent_message_mapping.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/services/ai/context_message_matcher.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/database/type_converters.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/context_message_matcher.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';

void main() {
  const converter = AiMessageBlockListConverter();
  const child = AiNestedToolCall(
    callId: 'child',
    toolName: 'Write',
    targetPath: 'chapters/id/title',
    argumentsPreview: 'PRIVATE_ARGUMENTS',
    resultPreview: 'PRIVATE_BODY',
    status: AiNestedToolStatus.success,
    effectStatus: AiToolEffectStatus.confirmed,
    resourceId: 'resource',
    workingChangeId: 'change',
    workingChangeScope: AiWorkingChangeScope(
      sourceSessionId: 'session',
      sourceTurnId: 'turn',
      resourcePath: 'chapters/id',
    ),
    hasMultipleWorkingChanges: true,
    durationMs: 12,
  );
  const parent = AiToolCallBlock(
    id: 'block',
    callId: 'parent',
    toolName: 'Codemode',
    arguments: {'code': 'return "summary";'},
    status: AiToolCallStatus.success,
    result: {
      'ok': true,
      'output': ['summary'],
    },
    nestedCalls: [child],
  );

  test(
    'old messages default to no children and real converter preserves identities',
    () {
      final legacy = Map<String, dynamic>.from(parent.toJson())
        ..remove('nested_calls');
      expect(AiToolCallBlock.fromJson(legacy).nestedCalls, isEmpty);
      final restored =
          converter.fromSql(converter.toSql([parent])).single
              as AiToolCallBlock;
      expect(restored.callId, 'parent');
      expect(restored.nestedCalls.single.toJson(), child.toJson());
      expect(
        restored
            .copyWith(status: AiToolCallStatus.cancelled)
            .nestedCalls
            .single
            .workingChangeId,
        'change',
      );
    },
  );

  test(
    'warm, restored, model-switch and compact history contain only the parent',
    () {
      final persisted = converter.fromSql(converter.toSql([parent]));
      final message = AiMessage.assistant(
        id: 'assistant',
        content: '',
        blocks: persisted,
      );
      final scenarios = [
        [message],
        stripProviderPrivateConversationState([message]),
        restorePersistedChatContext([
          AiMessage.user(id: 'old', content: 'old'),
          AiMessage.user(
            id: 'compact',
            content: 'summary',
            type: AiMessageType.compact_summary,
            metadata: buildCompactSummaryMetadata(
              compactionCount: 1,
              replayFromMessageId: message.id,
            ),
          ),
          message,
        ]).retainedMessages,
      ];
      for (final messages in scenarios) {
        final history = messages
            .expand(convertAiMessageToAgentMessagesForModel)
            .toList();
        final blocks = history.expand((message) => message.blocks).toList();
        expect(blocks.whereType<ToolCallBlock>().map((call) => call.callId), [
          'parent',
        ]);
        expect(
          blocks.whereType<ToolResultBlock>().map((call) => call.toolCallId),
          ['parent'],
        );
        final output =
            (blocks.whereType<ToolResultBlock>().single.content.single
                    as TextBlock)
                .text;
        expect(output, contains('summary'));
        expect(output, isNot(contains('PRIVATE')));
        expect(output, isNot(contains('nested_calls')));
      }
    },
  );

  test(
    'terminal parent settles running children but preserves completed write facts',
    () {
      final running = parent.copyWith(
        nestedCalls: [
          child,
          const AiNestedToolCall(
            callId: 'in-flight',
            toolName: 'Edit',
            effectStatus: AiToolEffectStatus.unknown,
          ),
        ],
      );
      final restored = AiToolCallBlock.fromJson(
        running.copyWith(status: AiToolCallStatus.cancelled).toJson(),
      );
      expect(
        restored.nestedCalls.first.effectStatus,
        AiToolEffectStatus.confirmed,
      );
      expect(restored.nestedCalls.first.status, AiNestedToolStatus.success);
      expect(restored.nestedCalls.last.status, AiNestedToolStatus.cancelled);
      expect(
        restored.nestedCalls.last.effectStatus,
        AiToolEffectStatus.unknown,
      );

      final merged = finalizeAiMessagesToolCallsForPersistence([
        AiMessage.assistant(
          id: 'a',
          content: '',
          blocks: [running.copyWith(status: AiToolCallStatus.running)],
        ),
        AiMessage.user(
          id: 'r',
          content: '{"ok":false,"cancelled":true}',
          type: AiMessageType.tool_result,
          metadata: const {'tool_call_id': 'parent'},
        ),
      ]);
      final block = merged.single.blocks.single as AiToolCallBlock;
      expect(block.nestedCalls.last.status, AiNestedToolStatus.cancelled);
      expect(block.nestedCalls.first.workingChangeId, 'change');
    },
  );
}
