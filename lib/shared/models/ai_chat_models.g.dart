// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_chat_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AiEmbeddingChunk _$AiEmbeddingChunkFromJson(Map<String, dynamic> json) =>
    AiEmbeddingChunk(
      sourceId: json['source_id'] as String,
      sourceType: json['source_type'] as String,
      chunkId: json['chunk_id'] as String,
      chunkIndex: (json['chunk_index'] as num).toInt(),
      startOffset: (json['start_offset'] as num).toInt(),
      endOffset: (json['end_offset'] as num).toInt(),
      text: json['text'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$AiEmbeddingChunkToJson(AiEmbeddingChunk instance) =>
    <String, dynamic>{
      'source_id': instance.sourceId,
      'source_type': instance.sourceType,
      'chunk_id': instance.chunkId,
      'chunk_index': instance.chunkIndex,
      'start_offset': instance.startOffset,
      'end_offset': instance.endOffset,
      'text': instance.text,
      'metadata': instance.metadata,
    };

AiEmbeddingSearchResult _$AiEmbeddingSearchResultFromJson(
  Map<String, dynamic> json,
) => AiEmbeddingSearchResult(
  sourceId: json['source_id'] as String,
  sourceType: json['source_type'] as String,
  chunkId: json['chunk_id'] as String,
  path: json['path'] as String,
  title: json['title'] as String,
  excerpt: json['excerpt'] as String,
  score: (json['score'] as num).toDouble(),
  chunkIndex: (json['chunk_index'] as num).toInt(),
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$AiEmbeddingSearchResultToJson(
  AiEmbeddingSearchResult instance,
) => <String, dynamic>{
  'source_id': instance.sourceId,
  'source_type': instance.sourceType,
  'chunk_id': instance.chunkId,
  'path': instance.path,
  'title': instance.title,
  'excerpt': instance.excerpt,
  'score': instance.score,
  'chunk_index': instance.chunkIndex,
  'metadata': instance.metadata,
};

AiEmbeddingConfig _$AiEmbeddingConfigFromJson(Map<String, dynamic> json) =>
    AiEmbeddingConfig(
      strategy:
          $enumDecodeNullable(_$AiChunkingStrategyEnumMap, json['strategy']) ??
          AiChunkingStrategy.heading_aware,
      targetChunkChars: (json['target_chunk_chars'] as num?)?.toInt() ?? 800,
      maxChunkChars: (json['max_chunk_chars'] as num?)?.toInt() ?? 1200,
      overlapChars: (json['overlap_chars'] as num?)?.toInt() ?? 120,
      maxResults: (json['max_results'] as num?)?.toInt() ?? 6,
    );

Map<String, dynamic> _$AiEmbeddingConfigToJson(AiEmbeddingConfig instance) =>
    <String, dynamic>{
      'strategy': _$AiChunkingStrategyEnumMap[instance.strategy]!,
      'target_chunk_chars': instance.targetChunkChars,
      'max_chunk_chars': instance.maxChunkChars,
      'overlap_chars': instance.overlapChars,
      'max_results': instance.maxResults,
    };

const _$AiChunkingStrategyEnumMap = {
  AiChunkingStrategy.paragraph: 'paragraph',
  AiChunkingStrategy.heading_aware: 'heading_aware',
};

AiMessage _$AiMessageFromJson(Map<String, dynamic> json) => AiMessage(
  id: json['id'] as String,
  role: $enumDecode(_$AiMessageRoleEnumMap, json['role']),
  type:
      $enumDecodeNullable(_$AiMessageTypeEnumMap, json['type']) ??
      AiMessageType.text,
  content: json['content'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  metadata: json['metadata'] as Map<String, dynamic>?,
  isStreaming: json['is_streaming'] as bool? ?? false,
  blocks: json['blocks'] == null
      ? const []
      : const _AiMessageBlockListConverter().fromJson(json['blocks'] as List),
  usage: json['usage'] == null
      ? null
      : AiUsage.fromJson(json['usage'] as Map<String, dynamic>),
);

Map<String, dynamic> _$AiMessageToJson(AiMessage instance) => <String, dynamic>{
  'id': instance.id,
  'role': _$AiMessageRoleEnumMap[instance.role]!,
  'type': _$AiMessageTypeEnumMap[instance.type]!,
  'content': instance.content,
  'timestamp': instance.timestamp.toIso8601String(),
  'metadata': instance.metadata,
  'is_streaming': instance.isStreaming,
  'blocks': const _AiMessageBlockListConverter().toJson(instance.blocks),
  'usage': instance.usage,
};

const _$AiMessageRoleEnumMap = {
  AiMessageRole.user: 'user',
  AiMessageRole.assistant: 'assistant',
  AiMessageRole.system: 'system',
};

const _$AiMessageTypeEnumMap = {
  AiMessageType.text: 'text',
  AiMessageType.rewrite: 'rewrite',
  AiMessageType.outline: 'outline',
  AiMessageType.chapter_content: 'chapter_content',
  AiMessageType.diff: 'diff',
  AiMessageType.tool_result: 'tool_result',
  AiMessageType.compact_summary: 'compact_summary',
  AiMessageType.system_remind: 'system_remind',
};

RewriteSuggestion _$RewriteSuggestionFromJson(Map<String, dynamic> json) =>
    RewriteSuggestion(
      id: json['id'] as String,
      originalText: json['original_text'] as String,
      suggestedText: json['suggested_text'] as String,
      explanation: json['explanation'] as String,
      isAccepted: json['is_accepted'] as bool? ?? false,
    );

Map<String, dynamic> _$RewriteSuggestionToJson(RewriteSuggestion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'original_text': instance.originalText,
      'suggested_text': instance.suggestedText,
      'explanation': instance.explanation,
      'is_accepted': instance.isAccepted,
    };
