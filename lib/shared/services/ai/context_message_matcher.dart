// 职责: Agent 上下文消息与 UI 消息的内容匹配 — 按 role + type + 文本/call id 对齐，跨命名空间定位压缩切点
// 关联文件:
//   lib/shared/agent/message.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/desktop/widgets/ai/chat/message_mapping.dart

import 'dart:math';

import '../../agent/message.dart';
import '../../models/ai_chat_models.dart';
import '../../logger/app_logger.dart';

final _log = AppLogger.forModule('ContextMatcher');

/// compact_summary metadata：retained 在 UI 列表中的第一条消息 id。
///
/// 压缩当时写入；重建 Agent 时按这个 id 取后缀，不依赖摘要插在列表里的位置。
const compactReplayFromMessageIdKey = 'replay_from_message_id';

/// 压缩摘要消息 id：含压缩序号，append-only。
String compactSummaryMessageId(String sessionId, int compactionCount) =>
    'ctx_summary_${sessionId}_$compactionCount';

/// 摘要插入位置，以及 retained 对应的第一条 UI 消息 id。
class CompactSummaryPlacement {
  const CompactSummaryPlacement({
    required this.insertIndex,
    required this.replayFromMessageId,
  });

  final int insertIndex;
  final String replayFromMessageId;
}

/// 判断 UI 消息与 Agent 消息是否描述同一上下文内容。
///
/// 匹配规则：role + type；tool_result 优先按 `tool_call_id`，否则比文本；
/// 其余类型比文本内容。摘要插入点优先按消息 id 查找（用户消息两边共用 id）；
/// 对不上时才走这套内容匹配。assistant 流式气泡与 Agent id 仍不是同一套。
bool sameContextMessage(AiMessage uiMessage, AgentMessage agentMessage) {
  final roleMatches = switch (uiMessage.role) {
    AiMessageRole.user => agentMessage.role == AgentMessageRole.user,
    AiMessageRole.assistant => agentMessage.role == AgentMessageRole.assistant,
    AiMessageRole.system => agentMessage.role == AgentMessageRole.system,
  };
  if (!roleMatches) {
    return false;
  }
  final typeMatches = switch (uiMessage.type) {
    AiMessageType.tool_result =>
      agentMessage.type == AgentMessageType.tool_result,
    AiMessageType.compact_summary =>
      agentMessage.type == AgentMessageType.compact_summary,
    _ => agentMessage.type == AgentMessageType.text,
  };
  if (!typeMatches) {
    return false;
  }
  if (uiMessage.type == AiMessageType.tool_result) {
    return _sameToolResult(uiMessage, agentMessage);
  }
  if (uiMessage.blocks.any((b) => b is AiAttachmentBlock)) {
    // Attachment text is expanded only in the model representation. The shared
    // user-message identity survives restore/compaction without comparing bytes.
    return uiMessage.id == agentMessage.id;
  }
  return uiMessage.effectiveText.trim() == agentMessage.content.trim();
}

/// 将 Agent 上下文消息解析为对应的 UI 消息 id 集合。
///
/// retained 是原对话的后缀。从尾部向前匹配，避免「继续」或空 assistant
/// 命中历史上第一次出现、把摘要插到 overflow 里。
/// 插入点 = 第一条命中 retained 的 UI 消息之前。
List<String> resolveUiContextMessageIds(
  List<AiMessage> uiMessages,
  List<AgentMessage> agentMessages,
) {
  final matchedUiIndexByAgent = _matchUiIndexByAgent(uiMessages, agentMessages);
  final ids = <String>[];
  for (var agentIndex = 0; agentIndex < agentMessages.length; agentIndex++) {
    final uiIndex = matchedUiIndexByAgent[agentIndex];
    if (uiIndex != null) {
      ids.add(uiMessages[uiIndex].id);
    }
  }
  return ids;
}

