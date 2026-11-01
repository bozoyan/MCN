// 职责: 测试 assistant 消息工具块终态判定 — 对齐 AgentMessageEnd 与工具执行顺序。
// 关联文件:
//   lib/shared/providers/ai_providers.dart
//   lib/desktop/widgets/ai/chat/runtime.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/providers/ai_providers.dart';

void main() {
  group('aiAssistantMessageToolCallsSettled', () {
    test('returns false when message has no tool blocks', () {
      final message = AiMessage.assistant(
        id: 'a1',
        content: '',
        blocks: const [AiThinkingBlock(id: 't1', text: 'plan')],
      );

      expect(aiAssistantMessageToolCallsSettled(message), isFalse);
    });

    test('returns false while any tool call is still running', () {
      final message = AiMessage.assistant(
        id: 'a1',
        content: '',
        isStreaming: true,
        blocks: const [
          AiToolCallBlock(
            id: 'b1',
            callId: 'c1',
            toolName: 'Read',
            arguments: {'path': '/novel'},
            status: AiToolCallStatus.success,
          ),
          AiToolCallBlock(
            id: 'b2',
            callId: 'c2',
            toolName: 'Read',
            arguments: {'path': '/chapters'},
            status: AiToolCallStatus.running,
          ),
        ],
      );

      expect(aiAssistantMessageToolCallsSettled(message), isFalse);
    });

    test('returns true when every tool call block is terminal', () {
      final message = AiMessage.assistant(
        id: 'a1',
        content: '',
        isStreaming: true,
        blocks: const [
          AiToolCallBlock(
            id: 'b1',
            callId: 'c1',
            toolName: 'Read',
            arguments: {'path': '/novel'},
            status: AiToolCallStatus.success,
          ),
        ],
      );

      expect(aiAssistantMessageToolCallsSettled(message), isTrue);
    });
  });
}
