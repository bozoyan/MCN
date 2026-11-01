// 职责: AI 聊天消息数据访问对象 — 封装所有 AI 聊天消息相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/services/ai/tools_run.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';
import '../../logger/app_logger.dart';

part 'ai_chat_message_dao.drift.dart';

@DriftAccessor(tables: [AiChatMessages])
class AiChatMessageDao extends DatabaseAccessor<NovelContentDatabase>
    with _$AiChatMessageDaoMixin {
  AiChatMessageDao(super.db);

  Future<bool> hasSavedMessages(String sessionId) async {
    final query = selectOnly(aiChatMessages)
      ..addColumns([aiChatMessages.id])
      ..where(aiChatMessages.sessionId.equals(sessionId))
      ..limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<AiChatMessage?> getInSession(String sessionId, String id) {
    return (select(aiChatMessages)
          ..where((t) => t.sessionId.equals(sessionId) & t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Stable keyset batches; the caller projects and filters saved blocks.
  Future<List<AiChatMessage>> scanForTools({
    String? sessionId,
    AiChatMessage? after,
    bool descending = false,
  }) {
    final query = select(aiChatMessages);
    if (sessionId != null) {
      query.where((t) => t.sessionId.equals(sessionId));
    }
    if (after != null) {
      query.where((t) {
        final idAfter = descending
            ? t.id.isSmallerThanValue(after.id)
            : t.id.isBiggerThanValue(after.id);
        final dateAfter = descending
            ? t.createdAt.isSmallerThanValue(after.createdAt)
            : t.createdAt.isBiggerThanValue(after.createdAt);
        var condition =
            dateAfter | (t.createdAt.equals(after.createdAt) & idAfter);
        if (sessionId != null) {
          final sequenceAfter = descending
              ? t.sequence.isSmallerThanValue(after.sequence)
              : t.sequence.isBiggerThanValue(after.sequence);
          condition =
              sequenceAfter | (t.sequence.equals(after.sequence) & condition);
        }
        return condition;
      });
    }
    final mode = descending ? OrderingMode.desc : OrderingMode.asc;
    query
      ..orderBy([
        if (sessionId != null)
          (t) => OrderingTerm(expression: t.sequence, mode: mode),
        (t) => OrderingTerm(expression: t.createdAt, mode: mode),
        (t) => OrderingTerm(expression: t.id, mode: mode),
      ])
      ..limit(200);
    return query.get();
  }

  Future<DateTime?> lastActivityForSessions(List<String> ids) async {
    final latest = aiChatMessages.createdAt.max();
    final query = selectOnly(aiChatMessages)
      ..addColumns([latest])
      ..where(aiChatMessages.sessionId.isIn(ids));
    return (await query.getSingle()).read(latest);
  }

  Future<int> deleteCleanupSessions(List<String> ids) async {
    try {
      return await (delete(
        aiChatMessages,
      )..where((t) => t.sessionId.isIn(ids))).go();
    } catch (error, stackTrace) {
      AppLogger.forModule('DB').error(
        '[DB] table=ai_chat_messages op=DELETE_EXPIRED_SESSIONS ids=$ids',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<AiChatMessage>> getBySession(String sessionId) {
    return (select(aiChatMessages)
          ..where((table) => table.sessionId.equals(sessionId))
          ..orderBy([
            (table) => OrderingTerm(expression: table.sequence),
            (table) => OrderingTerm(expression: table.createdAt),
          ]))
        .get();
  }

  Stream<List<AiChatMessage>> watchBySession(String sessionId) {
    return (select(aiChatMessages)
          ..where((table) => table.sessionId.equals(sessionId))
          ..orderBy([
            (table) => OrderingTerm(expression: table.sequence),
            (table) => OrderingTerm(expression: table.createdAt),
          ]))
        .watch();
  }

  Future<void> replace({
    required String sessionId,
    required List<AiChatMessagesCompanion> messages,
  }) async {
    await syncSession(sessionId: sessionId, messages: messages);
  }

  Future<void> upsertSessionMessages({
    required List<AiChatMessagesCompanion> messages,
  }) async {
    if (messages.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(
        aiChatMessages,
        messages,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  /// Upserts [messages] and removes rows for [sessionId] that are not present.
  Future<void> syncSession({
    required String sessionId,
    required List<AiChatMessagesCompanion> messages,
  }) async {
    await transaction(() async {
      if (messages.isEmpty) {
        await deleteBySession(sessionId);
        return;
      }
      await batch((batch) {
        batch.insertAll(
          aiChatMessages,
          messages,
          mode: InsertMode.insertOrReplace,
        );
      });
      final keepIds = messages.map((message) => message.id.value).toList();
      await (delete(aiChatMessages)..where(
            (table) =>
                table.sessionId.equals(sessionId) & table.id.isNotIn(keepIds),
          ))
          .go();
    });
  }

  Future<void> deleteBySession(String sessionId) async {
    await (delete(
      aiChatMessages,
    )..where((table) => table.sessionId.equals(sessionId))).go();
  }

  /// 获取所有消息（用于 Usage 统计）
  Future<List<AiChatMessage>> getAllMessages() {
    return select(aiChatMessages).get();
  }

  /// 按消息 id 取完整内容。
  Future<AiChatMessage?> getById(String id) {
    return (select(
      aiChatMessages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 在 [sessionId] 范围内对 [query] 做 LIKE 检索。
  ///
  /// [roles] 非空时按角色过滤（如 `['user', 'assistant']`）。
  /// [excludeToolResult] 为 true 时排除 `type='tool_result'` 的消息（默认 true）。
  /// [limit] 默认 20。
  /// LIKE 过滤与 limit 在 SQL 层完成（遵循 db-query-aggregation 规则）。
  Future<List<AiChatMessage>> searchInSession(
    String sessionId,
    String query, {
    List<String>? roles,
    bool excludeToolResult = true,
    int limit = 20,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return Future.value(const <AiChatMessage>[]);
    }
    final pattern = '%$trimmed%';
    final stmt = select(aiChatMessages)
      ..where((t) => t.sessionId.equals(sessionId) & t.content.like(pattern));
    if (roles != null && roles.isNotEmpty) {
      stmt.where((t) => t.role.isIn(roles));
    }
    if (excludeToolResult) {
      stmt.where((t) => t.type.isNotIn(const ['tool_result']));
    }
    stmt
      ..orderBy([
        (t) => OrderingTerm(expression: t.sequence),
        (t) => OrderingTerm(expression: t.createdAt),
      ])
      ..limit(limit);
    return stmt.get();
  }
}
