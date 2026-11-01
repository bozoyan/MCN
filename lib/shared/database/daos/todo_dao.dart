// 职责: Todo 数据访问对象 — 负责 Todo 任务的持久化读写
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/todo.dart

import 'package:drift/drift.dart';

import '../../logger/app_logger.dart';
import '../../models/todo.dart';
import '../app_database.dart';

part 'todo_dao.drift.dart';

final _log = AppLogger.forModule('DB');

/// Todo 数据访问对象
@DriftAccessor(tables: [Todos])
class TodoDao extends DatabaseAccessor<AppDatabase> with _$TodoDaoMixin {
  TodoDao(super.db);

  Future<DateTime?> lastActivityForSessions(List<String> ids) async {
    final latest = todos.updatedAt.max();
    final query = selectOnly(todos)
      ..addColumns([latest])
      ..where(todos.sessionId.isIn(ids));
    return (await query.getSingle()).read(latest);
  }

  /// 仅供维护层在整棵过期会话树的主库事务中调用。
  Future<int> deleteCleanupSessions(List<String> ids) async {
    try {
      return await (delete(todos)..where((t) => t.sessionId.isIn(ids))).go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=todos op=DELETE_EXPIRED_SESSIONS ids=$ids',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 获取指定会话的所有 Todo 列表
  Future<List<Todo>> getTodosBySession(String sessionId) async {
    return await (select(todos)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// 获取单个 Todo
  Future<Todo?> getTodoById(String sessionId, String id) async {
    return await (select(todos)
          ..where((t) => t.sessionId.equals(sessionId) & t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 保存模型提交的活跃快照，并保留未显式提交的终态历史。
  Future<List<Todo>> saveTodos(String sessionId, List<Todo> items) async {
    final incomingIds = <String>{};
    for (final item in items) {
      if (!incomingIds.add(item.id)) {
        throw ArgumentError.value(
          item.id,
          'items',
          'duplicate Todo id in the same session snapshot',
        );
      }
    }

    try {
      return await transaction(() async {
        final existing = await getTodosBySession(sessionId);
        final existingById = {for (final todo in existing) todo.id: todo};
        final merged = <Todo>[
          ...items,
          for (final todo in existing)
            if ((todo.isCompleted || todo.isCancelled) &&
                !incomingIds.contains(todo.id))
              todo,
        ];

        await (delete(todos)..where((t) => t.sessionId.equals(sessionId))).go();

        // 位置在 todo 首次入库时定下，之后不随快照顺序变动：
        // 模型只看得到活跃项，让它的数组顺序主导全局排列会把历史项挤到尾部。
        var nextOrder =
            existing.fold<int>(
              -1,
              (max, todo) => todo.sortOrder > max ? todo.sortOrder : max,
            ) +
            1;

        final now = DateTime.now();
        final savedItems = <Todo>[];
        for (final item in merged) {
          final prior = existingById[item.id];
          final isIncoming = incomingIds.contains(item.id);
          final saved = item.copyWith(
            sessionId: sessionId,
            sortOrder: prior?.sortOrder ?? nextOrder++,
            createdAt: prior?.createdAt ?? item.createdAt,
            updatedAt: isIncoming ? now : item.updatedAt,
          );
          await into(todos).insert(
            TodosCompanion(
              id: Value(saved.id),
              content: Value(saved.content),
              status: Value(saved.status),
              priority: Value(saved.priority),
              sessionId: Value(saved.sessionId),
              sortOrder: Value(saved.sortOrder),
              createdAt: Value(saved.createdAt),
              updatedAt: Value(saved.updatedAt),
            ),
          );
          savedItems.add(saved);
        }
        // sortOrder 不再等于插入顺序，与 getTodosBySession 对齐后再返回。
        savedItems.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return savedItems;
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=todos operation=REPLACE_SESSION '
        'sessionId=$sessionId incomingIds=${items.map((item) => item.id).join(',')}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 插入单个 Todo
  Future<Todo> insertTodo(Todo item) async {
    final now = DateTime.now();
    try {
      final companion = TodosCompanion(
        id: Value(item.id),
        content: Value(item.content),
        status: Value(item.status),
        priority: Value(item.priority),
        sessionId: Value(item.sessionId),
        sortOrder: Value(item.sortOrder),
        createdAt: Value(item.createdAt),
        updatedAt: Value(now),
      );
      await into(todos).insert(companion, mode: InsertMode.insertOrReplace);
      return item.copyWith(updatedAt: now);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=todos operation=INSERT '
        'sessionId=${item.sessionId} id=${item.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 更新 Todo
  Future<Todo?> updateTodo(Todo item) async {
    final now = DateTime.now();
    try {
      final companion = TodosCompanion(
        content: Value(item.content),
        status: Value(item.status),
        priority: Value(item.priority),
        updatedAt: Value(now),
      );
      final updated =
          await (update(todos)..where(
                (t) =>
                    t.sessionId.equals(item.sessionId) & t.id.equals(item.id),
              ))
              .write(companion);
      if (updated == 0) {
        return null;
      }
      return item.copyWith(updatedAt: now);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=todos operation=UPDATE '
        'sessionId=${item.sessionId} id=${item.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 删除单个 Todo
  Future<bool> deleteTodo(String sessionId, String id) async {
    try {
      final deleted = await (delete(
        todos,
      )..where((t) => t.sessionId.equals(sessionId) & t.id.equals(id))).go();
      return deleted > 0;
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=todos operation=DELETE sessionId=$sessionId id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 删除指定会话的所有 Todos
  Future<int> deleteTodosBySession(String sessionId) async {
    try {
      return await (delete(
        todos,
      )..where((t) => t.sessionId.equals(sessionId))).go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=todos operation=DELETE_SESSION sessionId=$sessionId',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
