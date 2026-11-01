// 职责: 测试 SubAgent 落库前 tool_result 合并 — 避免 assistant 过程轮次被过滤。
// 关联文件:
//   lib/shared/services/ai/session_persistence.dart
//   lib/desktop/widgets/ai/chat/agent_factory.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';

void main() {
  test(
    'persistence and restored model history agree on legacy result status',
    () {
      for (final scenario in <(Map<String, dynamic>, AiToolCallStatus)>[
        ({'updated': false}, AiToolCallStatus.success),
        (
          {
            'value': {'ok': false, 'error': 'body'},
          },
          AiToolCallStatus.success,
        ),
        ({'error': 'failed'}, AiToolCallStatus.error),
        ({'ok': false}, AiToolCallStatus.error),
        ({'cancelled': true}, AiToolCallStatus.cancelled),
        ({'skipped': true}, AiToolCallStatus.cancelled),
      ]) {
        final finalized = finalizeAiMessagesToolCallsForPersistence([
          AiMessage.assistant(
            id: 'a',
            content: '',
            blocks: const [
              AiToolCallBlock(
                id: 'b',
                callId: 'c',
                toolName: 'Write',
                arguments: {'path': 'chapters/id/title'},
                status: AiToolCallStatus.running,
              ),
            ],
          ),
          AiMessage(
            id: 'r',
            role: AiMessageRole.user,
            type: AiMessageType.tool_result,
            content: jsonEncode(scenario.$1),
            timestamp: DateTime(2026),
            metadata: const {'tool_call_id': 'c'},
          ),
        ]);
        final block = finalized.single.blocks
            .whereType<AiToolCallBlock>()
            .single;
        expect(block.status, scenario.$2, reason: '${scenario.$1}');
        expect(block.result, isNotNull);
        expect(block.result!['ok'], scenario.$2 == AiToolCallStatus.success);
      }
    },
  );

  group('finalizeAiMessagesToolCallsForPersistence', () {
    test(
      'merges tool_result into assistant blocks so rounds stay persistable',
      () {
        final messages = [
          AiMessage.user(id: 'user_1', content: 'review opening'),
          AiMessage.assistant(
            id: 'assistant_1',
            content: '',
            blocks: const [
              AiThinkingBlock(id: 'think_1', text: 'check rules'),
              AiToolCallBlock(
                id: 'block_c1',
                callId: 'call_1',
                toolName: 'Read',
                arguments: {'path': '/novel'},
                status: AiToolCallStatus.running,
              ),
            ],
          ),
          AiMessage(
            id: 'tool_1',
            role: AiMessageRole.user,
            type: AiMessageType.tool_result,
            content: '{"ok":true,"output":"chapter text"}',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1),
            metadata: const {
              'tool_call_id': 'call_1',
              'tool_name': 'Read',
              'is_error': false,
            },
          ),
          AiMessage.assistant(id: 'assistant_2', content: '审查报告…'),
        ];

        final finalized = finalizeAiMessagesToolCallsForPersistence(messages);

        expect(
          finalized.any((message) => message.type == AiMessageType.tool_result),
          isFalse,
        );
        final roundOne = finalized.firstWhere(
          (message) => message.id == 'assistant_1',
        );
        expect(aiAssistantMessageToolCallsSettled(roundOne), isTrue);
        final tool = roundOne.blocks.whereType<AiToolCallBlock>().single;
        expect(tool.status, AiToolCallStatus.success);
        expect(tool.result?['output'], 'chapter text');
        expect(finalized.any((message) => message.id == 'assistant_2'), isTrue);
      },
    );
  });
}
