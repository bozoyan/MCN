// 职责: AgentMessage / MessageBlock 数据模型测试 — 验证 ImageBlock / ToolResultBlock
// 关联文件:
//   lib/shared/agent/message.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/shared/agent/message.dart';

void main() {
  group('MessageBlock subtypes', () {
    test('TextBlock holds text', () {
      const b = TextBlock('hi');
      expect(b.text, 'hi');
    });

    test('ImageBlock holds data + mimeType', () {
      const b = ImageBlock(data: 'AAA=', mimeType: 'image/png');
      expect(b.data, 'AAA=');
      expect(b.mimeType, 'image/png');
    });

    test('ThinkingBlock holds optional signature/encrypted contents', () {
      const a = ThinkingBlock('reason', signature: 'sig');
      expect(a.text, 'reason');
      expect(a.signature, 'sig');
      expect(a.encryptedContents, isEmpty);

      const b = ThinkingBlock('r2', encryptedContents: ['enc_a', 'enc_b']);
      expect(b.encryptedContents, ['enc_a', 'enc_b']);
    });

    test('ToolCallBlock holds callId, toolName, arguments', () {
      const b = ToolCallBlock(
        callId: 'c1',
        toolName: 'Read',
        arguments: {'path': '/x'},
      );
      expect(b.callId, 'c1');
      expect(b.toolName, 'Read');
      expect(b.arguments, {'path': '/x'});
    });

    test('ToolResultBlock defaults isError to false', () {
      const b = ToolResultBlock(
        toolCallId: 'c1',
        toolName: 'Read',
        content: [TextBlock('ok')],
      );
      expect(b.isError, isFalse);
      expect(b.toolCallId, 'c1');
      expect(b.toolName, 'Read');
      expect(b.content.length, 1);
      expect((b.content.first as TextBlock).text, 'ok');
    });

    test('ToolResultBlock supports mixed text + image content', () {
      const b = ToolResultBlock(
        toolCallId: 'c2',
        toolName: 'Screenshot',
        isError: false,
        content: [
          TextBlock('see attached'),
          ImageBlock(data: 'BBB=', mimeType: 'image/jpeg'),
        ],
      );
      expect(b.content.length, 2);
      expect(b.content[0], isA<TextBlock>());
      expect(b.content[1], isA<ImageBlock>());
    });

    test('ToolResultBlock preserves isError=true', () {
      const b = ToolResultBlock(
        toolCallId: 'c3',
        toolName: 'X',
        isError: true,
        content: [TextBlock('bad')],
      );
      expect(b.isError, isTrue);
    });
  });

  group('AgentMessage', () {
    test('user factory sets role.user', () {
      final m = AgentMessage.user(id: 'u1', content: 'hi');
      expect(m.role, AgentMessageRole.user);
      expect(m.id, 'u1');
      expect(m.content, 'hi');
      expect(m.type, AgentMessageType.text);
      expect(m.blocks, isEmpty);
    });

    test('assistant factory carries blocks', () {
      final m = AgentMessage.assistant(
        id: 'a1',
        content: '',
        blocks: const [TextBlock('out')],
      );
      expect(m.role, AgentMessageRole.assistant);
      expect(m.blocks.length, 1);
    });

    test('system factory sets role.system', () {
      final m = AgentMessage.system(id: 's1', content: 'sys');
      expect(m.role, AgentMessageRole.system);
    });

    test('explicit constructor with tool_result type + ToolResultBlock', () {
      final m = AgentMessage(
        id: 'tool_c1',
        role: AgentMessageRole.user,
        type: AgentMessageType.tool_result,
        blocks: const [
          ToolResultBlock(
            toolCallId: 'c1',
            toolName: 'Read',
            content: [TextBlock('contents')],
          ),
        ],
      );
      expect(m.role, AgentMessageRole.user);
      expect(m.type, AgentMessageType.tool_result);
      expect(m.blocks.first, isA<ToolResultBlock>());
    });

    test('copyWith preserves blocks if not provided', () {
      final m = AgentMessage(
        id: 'a1',
        role: AgentMessageRole.assistant,
        blocks: const [TextBlock('x')],
      );
      final m2 = m.copyWith(content: 'y');
      expect(m2.id, 'a1');
      expect(m2.content, 'y');
      expect(m2.blocks.length, 1);
    });
  });
}
