// 职责: 验证 groupMessagesForUi 的跨响应合并规则 — 连续 assistant 合并、特殊边界切分、streaming tail。
// 关联文件:
//   lib/shared/widgets/ai/chat/ui_message.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/models/ai_message_block.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/widgets/ai/chat/ui_message.dart';

AiMessage _assistant(
  String id, {
  List<AiMessageBlock> blocks = const [],
  String content = '',
  bool isStreaming = false,
}) => AiMessage.assistant(
  id: id,
  content: content,
  blocks: blocks,
  isStreaming: isStreaming,
);

AiThinkingBlock _think(String id) => AiThinkingBlock(id: id, text: 'reasoning');

AiToolCallBlock _tool(String id, String name) => AiToolCallBlock(
  id: id,
  callId: 'call_$id',
  toolName: name,
  arguments: const {},
  status: AiToolCallStatus.success,
);

void main() {
  group('groupMessagesForUi', () {
    test('连续两条带 blocks 的 assistant 合并为一条，blocks 按序拼接', () {
      // 需求核心：相邻请求之间无特殊 block 时合并为一张活动卡，
      // 故两轮响应的 blocks 必须保持原顺序拼接进同一个 UIMessage。
      final messages = [
        _assistant(
          'r1',
          blocks: [_think('t1'), _tool('read', 'Read'), _tool('w1', 'Write')],
        ),
        _assistant('r2', blocks: [_think('t2'), _tool('w2', 'Write')]),
      ];

      final ui = groupMessagesForUi(messages);

      expect(ui, hasLength(1));
      expect(ui.single.id, 'r1', reason: '合并组以首条源 id 作为稳定 key');
      expect(ui.single.blocks.map((b) => b.id).toList(), [
        't1',
        'read',
        'w1',
        't2',
        'w2',
      ]);
      expect(ui.single.sourceIds, ['r1', 'r2']);
    });

    test('中间夹 user 消息会切断合并', () {
      // user 输入代表一次新的请求边界，前后 assistant 不能并卡。
      final messages = [
        _assistant('a1', blocks: [_tool('x', 'Read')]),
        AiMessage.user(id: 'u1', content: '继续'),
        _assistant('a2', blocks: [_tool('y', 'Write')]),
      ];

      final ui = groupMessagesForUi(messages);

      expect(ui.map((m) => m.id).toList(), ['a1', 'u1', 'a2']);
      expect(ui[1].role, AiMessageRole.user);
    });

    test('空 blocks 的 assistant（可重试纯文本）独立成条，不与邻居合并', () {
      // 纯文本/错误消息走 ChatMessageView 的 plain-text 分支（保留 content/重试），
      // 不能被并进活动卡，否则会丢失内容与重试入口。
      final messages = [
        _assistant('a1', blocks: [_tool('x', 'Read')]),
        _assistant('plain', content: '出错了，请重试'),
        _assistant('a2', blocks: [_tool('y', 'Write')]),
      ];

      final ui = groupMessagesForUi(messages);

      expect(ui.map((m) => m.id).toList(), ['a1', 'plain', 'a2']);
      expect(ui[1].blocks, isEmpty);
      expect(ui[1].content, '出错了，请重试');
    });

    test('流式中的空 blocks 占位并入前一条 assistant-blocks 组（修复加载跳动）', () {
      // 请求中 startStreamingMessage 先插入一条空 blocks、isStreaming 的占位消息。
      // 它必须并入当前轮组（而非独立成底部 loading 气泡），否则首个 thinking/tool
      // block 到达时会发生「删除底部 loading + 内容上跳」的突兀效果。
      final messages = [
        _assistant('a1', blocks: [_tool('x', 'Read')]),
        _assistant('placeholder', isStreaming: true), // 空 blocks 流式占位
      ];

      final ui = groupMessagesForUi(messages);

      expect(ui, hasLength(1), reason: '空 blocks 流式占位并入上一组，不独立成条');
      expect(ui.single.id, 'a1');
      expect(ui.single.sourceIds, ['a1', 'placeholder']);
      expect(ui.single.blocks.map((b) => b.id).toList(), ['x']);
      expect(ui.single.isStreaming, isTrue);
      expect(
        ui.single.isStreamingTail,
        isTrue,
        reason: '末源为流式占位 → 合并组成为 streaming tail，驱动卡尾就地 loading',
      );
    });

    test('非流式空 blocks 的 assistant 不并入前一组（守住错误/重试分支）', () {
      final messages = [
        _assistant('a1', blocks: [_tool('x', 'Read')]),
        _assistant('err', content: '出错了'), // 非流式空 blocks
      ];

      final ui = groupMessagesForUi(messages);

      expect(ui.map((m) => m.id).toList(), ['a1', 'err']);
      expect(ui[1].blocks, isEmpty);
      expect(ui[1].content, '出错了');
    });

    test('isStreamingTail 仅在最后一条且其末源 streaming 时为 true', () {
      // 尾部 streaming 标志驱动活动卡的 running 态与续接 loading，
      // 只有会话最后一条、且其最后一条源消息在流式时才成立。
      final messages = [
        _assistant('a1', blocks: [_tool('x', 'Read')]),
        _assistant('a2', blocks: [_think('t')], isStreaming: true),
      ];

      final ui = groupMessagesForUi(messages);

      // a1 与 a2 合并（均带 blocks，中间无特殊 block）。
      expect(ui, hasLength(1));
      expect(ui.single.isStreamingTail, isTrue);
      expect(ui.single.isStreaming, isTrue);
    });

    test('末源非 streaming 时 isStreamingTail 全为 false', () {
      final messages = [
        _assistant('a1', blocks: [_tool('x', 'Read')]),
        AiMessage.user(id: 'u1', content: '问题'),
      ];

      final ui = groupMessagesForUi(messages);

      expect(ui.every((m) => !m.isStreamingTail), isTrue);
    });

    test('单条 user 消息保持 role/content', () {
      final ui = groupMessagesForUi([AiMessage.user(id: 'u1', content: '你好')]);

      expect(ui, hasLength(1));
      expect(ui.single.role, AiMessageRole.user);
      expect(ui.single.content, '你好');
      expect(ui.single.blocks, isEmpty);
    });

    test('空列表返回空', () {
      expect(groupMessagesForUi(const []), isEmpty);
    });

    test('system_remind 消息不渲染', () {
      // 需求核心：<system-remind> 是持久化的 model-only 运行时状态，
      // 必须参与 agent history 但绝不能出现在聊天 UI 中。
      final messages = [
        AiMessage.user(
          id: 'system_remind_current_workspace_context_1',
          content: "<system-remind type='current_workspace_context' />",
          type: AiMessageType.system_remind,
        ),
        AiMessage.user(id: 'u1', content: '你好'),
        _assistant('r1', blocks: [_think('t1')]),
      ];

      final ui = groupMessagesForUi(messages);

      expect(ui, hasLength(2));
      expect(ui.every((m) => !m.content.contains('system-remind')), isTrue);
      expect(ui.first.content, '你好');
    });
  });
}
