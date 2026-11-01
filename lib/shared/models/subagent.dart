// 职责: SubAgent 领域模型 — 表达可编辑的内置或自定义子智能体配置
// 关联文件:
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/database/app_database.dart
//   lib/desktop/widgets/agent_management/subagent_edit_panel.dart

import 'package:json_annotation/json_annotation.dart';

part 'subagent.g.dart';

class SubAgentNameConflictException implements Exception {
  const SubAgentNameConflictException(this.name);

  final String name;

  @override
  String toString() => 'SubAgent name conflict: "$name"';
}

enum SubAgentMode {
  chat,
  council;

  String get value => name;

  static SubAgentMode fromString(String s) => SubAgentMode.values.firstWhere(
    (e) => e.value == s,
    orElse: () => SubAgentMode.chat,
  );
}

enum SubAgentScope { global, novel }

@JsonSerializable(fieldRename: FieldRename.snake)
class SubAgent {
  const SubAgent({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.prompt,
    required this.scope,
    required this.sortOrder,
    this.mode = 'chat',
    this.avatarEmoji,
    this.avatarPath,
    this.enabled = true,
    this.useCustomPrompt = false,
    this.novelId,
    this.providerId,
    this.model,
    this.reasoningEffort,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String slug;
  final String name;
  final String description;
  final String prompt;
  final String mode;
  final String? avatarEmoji;
  final String? avatarPath;
  final SubAgentScope scope;
  final int sortOrder;
  final bool enabled;
  final bool useCustomPrompt;
  final String? novelId;
  final String? providerId;
  final String? model;
  final String? reasoningEffort;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SubAgent.fromJson(Map<String, dynamic> json) =>
      _$SubAgentFromJson(json);

  Map<String, dynamic> toJson() => _$SubAgentToJson(this);

  SubAgent copyWith({
    String? id,
    String? slug,
    String? name,
    String? description,
    String? prompt,
    String? mode,
    String? avatarEmoji,
    String? avatarPath,
    SubAgentScope? scope,
    int? sortOrder,
    bool? enabled,
    bool? useCustomPrompt,
    String? novelId,
    Object? providerId = _sentinel,
    Object? model = _sentinel,
    Object? reasoningEffort = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SubAgent(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      description: description ?? this.description,
      prompt: prompt ?? this.prompt,
      mode: mode ?? this.mode,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      avatarPath: avatarPath ?? this.avatarPath,
      scope: scope ?? this.scope,
      sortOrder: sortOrder ?? this.sortOrder,
      enabled: enabled ?? this.enabled,
      useCustomPrompt: useCustomPrompt ?? this.useCustomPrompt,
      novelId: novelId ?? this.novelId,
      providerId: providerId == _sentinel
          ? this.providerId
          : providerId as String?,
      model: model == _sentinel ? this.model : model as String?,
      reasoningEffort: reasoningEffort == _sentinel
          ? this.reasoningEffort
          : reasoningEffort as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const _sentinel = Object();

@JsonSerializable(fieldRename: FieldRename.snake)
class SubAgentDraft {
  const SubAgentDraft({
    required this.slug,
    required this.name,
    required this.description,
    required this.prompt,
    required this.scope,
    this.mode = 'chat',
    this.enabled = true,
    this.useCustomPrompt = false,
    this.novelId,
    this.providerId,
    this.model,
    this.reasoningEffort,
    this.avatarPath,
  });

  final String slug;
  final String name;
  final String description;
  final String prompt;
  final String mode;
  final SubAgentScope scope;
  final bool enabled;
  final bool useCustomPrompt;
  final String? novelId;
  final String? providerId;
  final String? model;
  final String? reasoningEffort;
  final String? avatarPath;

  factory SubAgentDraft.fromJson(Map<String, dynamic> json) =>
      _$SubAgentDraftFromJson(json);

  Map<String, dynamic> toJson() => _$SubAgentDraftToJson(this);
}
