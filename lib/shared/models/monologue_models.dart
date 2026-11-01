// 职责: Monologue 模式数据模型 — 定义角色代入会话、内心独白与行动描述。
// 关联文件:
//   lib/shared/services/ai/monologue_orchestrator.dart
//   lib/shared/providers/monologue_providers.dart
//   lib/desktop/features/monologue/panel.dart
//   lib/shared/models/ai_run_failure.dart

import 'package:json_annotation/json_annotation.dart';

import 'ai_run_failure.dart';

part 'monologue_models.g.dart';

enum MonologuePhase { idle, generating, completed, cancelled, error }

@JsonSerializable(fieldRename: FieldRename.snake)
class MonologueParticipant {
  final String characterId;
  final String name;
  final String role;
  final String biography;
  final String description;
  final String? avatarAssetId;
  final String? avatarEmoji;
  final String? colorHex;

  const MonologueParticipant({
    required this.characterId,
    required this.name,
    required this.role,
    required this.biography,
    this.description = '',
    this.avatarAssetId,
    this.avatarEmoji,
    this.colorHex,
  });

  factory MonologueParticipant.fromJson(Map<String, dynamic> json) =>
      _$MonologueParticipantFromJson(json);

  Map<String, dynamic> toJson() => _$MonologueParticipantToJson(this);

  MonologueParticipant copyWith({
    String? characterId,
    String? name,
    String? role,
    String? biography,
    String? description,
    String? avatarAssetId,
    String? avatarEmoji,
    String? colorHex,
  }) {
    return MonologueParticipant(
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
class MonologueEntry {
  final String id;
  final String characterId;
  final String characterName;
  final String innerThoughts;
  final String plannedActions;
  final DateTime timestamp;

  const MonologueEntry({
    required this.id,
    required this.characterId,
    required this.characterName,
    required this.innerThoughts,
    required this.plannedActions,
    required this.timestamp,
  });

  factory MonologueEntry.fromJson(Map<String, dynamic> json) =>
      _$MonologueEntryFromJson(json);

  Map<String, dynamic> toJson() => _$MonologueEntryToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class MonologueSession {
  final String id;
  final String title;
  final String novelId;
  final String topic;
  final MonologueParticipant character;
  final List<MonologueEntry> monologues;
  final MonologuePhase phase;
  final AiRunFailure? failure;
  final String? providerId;
  final String? model;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MonologueSession({
    required this.id,
    required this.novelId,
    required this.topic,
    required this.character,
    this.title = '',
    this.monologues = const [],
    this.phase = MonologuePhase.idle,
    this.failure,
    this.providerId,
    this.model,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MonologueSession.fromJson(Map<String, dynamic> json) =>
      _$MonologueSessionFromJson(json);

  Map<String, dynamic> toJson() => _$MonologueSessionToJson(this);

  MonologueSession copyWith({
    String? id,
    String? title,
    String? novelId,
    String? topic,
    MonologueParticipant? character,
    List<MonologueEntry>? monologues,
    MonologuePhase? phase,
    AiRunFailure? failure,
    bool clearFailure = false,
    String? providerId,
    String? model,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MonologueSession(
      id: id ?? this.id,
      title: title ?? this.title,
      novelId: novelId ?? this.novelId,
      topic: topic ?? this.topic,
      character: character ?? this.character,
      monologues: monologues ?? this.monologues,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isActive => phase == MonologuePhase.generating;
}

class MonologueConfig {
  final double temperature;

  const MonologueConfig({this.temperature = 0.9});
}
