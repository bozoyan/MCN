// 职责: Agent Council 多智能体讨论的数据模型 — 定义参与者、讨论轮次、消息与总结。
// 关联文件:
//   lib/shared/services/ai/agent_council_orchestrator.dart
//   lib/shared/providers/agent_council_providers.dart
//   lib/shared/services/ai/council_session_codec.dart
//   lib/shared/models/ai_run_failure.dart

import 'package:json_annotation/json_annotation.dart';

import 'ai_run_failure.dart';

part 'agent_council_models.g.dart';

enum CouncilPhase { idle, discussing, summarizing, completed, cancelled, error }

/// 作者本人插话时 [CouncilMessage.participantId] 的取值。
const councilUserParticipantId = '__user__';

enum CouncilParticipantRole {
  moderator,
  plot_architect,
  character_analyst,
  world_builder,
  pacing_expert,
  conflict_designer,
  theme_guardian,
  custom,
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CouncilParticipant {
  final String id;
  final String name;
  final String nameKey;
  final String description;
  final String descKey;
  final String prompt;
  final String promptKey;
  final CouncilParticipantRole role;
  final String? avatarEmoji;
  final String? avatarPath;
  final String? colorHex;
  final String? modelOptionId;

  const CouncilParticipant({
    required this.id,
    required this.name,
    this.nameKey = '',
    required this.description,
    this.descKey = '',
    required this.prompt,
    this.promptKey = '',
    this.role = CouncilParticipantRole.custom,
    this.avatarEmoji,
    this.avatarPath,
    this.colorHex,
    this.modelOptionId,
  });

  factory CouncilParticipant.fromJson(Map<String, dynamic> json) =>
      _$CouncilParticipantFromJson(json);

  Map<String, dynamic> toJson() => _$CouncilParticipantToJson(this);

  CouncilParticipant copyWith({
    String? id,
    String? name,
    String? nameKey,
    String? description,
    String? descKey,
    String? prompt,
    String? promptKey,
    CouncilParticipantRole? role,
    String? avatarEmoji,
    String? avatarPath,
    String? colorHex,
    String? modelOptionId,
    bool clearModelOptionId = false,
  }) {
    return CouncilParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      nameKey: nameKey ?? this.nameKey,
      description: description ?? this.description,
      descKey: descKey ?? this.descKey,
      prompt: prompt ?? this.prompt,
      promptKey: promptKey ?? this.promptKey,
      role: role ?? this.role,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      avatarPath: avatarPath ?? this.avatarPath,
      colorHex: colorHex ?? this.colorHex,
      modelOptionId: clearModelOptionId
          ? null
          : modelOptionId ?? this.modelOptionId,
    );
  }

  String resolveName(String Function(String) t) {
    if (nameKey.isNotEmpty) {
      final translated = t(nameKey);
      if (translated != nameKey) return translated;
    }
    return name;
  }

  String resolveDescription(String Function(String) t) {
    if (descKey.isNotEmpty) {
      final translated = t(descKey);
      if (translated != descKey) return translated;
    }
    return description;
  }

