// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_message_block.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AiTextBlock _$AiTextBlockFromJson(Map<String, dynamic> json) =>
    AiTextBlock(id: json['id'] as String, text: json['text'] as String);

Map<String, dynamic> _$AiTextBlockToJson(AiTextBlock instance) =>
    <String, dynamic>{'id': instance.id, 'text': instance.text};

AiThinkingBlock _$AiThinkingBlockFromJson(Map<String, dynamic> json) =>
    AiThinkingBlock(
      id: json['id'] as String,
      text: json['text'] as String,
      signature: json['signature'] as String?,
      encryptedContents:
          (json['encryptedContents'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );

Map<String, dynamic> _$AiThinkingBlockToJson(AiThinkingBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'signature': instance.signature,
      'encryptedContents': instance.encryptedContents,
    };

AiToolCallBlock _$AiToolCallBlockFromJson(Map<String, dynamic> json) =>
    AiToolCallBlock(
      id: json['id'] as String,
      callId: json['call_id'] as String,
      toolName: json['tool_name'] as String,
      arguments: json['arguments'] as Map<String, dynamic>,
      requestId: (json['request_id'] as num?)?.toInt(),
      status:
          $enumDecodeNullable(_$AiToolCallStatusEnumMap, json['status']) ??
          AiToolCallStatus.pending,
      result: json['result'] as Map<String, dynamic>?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      errorMessage: json['error_message'] as String?,
      targetPath: json['target_path'] as String?,
      diffOldText: json['diff_old_text'] as String?,
      diffNewText: json['diff_new_text'] as String?,
      thoughtSignature: json['thought_signature'] as String?,
      nestedCalls:
          (json['nested_calls'] as List<dynamic>?)
              ?.map((e) => AiNestedToolCall.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$AiToolCallBlockToJson(AiToolCallBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'call_id': instance.callId,
      'tool_name': instance.toolName,
      'arguments': instance.arguments,
      'request_id': instance.requestId,
      'status': _$AiToolCallStatusEnumMap[instance.status]!,
      'result': instance.result,
      'metadata': instance.metadata,
      'error_message': instance.errorMessage,
      'target_path': instance.targetPath,
      'diff_old_text': instance.diffOldText,
      'diff_new_text': instance.diffNewText,
      'thought_signature': instance.thoughtSignature,
      'nested_calls': instance.nestedCalls.map((e) => e.toJson()).toList(),
    };

const _$AiToolCallStatusEnumMap = {
  AiToolCallStatus.pending: 'pending',
  AiToolCallStatus.rejected: 'rejected',
  AiToolCallStatus.cancelled: 'cancelled',
  AiToolCallStatus.running: 'running',
  AiToolCallStatus.success: 'success',
  AiToolCallStatus.error: 'error',
};

AiImageBlock _$AiImageBlockFromJson(Map<String, dynamic> json) => AiImageBlock(
  id: json['id'] as String,
  prompt: json['prompt'] as String,
  toolName: json['tool_name'] as String?,
  imageUrl: json['image_url'] as String?,
  imageBase64: json['image_base64'] as String?,
  localFilePath: json['local_file_path'] as String?,
  assetId: json['asset_id'] as String?,
  revisedPrompt: json['revised_prompt'] as String?,
  characterId: json['character_id'] as String?,
  itemId: json['item_id'] as String?,
  status:
      $enumDecodeNullable(_$AiImageStatusEnumMap, json['status']) ??
      AiImageStatus.generating,
  errorMessage: json['error_message'] as String?,
);

Map<String, dynamic> _$AiImageBlockToJson(AiImageBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'tool_name': instance.toolName,
      'image_url': instance.imageUrl,
      'image_base64': instance.imageBase64,
      'local_file_path': instance.localFilePath,
      'asset_id': instance.assetId,
      'revised_prompt': instance.revisedPrompt,
      'character_id': instance.characterId,
      'item_id': instance.itemId,
      'status': _$AiImageStatusEnumMap[instance.status]!,
      'error_message': instance.errorMessage,
    };

const _$AiImageStatusEnumMap = {
  AiImageStatus.generating: 'generating',
  AiImageStatus.success: 'success',
  AiImageStatus.error: 'error',
};

AiAskUserBlock _$AiAskUserBlockFromJson(Map<String, dynamic> json) =>
    AiAskUserBlock(
      id: json['id'] as String,
      callId: json['call_id'] as String,
      questions: (json['questions'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      status:
          $enumDecodeNullable(_$AiAskUserStatusEnumMap, json['status']) ??
          AiAskUserStatus.pending,
      answers: (json['answers'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
      errorMessage: json['error_message'] as String?,
      resolution: $enumDecodeNullable(
        _$AskUserResolutionEnumMap,
        json['resolution'],
      ),
      unansweredQuestionIds: (json['unanswered_question_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$AiAskUserBlockToJson(AiAskUserBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'call_id': instance.callId,
      'questions': instance.questions,
      'status': _$AiAskUserStatusEnumMap[instance.status]!,
      'answers': instance.answers,
      'error_message': instance.errorMessage,
      'resolution': _$AskUserResolutionEnumMap[instance.resolution],
      'unanswered_question_ids': instance.unansweredQuestionIds,
    };

const _$AiAskUserStatusEnumMap = {
  AiAskUserStatus.pending: 'pending',
  AiAskUserStatus.answered: 'answered',
  AiAskUserStatus.cancelled: 'cancelled',
  AiAskUserStatus.error: 'error',
  AiAskUserStatus.timed_out: 'timed_out',
  AiAskUserStatus.interrupted: 'interrupted',
};

const _$AskUserResolutionEnumMap = {
  AskUserResolution.timeout: 'timeout',
  AskUserResolution.interrupted: 'interrupted',
};

AiSuggestNextActionBlock _$AiSuggestNextActionBlockFromJson(
  Map<String, dynamic> json,
) => AiSuggestNextActionBlock(
  id: json['id'] as String,
  callId: json['call_id'] as String,
  suggestions: (json['suggestions'] as List<dynamic>)
      .map((e) => e as Map<String, dynamic>)
      .toList(),
);

Map<String, dynamic> _$AiSuggestNextActionBlockToJson(
  AiSuggestNextActionBlock instance,
) => <String, dynamic>{
  'id': instance.id,
  'call_id': instance.callId,
  'suggestions': instance.suggestions,
};
