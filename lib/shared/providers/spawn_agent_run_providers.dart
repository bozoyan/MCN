// 职责: 按主会话管理子运行、完成结果及停止边界，并按 run 归约工具卡片活动。
// 关联文件:
//   lib/shared/agent/agent_run_state.dart
//   lib/shared/agent/agent_event.dart
//   lib/shared/services/ai/spawn_agent_handler.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/providers/ai_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/misc.dart' show KeepAliveLink;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../agent/agent_event.dart';
import '../agent/agent_run_state.dart';
import '../logger/app_logger.dart';
import '../models/ai_message_block.dart';
import '../services/ai/spawn_agent_handler.dart';
import '../services/ai/tools.dart' show ToolExecutionContext;
import '../utils/random_id.dart';

part 'spawn_agent_run_providers.g.dart';

final _runsLog = AppLogger.forModule('SpawnAgentRuns');

/// 不持有 client 或取消句柄的运行快照；列表和卡片使用同一 run 身份。
class SpawnAgentRunRecord {
  SpawnAgentRunRecord(SpawnAgentRun run, {required this.background})
    : runId = run.runId,
      subSessionId = run.subSessionId,
      sourceTurnId = run.sourceTurnId,
      callId = run.callId,
      agentName = run.agentName,
      name = run.name,
      task = run.task,
      status = run.status,
      createdAt = run.createdAt;

  final String runId;
  final DateTime createdAt;
  final String subSessionId;
  final String? sourceTurnId;
  final String? callId;
  final String agentName;
  final String name;
  final String task;
  final SpawnAgentRunStatus status;
  final bool background;
}

/// 撤销/交付即移出队列的完成结果，不保留已结束执行的资源。
class SpawnAgentCompletion {
  SpawnAgentCompletion({
    required this.parentSessionId,
    required this.run,
    required Map<String, dynamic> result,
  }) : messageId = buildRandomId('sub_completion'),
       result = Map.unmodifiable(result);

  final String parentSessionId;
  final SpawnAgentRunRecord run;
  final String messageId;
  final Map<String, dynamic> result;

  String get reminder {
    final succeeded = result['ok'] == true;
    return '<system-remind type="subagent_completed">\n'
        'Agent: ${run.agentName}\n'
        'Task: ${run.name}\n'
        'session_id: ${run.subSessionId}\n'
        'Run: ${run.runId}\n'
        'Status: ${succeeded ? 'completed' : 'failed'}\n'
        '${succeeded ? 'Result: ${result['output'] ?? ''}' : 'Error code: ${result['error_code']}\nReason: ${result['error']}'}\n'
        '${result['context'] == null ? '' : 'Context: ${jsonEncode(result['context'])}\n'}'
        'Hint: 如需对本任务补充、纠错或复审，使用 SendAgentMessage，沿用此 session_id。\n'
        '</system-remind>';
  }
}

class SpawnAgentSessionState {
  const SpawnAgentSessionState({this.runs = const [], this.pending = const []});

  final List<SpawnAgentRunRecord> runs;
  final List<SpawnAgentCompletion> pending;
  int get backgroundCount => runs.where((run) => run.background).length;
  bool get needsRetention => runs.isNotEmpty || pending.isNotEmpty;
}

class _OwnedRun {
  _OwnedRun(this.run, this.background) : mayNotify = background;

  final SpawnAgentRun run;
  final bool background;
  bool mayNotify;
  void Function()? unlinkParent;
  late final Future<void> settled;
}

/// 生命周期归 AiChatRuntime，所有入口在第一次 await 前登记身份和取消资格。
/// 不从数据库恢复；应用重启后只有已保存的历史。
class SpawnAgentSessionRuns {
  SpawnAgentSessionRuns({
    required this.parentSessionId,
    required this.onChanged,
    required this.onActivityStarted,
    required this.onActivity,
    required this.onActivityFinished,
    this.onRunFinished,
  });

  final String? parentSessionId;
  final void Function(SpawnAgentSessionState) onChanged;
  final void Function(SpawnAgentRun) onActivityStarted;
  final void Function(SpawnAgentRun, AgentEvent) onActivity;
  final void Function(SpawnAgentRun) onActivityFinished;
  final void Function(SpawnAgentRunRecord, Map<String, dynamic>)? onRunFinished;
  final _runs = <String, _OwnedRun>{};
  final _pending = <String, SpawnAgentCompletion>{};
  bool _mutationInFlight = false;
  bool _disposed = false;
  int _stopAllDepth = 0;
  int _operationEpoch = 0;
  Completer<void> _startupChanged = Completer<void>();

