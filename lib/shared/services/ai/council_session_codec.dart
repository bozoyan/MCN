// 职责: 议会会话与持久化消息之间的编解码 — 双端唯一的读写入口，另含会话行 metadata 与交接到 chat 的讨论稿。
// 关联文件:
//   lib/shared/models/agent_council_models.dart
//   lib/shared/providers/agent_council_providers.dart
//   lib/shared/hooks/use_council_run.dart
//   lib/shared/services/ai/session_persistence.dart
import '../../agent/agent_run_state.dart';
import '../../database/app_database.dart' show AiChatSession;
import '../../models/agent_council_models.dart';
import '../../models/ai_chat_models.dart';

/// 议题消息与会话行 metadata 中完整参与者 JSON 的键。
const councilParticipantsMetadataKey = 'council_participants';

/// 总结消息 metadata 中完整 [CouncilSummary] JSON 的键。
const councilSummaryMetadataKey = 'council_summary';

List<AiMessageBlock> _assistantBlocks(
  String messageId,
  String content,
  AgentRunState? runState,
) {
  return [
    // blocks 已是有序的推理 + 工具块（含结构化 result/metadata），按原序落库。
    ...?runState?.blocks,
    AiTextBlock(id: '${messageId}_text', text: content),
  ];
}

/// 会话行 metadata：0 条消息的会话靠它恢复议题与参与者。
///
/// 参与者快照与消息编解码使用同一结构。
Map<String, dynamic> councilRowMetadata(AgentCouncilSession session) => {
  'mode': 'council',
  'topic': session.topic,
  ..._participantsMetadata(session.participants),
};

Map<String, dynamic> _participantsMetadata(
  List<CouncilParticipant> participants,
) => {
  councilParticipantsMetadataKey: [for (final p in participants) p.toJson()],
};

/// 把会话编码为持久化消息：首条 user 消息是议题，其后按轮次排列发言，
/// 总结紧跟在它覆盖到的那一轮之后。
List<AiMessage> encodeCouncilMessages(
  AgentCouncilSession session,
  Map<String, AgentRunState> runHistory,
) {
  final summary = session.summary;
  final messages = <AiMessage>[
    AiMessage.user(
      id: '${session.id}_user_topic',
      content: session.topic,
      metadata: {
        'mode': 'council',
        ..._participantsMetadata(session.participants),
      },
    ),
  ];
  var summaryAdded = false;
  for (final round in session.rounds) {
    for (final msg in round.messages) {
      messages.add(
        AiMessage(
          id: msg.id,
          role: msg.isUser ? AiMessageRole.user : AiMessageRole.assistant,
          content: msg.content,
          timestamp: msg.timestamp,
          blocks: msg.isUser
              ? const []
              : _assistantBlocks(msg.id, msg.content, runHistory[msg.id]),
          metadata: {
            'mode': 'council',
            'participantId': msg.participantId,
            'participantName': msg.participantName,
            'round': msg.round,
          },
        ),
      );
    }
    if (summary != null && summary.coveredThroughRound == round.roundNumber) {
      messages.add(_summaryMessage(session.id, summary));
      summaryAdded = true;
    }
  }
  if (summary != null && !summaryAdded) {
    messages.add(_summaryMessage(session.id, summary));
  }
  return messages;
}

AiMessage _summaryMessage(String sessionId, CouncilSummary summary) {
  return AiMessage(
    id: '${sessionId}_summary',
    role: AiMessageRole.assistant,
    content: summary.content,
    timestamp: summary.timestamp,
    metadata: {'type': 'summary', councilSummaryMetadataKey: summary.toJson()},
  );
}

bool _isSummary(AiMessage msg) => msg.metadata?['type'] == 'summary';

