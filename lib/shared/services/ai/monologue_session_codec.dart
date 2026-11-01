// 职责: 独白会话与持久化消息之间的编解码 — 双端唯一的读写入口，另含交接到 chat 的独白稿。
// 关联文件:
//   lib/shared/models/monologue_models.dart
//   lib/shared/providers/monologue_providers.dart
//   lib/shared/hooks/use_monologue_run.dart
//   lib/shared/services/ai/session_persistence.dart
import '../../agent/agent_run_state.dart';
import '../../database/app_database.dart' show AiChatSession;
import '../../models/ai_chat_models.dart';
import '../../models/monologue_models.dart';

/// 议题消息 metadata 中完整 [MonologueParticipant] JSON 的键。
const monologueParticipantMetadataKey = 'monologue_participant';

/// 独白消息 metadata 中完整 [MonologueEntry] JSON 的键。
const monologueEntryMetadataKey = 'monologue_entry';

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

/// 独白的纯文本形态：沿用模型输出的【】标记，与界面语言无关。
String monologueEntryText(MonologueEntry entry) {
  return [
    '【内心活动】${entry.innerThoughts}',
    if (entry.plannedActions.isNotEmpty) '【接下来的行动】${entry.plannedActions}',
  ].join('\n');
}

/// 把会话编码为持久化消息：首条 user 消息是议题，其后每段独白一条 assistant 消息。
///
/// 结构化字段写在 [monologueParticipantMetadataKey] / [monologueEntryMetadataKey]，
/// 解码与历史展示均读取同一份结构化快照。
List<AiMessage> encodeMonologueMessages(
  MonologueSession session,
  Map<String, AgentRunState> runHistory,
) {
  final character = session.character;
  return [
    AiMessage.user(
      id: '${session.id}_user_topic',
      content: session.topic,
      metadata: {
        'mode': 'monologue',
        'characterId': character.characterId,
        'characterName': character.name,
        monologueParticipantMetadataKey: character.toJson(),
      },
    ),
    for (final entry in session.monologues)
      AiMessage.assistant(
        id: entry.id,
        content: monologueEntryText(entry),
        blocks: _assistantBlocks(
          entry.id,
          monologueEntryText(entry),
          runHistory[entry.id],
        ),
        metadata: {
          'mode': 'monologue',
          monologueEntryMetadataKey: entry.toJson(),
        },
      ),
  ];
}

/// 从持久化消息重建会话；没有任何消息时返回 null。恢复后的会话一律处于 completed。
MonologueSession? decodeMonologueSession(
  AiChatSession aiSession,
  List<AiMessage> messages,
) {
  if (messages.isEmpty) return null;

  final topicMessage = messages.firstWhere(
    (m) => m.role == AiMessageRole.user,
    orElse: () => messages.first,
  );
  final character = _decodeParticipant(topicMessage.metadata);
  return MonologueSession(
    id: aiSession.id,
    title: aiSession.title,
    novelId: aiSession.novelId,
    topic: topicMessage.content,
    character: character,
    monologues: [
      for (final msg in messages)
        if (msg.role == AiMessageRole.assistant) _decodeEntry(msg),
    ],
    phase: MonologuePhase.completed,
    providerId: aiSession.provider,
    model: aiSession.model,
    createdAt: aiSession.createdAt,
    updatedAt: aiSession.updatedAt,
  );
}

MonologueParticipant _decodeParticipant(Map<String, dynamic>? metadata) {
  final value = metadata?[monologueParticipantMetadataKey];
  if (value is! Map) {
    throw const FormatException('Missing monologue participant snapshot.');
  }
  return MonologueParticipant.fromJson(Map<String, dynamic>.from(value));
}

MonologueEntry _decodeEntry(AiMessage msg) {
  final value = msg.metadata?[monologueEntryMetadataKey];
  if (value is! Map) {
    throw const FormatException('Missing monologue entry snapshot.');
  }
  return MonologueEntry.fromJson(Map<String, dynamic>.from(value));
}

/// 从持久化消息中取出每段独白的推理/工具过程，键为独白 id。
Map<String, AgentRunState> decodeMonologueRunHistory(List<AiMessage> messages) {
  final history = <String, AgentRunState>{};
  for (final msg in messages) {
    if (msg.role != AiMessageRole.assistant) continue;
    final entry = _decodeEntry(msg);
    final processBlocks = msg.blocks
        .where((b) => b is AiThinkingBlock || b is AiToolCallBlock)
        .toList();
    if (processBlocks.isEmpty) continue;
    history[msg.id] = AgentRunState(
      agentId: entry.characterId,
      agentName: entry.characterName,
      round: 1,
      accumulatedText: msg.content,
      blocks: processBlocks,
      isComplete: true,
    );
  }
  return history;
}

/// 交接到 chat 时作为 summary 的独白稿。
String monologueHandoffTranscript(MonologueSession session) {
  final buffer = StringBuffer()
    ..writeln('Topic: ${session.topic}')
    ..writeln('Character: ${session.character.name}')
    ..writeln('Role: ${session.character.role}');
  for (final entry in session.monologues) {
    buffer.writeln('${entry.characterName}: ${entry.innerThoughts}');
    if (entry.plannedActions.isNotEmpty) {
      buffer.writeln('Planned actions: ${entry.plannedActions}');
    }
  }
  return buffer.toString().trim();
}
