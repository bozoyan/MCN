// 职责: Agent 运行时事件 — 描述 process loop 中的 token / tool / steering / 完成 / 错误事件
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/models/ai_run_failure.dart
//   lib/shared/models/ai_nested_tool_call.dart

import '../models/ai_nested_tool_call.dart';
import '../models/ai_run_failure.dart';
import 'client.dart' show AiUsage, StreamFinishReason;
import 'message.dart';

/// Agent.process 流式事件。
sealed class AgentEvent {
  const AgentEvent();
}

/// 单 round LLM 调用结果(给 Agent runtime 用)。
class AgentRoundResult {
  AgentRoundResult({
    required this.text,
    required this.thinking,
    required this.toolCalls,
    this.thinkingSignature,
    this.encryptedContents = const [],
    this.usage,
    this.finishReason,
  });
  final String text;
  final String thinking;
  final String? thinkingSignature;
  final List<String> encryptedContents;
  final List<ToolCall> toolCalls;

  /// Token usage 统计
  final AiUsage? usage;

  final StreamFinishReason? finishReason;
}

/// 流式 round 事件，供 Agent process loop 用。
sealed class AgentRoundStreamEvent {
  const AgentRoundStreamEvent();
}

class AgentRoundTextDelta extends AgentRoundStreamEvent {
  const AgentRoundTextDelta(this.text);
  final String text;
}

class AgentRoundThinkingDelta extends AgentRoundStreamEvent {
  const AgentRoundThinkingDelta(this.text);
  final String text;
}

class AgentRoundToolCallDelta extends AgentRoundStreamEvent {
  const AgentRoundToolCallDelta(this.request);
  final ToolCall request;
}

class AgentRoundToolCallComplete extends AgentRoundStreamEvent {
  const AgentRoundToolCallComplete(this.request);
  final ToolCall request;
}

class AgentRoundToolCallIncomplete extends AgentRoundStreamEvent {
  const AgentRoundToolCallIncomplete(this.request);
  final ToolCall request;
}

class AgentRoundComplete extends AgentRoundStreamEvent {
  const AgentRoundComplete(this.result);
  final AgentRoundResult result;
}

/// Agent process 开始。
class AgentStart extends AgentEvent {
  const AgentStart({required this.task});
  final String task;
}

/// 一个 assistant message streaming 开始。
class AgentMessageStart extends AgentEvent {
  const AgentMessageStart({required this.round});
  final int round;
}

/// LLM 流式输出的文本增量。
class AgentTextDelta extends AgentEvent {
  const AgentTextDelta(this.text);
  final String text;
}

/// LLM 流式输出的推理增量。
class AgentThinkingDelta extends AgentEvent {
  const AgentThinkingDelta(this.text);
  final String text;
}

/// 本轮文本 streaming 完成。
class AgentTextComplete extends AgentEvent {
  const AgentTextComplete(this.text);
  final String text;
}

/// 本轮 thinking streaming 完成。
class AgentThinkingComplete extends AgentEvent {
  const AgentThinkingComplete(this.text);
  final String text;
}

/// 一个 LLM round 完成,产出文本(本轮 assistant 全部文本聚合)。
class AgentRoundText extends AgentEvent {
  const AgentRoundText({
    required this.round,
    required this.text,
    this.thinking = '',
  });
  final int round;
  final String text;
  final String thinking;
}

/// 工具调用参数仍在流式生成中。
class AgentToolCallDelta extends AgentEvent {
  const AgentToolCallDelta({
    required this.callId,
    required this.toolName,
    required this.arguments,
    this.thoughtSignature,
  });
  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final List<int>? thoughtSignature;
}

/// 一个工具调用参数已经完整生成，但尚未开始执行。
class AgentToolCallComplete extends AgentEvent {
  const AgentToolCallComplete({
    required this.callId,
    required this.toolName,
    required this.arguments,
    this.thoughtSignature,
  });
  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final List<int>? thoughtSignature;
}

/// 一个工具调用在流结束前未生成完整参数。
class AgentToolCallIncomplete extends AgentEvent {
  const AgentToolCallIncomplete({
    required this.callId,
    required this.toolName,
    required this.arguments,
    this.thoughtSignature,
    this.reason,
  });
  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final List<int>? thoughtSignature;
  final String? reason;
}

/// 工具调用即将开始。
class AgentToolCallStart extends AgentEvent {
  const AgentToolCallStart({
    required this.callId,
    required this.toolName,
    required this.arguments,
    this.thoughtSignature,
    this.metadata,
  });
  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final List<int>? thoughtSignature;
  final Map<String, dynamic>? metadata;
}

/// 工具调用结束(成功或失败)。
class AgentToolCallResult extends AgentEvent {
  const AgentToolCallResult({
    required this.callId,
    required this.toolName,
    this.output,
    this.metadata,
    this.errorMessage,
    this.nestedCalls = const [],
  });
  final String callId;
  final String toolName;

  /// 成功和失败均携带模型可见结果，供调用方保存错误码等结构化字段。
  /// 调用是否失败由 [errorMessage] 表示，不能以 output 非空判定成功。
  final Object? output;

  /// 由工具结果中的 `_metadata` 提取的 UI 辅助数据。不会发送给模型。
  final Map<String, dynamic>? metadata;
  final String? errorMessage;

  /// 批次收尾时的子调用展示快照，不发送给模型。
  final List<AiNestedToolCall> nestedCalls;

