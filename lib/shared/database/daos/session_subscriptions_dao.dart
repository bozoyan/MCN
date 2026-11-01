// 职责: Session 订阅关系数据访问对象 — 跨库 session 下行订阅者的增删查（幂等写入、按 session/target 级联清理）
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/services/remote/run_output_forwarder.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md
//   .agents/rules/error-handling.md
//   .agents/rules/db-query-aggregation.md

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../logger/app_logger.dart';
import '../app_database.dart';

part 'session_subscriptions_dao.drift.dart';

final _log = AppLogger.forModule('DB');

@DriftAccessor(tables: [SessionSubscriptions])
class SessionSubscriptionsDao extends DatabaseAccessor<AppDatabase>
    with _$SessionSubscriptionsDaoMixin {
  SessionSubscriptionsDao(super.db);

  /// 写入一条订阅关系；`(sessionId, subscriberType, targetId)` 唯一冲突即忽略，
  /// 保证幂等（首写为准，不覆盖既有 channel_type）。
  Future<void> add({
    required String sessionId,
    required String subscriberType,
    required String targetId,
    String? channelType,
  }) async {
    try {
      await into(sessionSubscriptions).insert(
        SessionSubscriptionsCompanion.insert(
          id: const Uuid().v4(),
          sessionId: sessionId,
          subscriberType: subscriberType,
          targetId: targetId,
          channelType: Value(channelType),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=session_subscriptions op=INSERT '
        'session=$sessionId subscriber=$subscriberType target=$targetId '
        'error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 某 session 的全部订阅行（forwarder 注册/恢复用），按创建时间升序。
  Future<List<SessionSubscription>> listBySession(String sessionId) {
    return (select(sessionSubscriptions)
          ..where((table) => table.sessionId.equals(sessionId))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.asc,
            ),
          ]))
        .get();
  }

  /// 某订阅者类型的全部订阅行（重启后 forwarder 重挂用），按创建时间升序。
  Future<List<SessionSubscription>> listBySubscriberType(
    String subscriberType,
  ) {
    return (select(sessionSubscriptions)
          ..where((table) => table.subscriberType.equals(subscriberType))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.asc,
            ),
          ]))
        .get();
  }

  /// 删除某 session 的全部订阅行 — session 删除时级联清理（跨库无 SQL cascade，app 层负责）。
  Future<int> deleteBySession(String sessionId) async {
    try {
      return await (delete(
        sessionSubscriptions,
      )..where((table) => table.sessionId.equals(sessionId))).go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=session_subscriptions op=DELETE session=$sessionId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 按 (subscriberType, targetId) 删除订阅行 — task 删除 / forwarder 遇死目标时清理。
  Future<int> deleteByTarget({
    required String subscriberType,
    required String targetId,
  }) async {
    try {
      return await (delete(sessionSubscriptions)..where(
            (table) =>
                table.subscriberType.equals(subscriberType) &
                table.targetId.equals(targetId),
          ))
          .go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=session_subscriptions op=DELETE '
        'subscriber=$subscriberType target=$targetId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
