// 职责: 在 provider SDK 序列化前校验 tool call/result 历史的 ID、配对与连续顺序。
// 关联文件:
//   lib/shared/agent/message.dart
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/client/openai_responses_client.dart
//   lib/shared/agent/client/anthropic_client.dart
//   lib/shared/agent/client/gemini_client.dart

import 'package:collection/collection.dart';

import '../message.dart';

enum ProviderHistoryProtocol {
  openAiChat('openai_chat'),
  openAiResponses('openai_responses'),
  anthropic('anthropic'),
  gemini('gemini');

  const ProviderHistoryProtocol(this.wireName);

  final String wireName;
}

enum ProviderHistoryIssue {
  emptyToolCallId('empty_tool_call_id'),
  emptyToolResultId('empty_tool_result_id'),
  duplicateToolCallId('duplicate_tool_call_id'),
  orphanToolResult('orphan_tool_result'),
  missingToolResult('missing_tool_result'),
  toolResultOutOfOrder('tool_result_out_of_order');

  const ProviderHistoryIssue(this.code);

  final String code;
}

class ProviderHistoryPolicy {
  const ProviderHistoryPolicy({
    required this.protocol,
    this.requiresNonEmptyToolIds = true,
    this.requiresUniqueToolCallIds = true,
    this.requiresContiguousToolResults = true,
  });

  static const openAiChat = ProviderHistoryPolicy(
    protocol: ProviderHistoryProtocol.openAiChat,
  );
  static const openAiResponses = ProviderHistoryPolicy(
    protocol: ProviderHistoryProtocol.openAiResponses,
  );
  static const anthropic = ProviderHistoryPolicy(
    protocol: ProviderHistoryProtocol.anthropic,
  );
  static const gemini = ProviderHistoryPolicy(
    protocol: ProviderHistoryProtocol.gemini,
  );

  final ProviderHistoryProtocol protocol;
  final bool requiresNonEmptyToolIds;
  final bool requiresUniqueToolCallIds;
  final bool requiresContiguousToolResults;
}

class ProviderHistoryValidationException implements Exception {
  const ProviderHistoryValidationException({
    required this.protocol,
    required this.issue,
    required this.messageIndex,
    required this.blockIndex,
    required this.pendingCallCount,
    this.duplicateOfMessageIndex,
    this.duplicateOfBlockIndex,
    this.sameMessageId,
    this.sameToolName,
    this.sameArguments,
  });

  final ProviderHistoryProtocol protocol;
  final ProviderHistoryIssue issue;
  final int messageIndex;
  final int blockIndex;
  final int pendingCallCount;
  final int? duplicateOfMessageIndex;
  final int? duplicateOfBlockIndex;
  final bool? sameMessageId;
  final bool? sameToolName;
  final bool? sameArguments;

  String get errorCode => 'history_${issue.code}';

  @override
  String toString() {
    return 'ProviderHistoryValidationException('
        'protocol=${protocol.wireName} '
        'issue=${issue.code} '
        'message_index=$messageIndex '
        'block_index=$blockIndex '
        'pending_call_count=$pendingCallCount'
        '${duplicateOfMessageIndex == null ? '' : ' duplicate_of_message_index=$duplicateOfMessageIndex duplicate_of_block_index=$duplicateOfBlockIndex same_message_id=$sameMessageId same_tool_name=$sameToolName same_arguments=$sameArguments'}'
        ')';
  }
}

class _PendingToolCall {
  const _PendingToolCall({
    required this.messageIndex,
    required this.blockIndex,
  });

  final int messageIndex;
  final int blockIndex;
}

