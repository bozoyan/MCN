// 职责: 测试聊天自动滚动 hook 在 AskUser pending 时只首次揭示并尊重用户回看
// 关联文件:
//   lib/shared/widgets/ai/chat/auto_scroll_hook.dart
//   lib/shared/widgets/ai/chat/ui_message.dart
//   lib/shared/models/ai_message_block.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/widgets/ai/chat/auto_scroll_hook.dart';
import 'package:reveric/shared/widgets/ai/chat/ui_message.dart';

void main() {
  testWidgets(
    'pending AskUser is revealed once and does not fight user scrollback',
    (tester) async {
      final messages = _messagesWithPendingAskUser();

      await tester.pumpWidget(_wrap(_AutoScrollHarness(uiMessages: messages)));
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final position = scrollable.position;
      expect(position.pixels, position.maxScrollExtent);

      await tester.drag(find.byType(ListView), const Offset(0, 260));
      await tester.pump();

      final scrolledBackOffset = position.pixels;
      expect(scrolledBackOffset, lessThan(position.maxScrollExtent));

      await tester.pumpWidget(
        _wrap(_AutoScrollHarness(uiMessages: _messagesWithPendingAskUser())),
      );
      await tester.pumpAndSettle();

      expect(position.pixels, scrolledBackOffset);
    },
  );

  testWidgets(
    'streaming follow still triggers when content grows past the viewport',
    (tester) async {
      // 意图：流式贴底必须在新内容真正增长（pixels 落后于 max）时仍然 jumpTo。
      // 若「已贴底就跳过」的 guard 误伤真增长，本测试失败。
      var messages = _streamingMessages(tailHeight: 480);

      await tester.pumpWidget(_wrap(_AutoScrollHarness(uiMessages: messages)));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.pixels, position.maxScrollExtent);

      // 流式继续：尾部增高（maxScrollExtent 增长），但仍是同一条 streaming 消息的新 identity。
      messages = _streamingMessages(tailHeight: 720);
      await tester.pumpWidget(_wrap(_AutoScrollHarness(uiMessages: messages)));
      await tester.pumpAndSettle();

      expect(position.pixels, position.maxScrollExtent);
    },
  );

  testWidgets(
    'compaction activity reveals its trailing status without a message update',
    (tester) async {
      final messages = _staticMessages();

      await tester.pumpWidget(
        _wrap(
          _AutoScrollHarness(uiMessages: messages, hasTrailingActivity: false),
        ),
      );
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.pixels, position.maxScrollExtent);

      // Compact 开始不会新增普通消息；仍必须滚到新增的瞬态状态行。
      await tester.pumpWidget(
        _wrap(
          _AutoScrollHarness(uiMessages: messages, hasTrailingActivity: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(position.pixels, position.maxScrollExtent);
    },
  );
}

List<UIMessage> _streamingMessages({required double tailHeight}) {
  // 用 content 长度近似驱动 tail 高度，让流式消息超过视口（320）以产生可滚动空间。
  final tail = List.generate(tailHeight ~/ 24, (i) => 'line $i').join(' ');
  return [
    UIMessage(
      id: 'streaming_message',
      role: AiMessageRole.assistant,
      type: AiMessageType.text,
      content: tail,
      blocks: const [],
      isStreaming: true,
      isStreamingTail: false,
      sourceIds: ['streaming_message'],
    ),
  ];
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 360, height: 320, child: child)),
  );
}

class _AutoScrollHarness extends HookWidget {
  const _AutoScrollHarness({
    required this.uiMessages,
    this.hasTrailingActivity = false,
  });

  final List<UIMessage> uiMessages;
  final bool hasTrailingActivity;

  @override
  Widget build(BuildContext context) {
    final userScrolledUp = useRef(false);
    final controller = useChatAutoScroll(
      uiMessages: uiMessages,
      userScrolledUp: userScrolledUp,
      sessionId: 'session_1',
      hasTrailingActivity: hasTrailingActivity,
    );

    return ListView.builder(
      controller: controller,
      itemCount: uiMessages.length + (hasTrailingActivity ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == uiMessages.length) {
          return const SizedBox(height: 96, child: Text('compacting'));
        }
        return SizedBox(height: 96, child: Text('message $index'));
      },
    );
  }
}

List<UIMessage> _messagesWithPendingAskUser() {
  return [
    for (var i = 0; i < 12; i++)
      UIMessage(
        id: 'message_$i',
        role: AiMessageRole.assistant,
        type: AiMessageType.text,
        content: 'message $i',
        blocks: const [],
        isStreaming: false,
        isStreamingTail: false,
        sourceIds: ['message_$i'],
      ),
    const UIMessage(
      id: 'ask_user_message',
      role: AiMessageRole.assistant,
      type: AiMessageType.text,
      content: '',
      blocks: [
        AiAskUserBlock(
          id: 'ask_user_block',
          callId: 'ask_user_call',
          questions: [
            {
              'id': 'q1',
              'question': 'Pick one',
              'options': [
                {'label': 'A'},
                {'label': 'B'},
              ],
            },
          ],
        ),
      ],
      isStreaming: false,
      isStreamingTail: false,
      sourceIds: ['ask_user_message'],
    ),
  ];
}

List<UIMessage> _staticMessages() {
  return [
    for (var i = 0; i < 12; i++)
      UIMessage(
        id: 'static_$i',
        role: AiMessageRole.assistant,
        type: AiMessageType.text,
        content: 'message $i',
        blocks: const [],
        isStreaming: false,
        isStreamingTail: false,
        sourceIds: ['static_$i'],
      ),
  ];
}
