// 职责: 小剧场会话与持久化消息之间的编解码 — 双端唯一的读写入口，另含交接到 chat 的剧本稿。
// 关联文件:
//   lib/shared/models/theater_models.dart
//   lib/shared/providers/theater_providers.dart
//   lib/shared/hooks/use_theater_run.dart
//   lib/shared/services/ai/session_persistence.dart
import '../../agent/agent_run_state.dart';
import '../../database/app_database.dart' show AiChatSession;
import '../../models/ai_chat_models.dart';
import '../../models/theater_models.dart';

/// 场景消息 metadata 中完整参与者 JSON 的键。
const theaterParticipantsMetadataKey = 'theater_participants';

/// 台词消息 metadata 中完整 [TheaterLine] JSON 的键。
const theaterLineMetadataKey = 'theater_line';

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

/// 台词的纯文本形态：舞台指示单独一行加全角括号，后接台词。
String theaterLineText(TheaterLine line) {
  final stage = line.stageDirection?.trim();
  return [
    if (stage != null && stage.isNotEmpty) '（$stage）',
    line.dialogue,
  ].join('\n');
}

/// 把会话编码为持久化消息：首条 user 消息是场景，其后每句台词一条 assistant 消息。
///
/// 结构化字段写在 [theaterParticipantsMetadataKey] / [theaterLineMetadataKey]，
/// 解码与历史展示均读取同一份结构化快照。
List<AiMessage> encodeTheaterMessages(
  TheaterSession session,
  Map<String, AgentRunState> runHistory,
) {
  return [
    AiMessage.user(
      id: '${session.id}_user_scene',
      content: session.sceneDescription,
      metadata: {
        'mode': 'theater',
        theaterParticipantsMetadataKey: [
          for (final p in session.participants) p.toJson(),
        ],
      },
    ),
    for (final line in session.lines)
      AiMessage.assistant(
        id: line.id,
        content: theaterLineText(line),
        blocks: _assistantBlocks(
          line.id,
          theaterLineText(line),
          runHistory[line.id],
        ),
        metadata: {'mode': 'theater', theaterLineMetadataKey: line.toJson()},
      ),
  ];
}

/// 从持久化消息重建会话；没有任何消息时返回 null。恢复后的会话一律处于 completed。
TheaterSession? decodeTheaterSession(
  AiChatSession aiSession,
  List<AiMessage> messages,
) {
  if (messages.isEmpty) return null;

  final sceneMessage = messages.firstWhere(
    (m) => m.role == AiMessageRole.user,
    orElse: () => messages.first,
  );
  final lines = <TheaterLine>[];
  for (final msg in messages) {
    if (msg.role != AiMessageRole.assistant) continue;
    lines.add(_decodeLine(msg));
  }

  return TheaterSession(
    id: aiSession.id,
    title: aiSession.title,
    novelId: aiSession.novelId,
    sceneDescription: sceneMessage.content,
    participants: _decodeParticipants(sceneMessage.metadata),
    lines: lines,
    phase: TheaterPhase.completed,
    createdAt: aiSession.createdAt,
    updatedAt: aiSession.updatedAt,
  );
}

List<TheaterParticipant> _decodeParticipants(Map<String, dynamic>? metadata) {
  final value = metadata?[theaterParticipantsMetadataKey];
  if (value is! List) {
    throw const FormatException('Missing theater participant snapshots.');
  }
  return [
    for (final participant in value)
      TheaterParticipant.fromJson(
        Map<String, dynamic>.from(participant as Map),
      ),
  ];
}

TheaterLine _decodeLine(AiMessage msg) {
  final value = msg.metadata?[theaterLineMetadataKey];
  if (value is! Map) {
    throw const FormatException('Missing theater line snapshot.');
  }
  return TheaterLine.fromJson(Map<String, dynamic>.from(value));
}

/// 从持久化消息中取出每句台词的推理/工具过程，键为台词 id。
Map<String, AgentRunState> decodeTheaterRunHistory(List<AiMessage> messages) {
  final history = <String, AgentRunState>{};
  for (final msg in messages) {
    if (msg.role != AiMessageRole.assistant) continue;
    final line = _decodeLine(msg);
    final processBlocks = msg.blocks
        .where((b) => b is AiThinkingBlock || b is AiToolCallBlock)
        .toList();
    if (processBlocks.isEmpty) continue;
    history[msg.id] = AgentRunState(
      agentId: line.characterId,
      agentName: line.characterName,
      round: line.turn,
      accumulatedText: msg.content,
      blocks: processBlocks,
      isComplete: true,
    );
  }
  return history;
}

/// 交接到 chat 时作为 summary 的剧本稿。
String theaterHandoffTranscript(TheaterSession session) {
  final buffer = StringBuffer()
    ..writeln('Scene: ${session.sceneDescription}')
    ..writeln(
      'Characters: ${session.participants.map((p) => p.name).join(', ')}',
    );
  for (final line in session.lines) {
    if (line.isDirection) {
      buffer.writeln('[Director] ${line.dialogue}');
      continue;
    }
    final stage = line.stageDirection?.trim();
    if (stage != null && stage.isNotEmpty) {
      buffer.writeln('${line.characterName}: ($stage) ${line.dialogue}');
    } else {
      buffer.writeln('${line.characterName}: ${line.dialogue}');
    }
  }
  return buffer.toString().trim();
}