/// 从持久化消息重建会话，恢复后一律处于 completed。
///
/// 没有任何消息时从会话行 metadata 兜底恢复议题与参与者，让 run 没产生发言的
/// 会话也能打开并继续讨论；议题与标题都为空时返回 null。
///
AgentCouncilSession? decodeCouncilSession(
  AiChatSession aiSession,
  List<AiMessage> messages,
) {
  final rowMetadata = aiSession.metadata;
  if (messages.isEmpty) {
    final metaTopic = (rowMetadata?['topic'] as String?)?.trim();
    final topic = metaTopic != null && metaTopic.isNotEmpty
        ? metaTopic
        : aiSession.title.trim();
    if (topic.isEmpty) return null;
    final participants = _decodeParticipants(rowMetadata);
    return AgentCouncilSession(
      id: aiSession.id,
      novelId: aiSession.novelId,
      title: aiSession.title,
      topic: topic,
      participants: participants,
      phase: CouncilPhase.completed,
      createdAt: aiSession.createdAt,
      updatedAt: aiSession.updatedAt,
    );
  }

  final topicMessage = messages.firstWhere(
    (m) => m.role == AiMessageRole.user && !_isSummary(m),
    orElse: () => messages.first,
  );
  final roundsByNumber = <int, List<CouncilMessage>>{};
  CouncilSummary? summary;
  for (final msg in messages) {
    if (_isSummary(msg)) {
      summary = _decodeSummary(msg);
      continue;
    }
    final metadata = msg.metadata;
    final participantId = metadata?['participantId'] as String? ?? '';
    // 议题消息既没有轮次也没有发言人。
    if (identical(msg, topicMessage) ||
        (metadata?['round'] == null && participantId.isEmpty)) {
      continue;
    }
    final round = metadata?['round'] as int? ?? 1;
    roundsByNumber
        .putIfAbsent(round, () => [])
        .add(
          CouncilMessage(
            id: msg.id,
            participantId: participantId,
            participantName: metadata?['participantName'] as String? ?? '',
            content: msg.content,
            timestamp: msg.timestamp,
            round: round,
          ),
        );
  }

  final participants = _decodeParticipants(topicMessage.metadata);
  return AgentCouncilSession(
    id: aiSession.id,
    novelId: aiSession.novelId,
    title: aiSession.title,
    topic: topicMessage.content,
    participants: participants,
    rounds: [
      for (final entry
          in roundsByNumber.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
        CouncilRound(
          roundNumber: entry.key,
          messages: entry.value,
          isComplete: true,
        ),
    ],
    summary: summary,
    phase: CouncilPhase.completed,
    createdAt: aiSession.createdAt,
    updatedAt: aiSession.updatedAt,
  );
}

List<CouncilParticipant> _decodeParticipants(Map<String, dynamic>? metadata) {
  final value = metadata?[councilParticipantsMetadataKey];
  if (value is! List) {
    throw const FormatException('Missing council participant snapshots.');
  }
  return [
    for (final participant in value)
      CouncilParticipant.fromJson(
        Map<String, dynamic>.from(participant as Map),
      ),
  ];
}

CouncilSummary _decodeSummary(AiMessage msg) {
  final value = msg.metadata?[councilSummaryMetadataKey];
  if (value is! Map) {
    throw const FormatException('Missing council summary snapshot.');
  }
  return CouncilSummary.fromJson(Map<String, dynamic>.from(value));
}

/// 从持久化消息中取出每条发言的推理/工具过程，键为消息 id。
Map<String, AgentRunState> decodeCouncilRunHistory(List<AiMessage> messages) {
  final history = <String, AgentRunState>{};
  for (final msg in messages) {
    if (msg.role != AiMessageRole.assistant) continue;
    final participantId = msg.metadata?['participantId'] as String?;
    final participantName = msg.metadata?['participantName'] as String?;
    final round = msg.metadata?['round'] as int?;
    if (participantId == null || participantName == null || round == null) {
      continue;
    }
    final processBlocks = msg.blocks
        .where((b) => b is AiThinkingBlock || b is AiToolCallBlock)
        .toList();
    if (processBlocks.isEmpty) continue;
    history[msg.id] = AgentRunState(
      agentId: participantId,
      agentName: participantName,
      round: round,
      accumulatedText: msg.content,
      blocks: processBlocks,
      isComplete: true,
    );
  }
  return history;
}

/// 交接到 chat 时作为 summary 的讨论稿（没有总结时使用）。
String councilHandoffTranscript(AgentCouncilSession session) {
  final buffer = StringBuffer()
    ..writeln('Topic: ${session.topic}')
    ..writeln(
      'Participants: ${session.participants.map((p) => p.name).join(', ')}',
    );
  for (final round in session.rounds) {
    for (final message in round.messages) {
      buffer.writeln(
        '${message.participantName} (round ${message.round}): '
        '${message.content}',
      );
    }
  }
  return buffer.toString().trim();
}
