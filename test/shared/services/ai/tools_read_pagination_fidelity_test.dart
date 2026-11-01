// 职责: 验证 Read 分页返回的文本是原文真子串，模型照抄后 Edit 必然命中
// 关联文件:
//   lib/shared/services/ai/tools_read.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/novel_content.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  group('Read 分页保真', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late AiToolManager toolManager;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: WorkingOverlayService(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        ),
      )..registerAllTools();
    });

    tearDown(() async {
      await db.close();
      await appDb.close();
    });

    Future<String> seedChapter(String content) async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '章节',
      );
      await contentService.updateChapterContent(
        chapterId: chapterId,
        title: '章节',
        outline: '',
        content: content,
      );
      return chapterId;
    }

    Future<String> readContent(
      String chapterId, {
      int? offset,
      int? limit,
    }) async {
      final result = await toolManager.executeTool(
        name: 'Read',
        input: {
          'path': 'chapters/$chapterId/content',
          'offset': ?offset,
          'limit': ?limit,
        },
        callId: 'call_read_fidelity',
      );
      return result['value'] as String;
    }

    // 线上 611 条 Edit old_text_not_found 的根因：分页曾用 LineSplitter + join('\n')，
    // 把 CRLF 归一化成 LF，模型照抄读到的文本回来做 Edit 必然找不到。
    test('CRLF 正文分页后仍是原串子串', () async {
      const content = '第一行\r\n第二行\r\n第三行';
      final chapterId = await seedChapter(content);

      final value = await readContent(chapterId);

      expect(content.contains(value), isTrue);
      expect(value, contains('\r\n'));
    });

    test('模型照抄 CRLF 分页结果做 Edit 能命中', () async {
      const content = '第一行\r\n第二行\r\n第三行';
      final chapterId = await seedChapter(content);

      final firstTwoLines = await readContent(chapterId, offset: 0, limit: 2);
      final edit = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'chapters/$chapterId/content',
          'old_text': firstTwoLines,
          'new_text': '改写后',
        },
        callId: 'call_read_fidelity_edit',
      );

      expect(edit['error'], isNull);
      expect(edit['edited'], isTrue);
    });

    test('末尾换行不会被吞掉', () async {
      const content = '第一行\n第二行\n';
      final chapterId = await seedChapter(content);

      final value = await readContent(chapterId);

      expect(content.contains(value), isTrue);
    });

    test('offset 分页切片是原串子串且不跨错行', () async {
      const content = '甲\r\n乙\n丙\r丁';
      final chapterId = await seedChapter(content);

      final tail = await readContent(chapterId, offset: 2, limit: 2);

      expect(content.contains(tail), isTrue);
      expect(tail, '丙\r丁');
    });

    test('空行与连续换行保持原样', () async {
      const content = '甲\n\n\n乙';
      final chapterId = await seedChapter(content);

      final value = await readContent(chapterId);

      expect(value, content);
    });

    // old_text 未命中时要给出可归因的原因，否则模型只能盲目重试
    // （线上单会话曾对同一 path 连撞 11 次）。
    test('换行符不一致时错误文本点明原因', () async {
      final chapterId = await seedChapter('第一行\r\n第二行');

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'chapters/$chapterId/content',
          'old_text': '第一行\n第二行',
          'new_text': '改写',
        },
        callId: 'call_diag_crlf',
      );

      expect(result['error_code'], 'failed_precondition');
      expect(result['error'], contains('line endings differ'));
      expect(result.containsKey('edit_diagnostics'), isFalse);
      expect(result['_metadata']['edit_diagnostics'], {
        'match_reason': 'line_endings',
        'source_length': 8,
        'old_text_length': 7,
      });
    });

    test('首行命中但后续分歧时报告分歧位置', () async {
      final chapterId = await seedChapter('第一行\n第二行\n第三行');

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'chapters/$chapterId/content',
          'old_text': '第一行\n我编造的第二行',
          'new_text': '改写',
        },
        callId: 'call_diag_diverge',
      );

      expect(result['error_code'], 'failed_precondition');
      expect(result['error'], contains('diverges'));
      final diagnostics = result['_metadata']['edit_diagnostics'];
      expect(diagnostics['match_reason'], 'first_line_diverged');
      expect(diagnostics['divergence_offset'], 4);
    });
  });
}