  bool get _blocked => _disposed || _mutationInFlight || _stopAllDepth > 0;

  void beginSessionMutation() {
    _operationEpoch++;
    _mutationInFlight = true;
  }

  void endSessionMutation() {
    _mutationInFlight = false;
    _wakeStartup();
    _publish();
  }

  SpawnAgentRun start({
    required SpawnAgentHandler handler,
    required Map<String, dynamic> input,
    String? resumeSessionId,
    required String? callId,
    required ToolExecutionContext? context,
    bool background = false,
  }) {
    if (_blocked) {
      throw StateError('Sub-agent startup is blocked by a session operation.');
    }
    if (parentSessionId == null ||
        handler.parentSessionId != parentSessionId ||
        (context?.sourceSessionId != null &&
            context!.sourceSessionId != parentSessionId)) {
      throw StateError('Sub-agent must belong to the current parent session.');
    }
    if (background &&
        (context?.sourceTurnId?.isNotEmpty != true ||
            callId?.isNotEmpty != true)) {
      throw StateError(
        'Background execution requires its original turn and call.',
      );
    }
    final requestedSessionId = resumeSessionId?.trim();
    if (_runs.values.any(
      (entry) =>
          entry.run.subSessionId == requestedSessionId ||
          (callId != null && entry.run.callId == callId),
    )) {
      throw StateError(
        'The sub-agent session or call already has an active run.',
      );
    }
    final run = handler.start(
      input: input,
      resumeSessionId: resumeSessionId,
      callId: callId,
      toolExecutionContext: context,
      onStatusChanged: (run) {
        _wakeStartup();
        if (_owns(run)) {
          _publish();
        }
      },
      onEvent: (run, event) {
        if (_owns(run)) {
          onActivity(run, event);
        }
      },
      waitForStart: (run) =>
          _blocked && !_disposed && run.status != SpawnAgentRunStatus.stopping
          ? _startupChanged.future
          : null,
    );
    final entry = _OwnedRun(run, background);
    _runs[run.runId] = entry;
    onActivityStarted(run);
    _publish();
    if (!background) {
      entry.unlinkParent = context?.cancellationToken?.onCancel(
        () => cancelRun(run.runId, source: 'parent_cancel'),
      );
    }
    entry.settled = _observe(entry);
    return run;
  }

  Future<SpawnAgentRun> resume({
    required SpawnAgentHandler handler,
    required String sessionId,
    required String message,
    required String? callId,
    required ToolExecutionContext? context,
  }) async {
    if (_blocked) {
      throw StateError(
        'Sub-agent continuation is blocked by a session operation.',
      );
    }
    final epoch = _operationEpoch;
    final input = await handler.prepareResume(sessionId, message);
    if (_blocked ||
        epoch != _operationEpoch ||
        context?.cancellationToken?.isCancellationRequested == true) {
      throw StateError(
        'Sub-agent continuation was cancelled by a session operation.',
      );
    }
    // start 在第一次 await 前登记身份，重复续跑不能创建第二个 run。
    return start(
      handler: handler,
      input: input,
      resumeSessionId: sessionId,
      callId: callId,
      context: context,
      background: true,
    );
  }

  bool _owns(SpawnAgentRun run) =>
      !_disposed && identical(_runs[run.runId]?.run, run);

  void _wakeStartup() {
    final previous = _startupChanged;
    _startupChanged = Completer<void>();
    previous.complete();
  }

  Future<void> _observe(_OwnedRun entry) async {
    final run = entry.run;
    Map<String, dynamic> result;
    try {
      result = await run.result;
    } catch (error, stackTrace) {
      _runsLog.error(
        'run cleanup failed runId=${run.runId}',
        error: error,
        stackTrace: stackTrace,
      );
      result = {
        'ok': false,
        'error_code': 'spawn_agent_cleanup_failed',
        'error': 'Sub-agent execution could not finish cleanup.',
        'session_id': run.subSessionId,
      };
    } finally {
      entry.unlinkParent?.call();
    }
    final started = await run.started;
    if (!_owns(run)) {
      _runs.remove(run.runId);
      onActivityFinished(run);
      return;
    }
    _runs.remove(run.runId);
    onRunFinished?.call(
      SpawnAgentRunRecord(run, background: entry.background),
      result,
    );
    if (entry.mayNotify && started && result['cancelled'] != true) {
      _pending[run.runId] = SpawnAgentCompletion(
        parentSessionId: parentSessionId!,
        run: SpawnAgentRunRecord(run, background: entry.background),
        result: result,
      );
      _runsLog.info(
        'completion queued sessionId=$parentSessionId runId=${run.runId}',
      );
    }
    onActivityFinished(run);
    _publish();
  }

