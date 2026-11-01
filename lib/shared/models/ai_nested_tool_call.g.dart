// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_nested_tool_call.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AiNestedToolCall _$AiNestedToolCallFromJson(Map<String, dynamic> json) =>
    AiNestedToolCall(
      callId: json['call_id'] as String,
      toolName: json['tool_name'] as String,
      targetPath: json['target_path'] as String?,
      argumentsPreview: json['arguments_preview'] as String? ?? '',
      resultPreview: json['result_preview'] as String? ?? '',
      status:
          $enumDecodeNullable(_$AiNestedToolStatusEnumMap, json['status']) ??
          AiNestedToolStatus.running,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      resourceId: json['resource_id'] as String?,
      workingChangeId: json['working_change_id'] as String?,
      workingChangeScope: json['working_change_scope'] == null
          ? null
          : AiWorkingChangeScope.fromJson(
              json['working_change_scope'] as Map<String, dynamic>,
            ),
      hasMultipleWorkingChanges:
          json['has_multiple_working_changes'] as bool? ?? false,
      effectStatus:
          $enumDecodeNullable(
            _$AiToolEffectStatusEnumMap,
            json['effect_status'],
          ) ??
          AiToolEffectStatus.none,
      errorCode: json['error_code'] as String?,
      source: json['source'] as String? ?? 'builtin',
      server: json['server'] as String?,
      remoteToolName: json['remote_tool_name'] as String?,
      sourceSessionId: json['source_session_id'] as String?,
      parentCallId: json['parent_call_id'] as String?,
      executionState: json['execution_state'] as String?,
    );

Map<String, dynamic> _$AiNestedToolCallToJson(AiNestedToolCall instance) =>
    <String, dynamic>{
      'call_id': instance.callId,
      'tool_name': instance.toolName,
      'target_path': instance.targetPath,
      'arguments_preview': instance.argumentsPreview,
      'result_preview': instance.resultPreview,
      'status': _$AiNestedToolStatusEnumMap[instance.status]!,
      'duration_ms': instance.durationMs,
      'resource_id': instance.resourceId,
      'working_change_id': instance.workingChangeId,
      'working_change_scope': instance.workingChangeScope?.toJson(),
      'has_multiple_working_changes': instance.hasMultipleWorkingChanges,
      'effect_status': _$AiToolEffectStatusEnumMap[instance.effectStatus]!,
      'error_code': instance.errorCode,
      'source': instance.source,
      'server': instance.server,
      'remote_tool_name': instance.remoteToolName,
      'source_session_id': instance.sourceSessionId,
      'parent_call_id': instance.parentCallId,
      'execution_state': instance.executionState,
    };

const _$AiNestedToolStatusEnumMap = {
  AiNestedToolStatus.running: 'running',
  AiNestedToolStatus.success: 'success',
  AiNestedToolStatus.error: 'error',
  AiNestedToolStatus.cancelled: 'cancelled',
  AiNestedToolStatus.rejected: 'rejected',
};

const _$AiToolEffectStatusEnumMap = {
  AiToolEffectStatus.none: 'none',
  AiToolEffectStatus.confirmed: 'confirmed',
  AiToolEffectStatus.unknown: 'unknown',
};

AiWorkingChangeScope _$AiWorkingChangeScopeFromJson(
  Map<String, dynamic> json,
) => AiWorkingChangeScope(
  sourceSessionId: json['source_session_id'] as String,
  sourceTurnId: json['source_turn_id'] as String,
  resourcePath: json['resource_path'] as String,
);

Map<String, dynamic> _$AiWorkingChangeScopeToJson(
  AiWorkingChangeScope instance,
) => <String, dynamic>{
  'source_session_id': instance.sourceSessionId,
  'source_turn_id': instance.sourceTurnId,
  'resource_path': instance.resourcePath,
};
