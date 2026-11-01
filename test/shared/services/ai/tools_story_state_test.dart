// 职责: 测试编年史者写后字段（brief/tension/emotion/events）与 story_state 读写
// 关联文件:
//   lib/shared/services/ai/tools_read.dart
//   lib/shared/services/ai/tools_write.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/database/novel_content_daos/novel_state_snapshot_dao.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  group('chronicler story state tools', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late AiToolManager toolManager;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
      final overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
      )..registerAllTools();
    });

    tearDown(() async {
      await db.close();
      await appDb.close();
    });

    Future<Map<String, dynamic>> write(
      String path,
      Map<String, dynamic> extra,
    ) {
      return toolManager.executeTool(
        name: 'Write',
        input: {'path': path, ...extra},
        callId: 'call_${path.hashCode}',
      );
    }

    Future<Map<String, dynamic>> read(String path) {
      return toolManager.executeTool(
        name: 'Read',
        input: {'path': path},
        callId: 'call_read_${path.hashCode}',
      );
    }

    Future<Map<String, dynamic>> edit(String path, Map<String, dynamic> extra) {
      return toolManager.executeTool(
        name: 'Edit',
        input: {'path': path, ...extra},
        callId: 'call_edit_${path.hashCode}',
      );
    }

    // -------------------------------------------------------------------------
    // /chapters/{id}/events
    // -------------------------------------------------------------------------

    test('writes and reads chapter events round-trip', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );

      final writeResult = await write('chapters/$chapterId/events', {
        'value': [
          {
            'title': '密室交易',
            'summary': '林越换回卖身契',
            'state_change': '林越持有卖身契，假印信落在对方手里',
          },
          {'title': '追兵入城', 'summary': '巡夜人封锁北门'},
        ],
      });
      expect(writeResult['updated'], isTrue);
      expect(writeResult['count'], 2);

      final readResult = await read('chapters/$chapterId/events');
      final events = readResult['value'] as List;
      expect(events, hasLength(2));
      expect(events.first['title'], '密室交易');
      expect(events.first['state_change'], '林越持有卖身契，假印信落在对方手里');
      // 没给 state_change 的事件不该凭空多出这个键。
      expect((events[1] as Map).containsKey('state_change'), isFalse);
    });

    test('chapter events default to an empty list before extraction', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );

      final result = await read('chapters/$chapterId/events');
      expect(result['value'], isEmpty);
    });

    test('rejects malformed events instead of writing partial data', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );

      final result = await write('chapters/$chapterId/events', {
        'value': ['不是对象'],
      });
      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');

      final stored = await read('chapters/$chapterId/events');
      expect(stored['value'], isEmpty);
    });

    test(
      'canonical validation preserves one-sided events and rejects mixed writes atomically',
      () async {
        final chapterId = await contentService.createChapter(
          siblingOrder: 1,
          title: '原标题',
        );
        final events = await write('chapters/$chapterId/events', {
          'value': [
            {'title': '只给标题'},
            {'summary': '只给摘要'},
          ],
        });
        expect(events['updated'], true, reason: '$events');
        expect((await read('chapters/$chapterId/events'))['value'], [
          {'title': '只给标题', 'summary': ''},
          {'title': '', 'summary': '只给摘要'},
        ]);
        final rejected = await write('chapters/$chapterId', {
          'fields': {'title': '不应写入', 'tension': 42},
        });
        expect(rejected['error_code'], 'invalid_argument');
        expect((await contentService.getChapterById(chapterId))!.title, '原标题');
        expect(
          await db.workingChangeDao.getByResource('chapters/$chapterId/title'),
          isEmpty,
        );
      },
    );

    // -------------------------------------------------------------------------
    // tension / emotion
    // -------------------------------------------------------------------------

    test(
      'writes tension and emotion, rejecting out-of-range tension',
      () async {
        final chapterId = await contentService.createChapter(
          siblingOrder: 1,
          title: '第一章',
        );

        expect(
          (await write('chapters/$chapterId/tension', {'value': 7}))['updated'],
          isTrue,
        );
        expect(
          (await write('chapters/$chapterId/emotion', {
            'value': ['压抑', '决绝'],
          }))['updated'],
          isTrue,
        );

        expect((await read('chapters/$chapterId/tension'))['value'], 7);
        expect((await read('chapters/$chapterId/emotion'))['value'], [
          '压抑',
          '决绝',
        ]);

        final tooHigh = await write('chapters/$chapterId/tension', {
          'value': 42,
        });
        expect(tooHigh['ok'], isFalse);
        expect(tooHigh['error_code'], 'invalid_argument');
        // 越界写入必须整条拒绝，不能把旧值冲掉。
        expect((await read('chapters/$chapterId/tension'))['value'], 7);
      },
    );

    // -------------------------------------------------------------------------
    // 已发布章节的写入边界
    // -------------------------------------------------------------------------

    test(
      'published chapters accept chronicler fields but not content',
      () async {
        final chapterId = await contentService.createChapter(
          siblingOrder: 1,
          title: '第一章',
        );
        await contentService.updateChapterStat(
          chapterId: chapterId,
          stat: chapterStatPublished,
        );

        // 编年史者在发布之后才运行，这四个字段必须能写，否则整条链路断在发布这步。
        for (final entry in <String, Object>{
          'brief': '## 本章摘要\n林越换回卖身契。',
          'tension': 6,
          'emotion': ['压抑'],
          'events': [
            {'title': '密室交易', 'summary': '换回卖身契'},
          ],
        }.entries) {
          final result = await write('chapters/$chapterId/${entry.key}', {
            'value': entry.value,
          });
          expect(
            result['updated'],
            isTrue,
            reason: '已发布章节应允许写 ${entry.key}，实际返回 $result',
          );
        }

        expect(
          (await read('chapters/$chapterId/brief'))['value'],
          '## 本章摘要\n林越换回卖身契。',
        );

        final blocked = await write('chapters/$chapterId/content', {
          'value': '偷偷改正文',
        });
        expect(blocked['ok'], isFalse);
        expect(blocked['error_code'], 'locked');
      },
    );

    // -------------------------------------------------------------------------
    // story_state
    // -------------------------------------------------------------------------

    test('reads an empty state before the first write', () async {
      final result = await read('story_state');
      expect(result['error_code'], isNull);
      expect(result['content'], '');
      expect(result.containsKey('source_chapter_id'), isFalse);
    });

    test(
      'writes content without any chapters and preserves field values',
      () async {
        const body = '# 故事状态（截至第 1 章）\n\n/林越：持有卖身契';
        final written = await write('story_state', {
          'fields': {'content': body},
        });
        expect(written['updated'], isTrue);
        final current = await read('story_state');
        expect(current['content'], body);
        expect(current.containsKey('status'), isFalse);
        expect(current.containsKey('source_chapter_id'), isFalse);
        expect(current.containsKey('stale'), isFalse);
        expect((await read('story_state/content'))['value'], body);
        expect(await contentService.getChapters(), isEmpty);
        final columns = await db
            .customSelect('PRAGMA table_info(novel_state_snapshots)')
            .get();
        expect(
          columns.map((row) => row.data['name']),
          isNot(contains('source_chapter_id')),
        );
      },
    );

    test('writes the content field and retains the previous version', () async {
      await write('story_state', {
        'fields': {'content': '截至第 20 章'},
      });
      final previous = (await contentService.getCurrentStateSnapshot())!;
      final result = await write('story_state/content', {
        'value': '截至第 3 章（返工）',
      });
      expect(result['updated'], isTrue);
      expect((await read('story_state'))['content'], '截至第 3 章（返工）');
      final historical = await db.novelStateSnapshotDao.getById(previous.id);
      expect(historical?.content, '截至第 20 章');
      expect(historical?.status, novelStateSnapshotStatusSuperseded);
      final rows = await db.select(db.novelStateSnapshots).get();
      expect(rows, hasLength(2));
      expect(
        rows.where((row) => row.status == novelStateSnapshotStatusActive),
        hasLength(1),
      );
      expect(
        (await contentService.watchCurrentStateSnapshot().first)?.content,
        '截至第 3 章（返工）',
      );
    });

    test('writes a full state from a string value', () async {
      const body = '# 故事状态（截至第 101 章）\n\n林越仍在北门。';

      final result = await write('story_state', {'value': body});

      expect(result['updated'], isTrue);
      expect((await read('story_state'))['content'], body);
    });

    test('edits an existing state and preserves history', () async {
      await write('story_state', {
        'fields': {'content': '林越持有卖身契'},
      });
      final result = await edit('story_state/content', {
        'old_text': '卖身契',
        'new_text': '断刃',
      });
      expect(result['edited'], isTrue);
      expect(result.containsKey('source_chapter_id'), isFalse);
      expect((await read('story_state'))['content'], '林越持有断刃');
      expect(
        (await db.novelStateSnapshotDao.getLatestActive())?.createdBy,
        novelStateSnapshotCreatedByUser,
      );
      expect(await db.select(db.novelStateSnapshots).get(), hasLength(2));
    });

    test(
      'rejects empty content and retired status path without changing history',
      () async {
        await write('story_state', {
          'fields': {'content': '当前状态'},
        });
        for (final fields in <Map<String, dynamic>>[
          {},
          {'content': ''},
          {'content': '   '},
        ]) {
          final result = await write('story_state', {'fields': fields});
          expect(result['error_code'], isNotNull);
        }
        expect(
          (await write('story_state/status', {
            'value': 'superseded',
          }))['error_code'],
          'invalid_argument',
        );
        expect((await read('story_state'))['content'], '当前状态');
        expect(await db.select(db.novelStateSnapshots).get(), hasLength(1));
      },
    );

    test('ignores retired fields without treating them as a source', () async {
      final result = await write('story_state', {
        'fields': {'content': '当前状态', 'source_chapter_id': 'missing'},
      });
      expect(result['ok'], isTrue, reason: '$result');
      expect(result['ignored_fields'], ['source_chapter_id']);
      expect((await read('story_state'))['content'], '当前状态');
      expect(await db.select(db.novelStateSnapshots).get(), hasLength(1));
      final skipped = await write('story_state', {
        'fields': {'source_chapter_id': 'missing'},
      });
      expect(skipped['ok'], isTrue);
      expect(skipped['updated'], isFalse);
      expect(await db.select(db.novelStateSnapshots).get(), hasLength(1));
      expect(
        (await read('story_state/source_chapter_id'))['error_code'],
        'invalid_argument',
      );
    });

    test(
      'Edit initializes empty state and requires exact text thereafter',
      () async {
        final missing = await edit('story_state/content', {
          'old_text': '不存在的状态',
          'new_text': '不应保存',
        });
        expect(missing['error_code'], 'failed_precondition');
        expect(await db.select(db.novelStateSnapshots).get(), isEmpty);
        final initialized = await edit('story_state/content', {
          'old_text': '',
          'new_text': '林越持有断刃',
        });
        expect(initialized['edited'], isTrue);
        expect(initialized['path'], 'story_state');
        final mismatch = await edit('story_state/content', {
          'old_text': '卖身契',
          'new_text': '钥匙',
        });
        expect(mismatch['error_code'], isNotNull);
        expect((await read('story_state'))['content'], '林越持有断刃');
        expect(await db.select(db.novelStateSnapshots).get(), hasLength(1));
      },
    );

    test(
      'Create and Write share current state and Remove never changes history',
      () async {
        for (final tool in ['Create', 'Write', 'Create']) {
          final updated = await toolManager.executeTool(
            name: tool,
            input: {
              'path': 'story_state',
              'fields': {'content': '  原始状态  '},
            },
          );
          expect(updated['updated'], isTrue);
          expect(updated['path'], 'story_state');
          expect((await read('story_state'))['content'], '原始状态');
          final historyBefore = await db.select(db.novelStateSnapshots).get();
          final withIgnoredField = await toolManager.executeTool(
            name: tool,
            input: {
              'path': 'story_state',
              'fields': {'content': '替换', 'status': 'active'},
            },
          );
          expect(withIgnoredField['ok'], isTrue, reason: '$withIgnoredField');
          expect(withIgnoredField['ignored_fields'], ['status']);
          expect((await read('story_state'))['content'], '替换');
          expect(
            await db.select(db.novelStateSnapshots).get(),
            hasLength(historyBefore.length + 1),
          );
        }
        final before = (await contentService.getCurrentStateSnapshot())!;
        final history = await db.select(db.novelStateSnapshots).get();
        for (final path in ['story_state', 'story_state/content']) {
          final result = await toolManager.executeTool(
            name: 'Remove',
            input: {'path': path, 'force': true, 'recursive': true},
          );
          expect(result['ok'], isFalse);
        }
        final after = (await contentService.getCurrentStateSnapshot())!;
        expect(after.id, before.id);
        expect(after.content, '替换');
        expect(await db.select(db.novelStateSnapshots).get(), history);

        final edited = await edit('story_state/content', {
          'old_text': '替换',
          'new_text': '  精确空白  ',
        });
        expect(edited['edited'], isTrue);
        expect((await read('story_state/content'))['value'], '  精确空白  ');
      },
    );

    test('legacy path still resolves to the current story document', () async {
      final result = await write('story_state', {
        'fields': {'content': '当前状态'},
      });
      expect(result['path'], 'story_state');
      expect((await read('story_state'))['content'], '当前状态');
    });
  });
}
