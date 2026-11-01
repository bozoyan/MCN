// 职责: AI TodoWrite 工具实现，负责会话任务列表的创建和管理
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/models/todo_models.dart
//   lib/shared/providers/todo_providers.dart
// ignore_for_file: use_null_aware_elements
part of 'tools.dart';

const _todoWriteInputSchema = {
  'type': 'object',
  'properties': {
    'todos': {
      'type': 'array',
      'description': '当前会话仍需继续跟踪的完整活跃 todo 快照。',
      'items': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': 'todo 项的唯一标识符'},
          'content': {'type': 'string', 'description': '具体、可执行的任务描述'},
          'status': {
            'type': 'string',
            'enum': ['pending', 'in_progress', 'completed', 'cancelled'],
            'description':
                '任务当前状态；同一时间最多一个 in_progress。'
                'pending 尚未开始，in_progress 正在处理，'
                'completed 已真正完成（含用户要求的验证），'
                'cancelled 不再需要或被新的用户要求取代。',
          },
          'priority': {
            'type': 'string',
            'enum': ['high', 'medium', 'low'],
            'description': '任务的优先级',
          },
        },
        'required': ['id', 'content', 'status', 'priority'],
      },
    },
  },
  'required': ['todos'],
};

const _todoWriteDescription = '''创建并维护当前会话的结构化任务列表。

用于跟踪进度、组织多步骤工作，并让用户看见当前状态。它不是思考草稿。

何时使用：
- 任务需要 3 个或更多独立行动，而不是同一概念步骤里的 3 次工具调用
- 工作非平凡，需要规划、跨文件修改、多阶段验证或持续跟踪
- 用户明确要求计划、清单或进度跟踪，或一次给出多个任务
- 收到新的实质性指令，需要并入当前清单

何时跳过：单个直接任务或少于 3 个简单步骤；纯信息性、解释性、对话型请求；只需执行一个明确命令并报告结果。不确定时，任务非平凡或可能扩展成多步骤工作就用。

快照语义：每次调用提交的是完整的活跃列表，不是增量。仍需继续跟踪的 pending/in_progress 必须全部带上；已标记 completed 或 cancelled 的项在后续调用中无需再提交。要重新打开一个任务，用原 id 提交 pending 或 in_progress。

状态纪律：
- 开始执行前先标 in_progress，完成后立即标 completed，不要等到最后批量更新
- 只在真正完成后标 completed，不能基于意图或「即将完成」；卡住或只完成一部分就保持 in_progress，并新增一个说明阻塞点或剩余工作的 todo
- 任务项要具体、可执行、可验证：写「更新 TodoWrite 描述文案」而不是「处理 todo」
- 保留用户提供的命令原文，包括参数、顺序和标志位
- 拆成有意义的步骤，不要把同一概念步骤拆成机械清单

示例：用户说「给设置加个深色模式开关，完成时跑测试和构建」→ 定位设置页与状态入口 / 添加开关 / 接入状态持久化 / 更新样式适配 / 运行测试和构建。''';

mixin _AiToolManagerTodoMixin on _AiToolManagerBase {
  /// Callback for TodoWrite tool — 由外部注入以访问 Provider。
  ///
  /// [sessionId] 来自 [ToolExecutionContext.sessionId]，表示当前 Agent 会话。
  Future<List<Todo>> Function(List<Todo> todos, String sessionId)?
  todoWriteCallback;

  Future<Map<String, dynamic>> _handleTodoWrite(
    Map<String, dynamic> input,
  ) async {
    final now = DateTime.now();
    final todosData = _parseListArgument(input['todos']);
    final todos = todosData.indexed
        .map((entry) {
          final index = entry.$1;
          final item = entry.$2;
          final map = _parseMapArgument(item);
          final content = map == null
              ? _parseStringArgument(item)
              : _parseStringArgument(map['content']);
          return Todo(
            id: map == null
                ? 'todo_${index + 1}'
                : _parseStringArgument(
                    map['id'],
                    defaultValue: 'todo_${index + 1}',
                  ),
            content: content,
            // status / priority 直接落库并按字面量比对，需要归一化。
            status: map == null
                ? 'pending'
                : _parseStringArgument(
                    map['status'],
                    defaultValue: 'pending',
                    trim: true,
                  ),
            priority: map == null
                ? 'medium'
                : _parseStringArgument(
                    map['priority'],
                    defaultValue: 'medium',
                    trim: true,
                  ),
            sessionId: '',
            sortOrder: index,
            createdAt: now,
            updatedAt: now,
          );
        })
        .where((todo) => todo.content.trim().isNotEmpty)
        .toList();

    List<Todo> savedTodos = todos;
    if (todoWriteCallback != null) {
      final executionContext = _currentToolExecutionContext;
      final sessionId =
          (executionContext?.sessionId ?? this.sessionId)?.trim() ?? '';
      if (sessionId.isEmpty) {
        return {
          'ok': false,
          'error': 'TodoWrite requires an active session.',
          'error_code': ToolErrorCode.unavailable.name,
        };
      }
      savedTodos = await todoWriteCallback!(todos, sessionId);
    }

    final activeTodos = savedTodos
        .where((todo) => !todo.isCompleted && !todo.isCancelled)
        .toList(growable: false);
    return {
      'ok': true,
      'todos': activeTodos
          .map(
            (t) => {
              'id': t.id,
              'content': t.content,
              'status': t.status,
              'priority': t.priority,
            },
          )
          .toList(),
      'summary': '${activeTodos.length} pending todos',
    };
  }
}
