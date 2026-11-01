// 特殊 case: AgentProfile 不直接用 Drift GlobalAgent DataClass
// AgentProfile 包含 role 枚举 (AgentProfileRole) 和 isBuiltin 逻辑，
// GlobalAgent 存平铺字符串字段 (category/scope)，两者字段名/类型不同。
// 若直接用 GlobalAgent，枚举→字符串转换会散落在所有调用方，
// 且 role 专有逻辑 (planner/writer/artist/custom 区分) 不易用 extension 表达。
// 因此保留 AgentProfile 作为领域模型，通过 providers 层做 GlobalAgent ↔ AgentProfile 转换。

import 'package:json_annotation/json_annotation.dart';

import '../services/ai/builtin_agent_tools.dart';

part 'agent_profile.g.dart';

const builtinAgentSlugPlanner = 'planner';
const builtinAgentSlugWriter = 'writer';
const builtinAgentSlugArtist = 'artist';
const builtinAgentSlugChronicler = 'chronicler';
const builtinAgentSlugMonologueNarrator = 'monologue_narrator';
const builtinAgentSlugRoleplayMaster = 'roleplay_master';
const builtinAgentSlugTheaterActor = 'theater_actor';
const builtinAgentSlugOrchestrator = 'orchestrator';

class AgentProfileNameConflictException implements Exception {
  const AgentProfileNameConflictException(this.name);

  final String name;

  @override
  String toString() => 'AgentProfile name conflict: "$name"';
}

enum AgentProfileScope { global, novel }

enum AgentProfileRole { planner, writer, artist, custom }

@JsonSerializable(fieldRename: FieldRename.snake)
class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.systemPrompt,
    required this.role,
    required this.scope,
    required this.sortOrder,
    this.mode = 'chat',
    this.avatarEmoji,
    this.avatarPath,
    this.enabled = true,
    this.useCustomPrompt = false,
    this.ignoredSkillNames = const [],
    this.novelId,
    this.providerId,
    this.model,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String slug;
  final String name;
  final String description;
  final String systemPrompt;
  final String mode;
  final String? avatarEmoji;
  final String? avatarPath;
  final AgentProfileRole role;
  final AgentProfileScope scope;
  final int sortOrder;
  final bool enabled;
  final bool useCustomPrompt;
  final List<String> ignoredSkillNames;
  final String? novelId;
  final String? providerId;
  final String? model;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AgentProfile.fromJson(Map<String, dynamic> json) =>
      _$AgentProfileFromJson(json);

  Map<String, dynamic> toJson() => _$AgentProfileToJson(this);

  AgentProfile copyWith({
    String? id,
    String? slug,
    String? name,
    String? description,
    String? systemPrompt,
    String? mode,
    String? avatarEmoji,
    String? avatarPath,
    AgentProfileRole? role,
    AgentProfileScope? scope,
    int? sortOrder,
    bool? enabled,
    bool? useCustomPrompt,
    List<String>? ignoredSkillNames,
    String? novelId,
    Object? providerId = _sentinel,
    Object? model = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentProfile(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      mode: mode ?? this.mode,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      avatarPath: avatarPath ?? this.avatarPath,
      role: role ?? this.role,
      scope: scope ?? this.scope,
      sortOrder: sortOrder ?? this.sortOrder,
      enabled: enabled ?? this.enabled,
      useCustomPrompt: useCustomPrompt ?? this.useCustomPrompt,
      ignoredSkillNames: ignoredSkillNames ?? this.ignoredSkillNames,
      novelId: novelId ?? this.novelId,
      providerId: providerId == _sentinel
          ? this.providerId
          : providerId as String?,
      model: model == _sentinel ? this.model : model as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isBuiltin =>
      scope == AgentProfileScope.global &&
      (role != AgentProfileRole.custom ||
          builtinPrimaryAgentSlugs.contains(slug));
}

const _sentinel = Object();

@JsonSerializable(fieldRename: FieldRename.snake)
class AgentProfileDraft {
  const AgentProfileDraft({
    required this.slug,
    required this.name,
    required this.description,
    required this.systemPrompt,
    required this.role,
    required this.scope,
    this.mode = 'chat',
    this.useCustomPrompt = false,
    this.novelId,
    this.providerId,
    this.model,
  });

  final String slug;
  final String name;
  final String description;
  final String systemPrompt;
  final String mode;
  final AgentProfileRole role;
  final AgentProfileScope scope;
  final bool useCustomPrompt;
  final String? novelId;
  final String? providerId;
  final String? model;

  factory AgentProfileDraft.fromJson(Map<String, dynamic> json) =>
      _$AgentProfileDraftFromJson(json);

  Map<String, dynamic> toJson() => _$AgentProfileDraftToJson(this);
}
