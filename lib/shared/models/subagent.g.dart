// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subagent.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SubAgent _$SubAgentFromJson(Map<String, dynamic> json) => SubAgent(
  id: json['id'] as String,
  slug: json['slug'] as String,
  name: json['name'] as String,
  description: json['description'] as String,
  prompt: json['prompt'] as String,
  scope: $enumDecode(_$SubAgentScopeEnumMap, json['scope']),
  sortOrder: (json['sort_order'] as num).toInt(),
  mode: json['mode'] as String? ?? 'chat',
  avatarEmoji: json['avatar_emoji'] as String?,
  avatarPath: json['avatar_path'] as String?,
  enabled: json['enabled'] as bool? ?? true,
  useCustomPrompt: json['use_custom_prompt'] as bool? ?? false,
  novelId: json['novel_id'] as String?,
  providerId: json['provider_id'] as String?,
  model: json['model'] as String?,
  reasoningEffort: json['reasoning_effort'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$SubAgentToJson(SubAgent instance) => <String, dynamic>{
  'id': instance.id,
  'slug': instance.slug,
  'name': instance.name,
  'description': instance.description,
  'prompt': instance.prompt,
  'mode': instance.mode,
  'avatar_emoji': instance.avatarEmoji,
  'avatar_path': instance.avatarPath,
  'scope': _$SubAgentScopeEnumMap[instance.scope]!,
  'sort_order': instance.sortOrder,
  'enabled': instance.enabled,
  'use_custom_prompt': instance.useCustomPrompt,
  'novel_id': instance.novelId,
  'provider_id': instance.providerId,
  'model': instance.model,
  'reasoning_effort': instance.reasoningEffort,
  'created_at': instance.createdAt?.toIso8601String(),
  'updated_at': instance.updatedAt?.toIso8601String(),
};

const _$SubAgentScopeEnumMap = {
  SubAgentScope.global: 'global',
  SubAgentScope.novel: 'novel',
};

SubAgentDraft _$SubAgentDraftFromJson(Map<String, dynamic> json) =>
    SubAgentDraft(
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      prompt: json['prompt'] as String,
      scope: $enumDecode(_$SubAgentScopeEnumMap, json['scope']),
      mode: json['mode'] as String? ?? 'chat',
      enabled: json['enabled'] as bool? ?? true,
      useCustomPrompt: json['use_custom_prompt'] as bool? ?? false,
      novelId: json['novel_id'] as String?,
      providerId: json['provider_id'] as String?,
      model: json['model'] as String?,
      reasoningEffort: json['reasoning_effort'] as String?,
      avatarPath: json['avatar_path'] as String?,
    );

Map<String, dynamic> _$SubAgentDraftToJson(SubAgentDraft instance) =>
    <String, dynamic>{
      'slug': instance.slug,
      'name': instance.name,
      'description': instance.description,
      'prompt': instance.prompt,
      'mode': instance.mode,
      'scope': _$SubAgentScopeEnumMap[instance.scope]!,
      'enabled': instance.enabled,
      'use_custom_prompt': instance.useCustomPrompt,
      'novel_id': instance.novelId,
      'provider_id': instance.providerId,
      'model': instance.model,
      'reasoning_effort': instance.reasoningEffort,
      'avatar_path': instance.avatarPath,
    };
