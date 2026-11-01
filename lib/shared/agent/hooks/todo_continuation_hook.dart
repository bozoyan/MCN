// 职责: Agent Todo 结束检查 — 记录结束时未完成 Todo 的快照，启用时以 system-remind 续跑。
// 关联文件:
//   lib/shared/agent/agent_hook.dart
//   lib/shared/agent/message.dart
//   lib/shared/models/todo.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/services/ai/trace_reporter_service.dart

import 'dart:async';

import '../../logger/app_logger.dart';
import '../../models/todo.dart';
import '../../utils/random_id.dart';
import '../agent_event.dart' show AgentRoundResult;
import '../agent_hook.dart';
import '../message.dart';

final _log = AppLogger.forModule('TodoContinuationHook');

/// 结束时存在未完成 Todo 后的处置结果。
enum TodoContinuationDecision {
  continued,
  disabled,
  limit_reached,
  awaiting_user,
}

/// Agent 正常结束时仍有未完成 Todo 的快照，只含计数，不含 Todo 正文。
class UnfinishedTodoSnapshot {
  const UnfinishedTodoSnapshot({
    required this.totalCount,
    required this.pendingCount,
    required this.inProgressCount,
    required this.requestCount,
    required this.toolCallCount,
    required this.endsWithQuestion,
    required this.continuationCount,
    required this.decision,
  });

  final int totalCount;
  final int pendingCount;
  final int inProgressCount;

  /// 本次 process 内的 LLM 请求次数（含已续跑的轮次）。
  final int requestCount;
  final int toolCallCount;

  /// 最终回复以问号结尾，视为在等待用户。
  final bool endsWithQuestion;

  /// 本次结束检查之前已续跑的次数。
  final int continuationCount;
  final TodoContinuationDecision decision;

  Map<String, Object> toTraceJson() => {
    'total': totalCount,
    'unfinished': pendingCount + inProgressCount,
    'pending': pendingCount,
    'in_progress': inProgressCount,
    'ends_with_question': endsWithQuestion,
    'continuation_count': continuationCount,
    'decision': decision.name,
  };
}

class TodoContinuationHook extends AgentHook {
  TodoContinuationHook({
    required this.loadTodos,
    this.enabled = true,
    this.maxContinuations = 1,
    this.onUnfinishedAtDone,
  });

  final FutureOr<List<Todo>> Function() loadTodos;

  /// 为 false 时只上报快照，不追加续跑。
  final bool enabled;
  final int maxContinuations;
  final FutureOr<void> Function(UnfinishedTodoSnapshot snapshot)?
  onUnfinishedAtDone;

  int _continuationCount = 0;
  int _requestCount = 0;
  int _toolCallCount = 0;

  @override
  FutureOr<HookAction<AgentRoundResult>> afterLLM(AgentRoundResult round) {
    _requestCount += 1;
    return const HookAction.proceed();
  }

  @override
  FutureOr<HookAction<AfterToolCallContext>> afterToolCall(
    AfterToolCallContext ctx,
  ) {
    _toolCallCount += 1;
    return const HookAction.proceed();
  }

  @override
  Future<void> beforeDone(BeforeDoneContext ctx) async {
    late final List<Todo> todos;
    try {
      todos = await loadTodos();
    } catch (_) {
      return;
    }
    final unfinished = todos
        .where((todo) => !todo.isCompleted && !todo.isCancelled)
        .toList();
    if (unfinished.isEmpty) {
      return;
    }

    final endsWithQuestion = _endsWithQuestion(ctx.finalText);
    final decision = !enabled
        ? TodoContinuationDecision.disabled
        : _continuationCount >= maxContinuations
        ? TodoContinuationDecision.limit_reached
        : endsWithQuestion
        ? TodoContinuationDecision.awaiting_user
        : TodoContinuationDecision.continued;
    final snapshot = UnfinishedTodoSnapshot(
      totalCount: todos.length,
      pendingCount: unfinished.where((todo) => todo.isPending).length,
      inProgressCount: unfinished.where((todo) => todo.isInProgress).length,
      requestCount: _requestCount,
      toolCallCount: _toolCallCount,
      endsWithQuestion: endsWithQuestion,
      continuationCount: _continuationCount,
      decision: decision,
    );

    if (decision == TodoContinuationDecision.continued) {
      _continuationCount += 1;
      ctx.followUp(
        AgentMessage.user(
          id: buildRandomId('todo_continue'),
          content: buildTodoContinuationRemind(unfinished),
        ),
      );
    }

    try {
      await onUnfinishedAtDone?.call(snapshot);
    } catch (error, stackTrace) {
      // 匿名诊断记录失败不能影响 Agent 的结束或续跑。
      _log.warning('report unfinished todos failed error=$error\n$stackTrace');
    }
  }

  @override
  void onEnd() {
    _continuationCount = 0;
    _requestCount = 0;
    _toolCallCount = 0;
  }

  bool _endsWithQuestion(String text) {
    final trimmed = text.trimRight();
    return trimmed.endsWith('?') || trimmed.endsWith('？');
  }
}

String buildTodoContinuationRemind(List<Todo> todos) {
  final lines = todos
      .map((todo) => '- [${todo.status}] (${todo.priority}) ${todo.content}')
      .join('\n');
  return '''
<system-remind type='todo_continuation'>
你准备结束本轮，但 Todo 列表中仍有未完成项：
$lines

请按实际情况选择其一：
- 继续推进最合适的一项；
- 某项已不需要或无法完成时，用 TodoWrite 将其标记为 cancelled，并简要说明原因；
- 需要用户确认或补充信息时，直接说明在等待什么，然后结束本轮。
</system-remind>''';
}
