// 职责: 保存 Codemode 子调用的展示记录、真实资源身份及副作用状态。
// 关联文件:
//   lib/shared/models/ai_message_block.dart
//   lib/shared/services/ai/codemode/orchestrator.dart

import 'package:json_annotation/json_annotation.dart';

import '../utils/resource_path.dart';

part 'ai_nested_tool_call.g.dart';

enum AiNestedToolStatus { running, success, error, cancelled, rejected }

enum AiToolEffectStatus { none, confirmed, unknown }

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class AiNestedToolCall {
  const AiNestedToolCall({
    required this.callId,
    required this.toolName,
    this.targetPath,
    this.argumentsPreview = '',
    this.resultPreview = '',
    this.status = AiNestedToolStatus.running,
    this.durationMs,
    this.resourceId,
    this.workingChangeId,
    this.workingChangeScope,
    this.hasMultipleWorkingChanges = false,
    this.effectStatus = AiToolEffectStatus.none,
    this.errorCode,
    this.source = 'builtin',
    this.server,
    this.remoteToolName,
    this.sourceSessionId,
    this.parentCallId,
    this.executionState,
  });

  final String callId;
  final String toolName;
  final String? targetPath;
  final String argumentsPreview;
  final String resultPreview;
  final AiNestedToolStatus status;
  final int? durationMs;
  final String? resourceId;
  final String? workingChangeId;
  final AiWorkingChangeScope? workingChangeScope;
  final bool hasMultipleWorkingChanges;
  final AiToolEffectStatus effectStatus;
  final String? errorCode;
  final String source;
  final String? server;
  final String? remoteToolName;
  final String? sourceSessionId;
  final String? parentCallId;
  final String? executionState;

  AiNestedToolCall copyWith({
    String? targetPath,
    String? argumentsPreview,
    String? resultPreview,
    AiNestedToolStatus? status,
    int? durationMs,
    String? resourceId,
    String? workingChangeId,
    AiWorkingChangeScope? workingChangeScope,
    bool? hasMultipleWorkingChanges,
    AiToolEffectStatus? effectStatus,
    String? errorCode,
    String? executionState,
  }) => AiNestedToolCall(
    callId: callId,
    toolName: toolName,
    source: source,
    server: server,
    remoteToolName: remoteToolName,
    sourceSessionId: sourceSessionId,
    parentCallId: parentCallId,
    executionState: executionState ?? this.executionState,
    targetPath: targetPath ?? this.targetPath,
    argumentsPreview: argumentsPreview ?? this.argumentsPreview,
    resultPreview: resultPreview ?? this.resultPreview,
    status: status ?? this.status,
    durationMs: durationMs ?? this.durationMs,
    resourceId: resourceId ?? this.resourceId,
    workingChangeId: workingChangeId ?? this.workingChangeId,
    workingChangeScope: workingChangeScope ?? this.workingChangeScope,
    hasMultipleWorkingChanges:
        hasMultipleWorkingChanges ?? this.hasMultipleWorkingChanges,
    effectStatus: effectStatus ?? this.effectStatus,
    errorCode: errorCode ?? this.errorCode,
  );

  /// Retain a real identity and a bounded, explicit turn/target review scope.
  /// A bulk operation never appends an unbounded list of change IDs or snapshots.
  AiNestedToolCall withWorkingChange(
    String id,
    AiWorkingChangeScope scope, {
    bool multiple = false,
  }) {
    final previous = workingChangeScope;
    if (previous != null &&
        (previous.sourceSessionId != scope.sourceSessionId ||
            previous.sourceTurnId != scope.sourceTurnId)) {
      throw StateError('Nested changes must belong to the same source turn');
    }
    return copyWith(
      workingChangeId: workingChangeId ?? id,
      hasMultipleWorkingChanges:
          hasMultipleWorkingChanges ||
          multiple ||
          (workingChangeId != null && workingChangeId != id),
      workingChangeScope: previous == null ? scope : previous.cover(scope),
    );
  }

  factory AiNestedToolCall.fromJson(Map<String, dynamic> json) =>
      _$AiNestedToolCallFromJson(json);
  Map<String, dynamic> toJson() => _$AiNestedToolCallToJson(this);
}

/// Scope for the existing turn-level change review, not child-exclusive ownership.
@JsonSerializable(fieldRename: FieldRename.snake)
class AiWorkingChangeScope {
  const AiWorkingChangeScope({
    required this.sourceSessionId,
    required this.sourceTurnId,
    required this.resourcePath,
  });
  final String sourceSessionId;
  final String sourceTurnId;
  final String resourcePath;

  AiWorkingChangeScope cover(AiWorkingChangeScope other) {
    final left = canonicalResourcePath(
      resourcePath,
    ).split('/').where((part) => part.isNotEmpty).toList();
    final right = canonicalResourcePath(
      other.resourcePath,
    ).split('/').where((part) => part.isNotEmpty).toList();
    var common = 0;
    while (common < left.length &&
        common < right.length &&
        left[common] == right[common]) {
      common++;
    }
    return AiWorkingChangeScope(
      sourceSessionId: sourceSessionId,
      sourceTurnId: sourceTurnId,
      resourcePath: canonicalResourcePath(left.take(common).join('/')),
    );
  }

  bool contains({
    required String? sessionId,
    required String? turnId,
    required String path,
  }) =>
      sessionId == sourceSessionId &&
      turnId == sourceTurnId &&
      (resourcePath == '/' || resourcePathIsWithin(path, resourcePath));

  factory AiWorkingChangeScope.fromJson(Map<String, dynamic> json) =>
      _$AiWorkingChangeScopeFromJson(json);
  Map<String, dynamic> toJson() => _$AiWorkingChangeScopeToJson(this);
}

/// Returns a valid Unicode prefix within the UTF-8 budget.
List<AiNestedToolCall> settleNestedCalls(
  List<AiNestedToolCall> calls, {
  required bool cancelled,
}) => [
  for (final call in calls)
    if (call.status == AiNestedToolStatus.running)
      call.copyWith(
        status: cancelled
            ? AiNestedToolStatus.cancelled
            : AiNestedToolStatus.error,
        errorCode: cancelled ? 'user_cancelled' : 'tool_interrupted',
      )
    else
      call,
];
