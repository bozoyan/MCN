// 职责: Agent 日志钩子 — 统一替代 process loop 中散落的 debugPrint
// 关联文件:
//   lib/shared/agent/agent_hook.dart
//   lib/shared/agent/agent.dart

import 'dart:async';

import '../../logger/app_logger.dart';

import '../../services/ai/tool_error_normalize.dart';
import '../agent_hook.dart';
import '../agent_event.dart' show AgentRoundResult;

final _log = AppLogger.forModule('AgentHook');

class LoggingHook extends AgentHook {
  const LoggingHook({this.tag = 'Agent'});

  final String tag;
  @override
  FutureOr<HookAction<String>> onStart(String task) {
    if (_log.isDebugEnabled) {
      _log.debug('tag=$tag process start taskLength=${task.length}');
    }
    return const HookAction.proceed();
  }

  @override
  FutureOr<HookAction<void>> beforeRound(int roundIndex) {
    if (_log.isDebugEnabled) {
      _log.debug('tag=$tag round start round=$roundIndex');
    }
    return const HookAction.proceed();
  }

  @override
  FutureOr<HookAction<AgentRoundResult>> afterLLM(AgentRoundResult round) {
    if (_log.isDebugEnabled) {
      _log.debug(
        'tag=$tag round resolved toolCalls=${round.toolCalls.length} '
        'textChars=${round.text.length} thinkingChars=${round.thinking.length}',
      );
    }
    return const HookAction.proceed();
  }

  @override
  FutureOr<HookAction<BeforeToolCallContext>> beforeToolCall(
    BeforeToolCallContext ctx,
  ) {
    if (_log.isDebugEnabled) {
      _log.debug(
        'tag=$tag tool start name=${ctx.source == AgentToolSource.mcp ? 'MCP' : ctx.call.toolName} callId=${ctx.call.callId}',
      );
    }
    return const HookAction.proceed();
  }

  @override
  FutureOr<HookAction<AfterToolCallContext>> afterToolCall(
    AfterToolCallContext ctx,
  ) {
    if (_log.isDebugEnabled) {
      _log.debug(
        'tag=$tag tool result name=${ctx.source == AgentToolSource.mcp ? 'MCP' : ctx.call.toolName} callId=${ctx.call.callId} '
        'ok=${toolResultIsSuccess(ctx.result)} keys=${ctx.result.keys.join(',')}',
      );
    }
    return const HookAction.proceed();
  }

  @override
  void afterRound(AfterRoundContext ctx) {
    if (_log.isDebugEnabled) {
      _log.debug(
        'tag=$tag round complete round=${ctx.roundIndex} '
        'textChars=${ctx.roundResult.text.length} '
        'toolCalls=${ctx.roundResult.toolCalls.length}',
      );
    }
  }

  @override
  void onDone(String finalText) {
    if (_log.isDebugEnabled) {
      _log.debug('tag=$tag done finalTextChars=${finalText.length}');
    }
  }

  @override
  void onError(Object error, StackTrace? stackTrace) {
    _log.error('tag=$tag error=$error');
  }

  @override
  void onCancelled() {
    if (_log.isDebugEnabled) {
      _log.debug('tag=$tag cancelled');
    }
  }

  @override
  void onEnd() {
    if (_log.isDebugEnabled) {
      _log.debug('tag=$tag process end');
    }
  }
}
