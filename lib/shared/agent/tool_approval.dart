// 职责: 按会话与独立审批身份持有冻结的工具审批，处理一次性决策、规则保存和取消。
// 关联文件:
//   lib/shared/models/tool_permission.dart
//   lib/shared/services/tool_permission_gate.dart
//   lib/shared/providers/ai_providers.dart
import 'dart:async';
import '../models/tool_permission.dart';

enum ToolApprovalOutcome { allowed, denied, cancelled }

class AiToolApprovalRequest {
  AiToolApprovalRequest({
    required this.ownerSessionId,
    required this.approvalId,
    required this.callId,
    this.displayCallId,
    required this.toolName,
    required this.action,
    required this.permissionContext,
    required this.targetPath,
    this.targetLabel,
    required Map<String, dynamic> arguments,
    required this.saveRule,
  }) : arguments = freezeToolArguments(arguments);
  final String ownerSessionId, approvalId, callId, toolName, action, targetPath;
  final String? displayCallId, targetLabel;
  final ToolPermissionContext permissionContext;
  final Map<String, dynamic> arguments;
  final Future<void> Function(
    ToolPermissionScope scope,
    ToolPermissionDecision decision,
  )
  saveRule;
  final Completer<ToolApprovalOutcome> _completer = Completer();
  bool resolving = false;
  bool saveFailed = false;
  bool get isResolved => _completer.isCompleted;
  Future<ToolApprovalOutcome> get decision => _completer.future;
}

/// A single application broker holds only pending requests; terminal requests are removed.
/// Requests are keyed by their own approval identity: several operations from one
/// tool call wait side by side and are resolved independently.
class AiToolApprovalController {
  final _changes = StreamController<List<AiToolApprovalRequest>>.broadcast();
  final _pending = <(String, String), AiToolApprovalRequest>{};
  bool _disposed = false;
  List<AiToolApprovalRequest> get pending => List.unmodifiable(_pending.values);
  List<AiToolApprovalRequest> pendingFor(String sessionId) =>
      pending.where((r) => r.ownerSessionId == sessionId).toList();
  Stream<List<AiToolApprovalRequest>> get stream => _changes.stream;
  void _publish() {
    if (!_disposed) {
      _changes.add(pending);
    }
  }

  bool _owns(AiToolApprovalRequest req) =>
      identical(_pending[(req.ownerSessionId, req.approvalId)], req);

  Future<ToolApprovalOutcome> request(AiToolApprovalRequest req) {
    if (_disposed) {
      return Future.value(ToolApprovalOutcome.cancelled);
    }
    final key = (req.ownerSessionId, req.approvalId);
    if (_pending.containsKey(key)) {
      throw StateError('Approval ${req.approvalId} is already pending.');
    }
    _pending[key] = req;
    _publish();
    return req.decision;
  }

  Future<bool> resolve(
    AiToolApprovalRequest req, {
    required bool allow,
    ToolPermissionScope? scope,
  }) async {
    if (!_owns(req) || req.resolving || req.isResolved) {
      return false;
    }
    if (scope != null && !req.permissionContext.scopes.contains(scope)) {
      throw const ToolPermissionException(
        'permission_denied',
        'This approval cannot save a rule for that scope.',
      );
    }
    req.resolving = true;
    req.saveFailed = false;
    _publish();
    try {
      if (scope != null) {
        await req.saveRule(
          scope,
          allow ? ToolPermissionDecision.allow : ToolPermissionDecision.deny,
        );
      }
      if (!_owns(req)) {
        return false;
      }
      _finish(
        req,
        allow ? ToolApprovalOutcome.allowed : ToolApprovalOutcome.denied,
      );
      return true;
    } catch (_) {
      req.saveFailed = true;
      rethrow;
    } finally {
      req.resolving = false;
      _publish();
    }
  }

  void _finish(AiToolApprovalRequest req, ToolApprovalOutcome outcome) {
    if (!_owns(req)) {
      return;
    }
    _pending.remove((req.ownerSessionId, req.approvalId));
    if (!req.isResolved) {
      req._completer.complete(outcome);
    }
    _publish();
  }

  void cancel(AiToolApprovalRequest req) =>
      _finish(req, ToolApprovalOutcome.cancelled);
  void cancelSession(String sessionId) {
    for (final req in pendingFor(sessionId)) {
      cancel(req);
    }
  }

  void dispose() {
    for (final req in pending) {
      cancel(req);
    }
    _disposed = true;
    unawaited(_changes.close());
  }
}