/// 从尾部向前按内容匹配，返回 agent 消息下标 → UI 消息下标。
Map<int, int> _matchUiIndexByAgent(
  List<AiMessage> uiMessages,
  List<AgentMessage> agentMessages,
) {
  final matchedUiIndexByAgent = <int, int>{};
  var searchEnd = uiMessages.length;
  for (
    var agentIndex = agentMessages.length - 1;
    agentIndex >= 0;
    agentIndex--
  ) {
    final agentMessage = agentMessages[agentIndex];
    if (agentMessage.role == AgentMessageRole.system) {
      continue;
    }
    for (var uiIndex = searchEnd - 1; uiIndex >= 0; uiIndex--) {
      final uiMessage = uiMessages[uiIndex];
      if (uiMessage.isStreaming) {
        continue;
      }
      if (sameContextMessage(uiMessage, agentMessage)) {
        matchedUiIndexByAgent[agentIndex] = uiIndex;
        searchEnd = uiIndex;
        break;
      }
    }
  }
  return matchedUiIndexByAgent;
}

/// 在 UI 消息列表中定位摘要插入位置。
///
/// 返回插入 index，或 -1 表示未命中（调用方应跳过插入并告警）。
int resolveCompactionInsertIndex({
  required List<AiMessage> uiMessages,
  required List<AgentMessage> retainedMessages,
  required String sessionId,
}) {
  final retainedIds = resolveUiContextMessageIds(uiMessages, retainedMessages);
  if (retainedIds.isEmpty) {
    _log.warning(
      'summary placement skipped (no match) sessionId=$sessionId '
      'retainedFirstRole=${retainedMessages.isNotEmpty ? retainedMessages.first.role.name : "none"}',
    );
    return -1;
  }
  return uiMessages.indexWhere((message) => retainedIds.contains(message.id));
}

/// 在压缩当时同时得到插入下标和回放起点 UI id。
///
/// 回放起点优先用 retained 里第一条可回放消息的 id 在 UI 列表中查找（用户消息
/// 发送时两边共用这个 id），找不到再回退到内容匹配。
///
/// 给出 [compactedMessageCount]（压缩完成时 retained 的长度）时，摘要插在压缩
/// 实际发生的位置：第一条压缩后产生的消息之前；尚无此类消息时插在末尾的流式
/// 占位之前。摘要描述的是压缩当时的全部上下文，放在回放起点会让回退到本轮的
/// 截断留下「包含未来信息」的摘要。未给出时退回插在回放起点（旧行为）。
/// 未命中时返回 null，调用方应跳过插入（内存里的 snapshot.summary 仍生效）。
CompactSummaryPlacement? resolveCompactSummaryPlacement({
  required List<AiMessage> uiMessages,
  required List<AgentMessage> retainedMessages,
  required String sessionId,
  int? compactedMessageCount,
}) {
  final boundary = _replayBoundary(
    uiMessages: uiMessages,
    retainedMessages: retainedMessages,
    sessionId: sessionId,
  );
  if (boundary == null || compactedMessageCount == null) {
    return boundary;
  }
  final occurrenceIndex = _compactionOccurrenceIndex(
    uiMessages,
    retainedMessages,
    compactedMessageCount,
  );
  return CompactSummaryPlacement(
    insertIndex: max(boundary.insertIndex, occurrenceIndex),
    replayFromMessageId: boundary.replayFromMessageId,
  );
}

CompactSummaryPlacement? _replayBoundary({
  required List<AiMessage> uiMessages,
  required List<AgentMessage> retainedMessages,
  required String sessionId,
}) {
  final byId = _placementBySharedMessageId(uiMessages, retainedMessages);
  if (byId != null) {
    return byId;
  }
  final insertIndex = resolveCompactionInsertIndex(
    uiMessages: uiMessages,
    retainedMessages: retainedMessages,
    sessionId: sessionId,
  );
  if (insertIndex < 0 || insertIndex >= uiMessages.length) {
    return null;
  }
  return CompactSummaryPlacement(
    insertIndex: insertIndex,
    replayFromMessageId: uiMessages[insertIndex].id,
  );
}

/// 压缩发生处的 UI 下标：第一条匹配到「压缩后产生的 agent 消息」的 UI 消息；
/// 没有时取末尾连续流式占位之前。
int _compactionOccurrenceIndex(
  List<AiMessage> uiMessages,
  List<AgentMessage> retainedMessages,
  int compactedMessageCount,
) {
  if (compactedMessageCount < retainedMessages.length) {
    final matched = _matchUiIndexByAgent(uiMessages, retainedMessages);
    int? firstAfter;
    for (final entry in matched.entries) {
      if (entry.key < compactedMessageCount) {
        continue;
      }
      if (firstAfter == null || entry.value < firstAfter) {
        firstAfter = entry.value;
      }
    }
    if (firstAfter != null) {
      return firstAfter;
    }
  }
  var index = uiMessages.length;
  while (index > 0 && uiMessages[index - 1].isStreaming) {
    index--;
  }
  return index;
}

