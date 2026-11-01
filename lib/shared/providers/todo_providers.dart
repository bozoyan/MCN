// 职责: Todo 任务状态管理 — 提供会话级别的任务列表读写
// 关联文件:
//   lib/shared/database/daos/todo_dao.dart
//   lib/shared/models/todo_models.dart
//   lib/shared/services/ai/tools_todo.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/app_database.dart';
import '../database/daos/todo_dao.dart';
import '../models/todo.dart';
import 'ai_providers.dart';

part 'todo_providers.g.dart';

/// TodoDao Provider
@riverpod
Future<TodoDao> todoDao(Ref ref) async {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return TodoDao(db);
}

/// 当前会话的 Todo 列表 Provider（含增删改操作）
@riverpod
class SessionTodos extends _$SessionTodos {
  @override
  Future<List<Todo>> build(String? sessionId) async {
    if (sessionId == null ||
        sessionId.isEmpty ||
        isTemporaryAiChatSessionId(sessionId)) {
      return const [];
    }
    final dao = await ref.watch(todoDaoProvider.future);
    return dao.getTodosBySession(sessionId);
  }

  /// 保存 TodoWrite 的活跃快照；DAO 会把遗漏的终态历史合并回来。
  Future<List<Todo>> saveTodos(List<Todo> todos) async {
    final lease = ref.keepAlive();
    try {
      final targetSessionId = sessionId;
      if (targetSessionId == null ||
          targetSessionId.isEmpty ||
          isTemporaryAiChatSessionId(targetSessionId)) {
        throw StateError('TodoWrite requires a persisted session');
      }
      final dao = await ref.read(todoDaoProvider.future);
      final saved = await dao.saveTodos(targetSessionId, todos);
      if (ref.mounted) {
        state = AsyncValue.data(saved);
      }
      return saved;
    } finally {
      lease.close();
    }
  }

  Future<void> addTodo(Todo todo) async {
    final current = state.hasValue ? state.value! : const <Todo>[];
    await saveTodos([...current, todo]);
  }

  Future<void> updateTodo(Todo updated) async {
    final current = state.hasValue ? state.value! : const <Todo>[];
    final index = current.indexWhere((t) => t.id == updated.id);
    if (index == -1) return;
    final newList = List<Todo>.from(current);
    newList[index] = updated;
    await saveTodos(newList);
  }

  Future<void> deleteTodo(String id) async {
    final lease = ref.keepAlive();
    try {
      final targetSessionId = sessionId;
      if (targetSessionId == null ||
          targetSessionId.isEmpty ||
          isTemporaryAiChatSessionId(targetSessionId)) {
        throw StateError('Todo delete requires a persisted session');
      }
      final dao = await ref.read(todoDaoProvider.future);
      await dao.deleteTodo(targetSessionId, id);
      final saved = await dao.getTodosBySession(targetSessionId);
      if (ref.mounted) {
        state = AsyncValue.data(saved);
      }
    } finally {
      lease.close();
    }
  }

  Future<void> clearTodos() async {
    final lease = ref.keepAlive();
    try {
      final targetSessionId = sessionId;
      if (targetSessionId == null ||
          targetSessionId.isEmpty ||
          isTemporaryAiChatSessionId(targetSessionId)) {
        return;
      }
      final dao = await ref.read(todoDaoProvider.future);
      await dao.deleteTodosBySession(targetSessionId);
      if (ref.mounted) {
        state = const AsyncValue.data([]);
      }
    } finally {
      lease.close();
    }
  }
}

/// 当前待处理任务数量
@riverpod
int pendingTodoCount(Ref ref, String? sessionId) {
  final todosAsync = ref.watch(sessionTodosProvider(sessionId));
  return todosAsync.when(
    data: (todos) =>
        todos.where((t) => !t.isCompleted && !t.isCancelled).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
}

/// 当前进行中任务
@riverpod
Todo? currentInProgressTodo(Ref ref, String? sessionId) {
  final todosAsync = ref.watch(sessionTodosProvider(sessionId));
  return todosAsync.when(
    data: (todos) {
      try {
        return todos.firstWhere((t) => t.isInProgress);
      } catch (_) {
        return null;
      }
    },
    loading: () => null,
    error: (_, _) => null,
  );
}
