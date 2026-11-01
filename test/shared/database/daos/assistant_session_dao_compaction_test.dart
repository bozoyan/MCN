// 职责: 测试 AssistantSessionDao compaction 持久化 — append-only、多次压缩、metadata、插入位置
// 关联文件:
//   lib/shared/database/daos/assistant_session_dao.dart
//   lib/shared/agent/agent_context_manager.dart
//   lib/shared/agent/message.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/daos/assistant_session_dao.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';

void main() {
  late AppDatabase db;
  late AssistantSessionDao dao;

  setUp(() async {
    db = AppDatabase.forTest(NativeDatabase.memory());
    dao = db.assistantSessionDao;
    await dao.getOrCreateByChat(channelType: 'wechat', chatId: 'wxid_test');
  });

  tearDown(() async {
    await db.close();
  });

  AgentContextSnapshot snapshot({
    required String summary,
    required int compactionCount,
    List<AgentMessage> retained = const [],
    int? tokensBefore,
    int? tokensAfter,
  }) {
    return AgentContextSnapshot(
      messages: retained,
      summary: summary,
      compactionCount: compactionCount,
      lastCompactionTokensBefore: tokensBefore,
      lastCompactionTokensAfter: tokensAfter,
    );
  }

  group('AssistantSessionDao compaction persistence', () {
    test(
      'inserts compact_summary before retained messages on first compaction',
      () async {
        // 模拟一次压缩后落库：retained = [assistant("answer")]，summary = "summary v1"
        final snap = snapshot(
          summary: 'summary v1',
          compactionCount: 1,
          retained: [AgentMessage.assistant(id: 'a1', content: 'answer')],
          tokensBefore: 50000,
          tokensAfter: 20000,
        );

        await dao.upsertMessages(
          sessionId: 'wxid_test',
          messages: [
            AiMessage.user(id: 'u1', content: 'question'),
            AiMessage.assistant(id: 'a1', content: 'answer'),
          ],
          contextSnapshot: snap,
        );

        final rows = await dao.loadMessages('wxid_test');
        final types = rows.map((r) => r.type).toList();

        // compact_summary 应在 retained 首条（a1）之前
        expect(types, contains(AiMessageType.compact_summary));
        final summaryIdx = types.indexOf(AiMessageType.compact_summary);
        final answerIdx = rows.indexWhere((r) => r.id == 'a1');
        expect(summaryIdx, lessThan(answerIdx));
      },
    );

    test(
      'append-only: second compaction preserves first compact_summary',
      () async {
        // 第一次压缩
        final snap1 = snapshot(
          summary: 'summary v1',
          compactionCount: 1,
          retained: [AgentMessage.assistant(id: 'a1', content: 'answer 1')],
        );
        await dao.upsertMessages(
          sessionId: 'wxid_test',
          messages: [
            AiMessage.user(id: 'u1', content: 'question 1'),
            AiMessage.assistant(id: 'a1', content: 'answer 1'),
          ],
          contextSnapshot: snap1,
        );

        // 第二次压缩：retained 变化，新 summary
        final snap2 = snapshot(
          summary: 'summary v2',
          compactionCount: 2,
          retained: [
            AgentMessage.user(id: 'u2', content: 'question 2'),
            AgentMessage.assistant(id: 'a2', content: 'answer 2'),
          ],
        );
        await dao.upsertMessages(
          sessionId: 'wxid_test',
          messages: [
            // 旧 compact_summary 仍在 messages 列表里（append-only 不删）
            AiMessage.user(
              id: 'ctx_summary_wxid_test_1',
              content: 'summary v1',
              type: AiMessageType.compact_summary,
            ),
            AiMessage.user(id: 'u2', content: 'question 2'),
            AiMessage.assistant(id: 'a2', content: 'answer 2'),
          ],
          contextSnapshot: snap2,
        );

        final rows = await dao.loadMessages('wxid_test');
        final summaries = rows
            .where((r) => r.type == AiMessageType.compact_summary)
            .toList();

        // 两条 compact_summary 都应存在（append-only）
        expect(summaries.length, 2);
        expect(summaries[0].content, 'summary v1');
        expect(summaries[1].content, 'summary v2');
        // id 唯一（含 compactionCount）
        expect(summaries[0].id, 'ctx_summary_wxid_test_1');
        expect(summaries[1].id, 'ctx_summary_wxid_test_2');
      },
    );

    test('compact_summary carries compaction metadata', () async {
      final snap = snapshot(
        summary: 'summary with metadata',
        compactionCount: 3,
        retained: [AgentMessage.assistant(id: 'a1', content: 'answer')],
        tokensBefore: 80000,
        tokensAfter: 30000,
      );

      await dao.upsertMessages(
        sessionId: 'wxid_test',
        messages: [
          AiMessage.user(id: 'u1', content: 'question'),
          AiMessage.assistant(id: 'a1', content: 'answer'),
        ],
        contextSnapshot: snap,
      );

      final rows = await dao.loadMessages('wxid_test');
      final summary = rows.firstWhere(
        (r) => r.type == AiMessageType.compact_summary,
      );

      expect(summary.metadata, isNotNull);
      expect(summary.metadata!['compaction_count'], 3);
      expect(summary.metadata!['tokens_before'], 80000);
      expect(summary.metadata!['tokens_after'], 30000);
    });

    test(
      'skips summary insertion when retained has no content match',
      () async {
        // retained 消息在 UI messages 中不存在（内容不匹配）
        final snap = snapshot(
          summary: 'orphan summary',
          compactionCount: 1,
          retained: [
            AgentMessage.assistant(id: 'ghost', content: 'nonexistent answer'),
          ],
        );

        await dao.upsertMessages(
          sessionId: 'wxid_test',
          messages: [
            AiMessage.user(id: 'u1', content: 'question'),
            AiMessage.assistant(id: 'a1', content: 'answer'),
          ],
          contextSnapshot: snap,
        );

        final rows = await dao.loadMessages('wxid_test');
        // 未命中时跳过插入，compact_summary 不落库
        expect(
          rows.where((r) => r.type == AiMessageType.compact_summary),
          isEmpty,
        );
      },
    );

    test('no snapshot: persists messages without compact_summary', () async {
      await dao.upsertMessages(
        sessionId: 'wxid_test',
        messages: [
          AiMessage.user(id: 'u1', content: 'question'),
          AiMessage.assistant(id: 'a1', content: 'answer'),
        ],
      );

      final rows = await dao.loadMessages('wxid_test');
      expect(rows.map((r) => r.id), ['u1', 'a1']);
      expect(
        rows.where((r) => r.type == AiMessageType.compact_summary),
        isEmpty,
      );
    });
  });
}
