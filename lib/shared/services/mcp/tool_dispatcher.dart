// 职责: 校验 MCP 调用身份和参数，统一记录未发送、已确认与结果未知状态。
// 关联文件:
//   lib/shared/services/mcp/runtime.dart
//   lib/shared/services/mcp/result_adapter.dart
//   lib/shared/models/mcp/call_result.dart
import 'dart:async';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import '../../models/mcp/call_result.dart';
import 'runtime.dart';
import 'client_adapter.dart';
import 'result_adapter.dart';
import 'diagnostics.dart';

class McpToolDispatcher {
  McpToolDispatcher(this.runtime, {this.session});
  final McpRuntime runtime;
  final McpSession? session;

  Future<McpCallResult> call(
    String name,
    Map<String, dynamic> arguments, {
    sdk.AbortSignal? signal,
    void Function(Map<String, dynamic>)? onProgress,
  }) async {
    McpCallResult rejected(String code, String message) => McpCallResult(
      executionState: McpExecutionState.not_started,
      errorCode: code,
      error: message,
      rejected: true,
    );
    if (session?.toolFailure(name) case final failure?) {
      return rejected(failure.code, failure.toString());
    }
    final identity = runtime.tools[name] ?? runtime.knownTools[name];
    if (identity == null) {
      return rejected(
        'mcp_tool_not_found',
        'MCP tool not found; discover the current tools.',
      );
    }
    final config = runtime.configs
        .where((s) => s.name == identity.server)
        .firstOrNull;
    if (config == null || !config.enabled) {
      return rejected(
        'mcp_server_unavailable',
        'MCP server is disabled or deleted.',
      );
    }
    if (signal?.aborted == true) {
      return McpCallResult(
        executionState: McpExecutionState.not_started,
        errorCode: 'mcp_cancelled',
        error: 'Cancelled before sending.',
        cancelled: true,
      );
    }
    var sent = false;
    try {
      final cancelledReady = Completer<McpConnection>();
      final subscription = signal?.onAbort.listen((_) {
        if (!cancelledReady.isCompleted) {
          cancelledReady.completeError(
            StateError('Cancelled while waiting for MCP initialization'),
          );
        }
      });
      final McpConnection connection;
      try {
        connection = await Future.any([
          session?.ensureReady(identity.server) ??
              runtime.ensureReady(identity.server),
          cancelledReady.future,
        ]);
      } finally {
        await subscription?.cancel();
      }
      final descriptor = runtime.tools[name];
      if (descriptor == null) {
        return rejected(
          'mcp_tool_not_found',
          'MCP tool is no longer available.',
        );
      }
      if ((descriptor.definition['execution'] as Map?)?['taskSupport'] ==
          'required') {
        return rejected(
          'mcp_unsupported',
          'This tool requires MCP Tasks, which are not supported.',
        );
      }
      try {
        sdk.JsonSchema.fromJson(descriptor.inputSchema).validate(arguments);
      } catch (error) {
        return rejected('mcp_invalid_arguments', mcpDiagnostic(error, config));
      }
      if (signal?.aborted == true) {
        return McpCallResult(
          executionState: McpExecutionState.not_started,
          errorCode: 'mcp_cancelled',
          error: 'Cancelled before sending.',
          cancelled: true,
        );
      }
      sent = true;
      var progressCount = 0;
      final progressClock = Stopwatch()..start();
      var lastProgressMs = -100;
      final raw = await connection.callTool(
        descriptor.rawName,
        arguments,
        signal: signal,
        onProgress: onProgress == null
            ? null
            : (progress) {
                final now = progressClock.elapsedMilliseconds;
                if (progressCount >= 64 ||
                    now - lastProgressMs < 100 ||
                    !progress.progress.isFinite) {
                  return;
                }
                progressCount++;
                lastProgressMs = now;
                onProgress({
                  'progress': progress.progress,
                  if (progress.total?.isFinite == true) 'total': progress.total,
                  if (progress.message != null)
                    'message': mcpDiagnostic(
                      progress.message!,
                      config,
                      maxCharacters: 256,
                    ),
                });
              },
      );
      return McpResultAdapter.normalize(raw);
    } catch (error) {
      if (error is McpSessionFailure) {
        return rejected(error.code, error.toString());
      }
      final cause = error is McpCommandException ? error.cause : error;
      if (cause is McpNeedsAuth) {
        await runtime.requireAuthentication(identity.server);
        return McpCallResult(
          executionState: cause.requestRejected
              ? McpExecutionState.failed
              : McpExecutionState.not_started,
          errorCode: 'mcp_needs_auth',
          error: mcpDiagnostic(cause, config),
        );
      }
      if (cause is McpCredentialsRejected) {
        return McpCallResult(
          executionState: McpExecutionState.failed,
          errorCode: 'mcp_unauthorized',
          error: mcpDiagnostic(cause, config),
          recovery:
              'The server refused the request before running the tool. Retrying with the same credentials will fail; ask the user to check this MCP server\'s credentials in settings.',
        );
      }
      final cancelled = signal?.aborted == true;
      final timedOut =
          cause is TimeoutException ||
          (cause is sdk.McpError &&
              cause.code == sdk.ErrorCode.requestTimeout.value);
      final tooLarge = cause is McpResponseUnavailable;
      final invalidResponse =
          cause is FormatException ||
          (cause is sdk.McpError &&
              cause.message.startsWith('Structured content does not match'));
      final rejectedByProtocol =
          cause is sdk.McpError &&
          [
            sdk.ErrorCode.invalidRequest.value,
            sdk.ErrorCode.invalidParams.value,
            sdk.ErrorCode.methodNotFound.value,
          ].contains(cause.code) &&
          !cause.message.startsWith('Structured content does not match');
      if (sent && rejectedByProtocol) {
        return McpCallResult(
          executionState: McpExecutionState.failed,
          errorCode: 'mcp_protocol_error',
          error: mcpDiagnostic(error, config),
        );
      }
      return McpCallResult(
        executionState: sent
            ? McpExecutionState.unknown
            : McpExecutionState.not_started,
        errorCode: cancelled
            ? 'mcp_cancelled'
            : tooLarge
            ? 'mcp_result_unavailable'
            : invalidResponse
            ? 'mcp_invalid_response'
            : timedOut
            ? 'mcp_timeout'
            : sent
            ? 'mcp_connection_lost'
            : 'mcp_connection_failed',
        error: mcpDiagnostic(error, config),
        cancelled: cancelled,
        recovery: sent
            ? 'Verify external state before another call. Do not automatically replay this operation.'
            : null,
      );
    }
  }
}