  String resolvePrompt(String Function(String) t) {
    if (promptKey.isNotEmpty) {
      final translated = t(promptKey);
      if (translated != promptKey) return translated;
    }
    return prompt;
  }
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CouncilMessage {
  final String id;
  final String participantId;
  final String participantName;
  final String content;
  final DateTime timestamp;
  final int round;

  /// 发言最后点名请其回应的成员 id；没有点名为 null。
  final String? addresseeId;

  const CouncilMessage({
    required this.id,
    required this.participantId,
    required this.participantName,
    required this.content,
    required this.timestamp,
    required this.round,
    this.addresseeId,
  });

  bool get isUser => participantId == councilUserParticipantId;

  factory CouncilMessage.fromJson(Map<String, dynamic> json) =>
      _$CouncilMessageFromJson(json);

  Map<String, dynamic> toJson() => _$CouncilMessageToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CouncilRound {
  final int roundNumber;
  final List<CouncilMessage> messages;
  final bool isComplete;

  const CouncilRound({
    required this.roundNumber,
    required this.messages,
    this.isComplete = false,
  });

  factory CouncilRound.fromJson(Map<String, dynamic> json) =>
      _$CouncilRoundFromJson(json);

  Map<String, dynamic> toJson() => _$CouncilRoundToJson(this);

  CouncilRound copyWith({
    int? roundNumber,
    List<CouncilMessage>? messages,
    bool? isComplete,
  }) {
    return CouncilRound(
      roundNumber: roundNumber ?? this.roundNumber,
      messages: messages ?? this.messages,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CouncilSummary {
  final String content;
  final DateTime timestamp;
  @JsonKey(defaultValue: 0)
  final int coveredThroughRound;

  /// 生成总结时的最后一条发言；之后再有发言即视为过期。尚无发言时为 null。
  final String? coveredThroughMessageId;

  /// 以下三项从 [content] 的固定小节解析而来，供交接到 chat 使用；展示只用 [content]。
  final List<String> keyPoints;
  final List<String> actionItems;
  @JsonKey(defaultValue: <String>[])
  final List<String> openQuestions;

  const CouncilSummary({
    required this.content,
    required this.timestamp,
    required this.coveredThroughRound,
    this.coveredThroughMessageId,
    this.keyPoints = const [],
    this.actionItems = const [],
    this.openQuestions = const [],
  });

  factory CouncilSummary.fromJson(Map<String, dynamic> json) =>
      _$CouncilSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$CouncilSummaryToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AgentCouncilSession {
  final String id;
  final String title;
  final String novelId;
  final String topic;
  final List<CouncilParticipant> participants;
  final List<CouncilRound> rounds;
  final CouncilSummary? summary;
  final CouncilPhase phase;
  final AiRunFailure? failure;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AgentCouncilSession({
    required this.id,
    required this.novelId,
    required this.topic,
    required this.participants,
    this.title = '',
    this.rounds = const [],
    this.summary,
    this.phase = CouncilPhase.idle,
    this.failure,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgentCouncilSession.fromJson(Map<String, dynamic> json) =>
      _$AgentCouncilSessionFromJson(json);

  Map<String, dynamic> toJson() => _$AgentCouncilSessionToJson(this);

  AgentCouncilSession copyWith({
    String? id,
    String? title,
    String? novelId,
    String? topic,
    List<CouncilParticipant>? participants,
    List<CouncilRound>? rounds,
    CouncilSummary? summary,
    bool clearSummary = false,
    CouncilPhase? phase,
    AiRunFailure? failure,
    bool clearFailure = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentCouncilSession(
      id: id ?? this.id,
      title: title ?? this.title,
      novelId: novelId ?? this.novelId,
      topic: topic ?? this.topic,
      participants: participants ?? this.participants,
      rounds: rounds ?? this.rounds,
      summary: clearSummary ? null : summary ?? this.summary,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : failure ?? this.failure,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  int get currentRoundNumber => rounds.isEmpty ? 0 : rounds.last.roundNumber;

  int get nextDiscussionRoundNumber {
    if (rounds.isEmpty) {
      return 1;
    }
    final lastRound = rounds.last;
    return lastRound.isComplete
        ? lastRound.roundNumber + 1
        : lastRound.roundNumber;
  }

  String? get lastMessageId =>
      rounds.reversed.expand((r) => r.messages.reversed).firstOrNull?.id;

  bool get hasOutdatedSummary {
    final currentSummary = summary;
    if (currentSummary == null) return false;
    final coveredId = currentSummary.coveredThroughMessageId;
    // 点名单人发言追加在最后一轮里，轮次不变，只能按消息判断。
    return lastMessageId != coveredId;
  }

  bool get canUpdateSummary {
    return rounds.isNotEmpty &&
        rounds.last.isComplete &&
        (summary == null || hasOutdatedSummary);
  }

  bool get isActive =>
      phase == CouncilPhase.discussing || phase == CouncilPhase.summarizing;
}

class AgentCouncilConfig {
  final int maxRounds;
  final bool autoSummarize;

  const AgentCouncilConfig({this.maxRounds = 3, this.autoSummarize = true});
}

List<CouncilParticipant> defaultCouncilParticipants() {
  return const [
    CouncilParticipant(
      id: 'plot_architect',
      name: 'Plot Architect',
      nameKey: 'council.plot_architect.name',
      description: 'Focus on plot structure, foreshadowing and climax design',
      descKey: 'council.plot_architect.desc',
      prompt:
          'You are a senior plot architect. Your role is to analyze story structure, ensure proper narrative arcs, foreshadowing payoff, and impactful climaxes. You focus on the overall narrative arc and pacing. In discussions, provide constructive feedback from a plot structure perspective, pointing out potential plot holes or improvement opportunities.',
      promptKey: 'council.plot_architect.prompt',
      role: CouncilParticipantRole.plot_architect,
      avatarEmoji: '🏗️',
      colorHex: '#E67E22',
    ),
    CouncilParticipant(
      id: 'character_analyst',
      name: 'Character Analyst',
      nameKey: 'council.character_analyst.name',
      description:
          'Analyze character motivations, growth arcs and relationships',
      descKey: 'council.character_analyst.desc',
      prompt:
          'You are a character analysis expert. Your role is to deeply analyze characters\' inner motivations, personality consistency, growth arcs, and interpersonal dynamics. You ensure each character\'s behavior aligns with their personality and drives the story forward. In discussions, provide insights from a character development perspective, assessing whether character behavior is believable and where there\'s room for deeper exploration.',
      promptKey: 'council.character_analyst.prompt',
      role: CouncilParticipantRole.character_analyst,
      avatarEmoji: '🎭',
      colorHex: '#9B59B6',
    ),
    CouncilParticipant(
      id: 'world_builder',
      name: 'World Builder',
      nameKey: 'council.world_builder.name',
      description: 'Maintain world consistency and enrich setting details',
      descKey: 'council.world_builder.desc',
      prompt:
          'You are a world-building expert. Your role is to ensure story world consistency, richness, and logical coherence. You focus on setting details, rule systems, cultural backgrounds, and historical context. In discussions, provide supplementary suggestions from a world-building perspective, point out potential setting contradictions, and suggest ways to enrich the story background.',
      promptKey: 'council.world_builder.prompt',
      role: CouncilParticipantRole.world_builder,
      avatarEmoji: '🌍',
      colorHex: '#3498DB',
    ),
    CouncilParticipant(
      id: 'pacing_expert',
      name: 'Pacing Expert',
      nameKey: 'council.pacing_expert.name',
      description: 'Control narrative rhythm and balance tension with relief',
      descKey: 'council.pacing_expert.desc',
      prompt:
          'You are a narrative pacing expert. Your role is to analyze story rhythm, ensuring tension and relief alternate appropriately, preventing reader fatigue or loss of interest. You focus on scene transitions, information density, and emotional flow. In discussions, provide suggestions from a pacing perspective, pointing out which parts need acceleration or deceleration.',
      promptKey: 'council.pacing_expert.prompt',
      role: CouncilParticipantRole.pacing_expert,
      avatarEmoji: '⏱️',
      colorHex: '#1ABC9C',
    ),
    CouncilParticipant(
      id: 'conflict_designer',
      name: 'Conflict Designer',
      nameKey: 'council.conflict_designer.name',
      description:
          'Design conflicts and confrontations to enhance story tension',
      descKey: 'council.conflict_designer.desc',
      prompt:
          'You are a conflict design expert. Your role is to analyze conflict setup in stories, ensuring internal and external conflicts intertwine, confrontations have layered depth and escalating stakes. You focus on conflict origins, development, and resolution. In discussions, provide enhancement suggestions from a conflict perspective, pointing out confrontational elements that could be added or deepened.',
      promptKey: 'council.conflict_designer.prompt',
      role: CouncilParticipantRole.conflict_designer,
      avatarEmoji: '⚔️',
      colorHex: '#E74C3C',
    ),
    CouncilParticipant(
      id: 'theme_guardian',
      name: 'Theme Guardian',
      nameKey: 'council.theme_guardian.name',
      description: 'Guard story themes and ensure deeper meaning throughout',
      descKey: 'council.theme_guardian.desc',
      prompt:
          'You are a theme guardian expert. Your role is to ensure the story\'s core theme permeates throughout, deepening thematic expression through plot, characters, and symbolism. You focus on the story\'s deeper meaning, emotional resonance, and intellectual value. In discussions, provide insights from a thematic perspective, suggesting how to more effectively convey core ideas.',
      promptKey: 'council.theme_guardian.prompt',
      role: CouncilParticipantRole.theme_guardian,
      avatarEmoji: '🔮',
      colorHex: '#F1C40F',
    ),
  ];
}
