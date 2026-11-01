// 职责: 渲染期消息分组 — 过滤 model-only 的 system_remind 消息，把连续的、仅含 thinking/普通 tool call 的 assistant 消息合并为一条 UIMessage，供聊天列表渲染
// 关联文件:
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/widgets/ai/chat/chat_message_view.dart
import '../../../models/ai_chat_models.dart';

/// 纯渲染期的消息单元。把「相邻的、带 blocks 的 assistant 消息」合并成一条，
/// 让连续多轮（thinking + 普通 tool call，中间无 text 等特殊 block）渲染为单张活动卡。
///
/// 仅在 build 期由 [groupMessagesForUi] 生成；不参与持久化 / DB / agent context。
class UIMessage {
  const UIMessage({
    required this.id,
    required this.role,
    required this.type,
    required this.content,
    required this.blocks,
    required this.isStreaming,
    required this.isStreamingTail,
    required this.sourceIds,
    this.metadata,
  });

  /// 取合并组首条源 [AiMessage.id]，作为列表 key 稳定不变。
  final String id;
  final AiMessageRole role;

  /// 取首条源消息 type（compact_summary 等特殊类型渲染判定）。
  final AiMessageType type;

  /// 取首条源消息 content（user 气泡解析 / 空-blocks 纯文本回退用）。
  final String content;

  /// 合并组内各源消息 blocks 按序拼接；非合并消息即其原 blocks。
  final List<AiMessageBlock> blocks;

  /// 组内任一源消息仍在 streaming。
  final bool isStreaming;

  /// 该 UIMessage 是会话最后一条，且其最后一条源消息在 streaming。
  /// 驱动尾部活动组的 running 态与续接 loading。
  final bool isStreamingTail;

  /// 取首条源消息 metadata（供 retryable 等判定）。
  final Map<String, dynamic>? metadata;

  /// 合并进来的全部源消息 id（调试 / 后续扩展用）。
  final List<String> sourceIds;
}

/// 把 [messages] 分组为渲染用的 [UIMessage] 列表。
///
/// 规则：连续的「assistant 且 blocks 非空，或正在 streaming」消息合并为一条（拼接 blocks）；
/// user / system / 非流式空-blocks 的 assistant（可重试纯文本/错误消息）各自独立成一条。
/// 特殊 block（text/image/askUser/TodoWrite-success）的切卡由 chat_message_view 的
/// block 级 flush 处理，本函数不做 block 类型判断。
List<UIMessage> groupMessagesForUi(List<AiMessage> rawMessages) {
  // system_remind 是 model-only 的运行时状态消息，持久化但不渲染。
  final messages = rawMessages
      .where((message) => message.type != AiMessageType.system_remind)
      .toList(growable: false);
  final result = <UIMessage>[];
  final run = <AiMessage>[];

  void flushRun() {
    if (run.isEmpty) {
      return;
    }
    final first = run.first;
    result.add(
      UIMessage(
        id: first.id,
        role: first.role,
        type: first.type,
        content: first.content,
        blocks: [for (final m in run) ...m.blocks],
        isStreaming: run.any((m) => m.isStreaming),
        isStreamingTail: false,
        metadata: first.metadata,
        sourceIds: [for (final m in run) m.id],
      ),
    );
    run.clear();
  }

  // 带 blocks 的 assistant 合并；正在流式的占位（空 blocks）也并入当前轮，
  // 避免「请求中底部 loading 气泡」在首个 thinking/tool block 到达时被删除并上跳。
  // 非流式空-blocks（错误/可重试纯文本）仍独立成条。
  bool mergeable(AiMessage m) =>
      m.role == AiMessageRole.assistant &&
      (m.blocks.isNotEmpty || m.isStreaming);

  for (final message in messages) {
    if (mergeable(message)) {
      run.add(message);
      continue;
    }
    flushRun();
    result.add(
      UIMessage(
        id: message.id,
        role: message.role,
        type: message.type,
        content: message.content,
        blocks: message.blocks,
        isStreaming: message.isStreaming,
        isStreamingTail: false,
        metadata: message.metadata,
        sourceIds: [message.id],
      ),
    );
  }
  flushRun();

  // 末源 streaming 时，标记最后一条 UIMessage 为 streaming tail。
  // 最后一条源消息必落在最后一个 UIMessage 内。
  if (messages.isNotEmpty && messages.last.isStreaming && result.isNotEmpty) {
    final last = result.last;
    result[result.length - 1] = UIMessage(
      id: last.id,
      role: last.role,
      type: last.type,
      content: last.content,
      blocks: last.blocks,
      isStreaming: last.isStreaming,
      isStreamingTail: true,
      metadata: last.metadata,
      sourceIds: last.sourceIds,
    );
  }

  return result;
}
