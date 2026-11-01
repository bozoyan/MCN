// 职责: 测试 Glob AI 工具，验证它基于资源路径列出 Read 可见内容。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_glob.dart
//   lib/shared/services/ai/tools_resource_search_support.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  group('Glob tool', () {
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

    // lore/materials 的 `?search=` 只过滤 path 的直属子节点，查不到
    // 子文件夹里的文档。`**/{标题}` 是它的替代，且根级与嵌套都覆盖。
    test('`**/{标题}` 跨层定位文档，根级与嵌套都命中', () async {
      final folderId = await contentService.documentsService.createFolder(
        type: 'lore',
        title: '魔法系统',
      );
      await contentService.documentsService.createDocument(
        type: 'lore',
        parentId: folderId,
        title: '火系魔法',
      );
      await contentService.documentsService.createDocument(
        type: 'lore',
        title: '根级设定',
      );

      final nested = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': '**/火系魔法'},
        callId: 'call_glob_nested_title',
      );
      final rootLevel = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': '**/根级设定'},
        callId: 'call_glob_root_title',
      );

      expect(nested['matches'], ['lore/魔法系统/火系魔法']);
      expect(rootLevel['matches'], ['lore/根级设定']);
    });

    // relations 整个集合不进资源树：listing 是全量的，Glob 枚举不出任何 listing
    // 之外的东西；而关系条数远超实体条数，展开只会吃掉扫描预算、把章节和角色挤出
    // 结果。关系一律走 /relations 或 GraphSearch。
    test('Glob 不覆盖 relations', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );
      final source = await contentService.createCharacterProfile(
        defaultName: '张三',
      );
      final target = await contentService.createCharacterProfile(
        defaultName: '李四',
      );
      for (var i = 0; i < 5; i++) {
        await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'relations',
            'fields': {
              'source_type': 'character',
              'source_id': source,
              'target_type': 'character',
              'target_id': target,
              'relation_type': i.isEven ? 'friend' : 'enemy',
              'chapter_id': chapterId,
              'proof': '证据 $i',
            },
          },
        );
      }

      final scoped = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'relations/**'},
        callId: 'call_glob_relations_scoped',
      );
      final all = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': '**'},
        callId: 'call_glob_relations_all',
      );

      // 展开的话这 5 条关系会占 41 条路径（1 集合根 + 5 资源 + 35 字段）。
      expect(scoped['matches'], isEmpty);
      // 空结果不等于「没有关系」，得指回 GraphSearch。
      expect(scoped['hint'], contains('GraphSearch'));
      expect(all['hint'], isNull);
      final everything = (all['matches'] as List).cast<String>();
      expect(everything.where((p) => p.startsWith('relations')), isEmpty);
      // 同库里的章节和角色照常可见。
      expect(everything.any((p) => p.startsWith('chapters/')), isTrue);
      expect(everything.any((p) => p.startsWith('characters/')), isTrue);
    });

    test('Read relations/{id}/proof 返回精确原值但不开放搜索', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );
      final source = await contentService.createCharacterProfile(
        defaultName: '张三',
      );
      final target = await contentService.createCharacterProfile(
        defaultName: '李四',
      );
      await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'relations',
          'fields': {
            'source_type': 'character',
            'source_id': source,
            'target_type': 'character',
            'target_id': target,
            'relation_type': 'friend',
            'chapter_id': chapterId,
            'proof': '雪夜里两人共饮。',
          },
        },
      );
      final relations = await contentService.entityRelationsService
          .getAllRelations();
      final relationId = relations.single.id;

      final field = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'relations/$relationId/proof'},
        callId: 'call_read_relation_field',
      );
      expect(field['value'], '雪夜里两人共饮。');
      expect(field['path'], 'relations/$relationId/proof');
      final paths = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'relations/**'},
      );
      expect(paths['matches'], isEmpty);
    });

    test('lists matching chapter field resource paths', () async {
      final firstId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );
      final secondId = await contentService.createChapter(
        siblingOrder: 2,
        title: '第二章',
      );

      final result = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'chapters/*/content'},
        callId: 'call_glob_chapter_content_test',
      );

      expect(result['ok'], isTrue);
      expect(result['truncated'], isFalse);
      expect(result['matches'], contains('chapters/$firstId/content'));
      expect(result['matches'], contains('chapters/$secondId/content'));
      expect(result['matches'], isNot(contains('chapters/$firstId/title')));
    });

    test('supports brace expansion across resource fields', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );

      final result = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'chapters/*/{title,outline}'},
        callId: 'call_glob_brace_expansion_test',
      );

      expect(result['ok'], isTrue);
      expect(result['matches'], contains('chapters/$chapterId/title'));
      expect(result['matches'], contains('chapters/$chapterId/outline'));
      expect(result['matches'], isNot(contains('chapters/$chapterId/content')));
    });

    test('supports question, recursive and character-class patterns', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '第一章',
      );

      final recursiveResult = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'chapters/**/conten?'},
        callId: 'call_glob_recursive_question_test',
      );
      final classResult = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'chapters/*/conten[tx]'},
        callId: 'call_glob_character_class_test',
      );

      expect(recursiveResult['ok'], isTrue);
      expect(
        recursiveResult['matches'],
        contains('chapters/$chapterId/content'),
      );
      expect(classResult['ok'], isTrue);
      expect(classResult['matches'], contains('chapters/$chapterId/content'));
    });

    test('returns a structured error for invalid glob patterns', () async {
      final result = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'chapters/[z-a]/content'},
        callId: 'call_glob_invalid_pattern_test',
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
      expect(result['error'], contains('Invalid glob pattern'));
    });

    test('reports scan statistics', () async {
      await contentService.createChapter(siblingOrder: 1, title: '第一章');

      final result = await toolManager.executeTool(
        name: 'Glob',
        input: {'pattern': 'chapters/*/content', 'path': 'chapters'},
        callId: 'call_glob_scan_stats_test',
      );

      expect(result['ok'], isTrue);
      expect(result['scanned_paths'], greaterThan(0));
      expect(result['scan_limit'], greaterThan(0));
      expect(result['scan_truncated'], isFalse);
    });

    test(
      'matches character name paths without filtering by name value',
      () async {
        final targetId = await contentService.createCharacterProfile(
          defaultName: '阿青',
        );
        final otherId = await contentService.createCharacterProfile(
          defaultName: '李四',
        );
        await contentService.updateCharacterProfile(
          entryId: targetId,
          name: '阿青',
          role: characterRoleProtagonist,
          gender: characterGenderFemale,
          biography: '越女剑影',
          description: '正在竹林练剑',
        );
        await contentService.updateCharacterProfile(
          entryId: otherId,
          name: '李四',
          role: characterRoleSupporting,
          gender: characterGenderMale,
          biography: '茶馆伙计',
          description: '正在打听消息',
        );

        final result = await toolManager.executeTool(
          name: 'Glob',
          input: {'pattern': 'characters/*/name'},
          callId: 'call_glob_character_name_paths_test',
        );

        expect(result['ok'], isTrue);
        expect(result['matches'], contains('characters/$targetId/name'));
        expect(result['matches'], contains('characters/$otherId/name'));
        expect(result['matches'], isNot(contains('characters/阿青/name')));
      },
    );
  });
}