  /// 工具按 session 解析一次，之后必须携带返回的 runId 操作。
  String? currentRunId(String subSessionId) {
    for (final entry in _runs.values) {
      if (entry.run.subSessionId == subSessionId) {
        return entry.run.runId;
      }
    }
    return null;
  }

  bool sendMessage(String runId, String message) {
    if (_blocked) {
      return false;
    }
    return _runs[runId]?.run.sendMessage(message) ?? false;
  }

  bool cancelRun(String runId, {String source = 'user_click'}) {
    final entry = _runs[runId];
    final revoked = _pending.remove(runId) != null;
    if (entry != null) {
      entry.mayNotify = false;
      entry.run.cancel(source: source);
    }
    _publish();
    return entry != null || revoked;
  }

  Future<void> waitForRun(String runId) async {
    final entry = _runs[runId];
    if (entry != null) {
      await _waitForEntry(entry);
    }
  }

  Future<void> _waitForEntry(_OwnedRun entry) async {
    try {
      await entry.run.result;
    } finally {
      await entry.settled;
    }
  }

  void cancelAll({required String source}) {
    _operationEpoch++;
    _revokeAndCancel(_runs.values.toList(), (_) => true, source);
  }

  /// 只停止调用时已有的后台任务；主回复和同步子任务可以继续执行及派发新任务。
  Future<void> stopBackground({required String source}) async {
    _operationEpoch++;
    final entries = _runs.values.where((entry) => entry.background).toList();
    _revokeAndCancel(entries, (notice) => notice.run.background, source);
    await Future.wait(entries.map(_waitForEntry));
  }

  Future<void> stopAll({required String source}) async {
    _operationEpoch++;
    _stopAllDepth++;
    try {
      final entries = _runs.values.toList();
      _revokeAndCancel(entries, (_) => true, source);
      await Future.wait(entries.map(_waitForEntry));
    } finally {
      _stopAllDepth--;
      _wakeStartup();
      _publish();
    }
  }

  Future<void> stopTurns(Set<String> sourceTurnIds) async {
    if (!_mutationInFlight) {
      throw StateError(
        'Stopping rollback turns requires the session mutation guard.',
      );
    }
    final entries = _runs.values
        .where((entry) => sourceTurnIds.contains(entry.run.sourceTurnId))
        .toList();
    _revokeAndCancel(
      entries,
      (notice) => sourceTurnIds.contains(notice.run.sourceTurnId),
      'rollback',
    );
    await Future.wait(entries.map(_waitForEntry));
  }

  void _revokeAndCancel(
    List<_OwnedRun> entries,
    bool Function(SpawnAgentCompletion) matches,
    String source,
  ) {
    // 先统一撤销，再调用任何 cancel；取消回调可能同步触发其他收尾。
    _pending.removeWhere((runId, notice) {
      if (!matches(notice)) {
        return false;
      }
      _runsLog.info(
        'completion revoked sessionId=$parentSessionId runId=$runId source=$source',
      );
      return true;
    });
    for (final entry in entries) {
      entry.mayNotify = false;
    }
    for (final entry in entries) {
      entry.run.cancel(source: source);
    }
    _publish();
  }

  /// 消费时复核守卫及 run 资格。拿到列表快照并不代表已交付。
  SpawnAgentCompletion? takeCompletion(String runId) {
    if (_blocked) {
      return null;
    }
    final completion = _pending.remove(runId);
    if (completion != null) {
      _runsLog.info(
        'completion consumed sessionId=$parentSessionId runId=$runId',
      );
      _publish();
    }
    return completion;
  }

  void dispose() {
    _disposed = true;
    cancelAll(source: 'runtime_dispose');
    _wakeStartup();
  }

  void _publish() {
    if (_disposed) {
      return;
    }
    onChanged(
      SpawnAgentSessionState(
        runs: List.unmodifiable(
          _runs.values.map(
            (entry) =>
                SpawnAgentRunRecord(entry.run, background: entry.background),
          ),
        ),
        pending: List.unmodifiable(_pending.values),
      ),
    );
  }
}

/// thinking / text delta 逐字到达，按窗口发布，避免每个 delta 都重建卡片行。
/// 与 [AiChatSession] 的 stream 通知窗口保持一致。
const _notifyWindow = Duration(milliseconds: 100);