  AgentToolCallResult withNestedCalls(List<AiNestedToolCall> nestedCalls) {
    return AgentToolCallResult(
      callId: callId,
      toolName: toolName,
      output: output,
      metadata: metadata,
      errorMessage: errorMessage,
      nestedCalls: nestedCalls,
    );
  }
}

/// 工具被跳过执行。
class AgentToolSkipped extends AgentEvent {
  const AgentToolSkipped({
    required this.callId,
    required this.toolName,
    required this.arguments,
    this.reason,
    this.output,
    this.metadata,
    this.nestedCalls = const [],
  });
  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? reason;

  /// 写入上下文的工具结果；取消时可能带有已发生、未撤销的部分结果。
  final Map<String, dynamic>? output;

  /// 由工具结果中的 `_metadata` 提取的 UI 辅助数据。不会发送给模型。
  final Map<String, dynamic>? metadata;

  /// 取消前已发生的子调用，保留真实执行结果与副作用状态。
  final List<AiNestedToolCall> nestedCalls;

  AgentToolSkipped withNestedCalls(List<AiNestedToolCall> nestedCalls) {
    return AgentToolSkipped(
      callId: callId,
      toolName: toolName,
      arguments: arguments,
      reason: reason,
      output: output,
      metadata: metadata,
      nestedCalls: nestedCalls,
    );
  }
}

/// Steering 队列被消费。
class AgentSteeringApplied extends AgentEvent {
  const AgentSteeringApplied(this.count);
  final int count;
}

/// FollowUp 队列被消费,准备开下一 round。
class AgentFollowUpApplied extends AgentEvent {
  const AgentFollowUpApplied(this.count);
  final int count;
}

/// NextTurn 队列被消费,会在同一 process 内开下一次 LLM 请求。
class AgentNextTurnApplied extends AgentEvent {
  const AgentNextTurnApplied(this.count);
  final int count;
}

/// 一个 assistant message 已写入上下文。
class AgentMessageAdded extends AgentEvent {
  const AgentMessageAdded(this.message);
  final AgentMessage message;
}

/// 一个 assistant message 生命周期结束。
class AgentMessageEnd extends AgentEvent {
  const AgentMessageEnd({required this.round});
  final int round;
}

/// 检测到 agent loop。
class AgentLoopDetected extends AgentEvent {
  const AgentLoopDetected({required this.reason, this.details = const {}});
  final String reason;
  final Map<String, dynamic> details;
}

/// process 正常完成,带最终文本。
class AgentDone extends AgentEvent {
  const AgentDone(this.finalText);
  final String finalText;
}

/// Agent process 结束。
class AgentEnd extends AgentEvent {
  const AgentEnd();
}

/// 被取消。
class AgentCancelled extends AgentEvent {
  const AgentCancelled();
}

/// 出错(LLM 异常 / 超过最大迭代次数等)。
class AgentError extends AgentEvent {
  const AgentError(this.failure, {this.technicalMessage});

  final AiRunFailure failure;
  final String? technicalMessage;
}

/// 本轮 LLM 流式调用失败、即将重试同一 round。
///
/// 消费方应清空当前 streaming 气泡的 partial 内容（文本 / thinking / tool call
/// blocks）并重置 per-round 标志，复用同一气泡承接重试流；roundIndex 不变。
class AgentRoundRetry extends AgentEvent {
  const AgentRoundRetry({
    required this.attempt,
    required this.reason,
    required this.retryLimit,
  });

  /// 刚失败的尝试序数（第 1 次调用失败 → 1，第 1 次重试失败 → 2），
  /// 不是剩余重试次数；发出事件时也对应即将开始的重试序数。
  final int attempt;

  /// 当前请求允许的重试总次数。
  final int retryLimit;

  /// 仅日志用，可能含底层异常原始信息（路径 / 状态码 / 连接串片段等敏感信息），
  /// 消费方不得向用户展示。用户可见文案由 [AgentError.failure] 统一映射。
  final String reason;
}

/// 上下文压缩开始。
///
/// Agent 在每轮 LLM 调用前检查是否需要压缩，触发时先发此事件，
/// 供 UI 显示「正在压缩上下文…」状态。
class AgentCompactionStart extends AgentEvent {
  const AgentCompactionStart({required this.tokensBefore});

  /// 触发压缩时的评估 token 数。
  final int tokensBefore;
}

/// 上下文压缩结束。
///
/// 无论成功或失败都会发出。失败时 [ok] 为 false，[reason] 含失败原因
/// （仅日志用，不展示给用户）。
class AgentCompactionEnd extends AgentEvent {
  const AgentCompactionEnd({
    required this.ok,
    required this.tokensBefore,
    required this.tokensAfter,
    this.reason,
  });

  /// 压缩是否成功。
  final bool ok;

  /// 触发压缩时的评估 token 数。
  final int tokensBefore;

  /// 压缩后 retained + summary 的估算 token 数。
  final int tokensAfter;

  /// 失败原因（仅 [ok] 为 false 时有值，仅日志用）。
  final String? reason;
}

/// Bounded presentation-only progress; does not add history or execute hooks.
class AgentToolCallProgress extends AgentEvent {
  const AgentToolCallProgress({
    required this.callId,
    required this.toolName,
    required this.arguments,
    required this.progress,
    this.metadata,
  });
  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final Map<String, dynamic> progress;
  final Map<String, dynamic>? metadata;
}
