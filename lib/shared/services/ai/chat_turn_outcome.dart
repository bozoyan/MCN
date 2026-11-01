// 职责: ChatTurnRunner.runTurn 的结构化结果 — 让聊天与后台调用方区分完成/取消/失败并 fail-loud
// 关联文件:
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/agent/client.dart

import '../../agent/client.dart';

/// 一轮 turn 的终态。
enum ChatTurnStatus { completed, cancelled, failed }

/// 失败原因分类。底层只产出结构化错误，是否写 transcript 或安排后续执行 由上层决定。
enum ChatTurnErrorKind { serviceUnavailable, providerError, runtimeError }

/// 结构化错误：[safeMessage] 可展示给用户，[technicalMessage] 仅进日志。
class ChatTurnError {
  const ChatTurnError({
    required this.kind,
    required this.safeMessage,
    required this.technicalMessage,
    this.retryable = true,
    this.cause,
  });

  final ChatTurnErrorKind kind;
  final String safeMessage;
  final String technicalMessage;
  final bool retryable;
  final Object? cause;
}

/// runTurn 的返回值。failed 不代表没有消息；失败前完成的消息仍保留。
class ChatTurnOutcome {
  const ChatTurnOutcome({
    required this.status,
    required this.sessionId,
    required this.requestId,
    this.finalText = '',
    this.error,
    this.usage,
  });

  factory ChatTurnOutcome.completed({
    required String? sessionId,
    required int requestId,
    String finalText = '',
    AiUsage? usage,
  }) => ChatTurnOutcome(
    status: ChatTurnStatus.completed,
    sessionId: sessionId,
    requestId: requestId,
    finalText: finalText,
    usage: usage,
  );

  factory ChatTurnOutcome.cancelled({
    required String? sessionId,
    required int requestId,
    String finalText = '',
  }) => ChatTurnOutcome(
    status: ChatTurnStatus.cancelled,
    sessionId: sessionId,
    requestId: requestId,
    finalText: finalText,
  );

  factory ChatTurnOutcome.failed({
    required String? sessionId,
    required int requestId,
    required ChatTurnError error,
    String finalText = '',
  }) => ChatTurnOutcome(
    status: ChatTurnStatus.failed,
    sessionId: sessionId,
    requestId: requestId,
    finalText: finalText,
    error: error,
  );

  final ChatTurnStatus status;
  final String? sessionId;
  final int requestId;
  final String finalText;
  final ChatTurnError? error;
  final AiUsage? usage;

  bool get isCompleted => status == ChatTurnStatus.completed;
  bool get isCancelled => status == ChatTurnStatus.cancelled;
  bool get isFailed => status == ChatTurnStatus.failed;
}
