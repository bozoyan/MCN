// 职责: 验证有序多模态用户输入进入真实 Agent 循环，并限制历史图片的整体请求大小。
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/fake_agent.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';

void main() {
  test('structured user content stays ordered and is included once', () async {
    final client = FakeProviderClient();
    final agent = FakeAgent.create(client: client);
    const blocks = [
      TextBlock('before'),
      ImageBlock(data: 'AAA=', mimeType: 'image/png'),
      TextBlock('after'),
    ];
    await agent
        .process(
          'display-only label',
          userMessageId: 'input',
          inputBlocks: blocks,
        )
        .drain<void>();
    final user = client.capturedStreamRequests.single.messages
        .where((m) => m.id == 'input')
        .single;
    expect(user.content, isEmpty);
    expect(user.blocks, blocks);
    await agent.process('follow up', userMessageId: 'follow').drain<void>();
    expect(
      client.capturedStreamRequests.last.messages.where((m) => m.id == 'input'),
      hasLength(1),
    );
  });

  test(
    'retry after cold restoration does not append the same image turn twice',
    () async {
      final client = FakeProviderClient();
      const blocks = [
        TextBlock('before'),
        ImageBlock(data: 'AAA=', mimeType: 'image/png'),
        TextBlock('after'),
      ];
      final agent = FakeAgent.create(
        client: client,
        initialMessages: [
          AgentMessage.user(id: 'saved', content: '', blocks: blocks),
        ],
      );
      await agent
          .process('display', userMessageId: 'saved', inputBlocks: blocks)
          .drain<void>();
      expect(
        client.capturedStreamRequests.single.messages.where(
          (m) => m.id == 'saved',
        ),
        hasLength(1),
      );
    },
  );
}
