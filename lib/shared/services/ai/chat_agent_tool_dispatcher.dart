// 职责: 将主聊天的子 agent 委派、传话和停止路由到当前会话运行态，其余工具委托底层调度器。
// 关联文件:
//   lib/shared/agent/agent_tool_dispatcher.dart
//   lib/shared/services/ai/spawn_agent_handler.dart
//   lib/shared/providers/spawn_agent_run_providers.dart
//   lib/shared/services/ai/tools.dart

import 'dart:async';

import '../../logger/app_logger.dart';
import '../../providers/spawn_agent_run_providers.dart';
import 'spawn_agent_handler.dart';
import 'tool_error_normalize.dart';
import 'tool_result_payloads.dart';
import 'tools.dart';
import 'codemode/tool.dart';

final _dispatcherLog = AppLogger.forModule('ChatAgentToolDispatcher');

typedef ChatSubAgentStarter =
    SpawnAgentRun Function(
      Map<String, dynamic> input,
      String? callId,
      ToolExecutionContext? context, {
      required bool background,
    });

typedef ChatCodemodeRunner =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> input,
      String callId,
      ToolExecutionContext context,
    );

typedef ChatSubAgentResumer =
    Future<SpawnAgentRun> Function(
      String sessionId,
      String message,
      String? callId,
      ToolExecutionContext? context,
    );

class ChatAgentToolDispatcher implements AgentToolDispatcher {
  const ChatAgentToolDispatcher({
    required this.inner,
    required this.startSubAgent,
    required this.resumeSubAgent,
    required this.subAgents,
    this.runCodemode,
    this.codemodeAllowed,
  });

  final ChatCodemodeRunner? runCodemode;
  final bool Function()? codemodeAllowed;
  bool get _hasCodemode =>
      runCodemode != null && codemodeAllowed?.call() == true;

