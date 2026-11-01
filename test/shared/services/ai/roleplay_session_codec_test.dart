// 职责: 验证角色扮演会话编解码 — 角色卡仍在时对齐最新角色卡，角色卡已删除时用落库快照保住头像，缺失结构化快照时拒绝恢复。
// 关联文件:
//   lib/shared/services/ai/roleplay_session_codec.dart
//   lib/shared/models/roleplay_models.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart'
    show AiChatSession, notDeletedSentinel;
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/models/roleplay_models.dart';
import 'package:reveric/shared/services/ai/roleplay_session_codec.dart';

final _created = DateTime(2026, 9, 1, 10);
final _updated = DateTime(2026, 9, 1, 11);

AiChatSession _aiSession() => AiChatSession(
  id: 'rp_1',
  novelId: 'novel_1',
  title: '和阿离聊聊',
  mode: 'roleplay',
  createdAt: _created,
  updatedAt: _updated,
  deletedAt: DateTime(0),
);

/// 模拟落库：metadata 以 JSON 文本存取。
List<AiMessage> _throughDatabase(List<AiMessage> messages) => [
  for (final m in messages)
    m.copyWith(
      metadata: m.metadata == null
          ? null
          : jsonDecode(jsonEncode(m.metadata)) as Map<String, dynamic>,
    ),
];

void main() {
  const alice = RoleplayParticipant(
    characterId: 'c_alice',
    name: '阿离',
    role: '剑客',
    biography: '流亡的剑客',
    description: '寡言',
    avatarAssetId: '/avatars/alice.png',
  );

  RoleplaySession session() => RoleplaySession(
    id: 'rp_1',
    title: '和阿离聊聊',
    novelId: 'novel_1',
    character: alice,
    messages: [
      RoleplayMessage(
        id: 'u_1',
        speakerId: roleplayUserSpeakerId,
        speakerName: roleplayUserSpeakerId,
        content: '你为什么回来？',
        timestamp: _created,
      ),
      RoleplayMessage(
        id: 'a_1',
        speakerId: alice.characterId,
        speakerName: alice.name,
        content: '雨太大了。',
        timestamp: _created,
      ),
      RoleplayMessage(
        id: 'u_2',
        speakerId: roleplayUserSpeakerId,
        speakerName: roleplayUserSpeakerId,
        content: '只是因为雨？',
        timestamp: _updated,
      ),
    ],
    createdAt: _created,
    updatedAt: _updated,
  );

  test('deleted character keeps the stored snapshot including avatar', () {
    final messages = _throughDatabase(encodeRoleplayMessages(session(), {}));
    final restored = decodeRoleplaySession(_aiSession(), messages, const [])!;

    expect(restored.title, '和阿离聊聊');
    expect(restored.character.avatarAssetId, '/avatars/alice.png');
    expect(restored.character.description, '寡言');
    expect(restored.phase, RoleplayPhase.completed);
    expect(restored.messages.map((m) => (m.speakerId, m.content)), [
      (roleplayUserSpeakerId, '你为什么回来？'),
      ('c_alice', '雨太大了。'),
      (roleplayUserSpeakerId, '只是因为雨？'),
    ]);
  });

  test('existing character card wins over the stored snapshot', () {
    final messages = _throughDatabase(encodeRoleplayMessages(session(), {}));
    final restored = decodeRoleplaySession(_aiSession(), messages, [
      CharacterProfile(
        id: 'c_alice',
        name: '阿离',
        role: '剑客',
        gender: 'unknown',
        aliases: const [],
        tags: const [],
        biography: '流亡的剑客',
        appearance: '',
        description: '寡言',
        currentState: '',
        identity: '',
        age: '',
        motivation: '',
        arc: '',
        personality: '',
        behaviorTags: const [],
        avatarAssetId: '/avatars/alice_v2.png',
        sortOrder: 0,
        createdAt: _created,
        updatedAt: _updated,
        deletedAt: notDeletedSentinel,
      ),
    ])!;
    expect(restored.character.avatarAssetId, '/avatars/alice_v2.png');
  });

  test('participant snapshot is written once, on the first user message', () {
    final messages = encodeRoleplayMessages(session(), {});
    final carriers = messages.where(
      (m) => m.metadata?.containsKey(roleplayParticipantMetadataKey) ?? false,
    );
    expect(carriers.map((m) => m.id), ['u_1']);
  });

  test('rejects messages without structured snapshots', () {
    final messages = [
      AiMessage.user(
        id: 'topic',
        content: 'Topic',
        metadata: const {
          'characterId': 'c_alice',
          'characterName': '阿离',
          'participants': [],
        },
      ),
    ];
    expect(
      () => decodeRoleplaySession(_aiSession(), messages, const []),
      throwsFormatException,
    );
  });
}
