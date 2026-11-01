// 职责: 验证桌面 AI 聊天待发送消息按会话隔离，切换会话不会覆盖或清除其它会话的队列。
// 关联文件:
//   lib/desktop/widgets/ai/chat/state.dart
//   lib/desktop/widgets/ai/chat/agent_factory.dart
//   lib/shared/services/ai/chat_session_controller.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/ai/chat/state.dart';

void main() {
  test('queues stay isolated while the panel switches sessions', () {
    final notifier = ValueNotifier<Map<String?, QueuedChatMessage>>(
      <String?, QueuedChatMessage>{},
    );
    addTearDown(notifier.dispose);
    final queues = SessionQueuedMessageStore(notifier);
    const a = QueuedChatMessage(
      text: 'message for session A',
      agentText: 'message for session A',
      references: [],
      sessionId: 'session_a',
      sendOnNextTurn: true,
    );
    const b = QueuedChatMessage(
      text: 'message for session B',
      agentText: 'message for session B',
      references: [],
      sessionId: 'session_b',
    );

    queues.setForSession('session_a', a);
    queues.setForSession('session_b', b);
    // 首轮请求可能由临时 session 创建真实 session；消费回调必须按真实
    // session 清队列，不能误清仍持有旧 session 的 composer store。
    queues.setForSession('session_a', null);

    expect(
      queues.forSession('session_a'),
      isNull,
      reason: '消费 A 会话的下一轮消息后必须移除 A 的队列横幅',
    );
    expect(
      queues.forSession('session_b'),
      b,
      reason: '清理 A 会话时不能撤销 B 已 staged 的立即发送消息',
    );
  });
}
