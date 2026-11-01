// 职责: 限制 MCP 诊断输出长度。
// 关联文件:
//   lib/shared/models/mcp/config.dart
//   lib/shared/services/mcp/runtime.dart
//   lib/shared/services/mcp/client_adapter.dart
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import '../../models/mcp/config.dart';

String mcpDiagnostic(
  Object error,
  McpServerConfig? config, {
  int? maxCharacters = 2048,
}) {
  final message = error.toString();
  return maxCharacters == null
      ? message
      : String.fromCharCodes(message.runes.take(maxCharacters));
}

class McpNeedsAuth implements Exception {
  const McpNeedsAuth({this.requestRejected = false});
  final bool requestRejected;
  @override
  String toString() => 'mcp_needs_auth: Sign in to this MCP service.';
}

/// The server answered the request with HTTP 401/403, so it never ran.
class McpCredentialsRejected implements Exception {
  const McpCredentialsRejected(this.statusCode, this.cause);
  final int statusCode;
  final Object cause;
  @override
  String toString() =>
      'mcp_unauthorized: MCP server rejected the credentials '
      '(HTTP $statusCode): $cause';
}

enum McpFailureKind {
  command_not_found,
  working_directory,
  process,
  protocol,
  credentials,
  oauth_client,
  oauth_callback,
  connection,
}

class McpConfigurationFailure implements Exception {
  const McpConfigurationFailure(this.kind, this.diagnostic);
  final McpFailureKind kind;
  final String diagnostic;
  @override
  String toString() => diagnostic;
}

McpFailureKind mcpFailureKind(Object error, {bool authorization = false}) {
  if (error is McpConfigurationFailure) {
    return error.kind;
  }
  if (error is ProcessException) {
    return error.errorCode == 2
        ? McpFailureKind.command_not_found
        : McpFailureKind.process;
  }
  // SDK stdio startup wraps ProcessException in StateError and drops its code.
  if (error is StateError &&
      error.message.startsWith(
        'Failed to start server process: ProcessException:',
      )) {
    return error.message.contains('No such file or directory') ||
            error.message.contains('The system cannot find')
        ? McpFailureKind.command_not_found
        : McpFailureKind.process;
  }
  if (authorization) {
    final text = error.toString().toLowerCase();
    if (text.contains('client') || text.contains('registration')) {
      return McpFailureKind.oauth_client;
    }
    if (text.contains('redirect') ||
        text.contains('callback') ||
        text.contains('issuer') ||
        text.contains('state')) {
      return McpFailureKind.oauth_callback;
    }
  }
  if (error is sdk.UnauthorizedError ||
      error is McpNeedsAuth ||
      error is McpCredentialsRejected) {
    return McpFailureKind.credentials;
  }
  if (error is sdk.McpError || error is FormatException) {
    return McpFailureKind.protocol;
  }
  return McpFailureKind.connection;
}
