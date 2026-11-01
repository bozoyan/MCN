// 职责: 测试 AI Read/Write/Edit 对章节与分卷路径的类型隔离和暂存语义
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_read.dart
//   lib/shared/services/ai/tools_write.dart
//   lib/shared/services/ai/tools_edit.dart
//   lib/shared/services/working_overlay.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import '../../../helpers/working_change_test_helper.dart';

void main() {
  group('AI chapter and volume tool routing', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late WorkingOverlayService overlay;
    late AiToolManager toolManager;
    late String volumeId;
    late String chapterId;

    setUp(() async {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
      overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
      )..registerAllTools();

      volumeId = await contentService.createVolume(
        title: '世界开端',
        description: '旧卷大纲',
      );
      chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );
    });

    tearDown(() async {
      await db.close();
      await appDb.close();
    });

    test('Read chapters lists chapters but not volumes', () async {
      await contentService.updateChapterContentPartial(
        chapterId: chapterId,
        content: '四字正文',
      );

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters'},
      );

      expect(result['type'], 'listing');
      final entries = result['entries'] as List<dynamic>;
      expect(entries.map((entry) => entry['id']), contains(chapterId));
      expect(entries.map((entry) => entry['id']), isNot(contains(volumeId)));
      final chapterEntry = entries.singleWhere(
        (entry) => entry['id'] == chapterId,
      );
      expect(chapterEntry['word_count'], 4);
    });

    test(
      'Write chapter content returns current counts with and without punctuation',
      () async {
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'chapters/$chapterId/content', 'value': '新的正文。'},
        );

        expect(result['updated'], isTrue);
        expect(result['content_word_counts'], {
          'with_punctuation': 5,
          'without_punctuation': 4,
        });
        expect(result, isNot(contains('word_count_before')));
        expect(result, isNot(contains('word_count')));
        expect(result, isNot(contains('word_count_delta')));
        expect(
          (await contentService.getChapterById(chapterId))!.wordCount,
          (result['content_word_counts']
              as Map<String, dynamic>)['with_punctuation'],
        );
      },
    );

    test(
      'Write chapter fields returns word count when content is included',
      () async {
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'chapters/$chapterId',
            'fields': {'title': '新标题', 'content': '多字段正文！'},
          },
        );

        expect(result['updated'], isTrue);
        expect(result['fields'], containsAll(['title', 'content']));
        expect(result['content_word_counts'], {
          'with_punctuation': 6,
          'without_punctuation': 5,
        });
      },
    );

    test(
      'Edit chapter content returns current counts with and without punctuation',
      () async {
        await contentService.updateChapterContentPartial(
          chapterId: chapterId,
          content: '旧的正文。',
        );

        final result = await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'chapters/$chapterId/content',
            'old_text': '旧的正文。',
            'new_text': '新文！',
          },
        );

        expect(result['edited'], isTrue);
        expect(result['content_word_counts'], {
          'with_punctuation': 3,
          'without_punctuation': 2,
        });
        expect(result, isNot(contains('word_count_before')));
        expect(result, isNot(contains('word_count')));
        expect(result, isNot(contains('word_count_delta')));
        expect(
          (await contentService.getChapterById(chapterId))!.wordCount,
          (result['content_word_counts']
              as Map<String, dynamic>)['with_punctuation'],
        );
      },
    );

    test('只读字段回 read_only_field 而不是 unknown_field', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/word_count', 'value': '999'},
      );

      // unknown_field 是「字段不存在」，会让模型回头重读资源改字段名再试一次。
      expect(result['error_code'], 'permission_denied');
      expect(result['ignored_fields'], ['word_count']);
    });

    test('Write 暂不支持章节 type', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/type', 'value': 'extra'},
      );

      expect(result['error_code'], 'invalid_argument');
      expect((await contentService.getChapterById(chapterId))!.type, 'chapter');
    });

    test('Write 批量字段跳过 type，可写字段照常生效', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'chapters/$chapterId',
          'fields': {'volume_id': volumeId, 'type': 'extra'},
        },
      );

      expect(result['ok'], isTrue, reason: '$result');
      expect(result['updated'], isTrue);
      expect(result['ignored_fields'], ['type']);
      final chapter = await contentService.getChapterById(chapterId);
      expect(chapter!.parentId, volumeId);
      expect(chapter.type, 'chapter');
    });

    test('Write 批量字段只有 type 时不改变任何章节字段', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'chapters/$chapterId',
          'fields': {'type': 'extra'},
        },
      );

      expect(result['ok'], isTrue, reason: '$result');
      expect(result['updated'], isFalse);
      expect(result['ignored_fields'], ['type']);
      final chapter = await contentService.getChapterById(chapterId);
      expect(chapter!.parentId, isNull);
      expect(chapter.type, 'chapter');
    });

    // Edit 是「读旧值 → 文本替换 → 写回」，中途不经过 Write 的枚举校验。
    // 白名单是这条路径上唯一的防线，枚举字段必须挡在外面。type 属 writeScalar
    // 字段，返回 use_write_for_scalar 引导模型改用 Write（而非 unknown_field）。
    test('Edit 拒绝枚举字段，挡住写入非法值', () async {
      final locationId = await contentService.locationsService.createLocation(
        name: '世界',
        type: 'world',
      );

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'locations/$locationId/type',
          'old_text': 'world',
          'new_text': 'worlld',
        },
      );

      expect(result['error_code'], 'unsupported');
      expect(result['error'], contains('Write'));
      expect(
        (await contentService.locationsService.getLocationById(
          locationId,
        ))!.type,
        'world',
      );
    });

    test('Read chapters/{volumeId} rejects volume rows', () async {
      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters/$volumeId'},
      );

      expect(result['error'], 'Chapter not found: $volumeId');
    });

    test('Write chapters/{volumeId} rejects volume rows', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$volumeId/content', 'value': '错误写入'},
      );

      expect(result['error_code'], 'unsupported');
      expect(result['error'], contains('volumes/$volumeId/outline'));
    });

    test(
      'Write moves a chapter to a volume without a working change',
      () async {
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'chapters/$chapterId/volume_id', 'value': volumeId},
        );

        expect(result['updated'], isTrue);
        expect(result['volume_id'], volumeId);
        expect(result.containsKey('working_change_id'), isFalse);
        expect(
          (await contentService.getChapterById(chapterId))!.parentId,
          volumeId,
        );
        expect(await overlay.getWorkingChanges(), isEmpty);
      },
    );

    test('Write with an empty volume_id moves a chapter to the root', () async {
      await contentService.moveToVolume(chapterId, volumeId);

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/volume_id', 'value': ''},
      );

      expect(result['updated'], isTrue);
      expect(result['volume_id'], isNull);
      expect(
        (await contentService.getChapterById(chapterId))!.parentId,
        isNull,
      );
      expect(await overlay.getWorkingChanges(), isEmpty);
    });

    test(
      'Write leaves sibling order unchanged when volume_id is unchanged',
      () async {
        final siblingId = await contentService.createChapter(
          siblingOrder: 1,
          title: '第二章',
        );
        await contentService.moveToVolume(chapterId, volumeId);
        await contentService.moveToVolume(siblingId, volumeId);
        final before = await contentService.getChapterById(chapterId);

        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'chapters/$chapterId/volume_id', 'value': volumeId},
        );

        final after = await contentService.getChapterById(chapterId);
        expect(result['updated'], isFalse);
        expect(after!.siblingOrder, before!.siblingOrder);
        expect(await overlay.getWorkingChanges(), isEmpty);
      },
    );

    test('Write rejects a chapter ID as a target volume', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/volume_id', 'value': chapterId},
      );

      expect(result['error_code'], 'unsupported');
      expect(
        (await contentService.getChapterById(chapterId))!.parentId,
        isNull,
      );
    });

    test('Edit chapters/{volumeId} rejects volume rows', () async {
      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'chapters/$volumeId/outline',
          'old_text': '旧卷大纲',
          'new_text': '新卷大纲',
        },
      );

      expect(result['error'], contains('volumes/$volumeId/outline'));
    });

    test('Read volumes/{volumeId} exposes outline but not content', () async {
      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'volumes/$volumeId'},
      );

      expect(result['outline'], '旧卷大纲');
      expect(result.containsKey('content'), isFalse);
    });

    test('Read volumes/{volumeId}/content rejects content field', () async {
      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'volumes/$volumeId/content'},
      );

      expect(result['error'], contains('Unknown volume field: content'));
    });

    test('Write volumes/{volumeId}/content rejects content field', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'volumes/$volumeId/content', 'value': '错误写入'},
      );

      expect(result['error_code'], 'invalid_argument');
      expect(result['error'], contains('Writable fields: title, outline'));
    });

    test('Edit volumes/{volumeId}/content rejects content field', () async {
      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'volumes/$volumeId/content',
          'old_text': '旧卷大纲',
          'new_text': '新卷大纲',
        },
      );

      // 只锁语义，不锁措辞：字段清单从 schema 生成，文案会随之变。
      expect(result['error_code'], 'invalid_argument');
      expect(result['error'], contains('title, outline'));
    });

    test(
      'Write volumes applies change immediately and accept records it',
      () async {
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'volumes/$volumeId/outline', 'value': '新卷大纲'},
        );

        expect(result['updated'], isTrue);
        final beforeAccept = await contentService.getChapterById(volumeId);
        expect(beforeAccept!.outline, '新卷大纲');

        final commitId = await overlay.commitWorkingChanges(
          [await onlyActiveWorkingChangeId(db)],
          source: workingChangeSourceAi,
          message: 'test.accept_ai_volume_write',
        );

        expect(commitId, isNotNull);
        final afterAccept = await contentService.getChapterById(volumeId);
        expect(afterAccept!.outline, '新卷大纲');
      },
    );

    test(
      'Edit volumes applies change immediately and accept records it',
      () async {
        final result = await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'volumes/$volumeId/outline',
            'old_text': '旧卷',
            'new_text': '新卷',
          },
        );

        expect(result['edited'], isTrue);
        final beforeAccept = await contentService.getChapterById(volumeId);
        expect(beforeAccept!.outline, '新卷大纲');

        final commitId = await overlay.commitWorkingChanges(
          [await onlyActiveWorkingChangeId(db)],
          source: workingChangeSourceAi,
          message: 'test.accept_ai_volume_edit',
        );

        expect(commitId, isNotNull);
        final afterAccept = await contentService.getChapterById(volumeId);
        expect(afterAccept!.outline, '新卷大纲');
      },
    );

    test(
      'Edit empty chapter outline with empty old_text initializes the field',
      () async {
        final result = await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'chapters/$chapterId/outline',
            'old_text': '',
            'new_text': '初始化章节大纲',
          },
        );

        expect(result['edited'], isTrue);
        expect(result['error_code'], isNull);
        expect(
          (await contentService.getChapterById(chapterId))!.outline,
          '初始化章节大纲',
        );
      },
    );

    test(
      'Edit empty chapter outline with non-empty old_text is not unknown_field',
      () async {
        final result = await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'chapters/$chapterId/outline',
            'old_text': '不存在的大纲',
            'new_text': '新大纲',
          },
        );

        expect(result['error_code'], 'failed_precondition');
        expect(result['error'], isNot(contains('Unknown chapter field')));
        expect(result['hint'], contains('empty string'));
      },
    );

    test('Edit can initialize an empty field with empty old_text', () async {
      final emptyVolumeId = await contentService.createVolume(
        title: '空卷',
        description: '',
      );

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'volumes/$emptyVolumeId/outline',
          'old_text': '',
          'new_text': '初始化分卷大纲',
          'all': true,
        },
      );

      expect(result['edited'], isTrue);
      expect(result['match_count'], 1);
      final beforeAccept = await contentService.getChapterById(emptyVolumeId);
      expect(beforeAccept!.outline, '初始化分卷大纲');

      final commitId = await overlay.commitWorkingChanges(
        [await onlyActiveWorkingChangeId(db)],
        source: workingChangeSourceAi,
        message: 'test.accept_ai_volume_empty_edit',
      );

      expect(commitId, isNotNull);
      final afterAccept = await contentService.getChapterById(emptyVolumeId);
      expect(afterAccept!.outline, '初始化分卷大纲');
    });

    test(
      'published mixed resource writes reject before changing continuity fields',
      () async {
        await contentService.updateChapterContentPartial(
          chapterId: chapterId,
          content: '原文',
          brief: '旧摘要',
        );
        await contentService.updateChapterStat(
          chapterId: chapterId,
          stat: chapterStatPublished,
        );
        final before = await contentService.getChapterById(chapterId);
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'chapters/$chapterId',
            'fields': {'brief': '不应更新', 'content': '不应改文'},
          },
        );
        expect(result['error_code'], 'locked');
        final after = await contentService.getChapterById(chapterId);
        expect(after!.brief, before!.brief);
        expect(after.content, before.content);
        expect(after.updatedAt, before.updatedAt);
        expect(await db.workingChangeDao.getAll(), isEmpty);
      },
    );

    test('volume text changes retain identity when rolled back', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'volumes/$volumeId',
          'fields': {'title': '新卷名', 'outline': '新卷大纲'},
        },
      );
      expect(result['updated'], isTrue);
      final changes = await db.workingChangeDao.getAll();
      expect(changes, hasLength(2));
      final commitId = await overlay.commitWorkingChanges(
        changes.map((change) => change.id).toList(),
        source: workingChangeSourceAi,
        message: 'accept volume',
      );
      await overlay.rollbackCommit(commitId: commitId!);
      final restored = (await contentService.getChapterById(volumeId))!;
      expect(restored.title, '世界开端');
      expect(restored.outline, '旧卷大纲');
      expect(restored.id, volumeId);
    });

    test(
      'deleted chapter and volume targets refuse reads and mutations',
      () async {
        await db.chapterDao.softDelete(chapterId);
        await db.chapterDao.softDelete(volumeId);
        for (final path in ['chapters/$chapterId', 'volumes/$volumeId']) {
          for (final operation in ['Read', 'Write', 'Edit']) {
            final result = await toolManager.executeTool(
              name: operation,
              input: {
                'path': operation == 'Edit' ? '$path/outline' : path,
                if (operation == 'Write') 'fields': {'outline': '不应修改'},
                if (operation == 'Edit') ...{
                  'old_text': '',
                  'new_text': '不应修改',
                },
              },
            );
            expect(
              result['error_code'],
              'not_found',
              reason: '$operation $path: $result',
            );
          }
        }
        expect(await db.workingChangeDao.getAll(), isEmpty);
        expect(await contentService.getChapterById(chapterId), isNull);
        expect(await contentService.getChapterById(volumeId), isNull);
      },
    );

    test('Edit still rejects empty old_text for non-empty fields', () async {
      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'volumes/$volumeId/outline',
          'old_text': '',
          'new_text': '不应写入',
          'all': true,
        },
      );

      expect(result['error'], 'old_text must not be empty');
    });
  });
}
