// 职责: Assistant 通用收件箱的数据访问对象 — 接收 run_agent notify / run_observer 崩溃兜底等来源消息。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/services/ai/tools_run.dart
//   lib/shared/services/remote/run_output_forwarder.dart
//   lib/shared/services/ai/assistant/turn_runner.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md
//   .agents/rules/error-handling.md

import 'package:drift/drift.dart';

import '../../logger/app_logger.dart';
import '../../utils/random_id.dart';
import '../app_database.dart';

part 'assistant_inbox_dao.drift.dart';

final _log = AppLogger.forModule('DB');

/// Assistant 通用收件箱 DAO。
///
/// 写入由两条子通道触发：
/// - B1：run agent 通过 `Run notify` 工具主动调用（source='run_agent'）。
/// - B2：最小 observer 在 run 崩溃时兜底写入（source='run_observer'）。
///
/// 读取由 Assistant 下一轮 turn 组装 context 时拉取，注入为 `<system-remind>`
/// user 消息（参考 chat agent system-mind 注入），不混入 `assistant_messages`。
@DriftAccessor(tables: [AssistantInbox])
class AssistantInboxDao extends DatabaseAccessor<AppDatabase>
    with _$AssistantInboxDaoMixin {
  AssistantInboxDao(super.db);

  /// 追加一条 inbox 消息。返回写入行的 id。
  Future<String> append({
    required String assistantSessionId,
    required String source,
    required String messageType,
    required String content,
    String? sourceRef,
  }) async {
    final id = buildRandomId('inbox');
    try {
      await into(assistantInbox).insert(
        AssistantInboxCompanion.insert(
          id: id,
          assistantSessionId: assistantSessionId,
          source: source,
          messageType: messageType,
          content: content,
          sourceRef: Value(sourceRef),
        ),
      );
      return id;
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_inbox op=APPEND '
        'session=$assistantSessionId source=$source type=$messageType error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 按 createdAt 升序读取某 Assistant 会话的全部 inbox 消息。
  Future<List<AssistantInboxData>> loadByAssistantSession(
    String assistantSessionId,
  ) async {
    try {
      return await (select(assistantInbox)
            ..where(
              (table) => table.assistantSessionId.equals(assistantSessionId),
            )
            ..orderBy([
              (table) => OrderingTerm(
                expression: table.createdAt,
                mode: OrderingMode.asc,
              ),
            ]))
          .get();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_inbox op=LOAD '
        'session=$assistantSessionId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 删除某 Assistant 会话的全部 inbox 消息（会话清理时调用）。
  Future<void> deleteByAssistantSession(String assistantSessionId) async {
    try {
      await (delete(assistantInbox)..where(
            (table) => table.assistantSessionId.equals(assistantSessionId),
          ))
          .go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_inbox op=DELETE_BY_SESSION '
        'session=$assistantSessionId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 按本轮已读 id 列表删除 inbox 消息（消费确认）。
  ///
  /// 仅删除本轮 [loadByAssistantSession] 读到的 id，保留 load 与 delete 窗口内
  /// 并发写入的新消息，避免下轮丢失。在 turn_runner 持久化事务内调用，与
  /// reminder 落库原子完成。
  Future<void> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await (delete(assistantInbox)..where((table) => table.id.isIn(ids))).go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=assistant_inbox op=DELETE_BY_IDS '
        'count=${ids.length} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
