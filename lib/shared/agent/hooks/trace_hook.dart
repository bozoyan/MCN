// 职责: 捕获 Agent 生命周期事件，累计 turn 级别数据，委托 TraceReporterService 上报
// 关联文件:
//   lib/shared/agent/agent_hook.dart
//   lib/shared/agent/agent_event.dart
//   lib/shared/agent/client.dart (AiUsage)
//   lib/shared/services/ai/trace_reporter_service.dart
//

import 'dart:async';

import '../../services/ai/tool_error_normalize.dart';
import '../agent_hook.dart';
import '../agent_event.dart' show AgentRoundResult;
import '../client.dart'
    show AiUsage, IncompleteModelResponseException, isContextLengthExceeded;
import '../../logger/app_logger.dart';
import '../../services/ai/trace_reporter_service.dart' hide safeErrorTypeName;

final _log = AppLogger.forModule('TraceHook');

/// 匿名 trace 钩子 — 捕获 turn 生命周期事件并委托 [TraceReporterService] 上报。
///
/// 事件映射：
/// - [onStart] → turn_start
/// - [afterLLM] → 累计 turn 用量 + request_count
/// - [afterToolCall] → tool_call_count + 失败时 tool_call_error（含 error_code/collection/repeat）
/// - [onLLMError] → 累计流式问题，turn 结束时写一条 stream_retry_summary
/// - [onError] → request_error（最终失败）
/// - [onCancelled] → 标记正常取消，不写 tool/request error
/// - [onEnd] → retry summary / turn_cancelled / turn_end
class TraceHook extends AgentHook {
  final TraceReporterService _reporter;
  final String? Function() _sessionId;
  final String? Function() _model;
  final String? Function()? _providerId;
  final String Function() _sessionMode;
  final String? Function()? _cancelSource;

  // turn 级别累计
  int _turnRequestCount = 0;
  int _turnToolCallCount = 0;
  AiUsage _turnUsage = const AiUsage.empty();
  final Map<String, int> _streamIssueCounts = <String, int>{};
  _TraceTurnOutcome _turnOutcome = _TraceTurnOutcome.unknown;

  TraceHook({
    required this._reporter,
    required this._sessionId,
    required this._model,
    this._providerId,
    required this._sessionMode,
    this._cancelSource,
  });

  TraceHook copyWith({
    String? Function()? sessionId,
    String? Function()? model,
    String? Function()? providerId,
    String? Function()? cancelSource,
  }) {
    return TraceHook(
      reporter: _reporter,
      sessionId: sessionId ?? _sessionId,
      model: model ?? _model,
      providerId: providerId ?? _providerId,
      sessionMode: _sessionMode,
      cancelSource: cancelSource ?? _cancelSource,
    );
  }

  /// Turn 开始：重置 turn 级累计 + 入队 turn_start。
  @override
  FutureOr<HookAction<String>> onStart(String task) async {
    _turnRequestCount = 0;
    _turnToolCallCount = 0;
    _turnUsage = const AiUsage.empty();
    _streamIssueCounts.clear();
    _turnOutcome = _TraceTurnOutcome.unknown;
    final sid = _sessionId();
    final model = _model();
    final sessionMode = _sessionMode();
    if (_log.isDebugEnabled) {
      _log.debug('onStart sid=$sid model=$model mode=$sessionMode');
    }
    if (sid != null && model != null) {
      await _reporter.onTurnStart(sid, model, sessionMode: sessionMode);
    }
    return const HookAction.proceed();
  }

  /// LLM 请求完成后：累加 turn 用量 + request_count++。
  @override
  FutureOr<HookAction<AgentRoundResult>> afterLLM(
    AgentRoundResult round,
  ) async {
    _turnRequestCount++;
    final usage = round.usage;
    if (usage != null) {
      _turnUsage = AiUsage(
        inputTokens: _turnUsage.inputTokens + usage.inputTokens,
        outputTokens: _turnUsage.outputTokens + usage.outputTokens,
        cacheReadTokens: _turnUsage.cacheReadTokens + usage.cacheReadTokens,
        cacheWriteTokens: _turnUsage.cacheWriteTokens + usage.cacheWriteTokens,
        reasoningTokens: _turnUsage.reasoningTokens + usage.reasoningTokens,
      );
    }
    if (_log.isDebugEnabled) {
      _log.debug('afterLLM req=$_turnRequestCount usage=${usage != null}');
    }
    return const HookAction.proceed();
  }

