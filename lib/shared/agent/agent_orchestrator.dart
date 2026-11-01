// 职责: Agent 编排器 — 通用多 Agent 多轮循环,被 Council/Theater/Monologue 共享，支持流式输出
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/models/agent_run_state.dart
//   lib/shared/models/ai_run_failure.dart

import 'dart:async';

import '../models/ai_message_block.dart';
import '../models/ai_run_failure.dart';
import 'agent_run_state.dart';
import 'agent.dart';
import 'agent_tool_dispatcher.dart';
import 'agent_event.dart';

/// 为指定参与者构建对应的 [Agent](async,以便支持 per-participant 自定义模型)。
typedef AgentBuilder<P> = Future<Agent> Function(P participant);

/// 为指定轮次中的指定参与者构建 task prompt。
typedef AgentRoundTaskBuilder<P> = String Function(P participant, int round);

/// 解析 LLM 原始输出 → 业务类型 T。
typedef AgentOutputParser<P, T> =
    T Function(P participant, String rawOutput, int round);

/// 每当一个 agent 完成本轮输出时触发。
typedef AgentRoundOutputCallback<P, T> =
    void Function(int round, P participant, T output);

/// 单个 Agent 已产出结构化错误，调用方应停止当前编排。
class AgentOrchestratorFailure implements Exception {
  const AgentOrchestratorFailure(this.failure, {this.technicalMessage});

  final AiRunFailure failure;
  final String? technicalMessage;

  @override
  String toString() => 'AgentOrchestratorFailure: $failure';
}

/// 编排被用户主动取消，不属于失败。
class AgentOrchestratorCancelledException implements Exception {
  const AgentOrchestratorCancelledException();
}

/// 通用多 Agent 多轮编排器。
///
/// 同一个 participant 在多轮中**复用同一个 [Agent] 实例**,所以对话历史 +
/// 工具调用结果在轮次间自然累积,不需要业务代码手工拼"之前的发言"。
class AgentOrchestrator {
  bool _cancelled = false;
  final Set<Agent> _activeAgents = {};

  void cancel() {
    _cancelled = true;
    for (final a in _activeAgents) {
      a.cancel();
    }
  }

  /// 执行 [maxRounds] 轮编排。
  ///
  /// 轮次从 [startRound] 开始连续编号，所有 task / stream / output
  /// 回调都接收同一个绝对轮次号。
  ///
  /// 每轮每个 participant 恰好执行一次,每个 participant 的 [Agent] 由
  /// [buildAgent] 提供(只在第一轮构造,后续轮次复用)。默认按 [participants]
  /// 顺序；传入 [pickNext] 时由它从本轮尚未发言者中挑下一位，[previous] 为
  /// 本次编排中上一个产出（首位发言前为 null）。
  ///
  /// 可选流式回调 [onTextDelta]/[onToolCallStart]/[onToolCallResult]
  /// 让上层实时展示 LLM 生成过程；不传则保持阻塞行为（向后兼容）。
  Future<List<List<T>>> runRounds<P, T>({
    required List<P> participants,
    required AgentBuilder<P> buildAgent,
    required int maxRounds,
    int startRound = 1,
    required AgentRoundTaskBuilder<P> buildRoundTask,
    required AgentOutputParser<P, T> parseOutput,
    AgentRoundOutputCallback<P, T>? onAgentOutput,
    ToolExecutionContext Function(P participant, int round)?
    toolExecutionContext,
    void Function(P participant, int round)? onRoundBegin,
    void Function(P participant, int round, String text)? onTextDelta,
    void Function(P participant, int round, String thinking)? onThinkingDelta,
    void Function(P participant, int round, AiToolCallBlock block)? onToolCall,
    bool stopOnAgentError = false,
    P Function(List<P> remaining, T? previous)? pickNext,
  }) async {
    if (participants.isEmpty || maxRounds <= 0) return const [];

    final agentMap = <P, Agent>{};
    try {
      for (final p in participants) {
        agentMap[p] = await buildAgent(p);
        _activeAgents.add(agentMap[p]!);
      }

      final allRounds = <List<T>>[];
      T? previous;

      for (var roundOffset = 0; roundOffset < maxRounds; roundOffset++) {
        if (_cancelled) {
          break;
        }
        final round = startRound + roundOffset;

        final roundOutputs = <T>[];

        final remaining = [...participants];
        while (remaining.isNotEmpty) {
          if (_cancelled) break;

          final p = pickNext?.call(remaining, previous) ?? remaining.first;
          remaining.remove(p);
          final agent = agentMap[p]!;
          final task = buildRoundTask(p, round);

          onRoundBegin?.call(p, round);

          String raw = '';
          try {
            final stream = agent.process(
              task,
              toolExecutionContext: toolExecutionContext?.call(p, round),
            );
            await for (final ev in stream) {
              switch (ev) {
                case AgentTextDelta(:final text):
                  raw += text;
                  onTextDelta?.call(p, round, text);
                case AgentThinkingDelta(:final text):
                  onThinkingDelta?.call(p, round, text);
                case AgentToolCallStart(
                  :final callId,
                  :final toolName,
                  :final arguments,
                  :final metadata,
                ):
                  onToolCall?.call(
                    p,
                    round,
                    agentToolCallStartBlock(
                      callId: callId,
                      toolName: toolName,
                      arguments: arguments,
                      metadata: metadata,
                    ),
                  );
                case AgentToolCallProgress(
                  :final callId,
                  :final toolName,
                  :final arguments,
                  :final progress,
                  :final metadata,
                ):
                  onToolCall?.call(
                    p,
                    round,
                    agentToolCallStartBlock(
                      callId: callId,
                      toolName: toolName,
                      arguments: arguments,
                      metadata: metadata,
                    ).copyWith(result: {'mcp_progress': progress}),
                  );
                case AgentToolCallResult(
                  :final callId,
                  :final toolName,
                  :final output,
                  :final metadata,
                  :final errorMessage,
                ):
                  onToolCall?.call(
                    p,
                    round,
                    agentToolCallResultBlock(
                      callId: callId,
                      toolName: toolName,
                      output: output,
                      metadata: metadata,
                      errorMessage: errorMessage,
                    ),
                  );
                case AgentDone(:final finalText):
                  raw = finalText;
                case AgentError(:final failure, :final technicalMessage):
                  if (stopOnAgentError) {
                    throw AgentOrchestratorFailure(
                      failure,
                      technicalMessage: technicalMessage,
                    );
                  }
                  break;
                case AgentCancelled():
                  throw const AgentOrchestratorCancelledException();
                case AgentRoundRetry():
                  // 重试同一 round：重置本轮文本缓冲，避免跨 attempt 累积。
                  raw = '';
                default:
                  break;
              }
            }
          } on AgentOrchestratorCancelledException {
            rethrow;
          } on AgentOrchestratorFailure {
            rethrow;
          } catch (e) {
            if (stopOnAgentError) {
              rethrow;
            }
            raw = '';
          }
          final parsed = parseOutput(p, raw, round);
          previous = parsed;
          roundOutputs.add(parsed);
          onAgentOutput?.call(round, p, parsed);
        }

        if (!_cancelled && roundOutputs.isNotEmpty) {
          allRounds.add(roundOutputs);
        }
      }

      return allRounds;
    } finally {
      _activeAgents.clear();
    }
  }
}
