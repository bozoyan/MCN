// 职责: Agent 生命周期钩子接口 — 在 process loop 关键点提供拦截与扩展能力
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/agent_event.dart
//   lib/shared/agent/client.dart
//   lib/shared/agent/hooks/logging_hook.dart
//   lib/shared/models/ai_run_failure.dart

import 'dart:async';

import '../models/ai_run_failure.dart';
import 'agent_tool_dispatcher.dart' show ToolDef;
import 'client.dart' show IncompleteModelResponseException;
import 'message.dart' show AgentMessage, ToolCall;
import 'agent_event.dart' show AgentRoundResult;

// ---------------------------------------------------------------------------
// HookAction — 控制流返回类型
// ---------------------------------------------------------------------------

/// 钩子的控制流返回类型。
///
/// - [proceed]: 继续执行，不修改数据
/// - [mutate]: 继续执行但替换数据
/// - [abort]: 中断 agent 执行并带错误消息
sealed class HookAction<T> {
  const factory HookAction.proceed() = HookProceed<T>;
  const factory HookAction.mutate(T value) = HookMutate<T>;
  const factory HookAction.abort(
    AiRunFailure failure, {
    String? technicalMessage,
  }) = HookAbort<T>;
}

class HookProceed<T> implements HookAction<T> {
  const HookProceed();
}

class HookMutate<T> implements HookAction<T> {
  final T value;
  const HookMutate(this.value);
}

class HookAbort<T> implements HookAction<T> {
  const HookAbort(this.failure, {this.technicalMessage});

  final AiRunFailure failure;
  final String? technicalMessage;
}

// ---------------------------------------------------------------------------
// LLMErrorAction — LLM 调用失败的处置方式
// ---------------------------------------------------------------------------

sealed class LLMErrorAction {
  const LLMErrorAction();
  const factory LLMErrorAction.abort(AiRunFailure failure) = LLMErrorAbort;
  const factory LLMErrorAction.retry(Duration delay) = LLMErrorRetry;
  const factory LLMErrorAction.proceed() = LLMErrorProceed;
}

class LLMErrorAbort implements LLMErrorAction {
  final AiRunFailure failure;
  const LLMErrorAbort(this.failure);
}

class LLMErrorRetry implements LLMErrorAction {
  final Duration delay;
  const LLMErrorRetry(this.delay);
}

/// 无意见：交由 Agent 内建策略决定（重试短暂网络错误，否则中止）。
class LLMErrorProceed implements LLMErrorAction {
  const LLMErrorProceed();
}

// ---------------------------------------------------------------------------
// 钩子上下文类型
// ---------------------------------------------------------------------------

/// LLM 调用前的上下文——供 hook 修改 messages 或 tools。
class BeforeLLMContext {
  final List<AgentMessage> messages;
  final List<ToolDef> tools;
  const BeforeLLMContext({required this.messages, required this.tools});
}

/// Tool 执行前的上下文——供 hook 跳过或替换参数。
enum AgentToolSource { builtin, mcp }

class BeforeToolCallContext {
  final ToolCall call;
  final AgentToolSource source;
  const BeforeToolCallContext(
    this.call, {
    this.source = AgentToolSource.builtin,
  });
}

/// Tool 执行后的上下文——供 hook 修改结果。
class AfterToolCallContext {
  final ToolCall call;
  final Map<String, dynamic> result;
  final AgentToolSource source;
  const AfterToolCallContext({
    required this.call,
    required this.result,
    this.source = AgentToolSource.builtin,
  });
}

/// 每轮结束后的只读上下文。
class AfterRoundContext {
  final int roundIndex;
  final AgentRoundResult roundResult;
  final List<AgentMessage> currentMessages;
  final int totalToolCalls;
  final double? cumulativeCostUSD;
  const AfterRoundContext({
    required this.roundIndex,
    required this.roundResult,
    required this.currentMessages,
    required this.totalToolCalls,
    this.cumulativeCostUSD,
  });
}

/// Agent 准备正常结束前的上下文。
///
/// Hook 可以通过 [followUp] 追加一条 user message，让当前 process 继续下一轮。
class BeforeDoneContext {
  final String finalText;
  final List<AgentMessage> currentMessages;
  final void Function(AgentMessage message) _followUp;

  const BeforeDoneContext({
    required this.finalText,
    required this.currentMessages,
    required this._followUp,
  });

  void followUp(AgentMessage message) {
    _followUp(message);
  }
}

// ---------------------------------------------------------------------------
// AgentHook 接口
// ---------------------------------------------------------------------------

/// Agent 生命周期钩子接口。
///
/// 所有方法都有默认空实现，hook 只需覆写关心的切入点。
/// 方法返回 [FutureOr] 以同时支持同步与异步实现。
abstract class AgentHook {
  const AgentHook();

  /// Agent 开始处理 task 前触发。可修改 task 内容。
  FutureOr<HookAction<String>> onStart(String task) =>
      const HookAction.proceed();

  /// 每轮开始（steer/followUp/nextTurn 已消费，LLM 调用前）。
  FutureOr<HookAction<void>> beforeRound(int roundIndex) =>
      const HookAction.proceed();

  /// LLM 调用前触发。可修改 messages 或 tools。
  FutureOr<HookAction<BeforeLLMContext>> beforeLLM(BeforeLLMContext ctx) =>
      const HookAction.proceed();

  /// LLM 响应完成、tool 执行前触发。可修改 round result。
  FutureOr<HookAction<AgentRoundResult>> afterLLM(AgentRoundResult round) =>
      const HookAction.proceed();

  /// Provider 已结束但缺少完整结果；[willRetry] 表示 Agent 将自动续跑。
  FutureOr<void> onIncompleteResponse(
    IncompleteModelResponseException error, {
    required bool willRetry,
  }) {}

  /// LLM 调用出错时触发。返回 retry 可让 agent 重试本轮，abort 中止 run，
  /// proceed 表示无意见、交 Agent 内建策略决定（重试短暂网络错误，否则中止）。
  ///
  /// [attempt] 从 1 开始计数。
  /// [isStreamError] 为 true 表示流已经开始但中途出错，否则是请求发送阶段出错。
  FutureOr<LLMErrorAction> onLLMError(
    Object error,
    int attempt, {
    bool isStreamError = false,
  }) => const LLMErrorAction.proceed();

  /// 每个 tool call 执行前触发。可跳过/修改 call。
  FutureOr<HookAction<BeforeToolCallContext>> beforeToolCall(
    BeforeToolCallContext ctx,
  ) => const HookAction.proceed();

  /// 每个 tool call 执行后触发。可修改 result。
  FutureOr<HookAction<AfterToolCallContext>> afterToolCall(
    AfterToolCallContext ctx,
  ) => const HookAction.proceed();

  /// 本轮完全结束（tool results 已记入上下文）后触发。只读。
  FutureOr<void> afterRound(AfterRoundContext ctx) {}

  /// Agent 准备正常完成前触发。可追加 follow-up 让当前 process 继续。
  FutureOr<void> beforeDone(BeforeDoneContext ctx) {}

  /// Agent 正常完成时触发。
  FutureOr<void> onDone(String finalText) {}

  /// Agent 出错时触发。
  FutureOr<void> onError(Object error, StackTrace? stackTrace) {}

  /// Agent 被取消时触发。
  FutureOr<void> onCancelled() {}

  /// Agent process 结束（无论成功/失败/取消）时触发。
  FutureOr<void> onEnd() {}
}