  /// Tool call 执行完成后：tool_call_count++，失败时上报 tool_call_error。
  @override
  FutureOr<HookAction<AfterToolCallContext>> afterToolCall(
    AfterToolCallContext ctx,
  ) async {
    _turnToolCallCount++;
    if (ctx.result['cancelled'] == true ||
        ctx.result['skipped'] == true ||
        ctx.result['error_code'] == 'user_cancelled') {
      return const HookAction.proceed();
    }
    final metadata = ctx.result['_metadata'];
    if (metadata is Map && metadata['tool_error_reported'] == true) {
      return const HookAction.proceed();
    }
    final ok = toolResultIsSuccess(ctx.result);
    final sid = _sessionId();
    if (ok) {
      return const HookAction.proceed();
    }
    final model = _model();
    final sessionMode = _sessionMode();
    if (ctx.source == AgentToolSource.mcp) {
      if (sid != null && model != null) {
        final code = ctx.result['error_code'];
        await _reporter.onToolCallError(
          sid,
          model,
          'MCP',
          sessionMode: sessionMode,
          providerId: _providerId?.call(),
          result: {
            'ok': false,
            'error_code':
                code is String && RegExp(r'^mcp_[a-z_]+$').hasMatch(code)
                ? code
                : 'mcp_error',
          },
          toolInput: const {},
        );
      }
      return const HookAction.proceed();
    }
    if (_log.isDebugEnabled) {
      _log.debug(
        'afterToolCall failed tool=${ctx.call.toolName} '
        'code=${ctx.result['error_code']} collection=${ctx.result['collection']}',
      );
    }
    if (sid != null && model != null) {
      await _reporter.onToolCallError(
        sid,
        model,
        ctx.call.toolName,
        sessionMode: sessionMode,
        providerId: _providerId?.call(),
        result: ctx.result,
        toolInput: ctx.call.arguments,
      );
    }
    return const HookAction.proceed();
  }

  /// 在异常被转换为安全工具结果前上报；后台任务结束后也可独立调用。
  /// 诊断字段只进入 Outbox，不写回模型或 UI 可见的工具结果。
  Future<bool> reportToolException({
    required String toolName,
    required Map<String, dynamic> result,
    required Object error,
    required StackTrace stackTrace,
    String? model,
  }) async {
    try {
      final sid = _sessionId();
      final resolvedModel = model ?? _model();
      if (sid == null || resolvedModel == null) {
        return false;
      }
      await _reporter.onToolCallError(
        sid,
        resolvedModel,
        toolName,
        sessionMode: _sessionMode(),
        providerId: _providerId?.call(),
        result: {
          ...result,
          'exception_type': safeErrorTypeName(error),
          'exception_message': sanitizeExceptionMessage(error),
          'stack_top': sanitizeStackTop(stackTrace),
        },
      );
      return true;
    } catch (reportError, reportStack) {
      _log.warning(
        'tool exception report failed tool=$toolName '
        'error=$reportError\n$reportStack',
      );
      return false;
    }
  }

