// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theater_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TheaterParticipant _$TheaterParticipantFromJson(Map<String, dynamic> json) =>
    TheaterParticipant(
      characterId: json['character_id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      biography: json['biography'] as String,
      description: json['description'] as String? ?? '',
      avatarAssetId: json['avatar_asset_id'] as String?,
      avatarEmoji: json['avatar_emoji'] as String?,
      colorHex: json['color_hex'] as String?,
    );

Map<String, dynamic> _$TheaterParticipantToJson(TheaterParticipant instance) =>
    <String, dynamic>{
      'character_id': instance.characterId,
      'name': instance.name,
      'role': instance.role,
      'biography': instance.biography,
      'description': instance.description,
      'avatar_asset_id': instance.avatarAssetId,
      'avatar_emoji': instance.avatarEmoji,
      'color_hex': instance.colorHex,
    };

TheaterLine _$TheaterLineFromJson(Map<String, dynamic> json) => TheaterLine(
  id: json['id'] as String,
  characterId: json['character_id'] as String,
  characterName: json['character_name'] as String,
  dialogue: json['dialogue'] as String,
  stageDirection: json['stage_direction'] as String?,
  addresseeId: json['addressee_id'] as String?,
  kind:
      $enumDecodeNullable(_$TheaterLineKindEnumMap, json['kind']) ??
      TheaterLineKind.performance,
  turn: (json['turn'] as num).toInt(),
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$TheaterLineToJson(TheaterLine instance) =>
    <String, dynamic>{
      'id': instance.id,
      'character_id': instance.characterId,
      'character_name': instance.characterName,
      'dialogue': instance.dialogue,
      'stage_direction': instance.stageDirection,
      'addressee_id': instance.addresseeId,
      'kind': _$TheaterLineKindEnumMap[instance.kind]!,
      'turn': instance.turn,
      'timestamp': instance.timestamp.toIso8601String(),
    };

const _$TheaterLineKindEnumMap = {
  TheaterLineKind.performance: 'performance',
  TheaterLineKind.direction: 'direction',
};

TheaterSession _$TheaterSessionFromJson(Map<String, dynamic> json) =>
    TheaterSession(
      id: json['id'] as String,
      novelId: json['novel_id'] as String,
      sceneDescription: json['scene_description'] as String,
      participants: (json['participants'] as List<dynamic>)
          .map((e) => TheaterParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String? ?? '',
      lines:
          (json['lines'] as List<dynamic>?)
              ?.map((e) => TheaterLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      phase:
          $enumDecodeNullable(_$TheaterPhaseEnumMap, json['phase']) ??
          TheaterPhase.idle,
      failure: json['failure'] == null
          ? null
          : AiRunFailure.fromJson(json['failure'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$TheaterSessionToJson(TheaterSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'novel_id': instance.novelId,
      'scene_description': instance.sceneDescription,
      'participants': instance.participants,
      'lines': instance.lines,
      'phase': _$TheaterPhaseEnumMap[instance.phase]!,
      'failure': instance.failure,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

const _$TheaterPhaseEnumMap = {
  TheaterPhase.idle: 'idle',
  TheaterPhase.performing: 'performing',
  TheaterPhase.completed: 'completed',
  TheaterPhase.cancelled: 'cancelled',
  TheaterPhase.error: 'error',
};
