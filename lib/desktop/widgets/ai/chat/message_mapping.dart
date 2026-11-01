// 职责: AI 聊天面板 — 同步 Agent 上下文并解析智能体配置。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/desktop/widgets/ai/chat/agent_factory.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/agent/message.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/services/ai/context_message_matcher.dart
part of 'panel.dart';

extension _AiChatPanelMessageMapping on AiChatPanel {
  /// 将 Agent 内存中的压缩快照同步到 UI 会话消息列表。
  ///
  /// compaction 采用 append-only 语义：历史 compact_summary 永久留存，仅当本次
  /// compactionCount 对应的摘要尚未写入 UI 时才插入新记录。摘要插在压缩实际
  /// 发生处，回放起点写入 metadata。
  void _syncPersistedContextState(ProviderContainer container, Agent agent) {
    final current = container.read(aiChatSessionProvider(activeSessionId));
    final sessionId = current.sessionId;
    if (sessionId == null) {
      return;
    }
    final snapshot = agent.contextManager.snapshot();
    final summary = snapshot.summary?.trim();
    final nextMessages = List<AiMessage>.from(current.messages);

    if (summary != null && summary.isNotEmpty) {
      final compactionCount = snapshot.compactionCount;
      final summaryId = compactSummaryMessageId(sessionId, compactionCount);
      // 幂等：同一 compactionCount 的摘要已存在则跳过。
      final alreadyExists = nextMessages.any((m) => m.id == summaryId);
      if (!alreadyExists) {
        final placement = resolveCompactSummaryPlacement(
          uiMessages: nextMessages,
          retainedMessages: snapshot.messages,
          sessionId: sessionId,
          compactedMessageCount: snapshot.lastCompactionMessageCount,
        );
        if (placement != null) {
          nextMessages.insert(
            placement.insertIndex,
            AiMessage(
              id: summaryId,
              role: AiMessageRole.user,
              type: AiMessageType.compact_summary,
              content: summary,
              timestamp: DateTime.now(),
              metadata: buildCompactSummaryMetadata(
                compactionCount: compactionCount,
                replayFromMessageId: placement.replayFromMessageId,
                tokensBefore: snapshot.lastCompactionTokensBefore,
                tokensAfter: snapshot.lastCompactionTokensAfter,
              ),
            ),
          );
        }
        // placement == null 时由 resolveCompactionInsertIndex 内部告警，
        // 此处不追加到末尾——避免 messagesSinceLatestCompact 截断错位。
      }
    }

    container
        .read(aiChatSessionProvider(activeSessionId).notifier)
        .syncContext(messages: nextMessages);
  }
}