  final AgentToolDispatcher inner;
  final ChatSubAgentStarter startSubAgent;
  final ChatSubAgentResumer resumeSubAgent;
  final SpawnAgentSessionRuns subAgents;

  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) async {
    if (name == codemodeToolName) {
      if (!_hasCodemode ||
          callId == null ||
          context == null ||
          context.parentToolCallId != null) {
        return {
          'ok': false,
          'error_code': 'codemode_tool_forbidden',
          'error': 'Codemode is only available to the main chat Agent.',
        };
      }
      return runCodemode!(input, callId, context);
    }
    if (name != spawnAgentToolName &&
        name != sendAgentMessageToolName &&
        name != stopAgentToolName) {
      return inner.executeTool(
        name: name,
        input: input,
        callId: callId,
        emitEvents: emitEvents,
        context: context,
      );
    }
    final parentSessionId = subAgents.parentSessionId;
    if (parentSessionId == null ||
        context?.sessionId != parentSessionId ||
        (context?.sourceSessionId != null &&
            context!.sourceSessionId != parentSessionId)) {
      return {
        'ok': false,
        'error_code': ToolErrorCode.permission_denied.name,
        'error':
            'Sub-agent tools are only available to the current parent session.',
      };
    }
    if (name == spawnAgentToolName) {
      if (input.containsKey('session_id') || input.containsKey('sessionId')) {
        return {
          'ok': false,
          'error_code': ToolErrorCode.invalid_argument.name,
          'error':
              'SpawnAgent creates a new session. Use SendAgentMessage to continue an existing session.',
        };
      }
      final background = input['background'] ?? true;
      if (background is! bool) {
        return {
          'ok': false,
          'error_code': ToolErrorCode.invalid_argument.name,
          'error': 'background must be a boolean.',
        };
      }
      final SpawnAgentRun run;
      try {
        run = startSubAgent(input, callId, context, background: background);
      } on StateError catch (error, stackTrace) {
        _dispatcherLog.warning(
          'Sub-agent start rejected sessionId=$parentSessionId callId=$callId '
          'error=$error\n$stackTrace',
        );
        return {
          'ok': false,
          'error_code': ToolErrorCode.unavailable.name,
          'error':
              'Sub-agent could not start. The session may be busy or stopping, or the original turn is unavailable.',
        };
      }
      if (!background) {
        final result = await run.result;
        return {
          ...result,
          if (result['ok'] == true)
            'hint': '如需对本任务补充、纠错或复审，使用 SendAgentMessage，沿用此 session_id。',
        };
      }
      return _backgroundAcknowledgement(run, context);
    }
    final sessionId = input['session_id'];
    final message = input['message'];
    if (sessionId is! String ||
        sessionId.trim().isEmpty ||
        (name == sendAgentMessageToolName &&
            (message is! String || message.trim().isEmpty))) {
      return {
        'ok': false,
        'error_code': ToolErrorCode.invalid_argument.name,
        'error': name == sendAgentMessageToolName
            ? 'session_id and a non-empty message are required.'
            : 'session_id is required.',
      };
    }
    // 当前执行的收件箱关闭后不能自动续跑，必须等该 run 完成收尾。
    final runId = subAgents.currentRunId(sessionId.trim());
    if (runId == null && name == sendAgentMessageToolName) {
      try {
        final run = await resumeSubAgent(
          sessionId.trim(),
          message as String,
          callId,
          context,
        );
        final result = await _backgroundAcknowledgement(run, context);
        return {...result, 'accepted': result['ok'] == true};
      } on SpawnAgentResumeException catch (error) {
        return {
          'ok': false,
          'accepted': false,
          'error_code': error.code,
          'error': error.message,
        };
      } on StateError catch (error, stackTrace) {
        _dispatcherLog.warning(
          'Sub-agent continuation rejected sessionId=$parentSessionId callId=$callId error=$error\n$stackTrace',
        );
        return {
          'ok': false,
          'accepted': false,
          'error_code': ToolErrorCode.failed_precondition.name,
          'error':
              'Sub-agent continuation could not start. The session may be busy or stopping, or the original turn is unavailable.',
        };
      }
    }
    if (runId == null) {
      return {
        'ok': false,
        'error_code': ToolErrorCode.not_found.name,
        'error': 'No active sub-agent execution belongs to this session.',
      };
    }
    final accepted = name == sendAgentMessageToolName
        ? subAgents.sendMessage(runId, message as String)
        : subAgents.cancelRun(runId, source: 'stop_agent_tool');
    return {
      'ok': accepted,
      'accepted': accepted,
      if (accepted)
        'status': name == sendAgentMessageToolName ? 'accepted' : 'stopping',
      'session_id': sessionId.trim(),
      'run_id': runId,
      if (!accepted) ...{
        'error_code': ToolErrorCode.failed_precondition.name,
        'error':
            'Sub-agent did not accept the request. It may be stopping or finishing; wait for it to finish before sending again.',
      },
    };
  }

  Future<Map<String, dynamic>> _backgroundAcknowledgement(
    SpawnAgentRun run,
    ToolExecutionContext? context,
  ) async {
    // 只取消父工具对后台启动回执的等待；run 仍归会话持有。
    // 回退才能先收尾父执行，再在守卫内取消并等待受影响的子运行。
    final cancelledWait = Completer<bool?>();
    final unlink = context?.cancellationToken?.onCancel(
      () => cancelledWait.complete(null),
    );
    final bool? started;
    try {
      started = await Future.any<bool?>([run.started, cancelledWait.future]);
    } finally {
      unlink?.call();
    }
    if (started == null) {
      return aiCancelledToolResultPayload();
    }
    if (!started) {
      return run.result;
    }
    return {
      'ok': true,
      'status': 'running',
      'session_id': run.subSessionId,
      'run_id': run.runId,
      'hint':
          '子 agent 正在后台执行。如需在执行期间追加要求，使用 SendAgentMessage，沿用此 session_id。完成或失败后会自动通知。需要结果才能继续的步骤，请等待完成通知。',
    };
  }

  @override
  List<String> allToolNames() => [
    ...inner.allToolNames(),
    if (_hasCodemode) codemodeToolName,
  ];

  @override
  List<ToolDef> allToolDefs() => [
    ...inner.allToolDefs(),
    if (_hasCodemode) codemodeToolDef,
  ];

  @override
  List<ToolDef> toolDefsForNames(List<String> names) {
    return [
      ...inner.toolDefsForNames(names),
      if (_hasCodemode && names.contains(codemodeToolName)) codemodeToolDef,
    ];
  }
}
