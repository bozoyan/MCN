// 职责: Roleplay 模式数据模型 — 定义角色扮演会话、对话消息与参与者。
// 关联文件:
//   lib/shared/services/ai/roleplay_orchestrator.dart
//   lib/shared/providers/roleplay_providers.dart
//   lib/desktop/features/roleplay/panel.dart
//   lib/shared/models/ai_run_failure.dart

import 'package:json_annotation/json_annotation.dart';

import 'ai_run_failure.dart';

part 'roleplay_models.g.dart';

enum RoleplayPhase { idle, generating, completed, cancelled, error }

@JsonSerializable(fieldRename: FieldRename.snake)
class RoleplayParticipant {
  final String characterId;
  final String name;
  final String role;
  final String biography;
  final String description;
  final String? avatarAssetId;
  final String? avatarEmoji;
  final String? colorHex;

  const RoleplayParticipant({
    required this.characterId,
    required this.name,
    required this.role,
    required this.biography,
    this.description = '',
    this.avatarAssetId,
    this.avatarEmoji,
    this.colorHex,
  });

  factory RoleplayParticipant.fromJson(Map<String, dynamic> json) =>
      _$RoleplayParticipantFromJson(json);

  Map<String, dynamic> toJson() => _$RoleplayParticipantToJson(this);

  RoleplayParticipant copyWith({
    String? characterId,
    String? name,
    String? role,
    String? biography,
    String? description,
    String? avatarAssetId,
    String? avatarEmoji,
    String? colorHex,
  }) {
    return RoleplayParticipant(
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      role: role ?? this.role,
      biography: biography ?? this.biography,
      description: description ?? this.description,
      avatarAssetId: avatarAssetId ?? this.avatarAssetId,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}

@JsonSerializable(fieldRename: FieldRename.snake)
class RoleplayMessage {
  final String id;
  final String speakerId;
  final String speakerName;
  final String content;
  final DateTime timestamp;

  const RoleplayMessage({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.content,
    required this.timestamp,
  });

  factory RoleplayMessage.fromJson(Map<String, dynamic> json) =>
      _$RoleplayMessageFromJson(json);

  Map<String, dynamic> toJson() => _$RoleplayMessageToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class RoleplaySession {
  final String id;
  final String title;
  final String novelId;
  final RoleplayParticipant character;
  final List<RoleplayMessage> messages;
  final RoleplayPhase phase;
  final AiRunFailure? failure;
  final String? providerId;
  final String? model;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleplaySession({
    required this.id,
    required this.novelId,
    required this.character,
    this.title = '',
    this.messages = const [],
    this.phase = RoleplayPhase.idle,
    this.failure,
    this.providerId,
    this.model,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RoleplaySession.fromJson(Map<String, dynamic> json) =>
      _$RoleplaySessionFromJson(json);

  Map<String, dynamic> toJson() => _$RoleplaySessionToJson(this);

  RoleplaySession copyWith({
    String? id,
    String? title,
    String? novelId,
    RoleplayParticipant? character,
    List<RoleplayMessage>? messages,
    RoleplayPhase? phase,
    AiRunFailure? failure,
    bool clearFailure = false,
    String? providerId,
    String? model,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoleplaySession(
      id: id ?? this.id,
      title: title ?? this.title,
      novelId: novelId ?? this.novelId,
      character: character ?? this.character,
      messages: messages ?? this.messages,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isActive => phase == RoleplayPhase.generating;
}

class RoleplayConfig {
  final double temperature;

  const RoleplayConfig({this.temperature = 0.9});
}
