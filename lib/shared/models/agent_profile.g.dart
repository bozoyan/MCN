// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AgentProfile _$AgentProfileFromJson(Map<String, dynamic> json) => AgentProfile(
  id: json['id'] as String,
  slug: json['slug'] as String,
  name: json['name'] as String,
  description: json['description'] as String,
  systemPrompt: json['system_prompt'] as String,
  role: $enumDecode(_$AgentProfileRoleEnumMap, json['role']),
  scope: $enumDecode(_$AgentProfileScopeEnumMap, json['scope']),
  sortOrder: (json['sort_order'] as num).toInt(),
  mode: json['mode'] as String? ?? 'chat',
  avatarEmoji: json['avatar_emoji'] as String?,
  avatarPath: json['avatar_path'] as String?,
  enabled: json['enabled'] as bool? ?? true,
  useCustomPrompt: json['use_custom_prompt'] as bool? ?? false,
  ignoredSkillNames:
      (json['ignored_skill_names'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  novelId: json['novel_id'] as String?,
  providerId: json['provider_id'] as String?,
  model: json['model'] as String?,
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$AgentProfileToJson(AgentProfile instance) =>
    <String, dynamic>{
      'id': instance.id,
      'slug': instance.slug,
      'name': instance.name,
      'description': instance.description,
      'system_prompt': instance.systemPrompt,
      'mode': instance.mode,
      'avatar_emoji': instance.avatarEmoji,
      'avatar_path': instance.avatarPath,
      'role': _$AgentProfileRoleEnumMap[instance.role]!,
      'scope': _$AgentProfileScopeEnumMap[instance.scope]!,
      'sort_order': instance.sortOrder,
      'enabled': instance.enabled,
      'use_custom_prompt': instance.useCustomPrompt,
      'ignored_skill_names': instance.ignoredSkillNames,
      'novel_id': instance.novelId,
      'provider_id': instance.providerId,
      'model': instance.model,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

const _$AgentProfileRoleEnumMap = {
  AgentProfileRole.planner: 'planner',
  AgentProfileRole.writer: 'writer',
  AgentProfileRole.artist: 'artist',
  AgentProfileRole.custom: 'custom',
};

const _$AgentProfileScopeEnumMap = {
  AgentProfileScope.global: 'global',
  AgentProfileScope.novel: 'novel',
};

AgentProfileDraft _$AgentProfileDraftFromJson(Map<String, dynamic> json) =>
    AgentProfileDraft(
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      systemPrompt: json['system_prompt'] as String,
      role: $enumDecode(_$AgentProfileRoleEnumMap, json['role']),
      scope: $enumDecode(_$AgentProfileScopeEnumMap, json['scope']),
      mode: json['mode'] as String? ?? 'chat',
      useCustomPrompt: json['use_custom_prompt'] as bool? ?? false,
      novelId: json['novel_id'] as String?,
      providerId: json['provider_id'] as String?,
      model: json['model'] as String?,
    );

Map<String, dynamic> _$AgentProfileDraftToJson(AgentProfileDraft instance) =>
    <String, dynamic>{
      'slug': instance.slug,
      'name': instance.name,
      'description': instance.description,
      'system_prompt': instance.systemPrompt,
      'mode': instance.mode,
      'role': _$AgentProfileRoleEnumMap[instance.role]!,
      'scope': _$AgentProfileScopeEnumMap[instance.scope]!,
      'use_custom_prompt': instance.useCustomPrompt,
      'novel_id': instance.novelId,
      'provider_id': instance.providerId,
      'model': instance.model,
    };
