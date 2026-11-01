// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'roleplay_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoleplayParticipant _$RoleplayParticipantFromJson(Map<String, dynamic> json) =>
    RoleplayParticipant(
      characterId: json['character_id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      biography: json['biography'] as String,
      description: json['description'] as String? ?? '',
      avatarAssetId: json['avatar_asset_id'] as String?,
      avatarEmoji: json['avatar_emoji'] as String?,
      colorHex: json['color_hex'] as String?,
    );

Map<String, dynamic> _$RoleplayParticipantToJson(
  RoleplayParticipant instance,
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

RoleplayMessage _$RoleplayMessageFromJson(Map<String, dynamic> json) =>
    RoleplayMessage(
      id: json['id'] as String,
      speakerId: json['speaker_id'] as String,
      speakerName: json['speaker_name'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$RoleplayMessageToJson(RoleplayMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'speaker_id': instance.speakerId,
      'speaker_name': instance.speakerName,
      'content': instance.content,
      'timestamp': instance.timestamp.toIso8601String(),
    };

RoleplaySession _$RoleplaySessionFromJson(Map<String, dynamic> json) =>
    RoleplaySession(
      id: json['id'] as String,
      novelId: json['novel_id'] as String,
      character: RoleplayParticipant.fromJson(
        json['character'] as Map<String, dynamic>,
      ),
      title: json['title'] as String? ?? '',
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map((e) => RoleplayMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      phase:
          $enumDecodeNullable(_$RoleplayPhaseEnumMap, json['phase']) ??
          RoleplayPhase.idle,
      failure: json['failure'] == null
          ? null
          : AiRunFailure.fromJson(json['failure'] as Map<String, dynamic>),
      providerId: json['provider_id'] as String?,
      model: json['model'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$RoleplaySessionToJson(RoleplaySession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'novel_id': instance.novelId,
      'character': instance.character,
      'messages': instance.messages,
      'phase': _$RoleplayPhaseEnumMap[instance.phase]!,
      'failure': instance.failure,
      'provider_id': instance.providerId,
      'model': instance.model,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

const _$RoleplayPhaseEnumMap = {
  RoleplayPhase.idle: 'idle',
  RoleplayPhase.generating: 'generating',
  RoleplayPhase.completed: 'completed',
  RoleplayPhase.cancelled: 'cancelled',
  RoleplayPhase.error: 'error',
};
