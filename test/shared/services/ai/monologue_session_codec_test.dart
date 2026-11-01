// 职责: 验证独白会话编解码 — 结构化往返不丢头像/多行内容，拒绝旧格式消息。
// 关联文件:
//   lib/shared/services/ai/monologue_session_codec.dart
//   lib/shared/models/monologue_models.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' show AiChatSession;
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/monologue_models.dart';
import 'package:reveric/shared/services/ai/monologue_session_codec.dart';

final _created = DateTime(2026, 9, 1, 10);
final _updated = DateTime(2026, 9, 1, 11);

AiChatSession _aiSession() => AiChatSession(
  id: 'mono_1',
  novelId: 'novel_1',
  title: '阿离 · 要不要回去',
  mode: 'monologue',
  provider: 'openai',
  model: 'gpt-x',
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
  const alice = MonologueParticipant(
    characterId: 'c_alice',
    name: '阿离',
    role: '剑客',
    biography: '流亡的剑客',
    description: '寡言',
    avatarAssetId: '/avatars/alice.png',
  );

  test('structured round trip keeps avatar, title and multi-line text', () {
    final session = MonologueSession(
      id: 'mono_1',
      title: '阿离 · 要不要回去',
      novelId: 'novel_1',
      topic: '要不要回去',
      character: alice,
      monologues: [
        MonologueEntry(
          id: 'm_1',
          characterId: alice.characterId,
          characterName: alice.name,
          innerThoughts: '第一行。\n第二行也要在。',
          plannedActions: '先去城门。\n再找伯言。',
          timestamp: _created,
        ),
        MonologueEntry(
          id: 'm_2',
          characterId: alice.characterId,
          characterName: alice.name,
          innerThoughts: '只有内心活动。',
          plannedActions: '',
          timestamp: _updated,
        ),
      ],
      createdAt: _created,
      updatedAt: _updated,
    );

    final messages = _throughDatabase(encodeMonologueMessages(session, {}));
    final restored = decodeMonologueSession(_aiSession(), messages)!;

    expect(restored.title, '阿离 · 要不要回去');
    expect(restored.topic, '要不要回去');
    expect(restored.character.avatarAssetId, '/avatars/alice.png');
    expect(restored.character.description, '寡言');
    expect(restored.phase, MonologuePhase.completed);
    expect(restored.model, 'gpt-x');
    expect(restored.monologues.map((e) => e.innerThoughts), [
      '第一行。\n第二行也要在。',
      '只有内心活动。',
    ]);
    expect(restored.monologues.map((e) => e.plannedActions), [
      '先去城门。\n再找伯言。',
      '',
    ]);
  });

  test('written text does not depend on the UI language', () {
    final entry = MonologueEntry(
      id: 'm_1',
      characterId: alice.characterId,
      characterName: alice.name,
      innerThoughts: '想',
      plannedActions: '做',
      timestamp: _created,
    );
    expect(monologueEntryText(entry), '【内心活动】想\n【接下来的行动】做');
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
      () => decodeMonologueSession(_aiSession(), messages),
      throwsFormatException,
    );
  });
}