CompactSummaryPlacement? _placementBySharedMessageId(
  List<AiMessage> uiMessages,
  List<AgentMessage> retainedMessages,
) {
  final anchor = _firstReplayableRetainedMessage(retainedMessages);
  if (anchor == null) {
    return null;
  }
  final insertIndex = uiMessages.indexWhere(
    (message) =>
        !message.isStreaming &&
        message.id == anchor.id &&
        _sameSharedIdentity(message, anchor),
  );
  if (insertIndex < 0) {
    return null;
  }
  return CompactSummaryPlacement(
    insertIndex: insertIndex,
    replayFromMessageId: uiMessages[insertIndex].id,
  );
}

/// 跳过 system 与压缩合成消息（restate / 摘要 / Todo 补充），它们不在 UI 列表里。
AgentMessage? _firstReplayableRetainedMessage(
  List<AgentMessage> retainedMessages,
) {
  for (final message in retainedMessages) {
    if (message.role == AgentMessageRole.system) {
      continue;
    }
    if (_isSyntheticAgentMessageId(message.id)) {
      continue;
    }
    return message;
  }
  return null;
}

bool _isSyntheticAgentMessageId(String id) {
  return id.startsWith('ctx_restate_') ||
      id.startsWith('ctx_summary') ||
      id.startsWith('ctx_todos');
}

bool _sameSharedIdentity(AiMessage uiMessage, AgentMessage agentMessage) {
  final roleMatches = switch (uiMessage.role) {
    AiMessageRole.user => agentMessage.role == AgentMessageRole.user,
    AiMessageRole.assistant => agentMessage.role == AgentMessageRole.assistant,
    AiMessageRole.system => agentMessage.role == AgentMessageRole.system,
  };
  if (!roleMatches) {
    return false;
  }
  final uiIsToolResult = uiMessage.type == AiMessageType.tool_result;
  final agentIsToolResult = agentMessage.type == AgentMessageType.tool_result;
  return uiIsToolResult == agentIsToolResult;
}

/// 压缩摘要落库 / 写入 UI 时的 metadata。
Map<String, dynamic> buildCompactSummaryMetadata({
  required int compactionCount,
  required String replayFromMessageId,
  int? tokensBefore,
  int? tokensAfter,
}) {
  return <String, dynamic>{
    'compaction_count': compactionCount,
    compactReplayFromMessageIdKey: replayFromMessageId,
    'tokens_before': ?tokensBefore,
    'tokens_after': ?tokensAfter,
  };
}

String? compactReplayFromMessageId(Map<String, dynamic>? metadata) {
  final raw = metadata?[compactReplayFromMessageIdKey];
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return null;
}

bool _sameToolResult(AiMessage uiMessage, AgentMessage agentMessage) {
  final uiCallId = _uiToolCallId(uiMessage);
  final agentCallId = _agentToolCallId(agentMessage);
  if (uiCallId != null &&
      uiCallId.isNotEmpty &&
      agentCallId != null &&
      agentCallId.isNotEmpty) {
    return uiCallId == agentCallId;
  }
  return uiMessage.effectiveText.trim() == _agentToolResultText(agentMessage);
}

String? _uiToolCallId(AiMessage message) {
  final raw = message.metadata?['tool_call_id'];
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return null;
}

String? _agentToolCallId(AgentMessage message) {
  for (final block in message.blocks) {
    if (block is ToolResultBlock && block.toolCallId.isNotEmpty) {
      return block.toolCallId;
    }
  }
  return null;
}

String _agentToolResultText(AgentMessage message) {
  final direct = message.content.trim();
  if (direct.isNotEmpty) {
    return direct;
  }
  final buffer = StringBuffer();
  for (final block in message.blocks) {
    if (block is! ToolResultBlock) {
      continue;
    }
    for (final item in block.content) {
      if (item is TextBlock) {
        buffer.write(item.text);
      }
    }
  }
  return buffer.toString().trim();
}
