// 职责: 验证议会会话编解码 — 结构化往返保留成员人设/专属模型与总结小节，结构化空会话可恢复，旧格式会话被拒绝。
// 关联文件:
//   lib/shared/services/ai/council_session_codec.dart
//   lib/shared/models/agent_council_models.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' show AiChatSession;
import 'package:reveric/shared/models/agent_council_models.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/services/ai/council_session_codec.dart';

final _created = DateTime(2026, 2, 7, 21, 16, 6);
final _updated = DateTime(2026, 2, 7, 21, 16, 18);

AiChatSession _aiSession({
  String title = '康复房间发动机开发',
  Map<String, dynamic>? metadata,
}) => AiChatSession(
  id: 'council_1',
  novelId: 'novel_1',
  title: title,
  mode: 'council',
  metadata: metadata,
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

const _custom = CouncilParticipant(
  id: 'my_editor',
  name: '毒舌编辑',
  description: '只挑毛病',
  prompt: '你是一位毒舌编辑。',
  avatarPath: '/avatars/editor.png',
  modelOptionId: 'deepseek::deepseek-chat',
);

const _summaryText = '''## 共识要点
- 开篇保留悬念（剧情架构师）

## 关键分歧
- 是否提前揭示身份
  - 观点A（人物分析师）：提前
  - 观点B（剧情架构师）：延后

## 待决事项
- 主角的真实动机是否在第三章交代

## 下一步行动
1. 改写第一章结尾
2. 补一场配角戏''';

void main() {
  CouncilMessage message(
    String id,
    String participantId,
    String content,
    int round,
  ) => CouncilMessage(
    id: id,
    participantId: participantId,
    participantName: participantId == councilUserParticipantId
        ? '你'
        : participantId,
    content: content,
    timestamp: _created,
    round: round,
  );

  final session = AgentCouncilSession(
    id: 'council_1',
    novelId: 'novel_1',
    title: '开篇讨论',
    topic: '开篇要不要揭示身份？',
    participants: [defaultCouncilParticipants().first, _custom],
    rounds: [
      CouncilRound(
        roundNumber: 1,
        isComplete: true,
        messages: [
          message('m1', 'plot_architect', '延后揭示。', 1),
          message('m2', 'my_editor', '太拖了。', 1),
        ],
      ),
      CouncilRound(
        roundNumber: 2,
        isComplete: true,
        messages: [
          message('m3', councilUserParticipantId, '我倾向延后。', 2),
          message('m4', 'my_editor', '那就把钩子做足。', 2),
        ],
      ),
    ],
    summary: CouncilSummary(
      content: _summaryText,
      timestamp: _updated,
      coveredThroughRound: 1,
      coveredThroughMessageId: 'm2',
      keyPoints: const ['开篇保留悬念（剧情架构师）'],
      openQuestions: const ['主角的真实动机是否在第三章交代'],
      actionItems: const ['改写第一章结尾', '补一场配角戏'],
    ),
    phase: CouncilPhase.completed,
    createdAt: _created,
    updatedAt: _updated,
  );

  test('structured round trip keeps custom personas and summary sections', () {
    final messages = _throughDatabase(encodeCouncilMessages(session, const {}));
    final restored = decodeCouncilSession(_aiSession(), messages)!;

    expect(restored.topic, session.topic);
    final editor = restored.participants.last;
    expect(editor.prompt, _custom.prompt);
    expect(editor.avatarPath, _custom.avatarPath);
    expect(editor.modelOptionId, _custom.modelOptionId);

    expect(restored.rounds.map((r) => r.roundNumber), [1, 2]);
    expect(restored.rounds.last.messages.first.isUser, isTrue);
    expect(restored.rounds.expand((r) => r.messages).map((m) => m.id), [
      'm1',
      'm2',
      'm3',
      'm4',
    ]);

    final summary = restored.summary!;
    // 落库正文就是总结本身，不再把要点列表拼到后面。
    expect(summary.content, _summaryText);
    expect(summary.coveredThroughRound, 1);
    expect(summary.coveredThroughMessageId, 'm2');
    expect(summary.openQuestions, ['主角的真实动机是否在第三章交代']);
    expect(summary.actionItems, ['改写第一章结尾', '补一场配角戏']);
  });

  test('summary is stored right after the round it covers', () {
    final messages = encodeCouncilMessages(session, const {});
    expect(messages.map((m) => m.id), [
      'council_1_user_topic',
      'm1',
      'm2',
      'council_1_summary',
      'm3',
      'm4',
    ]);
  });

  test('rejects legacy participant metadata', () {
    expect(
      () => decodeCouncilSession(_aiSession(), [
        AiMessage.user(
          id: 'topic',
          content: 'Topic',
          metadata: const {
            'participants': [
              {'id': 'my_editor', 'name': 'Editor'},
            ],
          },
        ),
      ]),
      throwsFormatException,
    );
  });

  group('session without messages', () {
    test('restores topic and participants from row metadata', () {
      final restored = decodeCouncilSession(
        _aiSession(metadata: councilRowMetadata(session)),
        const [],
      )!;
      expect(restored.topic, session.topic);
      expect(restored.participants.last.prompt, _custom.prompt);
      expect(restored.rounds, isEmpty);
      expect(restored.phase, CouncilPhase.completed);
      expect(restored.createdAt, _created);
    });

    test('rejects legacy row metadata without messages', () {
      expect(
        () => decodeCouncilSession(
          _aiSession(
            metadata: {
              'topic': 'Topic',
              'participants': [
                {'id': 'my_editor', 'name': 'Editor'},
              ],
            },
          ),
          const [],
        ),
        throwsFormatException,
      );
    });

    test('rejects missing participant snapshots', () {
      expect(
        () => decodeCouncilSession(_aiSession(), const []),
        throwsFormatException,
      );
    });

    test('returns null when neither metadata topic nor title is usable', () {
      expect(
        decodeCouncilSession(
          _aiSession(title: '  ', metadata: {'topic': '  '}),
          const [],
        ),
        isNull,
      );
      expect(decodeCouncilSession(_aiSession(title: ''), const []), isNull);
    });
  });
}
