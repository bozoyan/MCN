// 职责: 测试下一步建议进模型上下文 — tool_use/tool_result 成对保留，UI 投影块不重复进上下文。
// 关联文件:
//   lib/shared/services/ai/agent_message_mapping.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/services/ai/tools.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/tools.dart'
    show suggestNextActionToolName;

void main() {
  group('SuggestNextAction 上下文', () {
    test('tool_use 与 tool_result 成对保留，模型看得见自己挂过什么', () {
      final message = AiMessage.assistant(
        id: 'assistant_1',
        content: '这一章写完了。',
        blocks: const [
          AiToolCallBlock(
            id: 'block_suggest_1',
            callId: 'call_suggest_1',
            toolName: suggestNextActionToolName,
            arguments: {
              'suggestions': [
                {'kind': 'prompt', 'label': '核对时间线', 'prompt': '核对第 3 章'},
              ],
            },
            status: AiToolCallStatus.success,
            result: {'ok': true},
          ),
          AiSuggestNextActionBlock(
            id: 'suggest_call_suggest_1',
            callId: 'call_suggest_1',
            suggestions: [
              {
                'id': 's0',
                'kind': 'prompt',
                'label': '核对时间线',
                'prompt': '核对第 3 章',
              },
            ],
          ),
        ],
      );

      final converted = convertAiMessageToAgentMessagesForModel(message);

      final toolCalls = converted
          .expand((m) => m.blocks)
          .whereType<ToolCallBlock>()
          .toList();
      final toolResultIds = converted
          .expand((m) => m.blocks)
          .whereType<ToolResultBlock>()
          .map((b) => b.toolCallId)
          .toList();

      expect(toolCalls.map((b) => b.callId), ['call_suggest_1']);
      expect(
        toolCalls.single.toolName,
        suggestNextActionToolName,
        reason: '与其他工具一视同仁地进上下文',
      );
      expect(toolResultIds, [
        'call_suggest_1',
      ], reason: 'tool_result 必须与 tool_use 成对，否则 API 报孤儿 tool_use');
      // 正文仍然进上下文。
      expect(converted.first.content, '这一章写完了。');
    });

    test('AiSuggestNextActionBlock 是 UI 投影，不重复进上下文', () {
      final message = AiMessage.assistant(
        id: 'assistant_2',
        content: '',
        blocks: const [
          AiSuggestNextActionBlock(
            id: 'suggest_orphan',
            callId: 'call_orphan',
            suggestions: [
              {
                'id': 's0',
                'kind': 'prompt',
                'label': '核对时间线',
                'prompt': '核对第 3 章',
              },
            ],
          ),
        ],
      );

      final converted = convertAiMessageToAgentMessagesForModel(message);

      expect(
        converted.expand((m) => m.blocks),
        isEmpty,
        reason: '裁决后的展示块与 tool_use 内容重复，只留 tool_use 一份',
      );
    });
  });
}