void preflightProviderHistory(
  List<AgentMessage> messages,
  ProviderHistoryPolicy policy,
) {
  final pending = <String, _PendingToolCall>{};
  final seenCallIds = <String, (int, int)>{};

  for (var messageIndex = 0; messageIndex < messages.length; messageIndex++) {
    final message = messages[messageIndex];
    var toolResultCount = 0;
    int? firstNonResultBlockIndex;

    for (var blockIndex = 0; blockIndex < message.blocks.length; blockIndex++) {
      final block = message.blocks[blockIndex];
      if (block is ToolResultBlock) {
        toolResultCount += 1;
        if (policy.requiresNonEmptyToolIds && block.toolCallId.trim().isEmpty) {
          _throwHistoryIssue(
            policy,
            ProviderHistoryIssue.emptyToolResultId,
            messageIndex,
            blockIndex,
            pending.length,
          );
        }
      } else {
        firstNonResultBlockIndex ??= blockIndex;
      }
    }

    if (pending.isNotEmpty) {
      final resultTurnHasOtherContent =
          message.content.isNotEmpty || firstNonResultBlockIndex != null;
      if (policy.requiresContiguousToolResults &&
          (toolResultCount == 0 || resultTurnHasOtherContent)) {
        _throwHistoryIssue(
          policy,
          ProviderHistoryIssue.toolResultOutOfOrder,
          messageIndex,
          firstNonResultBlockIndex ?? 0,
          pending.length,
        );
      }

      for (
        var blockIndex = 0;
        blockIndex < message.blocks.length;
        blockIndex++
      ) {
        final block = message.blocks[blockIndex];
        if (block is! ToolResultBlock) {
          continue;
        }
        if (pending.remove(block.toolCallId) == null) {
          _throwHistoryIssue(
            policy,
            ProviderHistoryIssue.orphanToolResult,
            messageIndex,
            blockIndex,
            pending.length,
          );
        }
      }
      continue;
    }

    if (toolResultCount > 0) {
      final blockIndex = message.blocks.indexWhere(
        (block) => block is ToolResultBlock,
      );
      _throwHistoryIssue(
        policy,
        ProviderHistoryIssue.orphanToolResult,
        messageIndex,
        blockIndex,
        0,
      );
    }

    for (var blockIndex = 0; blockIndex < message.blocks.length; blockIndex++) {
      final block = message.blocks[blockIndex];
      if (block is! ToolCallBlock) {
        continue;
      }
      if (policy.requiresNonEmptyToolIds && block.callId.trim().isEmpty) {
        _throwHistoryIssue(
          policy,
          ProviderHistoryIssue.emptyToolCallId,
          messageIndex,
          blockIndex,
          pending.length,
        );
      }
      final first = seenCallIds[block.callId];
      if (policy.requiresUniqueToolCallIds && first != null) {
        final previousMessage = messages[first.$1];
        final previous = previousMessage.blocks[first.$2] as ToolCallBlock;
        throw ProviderHistoryValidationException(
          protocol: policy.protocol,
          issue: ProviderHistoryIssue.duplicateToolCallId,
          messageIndex: messageIndex,
          blockIndex: blockIndex,
          pendingCallCount: pending.length,
          duplicateOfMessageIndex: first.$1,
          duplicateOfBlockIndex: first.$2,
          sameMessageId: message.id == previousMessage.id,
          sameToolName: block.toolName == previous.toolName,
          sameArguments: const DeepCollectionEquality().equals(
            block.arguments,
            previous.arguments,
          ),
        );
      }
      seenCallIds[block.callId] = (messageIndex, blockIndex);
      pending[block.callId] = _PendingToolCall(
        messageIndex: messageIndex,
        blockIndex: blockIndex,
      );
    }
  }

  if (pending.isNotEmpty) {
    final first = pending.values.first;
    _throwHistoryIssue(
      policy,
      ProviderHistoryIssue.missingToolResult,
      first.messageIndex,
      first.blockIndex,
      pending.length,
    );
  }
}

Never _throwHistoryIssue(
  ProviderHistoryPolicy policy,
  ProviderHistoryIssue issue,
  int messageIndex,
  int blockIndex,
  int pendingCallCount,
) {
  throw ProviderHistoryValidationException(
    protocol: policy.protocol,
    issue: issue,
    messageIndex: messageIndex,
    blockIndex: blockIndex,
    pendingCallCount: pendingCallCount,
  );
}
