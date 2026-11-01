// 职责: Agent 单次 run 的流式状态模型 — 文本增量、工具调用块、推理内容，供 Council/Theater/Monologue/Chat 共用
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/agent_orchestrator.dart
//   lib/shared/services/ai/ai_chat_service.dart
//   lib/shared/models/ai_message_block.dart

import '../models/ai_message_block.dart';

/// 从 [AgentToolCallStart] 事件构造工具调用块（status=running，带 arguments 与推导出的 targetPath）。
AiToolCallBlock agentToolCallStartBlock({
  required String callId,
  required String toolName,
  required Map<String, dynamic> arguments,
  Map<String, dynamic>? metadata,
}) {
  return AiToolCallBlock(
    id: 'block_$callId',
    callId: callId,
    toolName: toolName,
    arguments: arguments,
    metadata: metadata,
    status: AiToolCallStatus.running,
    targetPath: metadata?['tool_source'] == 'mcp'
        ? null
        : (arguments['path'] as String?) ??
              (arguments['targetPath'] as String?),
  );
}

/// 从 [AgentToolCallResult] 事件构造工具调用块（status=success/error，result 来自结构化 output）。
/// [callId]/[toolName] 仅在尚无对应 start 块时用于兜底构造；正常情况下会经
/// [AgentRunState.withToolCall] 与已有 start 块按 callId 合并。
AiToolCallBlock agentToolCallResultBlock({
  required String callId,
  required String toolName,
  Object? output,
  Map<String, dynamic>? metadata,
  String? errorMessage,
  List<AiNestedToolCall> nestedCalls = const [],
}) {
  return AiToolCallBlock(
    id: 'block_$callId',
    callId: callId,
    toolName: toolName,
    arguments: const {},
    status: errorMessage == null
        ? AiToolCallStatus.success
        : AiToolCallStatus.error,
    result: output is Map<String, dynamic> ? output : null,
    metadata: metadata,
    errorMessage: errorMessage,
    nestedCalls: nestedCalls,
  );
}

class AgentRunState {
  final String agentId;
  final String agentName;
  final int round;
  final String accumulatedText;

  /// 推理块（[AiThinkingBlock]）与工具调用块（[AiToolCallBlock]）按流式到达顺序
  /// 交错存放，保留「推理 → 工具 → 推理 → …」的真实时序，供详情对话框还原。
  /// 不含最终输出文本（见 [accumulatedText]）。
  final List<AiMessageBlock> blocks;
  final bool isComplete;

  const AgentRunState({
    required this.agentId,
    required this.agentName,
    required this.round,
    this.accumulatedText = '',
    this.blocks = const [],
    this.isComplete = false,
  });

  /// 仅工具调用块，按出现顺序。供只关心工具列表的消费方使用。
  List<AiToolCallBlock> get toolCalls =>
      blocks.whereType<AiToolCallBlock>().toList(growable: false);

  /// 全部推理块拼接后的文本，供流式预览等仅需合并视图的场景使用。
  String get accumulatedThinking =>
      blocks.whereType<AiThinkingBlock>().map((b) => b.text).join('\n\n');

  AgentRunState copyWith({
    String? agentId,
    String? agentName,
    int? round,
    String? accumulatedText,
    List<AiMessageBlock>? blocks,
    bool? isComplete,
  }) {
    return AgentRunState(
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      round: round ?? this.round,
      accumulatedText: accumulatedText ?? this.accumulatedText,
      blocks: blocks ?? this.blocks,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  AgentRunState withAppendedText(String delta) {
    return copyWith(accumulatedText: accumulatedText + delta);
  }

  /// 追加推理增量：若上一个块仍是推理块则并入（同一段推理），否则另起一段
  /// 新推理块——从而把工具调用前后的两段推理区分开。
  AgentRunState withAppendedThinking(String delta) {
    final list = blocks.toList();
    final last = list.isNotEmpty ? list.last : null;
    if (last is AiThinkingBlock) {
      list[list.length - 1] = last.copyWith(text: last.text + delta);
    } else {
      list.add(AiThinkingBlock(id: 'think_${list.length}', text: delta));
    }
    return copyWith(blocks: list);
  }

  /// 按 callId 合并 upsert：Result 事件的 arguments 为空，需保留 Start 时的
  /// arguments / targetPath；其余字段（status/result/metadata/errorMessage）以传入为准。
  AgentRunState withToolCall(AiToolCallBlock incoming) {
    final list = blocks.toList();
    final idx = list.indexWhere(
      (b) => b is AiToolCallBlock && b.callId == incoming.callId,
    );
    if (idx >= 0) {
      final prev = list[idx] as AiToolCallBlock;
      list[idx] = prev.copyWith(
        toolName: incoming.toolName,
        status: incoming.status,
        // arguments 传 null 即保留旧值（copyWith 为 ?? this.arguments 语义）。
        arguments: incoming.arguments.isNotEmpty ? incoming.arguments : null,
        result: incoming.result,
        metadata: incoming.metadata,
        errorMessage: incoming.errorMessage,
        targetPath: incoming.targetPath,
        nestedCalls: incoming.nestedCalls.isNotEmpty
            ? incoming.nestedCalls
            : null,
      );
    } else {
      list.add(incoming);
    }
    return copyWith(blocks: list);
  }
}
