// 职责: ProviderStreamEvent → AgentRoundStreamEvent 转换 — 可复用的 round 组装逻辑
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/client.dart
//   lib/shared/agent/agent_event.dart

import '../logger/app_logger.dart';

import 'client.dart'
    show
        StreamEvent,
        TextDelta,
        ThinkingDelta,
        ToolCallDelta,
        SignatureDelta,
        EncryptedContentDelta,
        StreamCancelled,
        StreamError,
        StreamComplete,
        StreamFinishReason;
import 'agent_event.dart'
    show
        AgentRoundResult,
        AgentRoundStreamEvent,
        AgentRoundTextDelta,
        AgentRoundThinkingDelta,
        AgentRoundToolCallDelta,
        AgentRoundToolCallComplete,
        AgentRoundToolCallIncomplete,
        AgentRoundComplete;
import 'message.dart' show ToolCall;
import 'client.dart' show AiUsage;

final _log = AppLogger.forModule('assembleRound');

/// 将 [ProviderClient.chatStream] 的原始事件流组装为 Agent runtime 可消费的 round 事件流。
Stream<AgentRoundStreamEvent> assembleRound(Stream<StreamEvent> source) async* {
  final textBuf = StringBuffer();
  final thinkBuf = StringBuffer();
  final toolCalls = <ToolCall>[];
  final completedToolCallIndexById = <String, int>{};
  final partialToolCalls = <String, ToolCall>{};
  final encryptedContents = <String>[];
  String? thinkingSignature;
  AiUsage? finalUsage;
  StreamFinishReason? finalFinishReason;

  await for (final event in source) {
    switch (event) {
      case TextDelta(:final text):
        if (text.isNotEmpty) {
          textBuf.write(text);
          yield AgentRoundTextDelta(text);
        }

      case ThinkingDelta(:final text):
        if (text.isNotEmpty) {
          thinkBuf.write(text);
          yield AgentRoundThinkingDelta(text);
        }

      case SignatureDelta(:final signature):
        if (signature.isNotEmpty) {
          thinkingSignature = signature;
        }

      case EncryptedContentDelta(:final encryptedContent):
        if (encryptedContent.isNotEmpty) {
          encryptedContents.add(encryptedContent);
        }
        break;

      case ToolCallDelta(
        :final callId,
        :final toolName,
        :final arguments,
        :final isPartial,
        :final thoughtSignature,
      ):
        if (callId.isEmpty || toolName.isEmpty) continue;
        final request = ToolCall(
          callId: callId,
          toolName: toolName,
          arguments: arguments,
          thoughtSignature: thoughtSignature,
        );
        if (isPartial) {
          partialToolCalls[callId] = request;
          yield AgentRoundToolCallDelta(request);
        } else {
          partialToolCalls.remove(callId);
          final existingIndex = completedToolCallIndexById[callId];
          if (existingIndex != null) {
            toolCalls[existingIndex] = request;
          } else {
            completedToolCallIndexById[callId] = toolCalls.length;
            toolCalls.add(request);
          }
          yield AgentRoundToolCallComplete(request);
        }

      case StreamComplete(:final usage, finishReason: final reason):
        // 捕获流式响应的 usage 统计
        finalUsage = usage;
        finalFinishReason = reason;

      case StreamError(:final message):
        _log.warning('stream error: $message');
        yield AgentRoundComplete(
          AgentRoundResult(
            text: textBuf.toString(),
            thinking: thinkBuf.toString(),
            thinkingSignature: thinkingSignature,
            encryptedContents: encryptedContents,
            toolCalls: toolCalls,
            usage: finalUsage,
            finishReason: finalFinishReason,
          ),
        );
        return;

      case StreamCancelled():
        return;
    }
  }

  if (partialToolCalls.isNotEmpty) {
    for (final request in partialToolCalls.values) {
      yield AgentRoundToolCallIncomplete(request);
    }
    // 半截参数不能执行。已完成的是有效产出，不论 finishReason 是 length
    // 还是断流，都交给 Agent 外层：有已完成的就 dispatch；没有已完成产出时，
    // Agent 根据是否有 thinking 选择原 round 重试或开启新一轮。
  }

  yield AgentRoundComplete(
    AgentRoundResult(
      text: textBuf.toString(),
      thinking: thinkBuf.toString(),
      thinkingSignature: thinkingSignature,
      encryptedContents: encryptedContents,
      toolCalls: toolCalls,
      usage: finalUsage,
      finishReason: finalFinishReason,
    ),
  );
}
