// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_council_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CouncilParticipant _$CouncilParticipantFromJson(Map<String, dynamic> json) =>
    CouncilParticipant(
      id: json['id'] as String,
      name: json['name'] as String,
      nameKey: json['name_key'] as String? ?? '',
      description: json['description'] as String,
      descKey: json['desc_key'] as String? ?? '',
      prompt: json['prompt'] as String,
      promptKey: json['prompt_key'] as String? ?? '',
      role:
          $enumDecodeNullable(_$CouncilParticipantRoleEnumMap, json['role']) ??
          CouncilParticipantRole.custom,
      avatarEmoji: json['avatar_emoji'] as String?,
      avatarPath: json['avatar_path'] as String?,
      colorHex: json['color_hex'] as String?,
      modelOptionId: json['model_option_id'] as String?,
    );

Map<String, dynamic> _$CouncilParticipantToJson(CouncilParticipant instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'name_key': instance.nameKey,
      'description': instance.description,
      'desc_key': instance.descKey,
      'prompt': instance.prompt,
      'prompt_key': instance.promptKey,
      'role': _$CouncilParticipantRoleEnumMap[instance.role]!,
      'avatar_emoji': instance.avatarEmoji,
      'avatar_path': instance.avatarPath,
      'color_hex': instance.colorHex,
      'model_option_id': instance.modelOptionId,
    };

const _$CouncilParticipantRoleEnumMap = {
  CouncilParticipantRole.moderator: 'moderator',
  CouncilParticipantRole.plot_architect: 'plot_architect',
  CouncilParticipantRole.character_analyst: 'character_analyst',
  CouncilParticipantRole.world_builder: 'world_builder',
  CouncilParticipantRole.pacing_expert: 'pacing_expert',
  CouncilParticipantRole.conflict_designer: 'conflict_designer',
  CouncilParticipantRole.theme_guardian: 'theme_guardian',
  CouncilParticipantRole.custom: 'custom',
};

CouncilMessage _$CouncilMessageFromJson(Map<String, dynamic> json) =>
    CouncilMessage(
      id: json['id'] as String,
      participantId: json['participant_id'] as String,
      participantName: json['participant_name'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      round: (json['round'] as num).toInt(),
      addresseeId: json['addressee_id'] as String?,
    );

Map<String, dynamic> _$CouncilMessageToJson(CouncilMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'participant_id': instance.participantId,
      'participant_name': instance.participantName,
      'content': instance.content,
      'timestamp': instance.timestamp.toIso8601String(),
      'round': instance.round,
      'addressee_id': instance.addresseeId,
    };

CouncilRound _$CouncilRoundFromJson(Map<String, dynamic> json) => CouncilRound(
  roundNumber: (json['round_number'] as num).toInt(),
  messages: (json['messages'] as List<dynamic>)
      .map((e) => CouncilMessage.fromJson(e as Map<String, dynamic>))
      .toList(),
  isComplete: json['is_complete'] as bool? ?? false,
);

Map<String, dynamic> _$CouncilRoundToJson(CouncilRound instance) =>
    <String, dynamic>{
      'round_number': instance.roundNumber,
      'messages': instance.messages,
      'is_complete': instance.isComplete,
    };

CouncilSummary _$CouncilSummaryFromJson(Map<String, dynamic> json) =>
    CouncilSummary(
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      coveredThroughRound:
          (json['covered_through_round'] as num?)?.toInt() ?? 0,
      coveredThroughMessageId: json['covered_through_message_id'] as String?,
      keyPoints:
          (json['key_points'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      actionItems:
          (json['action_items'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      openQuestions:
          (json['open_questions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );

Map<String, dynamic> _$CouncilSummaryToJson(CouncilSummary instance) =>
    <String, dynamic>{
      'content': instance.content,
      'timestamp': instance.timestamp.toIso8601String(),
      'covered_through_round': instance.coveredThroughRound,
      'covered_through_message_id': instance.coveredThroughMessageId,
      'key_points': instance.keyPoints,
      'action_items': instance.actionItems,
      'open_questions': instance.openQuestions,
    };

AgentCouncilSession _$AgentCouncilSessionFromJson(Map<String, dynamic> json) =>
    AgentCouncilSession(
      id: json['id'] as String,
      novelId: json['novel_id'] as String,
      topic: json['topic'] as String,
      participants: (json['participants'] as List<dynamic>)
          .map((e) => CouncilParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      title: json['title'] as String? ?? '',
      rounds:
          (json['rounds'] as List<dynamic>?)
              ?.map((e) => CouncilRound.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      summary: json['summary'] == null
          ? null
          : CouncilSummary.fromJson(json['summary'] as Map<String, dynamic>),
      phase:
          $enumDecodeNullable(_$CouncilPhaseEnumMap, json['phase']) ??
          CouncilPhase.idle,
      failure: json['failure'] == null
          ? null
          : AiRunFailure.fromJson(json['failure'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$AgentCouncilSessionToJson(
  AgentCouncilSession instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'novel_id': instance.novelId,
  'topic': instance.topic,
  'participants': instance.participants,
  'rounds': instance.rounds,
  'summary': instance.summary,
  'phase': _$CouncilPhaseEnumMap[instance.phase]!,
  'failure': instance.failure,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
};

const _$CouncilPhaseEnumMap = {
  CouncilPhase.idle: 'idle',
  CouncilPhase.discussing: 'discussing',
  CouncilPhase.summarizing: 'summarizing',
  CouncilPhase.completed: 'completed',
  CouncilPhase.cancelled: 'cancelled',
  CouncilPhase.error: 'error',
};
