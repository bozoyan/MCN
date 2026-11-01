// 职责: 角色扮演会话与持久化消息之间的编解码 — 双端唯一的读写入口，另含交接到 chat 的对话稿。
// 关联文件:
//   lib/shared/models/roleplay_models.dart
//   lib/shared/providers/roleplay_providers.dart
//   lib/shared/hooks/use_roleplay_run.dart
//   lib/shared/services/ai/session_persistence.dart
import '../../agent/agent_run_state.dart';
import '../../database/app_database.dart' show AiChatSession;
import '../../models/ai_chat_models.dart';
import '../../models/character_profile.dart';
import '../../models/roleplay_models.dart';

/// 首条用户消息 metadata 中完整 [RoleplayParticipant] JSON 的键。
const roleplayParticipantMetadataKey = 'roleplay_participant';

const roleplayMessageMetadataKey = 'roleplay_message';

/// [RoleplayMessage.speakerId] 中代表作者本人的取值。
const roleplayUserSpeakerId = 'user';

/// 按角色卡构造参与者；开局与恢复时对齐角色卡都走这里。
RoleplayParticipant roleplayParticipantFromCharacter(
  CharacterProfile character,
) {
  return RoleplayParticipant(
    characterId: character.id,
    name: character.name,
    role: character.role,
    biography: character.biography,
    description: character.promptPersonaContext,
    avatarAssetId: character.avatarAssetId,
  );
}

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

/// 把会话编码为持久化消息：作者发言为 user 消息，角色回应为 assistant 消息。
///
/// 完整参与者 JSON 只写在首条用户消息的 [roleplayParticipantMetadataKey]；
/// 解码与历史展示均读取同一份结构化快照。
List<AiMessage> encodeRoleplayMessages(
  RoleplaySession session,
  Map<String, AgentRunState> runHistory,
) {
  final character = session.character;
  final firstUserId = session.messages
      .where((m) => m.speakerId == roleplayUserSpeakerId)
      .firstOrNull
      ?.id;
  return [
    for (final msg in session.messages)
      if (msg.speakerId == roleplayUserSpeakerId)
        AiMessage.user(
          id: msg.id,
          content: msg.content,
          metadata: {
            'mode': 'roleplay',
            roleplayMessageMetadataKey: msg.toJson(),
            if (msg.id == firstUserId)
              roleplayParticipantMetadataKey: character.toJson(),
          },
        )
      else
        AiMessage.assistant(
          id: msg.id,
          content: msg.content,
          blocks: _assistantBlocks(msg.id, msg.content, runHistory[msg.id]),
          metadata: {
            'mode': 'roleplay',
            roleplayMessageMetadataKey: msg.toJson(),
          },
        ),
  ];
}

/// 从持久化消息重建会话；没有任何消息时返回 null。恢复后的会话一律处于 completed。
///
/// 角色优先对齐当前角色卡（头像、设定可能已更新）；角色卡已删除时用落库的快照。
RoleplaySession? decodeRoleplaySession(
  AiChatSession aiSession,
  List<AiMessage> messages,
  List<CharacterProfile> characters,
) {
  if (messages.isEmpty) return null;

  final firstUser = messages.firstWhere(
    (m) => m.role == AiMessageRole.user,
    orElse: () => messages.first,
  );
  final stored = _decodeParticipant(firstUser.metadata);
  final matched = characters
      .where((c) => c.id == stored.characterId)
      .firstOrNull;
  final character = matched == null
      ? stored
      : roleplayParticipantFromCharacter(matched);

  return RoleplaySession(
    id: aiSession.id,
    title: aiSession.title,
    novelId: aiSession.novelId,
    character: character,
    messages: [for (final msg in messages) _decodeMessage(msg)],
    phase: RoleplayPhase.completed,
    providerId: aiSession.provider,
    model: aiSession.model,
    createdAt: aiSession.createdAt,
    updatedAt: aiSession.updatedAt,
  );
}

RoleplayParticipant _decodeParticipant(Map<String, dynamic>? metadata) {
  final value = metadata?[roleplayParticipantMetadataKey];
  if (value is! Map) {
    throw const FormatException('Missing roleplay participant snapshot.');
  }
  return RoleplayParticipant.fromJson(Map<String, dynamic>.from(value));
}

RoleplayMessage _decodeMessage(AiMessage msg) {
  final value = msg.metadata?[roleplayMessageMetadataKey];
  if (value is! Map) {
    throw const FormatException('Missing roleplay message snapshot.');
  }
  return RoleplayMessage.fromJson(Map<String, dynamic>.from(value));
}

/// 从持久化消息中取出每条角色回应的推理/工具过程，键为消息 id。
Map<String, AgentRunState> decodeRoleplayRunHistory(List<AiMessage> messages) {
  final history = <String, AgentRunState>{};
  for (final msg in messages) {
    if (msg.role != AiMessageRole.assistant) continue;
    final message = _decodeMessage(msg);
    final processBlocks = msg.blocks
        .where((b) => b is AiThinkingBlock || b is AiToolCallBlock)
        .toList();
    if (processBlocks.isEmpty) continue;
    history[msg.id] = AgentRunState(
      agentId: message.speakerId,
      agentName: message.speakerName,
      round: 1,
      accumulatedText: msg.content,
      blocks: processBlocks,
      isComplete: true,
    );
  }
  return history;
}

/// 交接到 chat 时作为 summary 的对话稿。
String roleplayHandoffTranscript(RoleplaySession session) {
  final buffer = StringBuffer()
    ..writeln('Character: ${session.character.name}')
    ..writeln('Role: ${session.character.role}');
  for (final message in session.messages) {
    buffer.writeln('${message.speakerName}: ${message.content}');
  }
  return buffer.toString().trim();
}
