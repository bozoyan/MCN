// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monologue_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MonologueParticipant _$MonologueParticipantFromJson(
  Map<String, dynamic> json,
) => MonologueParticipant(
  characterId: json['character_id'] as String,
  name: json['name'] as String,
  role: json['role'] as String,
  biography: json['biography'] as String,
  description: json['description'] as String? ?? '',
  avatarAssetId: json['avatar_asset_id'] as String?,
  avatarEmoji: json['avatar_emoji'] as String?,
  colorHex: json['color_hex'] as String?,
);

Map<String, dynamic> _$MonologueParticipantToJson(
  MonologueParticipant instance,
) => <String, dynamic>{
  'character_id': instance.characterId,
  'name': instance.name,
  'role': instance.role,
  'biography': instance.biography,
  'description': instance.description,
  'avatar_asset_id': instance.avatarAssetId,
  'avatar_emoji': instance.avatarEmoji,
  'color_hex': instance.colorHex,
};

MonologueEntry _$MonologueEntryFromJson(Map<String, dynamic> json) =>
    MonologueEntry(
      id: json['id'] as String,
      characterId: json['character_id'] as String,
      characterName: json['character_name'] as String,
      innerThoughts: json['inner_thoughts'] as String,
      plannedActions: json['planned_actions'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$MonologueEntryToJson(MonologueEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'character_id': instance.characterId,
      'character_name': instance.characterName,
      'inner_thoughts': instance.innerThoughts,
      'planned_actions': instance.plannedActions,
      'timestamp': instance.timestamp.toIso8601String(),
    };

MonologueSession _$MonologueSessionFromJson(Map<String, dynamic> json) =>
    MonologueSession(
      id: json['id'] as String,
      novelId: json['novel_id'] as String,
      topic: json['topic'] as String,
      character: MonologueParticipant.fromJson(
        json['character'] as Map<String, dynamic>,
      ),
      title: json['title'] as String? ?? '',
      monologues:
          (json['monologues'] as List<dynamic>?)
              ?.map((e) => MonologueEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      phase:
          $enumDecodeNullable(_$MonologuePhaseEnumMap, json['phase']) ??
          MonologuePhase.idle,
      failure: json['failure'] == null
          ? null
          : AiRunFailure.fromJson(json['failure'] as Map<String, dynamic>),
      providerId: json['provider_id'] as String?,
      model: json['model'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$MonologueSessionToJson(MonologueSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'novel_id': instance.novelId,
      'topic': instance.topic,
      'character': instance.character,
      'monologues': instance.monologues,
      'phase': _$MonologuePhaseEnumMap[instance.phase]!,
      'failure': instance.failure,
      'provider_id': instance.providerId,
      'model': instance.model,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

const _$MonologuePhaseEnumMap = {
  MonologuePhase.idle: 'idle',
  MonologuePhase.generating: 'generating',
  MonologuePhase.completed: 'completed',
  MonologuePhase.cancelled: 'cancelled',
  MonologuePhase.error: 'error',
};
