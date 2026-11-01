// 职责: 小说状态数据访问对象 — 封装所有小说状态相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/ai/session_persistence.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';
import '../../logger/app_logger.dart';

part 'novel_state_dao.drift.dart';

const String _activeChatSessionKey = 'active_chat_session';

@DriftAccessor(tables: [NovelStates])
class NovelStateDao extends DatabaseAccessor<NovelContentDatabase>
    with _$NovelStateDaoMixin {
  NovelStateDao(super.db);

  Future<void> clearActiveChatSessionIn(List<String> ids) async {
    try {
      await (update(novelStates)..where(
            (t) => t.key.equals(_activeChatSessionKey) & t.data.isIn(ids),
          ))
          .write(
            NovelStatesCompanion(
              data: const Value(null),
              updatedAt: Value(DateTime.now()),
            ),
          );
    } catch (error, stackTrace) {
      AppLogger.forModule('DB').error(
        '[DB] table=novel_states op=CLEAR_ACTIVE_SESSION ids=$ids',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<NovelState?> get(String key) {
    return (select(
      novelStates,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
  }

  Stream<NovelState?> watch(String key) {
    return (select(
      novelStates,
    )..where((table) => table.key.equals(key))).watchSingleOrNull();
  }

  Future<void> upsert({
    required String key,
    required String status,
    String? data,
  }) async {
    final now = DateTime.now();
    await into(novelStates).insertOnConflictUpdate(
      NovelStatesCompanion(
        key: Value(key),
        status: Value(status),
        data: Value(data),
        createdAt: const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> remove(String key) {
    return (delete(novelStates)..where((table) => table.key.equals(key))).go();
  }

  // ==================== Active Chat Session ====================

  Future<String?> getActiveChatSessionId() async {
    final state = await get(_activeChatSessionKey);
    return state?.data;
  }

  Stream<String?> watchActiveChatSessionId() {
    return (select(novelStates)
          ..where((table) => table.key.equals(_activeChatSessionKey)))
        .watchSingleOrNull()
        .map((state) => state?.data);
  }

  Future<void> setActiveChatSessionId(String? sessionId) async {
    final now = DateTime.now();
    if (sessionId == null) {
      await remove(_activeChatSessionKey);
    } else {
      await into(novelStates).insertOnConflictUpdate(
        NovelStatesCompanion(
          key: const Value(_activeChatSessionKey),
          status: const Value(novelStateStatusIdle),
          data: Value(sessionId),
          createdAt: const Value.absent(),
          updatedAt: Value(now),
        ),
      );
    }
  }
}