/// 一次 SpawnAgent 调用期间子 Agent 的实时运行状态，key 为父会话里的 tool callId。
///
/// 子会话消息要等 SpawnAgent 跑完才落库，运行中只能靠这份内存状态展示动态。
/// 用 [KeepAliveLink] 在运行期间临时保活（行滚出视口也不丢），[clear] 时立即释放，
/// 因此不会随 family 参数增长常驻内存。
@riverpod
class SpawnAgentActiveRun extends _$SpawnAgentActiveRun {
  AgentRunState? _current;
  Timer? _notifyTimer;
  bool _pendingNotify = false;
  KeepAliveLink? _lease;
  String? _runId;

  @override
  AgentRunState? build(String callId) {
    ref.onDispose(() {
      _notifyTimer?.cancel();
      _notifyTimer = null;
    });
    return null;
  }

  /// 初始化开始即绑定身份，直到真正收尾；工具返回 running 不清空活动。
  void begin(String runId) {
    clear();
    _runId = runId;
    _lease = ref.keepAlive();
    _update(_ensureRun(), immediate: true);
  }

  /// 归约子 Agent 事件，保留批次计数、输出与子调用，供运行中详情展示。
  void apply(AgentEvent event, {String? runId}) {
    if (!ref.mounted || (runId != null && _runId != runId)) {
      return;
    }
    switch (event) {
      case AgentTextDelta(:final text):
        _update(_ensureRun().withAppendedText(text));
      case AgentThinkingDelta(:final text):
        _update(_ensureRun().withAppendedThinking(text));
      case AgentToolCallStart(
        callId: final toolCallId,
        :final toolName,
        :final arguments,
        :final metadata,
      ):
        _update(
          _ensureRun().withToolCall(
            agentToolCallStartBlock(
              callId: toolCallId,
              toolName: toolName,
              arguments: arguments,
              metadata: metadata,
            ),
          ),
          immediate: true,
        );
      case AgentToolCallProgress(
        :final callId,
        :final toolName,
        :final arguments,
        :final progress,
        :final metadata,
      ):
        _update(
          _ensureRun().withToolCall(
            agentToolCallStartBlock(
              callId: callId,
              toolName: toolName,
              arguments: arguments,
              metadata: metadata,
            ).copyWith(result: {'mcp_progress': progress}),
          ),
        );
      case AgentToolCallResult(
        callId: final toolCallId,
        :final toolName,
        :final output,
        :final metadata,
        :final errorMessage,
        :final nestedCalls,
      ):
        _update(
          _ensureRun().withToolCall(
            agentToolCallResultBlock(
              callId: toolCallId,
              toolName: toolName,
              output: output,
              metadata: metadata,
              errorMessage: errorMessage,
              nestedCalls: nestedCalls,
            ),
          ),
          immediate: true,
        );
      case AgentToolSkipped(
        callId: final toolCallId,
        :final toolName,
        :final arguments,
        :final reason,
        :final output,
        :final metadata,
        :final nestedCalls,
      ):
        _update(
          _ensureRun().withToolCall(
            AiToolCallBlock(
              id: 'block_$toolCallId',
              callId: toolCallId,
              toolName: toolName,
              arguments: arguments,
              status: AiToolCallStatus.cancelled,
              result: output,
              metadata: metadata,
              errorMessage: reason,
              nestedCalls: nestedCalls,
            ),
          ),
          immediate: true,
        );
      default:
        break;
    }
  }

  /// SpawnAgent 结束后清空并释放保活；后续展示交回已落库的 tool result。
  void clear({String? runId}) {
    if (runId != null && _runId != runId) {
      return;
    }
    _runId = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _pendingNotify = false;
    _current = null;
    _lease?.close();
    _lease = null;
    if (ref.mounted) {
      state = null;
    }
  }

  AgentRunState _ensureRun() {
    return _current ??= AgentRunState(
      agentId: _runId ?? callId,
      agentName: '',
      round: 0,
    );
  }

  void _update(AgentRunState next, {bool immediate = false}) {
    // 调用方每次事件都重新 read notifier；这里只防御持有了已释放实例的情况。
    if (!ref.mounted) {
      return;
    }
    _current = next;
    _lease ??= ref.keepAlive();
    if (immediate) {
      _flush();
      return;
    }
    if (_notifyTimer != null) {
      _pendingNotify = true;
      return;
    }
    _flush();
    _notifyTimer = Timer(_notifyWindow, _onNotifyWindowElapsed);
  }

  void _onNotifyWindowElapsed() {
    _notifyTimer = null;
    if (!_pendingNotify) {
      return;
    }
    _flush();
    // 窗口内仍有增量，继续开下一个窗口，保证持续 delta 也按固定频率发布。
    _notifyTimer = Timer(_notifyWindow, _onNotifyWindowElapsed);
  }

  void _flush() {
    _pendingNotify = false;
    if (!ref.mounted) {
      return;
    }
    state = _current;
  }
}
