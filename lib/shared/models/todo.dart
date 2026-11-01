// 职责: Todo 模型导出、工厂方法与扩展方法
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/todo_models.dart

import '../database/app_database.dart';

export '../database/app_database.dart' show Todo, Todos, TodosCompanion;

int _todoSequence = 0;
int _nextTodoSequence() {
  _todoSequence += 1;
  return _todoSequence;
}

Todo createTodo({
  required String content,
  String status = 'pending',
  String priority = 'medium',
  String sessionId = '',
}) {
  final now = DateTime.now();
  return Todo(
    id: 'todo_${now.millisecondsSinceEpoch}_$_nextTodoSequence',
    content: content,
    status: status,
    priority: priority,
    sessionId: sessionId,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

extension TodoX on Todo {
  bool get isPending => status == 'pending';

  bool get isInProgress => status == 'in_progress';

  bool get isCompleted => status == 'completed';

  bool get isCancelled => status == 'cancelled';

  bool get isHighPriority => priority == 'high';

  bool get isMediumPriority => priority == 'medium';

  bool get isLowPriority => priority == 'low';

  String get displayStatus {
    switch (status) {
      case 'pending':
        return '待处理';
      case 'in_progress':
        return '进行中';
      case 'completed':
        return '已完成';
      case 'cancelled':
        return '已取消';
      default:
        return status;
    }
  }
}

extension TodoListX on List<Todo> {
  List<Todo> get pending => where((t) => t.isPending).toList();

  List<Todo> get inProgress => where((t) => t.isInProgress).toList();

  List<Todo> get completed => where((t) => t.isCompleted).toList();
}
