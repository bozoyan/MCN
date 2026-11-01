// 职责: Remote / home page Assistant 会话与消息的数据访问对象 — 跨重启保留 Assistant 对话历史。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/services/ai/context_message_matcher.dart
//   lib/shared/agent/agent_context_manager.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md
//   .agents/rules/error-handling.md

import 'package:drift/drift.dart';

import '../../agent/agent_context_manager.dart';
import '../../agent/client.dart' show AiUsage;
import '../../agent/message.dart';
import '../../logger/app_logger.dart';
import '../../models/ai_chat_models.dart';
import '../../utils/random_id.dart';
import '../app_database.dart';
import '../../services/ai/context_message_matcher.dart';

part 'assistant_session_dao.drift.dart';

final _log = AppLogger.forModule('DB');

/// Assistant 会话/消息 DAO。
///
/// 消息序列化格式与 novel-scoped `ai_chat_messages` 对齐（字段、blocks、metadata、
/// token 统计），`_buildPersistedMessages` 语义镜像 `session_persistence.dart`：
/// compact_summary append-only、按 compactionCount 生成唯一 id、
/// 用 `resolveCompactionInsertIndex` 内容匹配定位插入位置。
@DriftAccessor(tables: [AssistantSessions, AssistantMessages])
class AssistantSessionDao extends DatabaseAccessor<AppDatabase>
    with _$AssistantSessionDaoMixin {
  AssistantSessionDao(super.db);

  /// 按 (channelType, chatId) 查找或创建会话。
  Future<AssistantSession> getOrCreateByChat({
    required String channelType,
    required String chatId,
  }) async {
    try {
      final existing =
          await (select(assistantSessions)..where(
                (table) =>
                    table.channelType.equals(channelType) &
                    table.chatId.equals(chatId),
              ))
              .getSingleOrNull();
      if (existing != null) {
        return existing;
      }
      final id = buildRandomId('assistant_session');
      await into(assistantSessions).insert(
        AssistantSessionsCompanion.insert(
          id: id,
          chatId: chatId,
          channelType: channelType,
        ),
      );
      return AssistantSession(
        id: id,
        chatId: chatId,
        channelType: channelType,
        provider: null,
        model: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_sessions op=getOrCreateByChat '
        'channel=$channelType chat=$chatId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 按 id 获取会话。
  Future<AssistantSession?> getById(String id) {
    return (select(
      assistantSessions,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  /// 更新会话 provider/model 并 touch updatedAt。
  Future<void> updateModelSelection({
    required String id,
    required String? provider,
    required String? model,
  }) async {
    try {
      await (update(
        assistantSessions,
      )..where((table) => table.id.equals(id))).write(
        AssistantSessionsCompanion(
          provider: Value(provider),
          model: Value(model),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_sessions op=UPDATE_MODEL '
        'session=$id provider=$provider model=$model error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 按 createdAt 升序读取某会话的全部消息。
  Future<List<AiMessage>> loadMessages(String sessionId) async {
    try {
      final rows =
          await (select(assistantMessages)
                ..where((table) => table.sessionId.equals(sessionId))
                ..orderBy([
                  (table) => OrderingTerm(
                    expression: table.createdAt,
                    mode: OrderingMode.asc,
                  ),
                ]))
              .get();
      return rows.map(_decodeMessage).toList();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_messages op=LOAD session=$sessionId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 增量 upsert 已完成消息（不删除会话其他行）。
  /// 调用方需自行过滤掉 streaming / system 消息。
  Future<void> upsertMessages({
    required String sessionId,
    required List<AiMessage> messages,
    AgentContextSnapshot? contextSnapshot,
  }) async {
    if (messages.isEmpty) {
      return;
    }
    final companions = _buildMessageCompanions(
      sessionId: sessionId,
      messages: messages,
      contextSnapshot: contextSnapshot,
    );
    if (companions.isEmpty) {
      return;
    }
    try {
      await batch((batch) {
        batch.insertAllOnConflictUpdate(assistantMessages, companions);
      });
      await touch(sessionId);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_messages op=UPSERT '
        'session=$sessionId count=${companions.length} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 完整同步会话消息：upsert 并删除不在 [messages] 中的孤儿行。
  Future<void> syncMessages({
    required String sessionId,
    required List<AiMessage> messages,
    AgentContextSnapshot? contextSnapshot,
  }) async {
    final companions = _buildMessageCompanions(
      sessionId: sessionId,
      messages: messages,
      contextSnapshot: contextSnapshot,
    );
    try {
      await transaction(() async {
        await (delete(
          assistantMessages,
        )..where((table) => table.sessionId.equals(sessionId))).go();
        if (companions.isNotEmpty) {
          await batch((batch) {
            batch.insertAll(assistantMessages, companions);
          });
        }
      });
      await touch(sessionId);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_messages op=SYNC '
        'session=$sessionId count=${companions.length} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 更新会话 updatedAt。
  Future<void> touch(String id) async {
    try {
      await (update(assistantSessions)..where((table) => table.id.equals(id)))
          .write(AssistantSessionsCompanion(updatedAt: Value(DateTime.now())));
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_sessions op=TOUCH session=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 删除某会话及其消息。
  Future<void> deleteSession(String id) async {
    try {
      await transaction(() async {
        await (delete(
          assistantMessages,
        )..where((table) => table.sessionId.equals(id))).go();
        await (delete(
          assistantSessions,
        )..where((table) => table.id.equals(id))).go();
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_sessions op=DELETE session=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  List<AssistantMessagesCompanion> _buildMessageCompanions({
    required String sessionId,
    required List<AiMessage> messages,
    AgentContextSnapshot? contextSnapshot,
  }) {
    final persistedMessages = _buildPersistedMessages(
      sessionId: sessionId,
      messages: messages,
      contextSnapshot: contextSnapshot,
    );
    final companions = <AssistantMessagesCompanion>[];
    for (var i = 0; i < persistedMessages.length; i++) {
      final msg = persistedMessages[i];
      companions.add(
        AssistantMessagesCompanion.insert(
          id: msg.id,
          sessionId: sessionId,
          role: msg.role.name,
          type: Value(msg.type.name),
          content: Value(msg.content),
          blocks: Value(msg.blocks.isEmpty ? null : msg.blocks),
          metadata: Value(msg.metadata),
          inputTokens: Value(msg.usage?.inputTokens ?? 0),
          outputTokens: Value(msg.usage?.outputTokens ?? 0),
          cacheReadTokens: Value(msg.usage?.cacheReadTokens ?? 0),
          cacheWriteTokens: Value(msg.usage?.cacheWriteTokens ?? 0),
          reasoningTokens: Value(msg.usage?.reasoningTokens ?? 0),
          sequence: Value(i),
          createdAt: Value(msg.timestamp),
        ),
      );
    }
    return companions;
  }

  List<AiMessage> _buildPersistedMessages({
    required String sessionId,
    required List<AiMessage> messages,
    AgentContextSnapshot? contextSnapshot,
  }) {
    final summary = contextSnapshot?.summary?.trim();
    // 历史 compact_summary 永久留存（append-only），不再插入前过滤掉。
    final persisted = messages
        .where((msg) => !msg.isStreaming)
        .where((msg) => msg.role != AiMessageRole.system)
        .where(_messageHasNoActiveToolCalls)
        .toList(growable: true);
    if (summary != null && summary.isNotEmpty) {
      final compactionCount = contextSnapshot?.compactionCount ?? 0;
      final summaryMessage = AiMessage.user(
        id: _compactSummaryMessageId(sessionId, compactionCount),
        content: summary,
        type: AiMessageType.compact_summary,
        metadata: _buildCompactionMetadata(contextSnapshot),
      );
      // 用内容匹配（role+type+text）解析 retained 对应的 UI 消息，
      // 取代原本依赖 agent 内部 id 对齐的做法——两套 id 命名空间不一致。
      final retainedMessages =
          contextSnapshot?.messages ?? const <AgentMessage>[];
      final insertIndex = resolveCompactionInsertIndex(
        uiMessages: persisted,
        retainedMessages: retainedMessages,
        sessionId: sessionId,
      );
      if (insertIndex < 0) {
        // 未命中时不再把摘要追加到末尾——那样会让后续 _messagesSinceLatestCompact
        // 截断到错位置。这里跳过插入，contextSnapshot.summary 仍在内存中生效。
        _log.warning(
          'table=assistant_messages operation=COMPACT_SUMMARY_SKIP '
          'sessionId=$sessionId compactionCount=$compactionCount '
          'reason=no_retained_match',
        );
      } else {
        persisted.insert(insertIndex, summaryMessage);
      }
    }
    return persisted;
  }

  Map<String, dynamic> _buildCompactionMetadata(
    AgentContextSnapshot? snapshot,
  ) {
    if (snapshot == null) return const <String, dynamic>{};
    final meta = <String, dynamic>{
      'compaction_count': snapshot.compactionCount,
    };
    if (snapshot.lastCompactionTokensBefore != null) {
      meta['tokens_before'] = snapshot.lastCompactionTokensBefore;
    }
    if (snapshot.lastCompactionTokensAfter != null) {
      meta['tokens_after'] = snapshot.lastCompactionTokensAfter;
    }
    return meta;
  }

  bool _messageHasNoActiveToolCalls(AiMessage message) {
    for (final block in message.blocks) {
      if (block is! AiToolCallBlock) {
        continue;
      }
      if (block.status == AiToolCallStatus.pending ||
          block.status == AiToolCallStatus.running) {
        return false;
      }
    }
    return true;
  }

  /// 压缩摘要消息 id 改为含压缩序号的唯一 id（append-only）。
  /// 历史摘要记录永久留存，不再被后续压缩覆盖。
  String _compactSummaryMessageId(String sessionId, int compactionCount) =>
      'ctx_summary_${sessionId}_$compactionCount';

  AiMessage _decodeMessage(AssistantMessage row) {
    return AiMessage(
      id: row.id,
      role: AiMessageRole.values.firstWhere(
        (e) => e.name == row.role,
        orElse: () => AiMessageRole.user,
      ),
      type: AiMessageType.values.firstWhere(
        (e) => e.name == row.type,
        orElse: () => AiMessageType.text,
      ),
      content: row.content,
      timestamp: row.createdAt,
      metadata: row.metadata,
      blocks: row.blocks ?? const <AiMessageBlock>[],
      usage: AiUsage(
        inputTokens: row.inputTokens,
        outputTokens: row.outputTokens,
        cacheReadTokens: row.cacheReadTokens,
        cacheWriteTokens: row.cacheWriteTokens,
        reasoningTokens: row.reasoningTokens,
      ),
    );
  }
}
