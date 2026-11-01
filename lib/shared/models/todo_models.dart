// 职责: Todo 枚举、工具 I/O 类型与字符串转换扩展
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/todo.dart
//   lib/shared/services/ai/tools_todo.dart

import '../database/app_database.dart';

/// Todo 任务状态
enum TodoStatus { pending, inProgress, completed, cancelled }

/// Todo 优先级
enum TodoPriority { high, medium, low }

/// TodoWrite 工具输入参数
class TodoWriteInput {
  final List<Todo> todos;

  const TodoWriteInput({required this.todos});
}

/// TodoWrite 工具输出结果
class TodoWriteResult {
  final bool ok;
  final List<Todo> todos;
  final String? error;

  const TodoWriteResult({required this.ok, this.todos = const [], this.error});
}

/// 扩展：将字符串转换为 TodoStatus
extension TodoStatusExtension on String {
  TodoStatus toTodoStatus() {
    switch (this) {
      case 'in_progress':
        return TodoStatus.inProgress;
      case 'completed':
        return TodoStatus.completed;
      case 'cancelled':
        return TodoStatus.cancelled;
      case 'pending':
      default:
        return TodoStatus.pending;
    }
  }
}

/// 扩展：将字符串转换为 TodoPriority
extension TodoPriorityExtension on String {
  TodoPriority toTodoPriority() {
    switch (this) {
      case 'high':
        return TodoPriority.high;
      case 'low':
        return TodoPriority.low;
      case 'medium':
      default:
        return TodoPriority.medium;
    }
  }
}
