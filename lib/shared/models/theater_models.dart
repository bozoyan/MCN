// 职责: 小剧场模式数据模型 — 定义多角色互动场景、台词与舞台指示。
// 关联文件:
//   lib/shared/services/ai/theater_orchestrator.dart
//   lib/shared/providers/theater_providers.dart
//   lib/desktop/features/theater/panel.dart
//   lib/shared/models/ai_run_failure.dart

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

import 'ai_run_failure.dart';

part 'theater_models.g.dart';

/// 「写成正文」带入 chat 的写作指令；[povCharacterName] 为空时用不限视角的第三人称。
String buildTheaterProseInstruction({String? povCharacterName}) {
  final pov = povCharacterName == null
      ? '第三人称'
      : '第三人称、$povCharacterName 的有限视角';
  return '把这场排练写成小说正文，用$pov叙述，接在当前章节末尾。'
      '保留台词的意思和情节走向，措辞、动作和环境描写可以重新组织；'
      '导演指令只是情节走向，不要写进正文。';
}

enum TheaterPhase { idle, performing, completed, cancelled, error }

/// 台词流条目类型：角色表演，或作者以导演身份插入的调度指令。
enum TheaterLineKind { performance, direction }

@JsonSerializable(fieldRename: FieldRename.snake)
class TheaterParticipant {
  final String characterId;
  final String name;
  final String role;
  final String biography;
  final String description;
  final String? avatarAssetId;
  final String? avatarEmoji;
  final String? colorHex;

  const TheaterParticipant({
    required this.characterId,
    required this.name,
    required this.role,
    required this.biography,
    this.description = '',
    this.avatarAssetId,
    this.avatarEmoji,
    this.colorHex,
  });

  factory TheaterParticipant.fromJson(Map<String, dynamic> json) =>
      _$TheaterParticipantFromJson(json);

  Map<String, dynamic> toJson() => _$TheaterParticipantToJson(this);

  TheaterParticipant copyWith({
    String? characterId,
    String? name,
    String? role,
    String? biography,
    String? description,
    String? avatarAssetId,
    String? avatarEmoji,
    String? colorHex,
  }) {
    return TheaterParticipant(
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
class TheaterLine {
  final String id;

  /// 导演指令为空串。
  final String characterId;
  final String characterName;

  /// 角色台词；导演指令时为指令正文。
  final String dialogue;
  final String? stageDirection;

  /// 本句主要对谁说（同场角色 id）；没有明确对象为 null。调度据此决定谁接话。
  final String? addresseeId;
  @JsonKey(defaultValue: TheaterLineKind.performance)
  final TheaterLineKind kind;
  final int turn;
  final DateTime timestamp;

  const TheaterLine({
    required this.id,
    required this.characterId,
    required this.characterName,
    required this.dialogue,
    this.stageDirection,
    this.addresseeId,
    this.kind = TheaterLineKind.performance,
    required this.turn,
    required this.timestamp,
  });

  TheaterLine.direction({
    required this.id,
    required String text,
    required this.turn,
    required this.timestamp,
  }) : characterId = '',
       characterName = '',
       dialogue = text,
       stageDirection = null,
       addresseeId = null,
       kind = TheaterLineKind.direction;

  bool get isDirection => kind == TheaterLineKind.direction;

  factory TheaterLine.fromJson(Map<String, dynamic> json) =>
      _$TheaterLineFromJson(json);

  Map<String, dynamic> toJson() => _$TheaterLineToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class TheaterSession {
  final String id;
  final String title;
  final String novelId;
  final String sceneDescription;
  final List<TheaterParticipant> participants;
  final List<TheaterLine> lines;
  final TheaterPhase phase;
  final AiRunFailure? failure;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TheaterSession({
    required this.id,
    required this.novelId,
    required this.sceneDescription,
    required this.participants,
    this.title = '',
    this.lines = const [],
    this.phase = TheaterPhase.idle,
    this.failure,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TheaterSession.fromJson(Map<String, dynamic> json) =>
      _$TheaterSessionFromJson(json);

  Map<String, dynamic> toJson() => _$TheaterSessionToJson(this);

  TheaterSession copyWith({
    String? id,
    String? title,
    String? novelId,
    String? sceneDescription,
    List<TheaterParticipant>? participants,
    List<TheaterLine>? lines,
    TheaterPhase? phase,
    AiRunFailure? failure,
    bool clearFailure = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TheaterSession(
      id: id ?? this.id,
      title: title ?? this.title,
      novelId: novelId ?? this.novelId,
      sceneDescription: sceneDescription ?? this.sceneDescription,
      participants: participants ?? this.participants,
      lines: lines ?? this.lines,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  int get currentTurn => lines.isEmpty ? 0 : lines.last.turn;

  /// 最近一句角色表演；导演指令不算。
  TheaterLine? get lastPerformance =>
      lines.lastWhereOrNull((line) => !line.isDirection);

  bool get isActive => phase == TheaterPhase.performing;
}

class TheaterConfig {
  final int maxRounds;

  const TheaterConfig({this.maxRounds = 3});
}
