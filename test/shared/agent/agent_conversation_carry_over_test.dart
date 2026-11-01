// 职责: 验证 Agent.conversation 能把含工具结果的上下文交给新建 Agent 继续使用
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/fake_agent.dart
//   lib/shared/services/ai/agent_council_orchestrator.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';

// Council 追加一轮不再复用 Agent 实例（它持有的 ProviderClient 绑定在上一次运行
// 借用的 http client 上，租约释放后就用不了），改为把 conversation 传给新建的
// Agent。本测试钉住这个交接：上一轮读到的工具结果必须出现在下一轮的请求里，
// 否则参与者只能把作品概览、设定重新读一遍。
const _settingDoc = 'SETTING_DOC_MARKER: 全息网游的解密规则';

String _describeBlock(MessageBlock block) {
  return switch (block) {
    TextBlock(:final text) => text,
    ThinkingBlock(:final text) => text,
    ToolCallBlock(:final toolName, :final arguments) => '$toolName($arguments)',
    ToolResultBlock(:final toolName, :final content) =>
      '$toolName->${content.map(_describeBlock).join()}',
    ImageBlock() => '<image>',
  };
}

String _flatten(List<AgentMessage> messages) {
  return messages
      .map(
        (m) => '${m.role.name}:${m.type.name}:${m.content}'
            '${m.blocks.map(_describeBlock).join('|')}',
      )
      .join('\n');
}

Future<void> _drain(Agent agent, String task) async {
  await agent.process(task).drain<void>();
}

void main() {
  test('conversation carries tool results into a freshly built agent', () async {
    final dispatcher = FakeAgentToolDispatcher.withResults(
      results: {
        'read': {'content': _settingDoc},
      },
    );

    final firstAgent = FakeAgent.create(
      id: 'worldbuilder',
      toolManager: dispatcher,
      allowedTools: const ['read'],
      responses: const [
        FakeProviderClientResponse.toolCalls([
          ToolCall(callId: 'c1', toolName: 'read', arguments: {'path': '/设定'}),
        ]),
        FakeProviderClientResponse.text('第一轮结论'),
      ],
    );
    await _drain(firstAgent, '第 1 轮任务');

    expect(dispatcher.capturedCalls.length, 1);
    final carried = firstAgent.conversation;
    expect(_flatten(carried), contains(_settingDoc));
    // system 不随上下文传递，由下一个 Agent 的 systemPrompt 重建。
    expect(carried.any((m) => m.role == AgentMessageRole.system), isFalse);

    // 下一轮：全新的 client（模拟上一轮租约已释放），只带上下文。
    final secondClient = FakeProviderClient(
      responses: const [FakeProviderClientResponse.text('第二轮结论')],
    );
    final secondAgent = FakeAgent.create(
      id: 'worldbuilder',
      client: secondClient,
      toolManager: dispatcher,
      allowedTools: const ['read'],
      initialMessages: carried,
    );
    await _drain(secondAgent, '第 2 轮任务');

    // 上一轮的工具结果随请求一起发出去了 —— 参与者不需要再读一次。
    final sent = _flatten(secondClient.capturedStreamRequests.single.messages);
    expect(sent, contains(_settingDoc));
    expect(sent, contains('第 1 轮任务'));
    expect(sent, contains('第 2 轮任务'));
    // 没有产生新的工具调用。
    expect(dispatcher.capturedCalls.length, 1);
  });
}
