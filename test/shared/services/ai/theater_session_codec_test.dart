// 职责: 验证小剧场会话编解码 — 结构化往返不丢头像/标题/舞台指示边界，缺失结构化快照时拒绝恢复。
// 关联文件:
//   lib/shared/services/ai/theater_session_codec.dart
//   lib/shared/models/theater_models.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' show AiChatSession;
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/theater_models.dart';
import 'package:reveric/shared/services/ai/theater_session_codec.dart';

final _created = DateTime(2026, 9, 1, 10);
final _updated = DateTime(2026, 9, 1, 11);

AiChatSession _aiSession({String title = '雨夜对峙'}) => AiChatSession(
  id: 'theater_1',
  novelId: 'novel_1',
  title: title,
  mode: 'theater',
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
  const alice = TheaterParticipant(
    characterId: 'c_alice',
    name: '阿离',
    role: '剑客',
    biography: '流亡的剑客',
    description: '寡言',
    avatarAssetId: '/avatars/alice.png',
  );
  const bob = TheaterParticipant(
    characterId: 'c_bob',
    name: '伯言',
    role: '谋士',
    biography: '旧识',
  );

  test('structured round trip keeps avatar, title and stage boundaries', () {
    final session = TheaterSession(
      id: 'theater_1',
      title: '雨夜对峙',
      novelId: 'novel_1',
      sceneDescription: '破庙，雨夜',
      participants: const [alice, bob],
      lines: [
        TheaterLine(
          id: 'line_1',
          characterId: alice.characterId,
          characterName: alice.name,
          dialogue: '你来晚了。',
          stageDirection: '按住剑柄',
          turn: 1,
          timestamp: _created,
        ),
        // 台词本身以全角括号开头：旧格式会被误当成舞台指示。
        TheaterLine(
          id: 'line_2',
          characterId: bob.characterId,
          characterName: bob.name,
          dialogue: '（低声）路上有人跟着。',
          turn: 1,
          timestamp: _created,
        ),
      ],
      phase: TheaterPhase.completed,
      createdAt: _created,
      updatedAt: _updated,
    );

    final messages = _throughDatabase(encodeTheaterMessages(session, const {}));
    final restored = decodeTheaterSession(_aiSession(), messages)!;

    expect(restored.title, '雨夜对峙');
    expect(restored.participants.first.avatarAssetId, '/avatars/alice.png');
    expect(restored.participants.map((p) => p.description), ['寡言', '']);
    expect(restored.lines[0].stageDirection, '按住剑柄');
    expect(restored.lines[0].dialogue, '你来晚了。');
    expect(restored.lines[1].stageDirection, isNull);
    expect(restored.lines[1].dialogue, '（低声）路上有人跟着。');
    expect(restored.phase, TheaterPhase.completed);
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
      () => decodeTheaterSession(_aiSession(), messages),
      throwsFormatException,
    );
  });

  test('no messages decodes to null', () {
    expect(decodeTheaterSession(_aiSession(), const []), isNull);
  });
}