  /// LLM 调用出错时触发：只累计分类；turn 结束时汇总到 trace。
  ///
  /// 旁路观测，不影响 retry 决策（返回 [LLMErrorAction.proceed]）。
  @override
  FutureOr<LLMErrorAction> onLLMError(
    Object error,
    int attempt, {
    bool isStreamError = false,
  }) async {
    final sid = _sessionId();
    final model = _model();
    if (_log.isDebugEnabled) {
      _log.debug(
        'onLLMError sid=$sid model=$model attempt=$attempt error=$error',
      );
    }
    if (isStreamError &&
        !isContextLengthExceeded(error) &&
        sid != null &&
        model != null) {
      final category = classifyStreamError(error);
      _streamIssueCounts.update(
        category,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return const LLMErrorAction.proceed();
  }

  @override
  FutureOr<void> onIncompleteResponse(
    IncompleteModelResponseException error, {
    required bool willRetry,
  }) {
    if (willRetry) {
      final category = classifyStreamError(error);
      _streamIssueCounts.update(
        category,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  @override
  void onDone(String finalText) {
    _turnOutcome = _TraceTurnOutcome.recovered;
  }

  /// Agent 出错时触发：上报 request_error（最终失败）。
  @override
  FutureOr<void> onError(Object error, StackTrace? stackTrace) async {
    _turnOutcome = _TraceTurnOutcome.failed;
    final sid = _sessionId();
    final model = _model();
    final sessionMode = _sessionMode();
    if (_log.isDebugEnabled) {
      _log.debug(
        'onError sid=$sid model=$model mode=$sessionMode error=$error',
      );
    }
    if (sid != null && model != null) {
      await _reporter.onRequestError(
        sid,
        model,
        error,
        providerId: _providerId?.call(),
        sessionMode: sessionMode,
      );
    }
  }

  @override
  void onCancelled() {
    _turnOutcome = _TraceTurnOutcome.cancelled;
  }

  /// Turn 结束：入队 turn_end（含本 turn 累计数据）。
  /// onEnd 在成功/失败/取消时都会触发，确保 turn_end 不丢失。
  @override
  FutureOr<void> onEnd() async {
    final sid = _sessionId();
    final model = _model();
    final sessionMode = _sessionMode();
    if (_log.isDebugEnabled) {
      _log.debug(
        'onEnd sid=$sid model=$model mode=$sessionMode '
        'req=$_turnRequestCount tools=$_turnToolCallCount',
      );
    }
    if (sid != null && model != null) {
      final cancelSource = _cancelSource?.call();
      // failed / recovered 是明确终态，优先于晚到的 dispose/cancel source，
      // 避免成功或失败 turn 被误标成 cancelled。
      // unknown + cancelSource：覆盖未走到 onCancelled 的控制流取消。
      final wasCancelled =
          _turnOutcome == _TraceTurnOutcome.cancelled ||
          (_turnOutcome == _TraceTurnOutcome.unknown && cancelSource != null);
      final outcome = switch (_turnOutcome) {
        _TraceTurnOutcome.failed => 'failed',
        _TraceTurnOutcome.recovered => 'recovered',
        _TraceTurnOutcome.cancelled => 'cancelled',
        _TraceTurnOutcome.unknown => wasCancelled ? 'cancelled' : 'unknown',
      };
      if (_streamIssueCounts.isNotEmpty) {
        await _reporter.onStreamRetrySummary(
          sid,
          model,
          providerId: _providerId?.call(),
          counts: Map<String, int>.unmodifiable(_streamIssueCounts),
          outcome: outcome,
          sessionMode: sessionMode,
        );
      }
      if (wasCancelled) {
        await _reporter.onTurnCancelled(
          sid,
          model,
          source: cancelSource ?? 'parent_cancel',
          sessionMode: sessionMode,
        );
      }
      await _reporter.onTurnEnd(
        sid,
        model,
        _turnRequestCount,
        _turnToolCallCount,
        _turnUsage,
        sessionMode: sessionMode,
      );
    }
  }
}

/// 构建匿名 trace hooks。sessionId 或 model 不可用时 TraceHook 会跳过上报。
List<AgentHook> buildTraceHooks({
  required TraceReporterService reporter,
  required String? Function() sessionId,
  required String? Function() model,
  required String sessionMode,
  String? Function()? providerId,
  String? Function()? cancelSource,
}) {
  return [
    TraceHook(
      reporter: reporter,
      sessionId: sessionId,
      model: model,
      providerId: providerId,
      sessionMode: () => sessionMode,
      cancelSource: cancelSource,
    ),
  ];
}

enum _TraceTurnOutcome { unknown, recovered, failed, cancelled }
