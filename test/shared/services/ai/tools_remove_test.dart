// 职责: 测试 AI Remove 工具的资源删除语义、错误保护与链接返回
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_remove.dart
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/services/working_overlay.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  group('Remove tool', () {
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

    for (final force in [false, true]) {
      test(
        'chapter-volume mismatches preserve nodes and references with force=$force',
        () async {
          final volumeId = await contentService.createVolume(title: '卷');
          final childId = await contentService.createChapter(
            parentId: volumeId,
            siblingOrder: 1,
            title: '卷内章',
          );
          final extraId = await contentService.createChapter(
            siblingOrder: 2,
            title: '番外',
          );
          await contentService.updateChapterNodeType(extraId, nodeTypeExtra);
          await contentService.entityRelationsService.createRelation(
            sourceType: 'character',
            sourceId: 'a',
            targetType: 'character',
            targetId: 'b',
            relationType: 'friend',
            chapterId: childId,
          );
          final beforeNodes = await db.select(db.chapters).get();
          final beforeRelations =
              (await contentService.entityRelationsService.getAllRelations())
                  .map((r) => r.toJson())
                  .toList();
          for (final path in [
            'chapters/$volumeId',
            'volumes/$childId',
            'volumes/$extraId',
          ]) {
            final result = await toolManager.executeTool(
              name: 'Remove',
              input: {'path': path, 'force': force},
            );
            if (force) {
              expect(result['removed'], isTrue);
              expect(result['missing'], isTrue);
            } else {
              expect(result['error_code'], 'not_found');
              expect(result['ok'], isFalse);
            }
            expect(
              await db.select(db.chapters).get(),
              beforeNodes,
              reason: path,
            );
            expect(
              (await contentService.entityRelationsService.getAllRelations())
                  .map((r) => r.toJson())
                  .toList(),
              beforeRelations,
              reason: path,
            );
            expect(await db.workingChangeDao.getAll(), isEmpty);
          }
        },
      );
    }

    test(
      'matching chapter, extra and volume paths preserve existing deletion behavior',
      () async {
        final volumeId = await contentService.createVolume(title: '卷');
        final childId = await contentService.createChapter(
          parentId: volumeId,
          siblingOrder: 1,
          title: '卷内章',
        );
        final chapterId = await contentService.createChapter(
          siblingOrder: 2,
          title: '独立章',
        );
        final extraId = await contentService.createChapter(
          siblingOrder: 3,
          title: '番外',
        );
        await contentService.updateChapterNodeType(extraId, nodeTypeExtra);
        for (final id in [chapterId, extraId]) {
          final result = await toolManager.executeTool(
            name: 'Remove',
            input: {'path': 'chapters/$id'},
          );
          expect(result['removed'], isTrue);
          expect(result['missing'], isNull);
          expect(await contentService.getChapterById(id), isNull);
          expect(await contentService.getChapterById(volumeId), isNotNull);
          expect(await contentService.getChapterById(childId), isNotNull);
        }
        final removedVolume = await toolManager.executeTool(
          name: 'Remove',
          input: {'path': 'volumes/$volumeId'},
        );
        expect(removedVolume['removed'], isTrue);
        expect(await db.select(db.chapters).get(), isEmpty);
        expect(await db.workingChangeDao.getAll(), isEmpty);
      },
    );

    test('removes a chapter resource path', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '待删除章节',
      );

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'chapters/$chapterId'},
      );

      expect(result['ok'], isTrue);
      expect(result['removed'], isTrue);
      expect(result['path'], 'chapters/$chapterId');
      expect(result.containsKey('_links'), isFalse);
      expect(result.containsKey('id'), isFalse);
      expect(result.containsKey('title'), isFalse);
      expect(await contentService.getChapterById(chapterId), isNull);
    });

    test('removes a relation path from graph search results', () async {
      final relationId = await contentService.entityRelationsService
          .createRelation(
            sourceType: 'character',
            sourceId: 'character_a',
            targetType: 'character',
            targetId: 'character_b',
            relationType: 'friend',
          );

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'relations/$relationId'},
      );

      expect(result['ok'], isTrue);
      expect(result['removed'], isTrue);
      expect(result['path'], 'relations/$relationId');
      expect(result.containsKey('_links'), isFalse);
      expect(result.containsKey('id'), isFalse);
      expect(result.containsKey('title'), isFalse);
      expect(
        await contentService.entityRelationsService.getAllRelations(),
        isEmpty,
      );
    });

    test('rejects collection root paths', () async {
      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'chapters'},
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
      expect(result['operation'], 'delete');
    });

    test('rejects field-level paths', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '字段路径保护',
      );

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'chapters/$chapterId/content'},
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
      expect(result['operation'], 'delete');
      expect(await contentService.getChapterById(chapterId), isNotNull);
    });

    test(
      'rejects missing standard resources instead of reporting success',
      () async {
        final result = await toolManager.executeTool(
          name: 'Remove',
          input: {'path': 'chapters/chapter_missing'},
        );

        expect(result['ok'], isFalse);
        expect(result['error_code'], 'not_found');
        expect(result['operation'], 'delete');
      },
    );

    test('force treats a missing resource as already deleted', () async {
      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'chapters/chapter_missing', 'force': true},
      );

      expect(result['removed'], isTrue);
      expect(result['missing'], isTrue);
      expect(result['ok'], isTrue);
    });

    test(
      'refuses a folder without recursive and leaves children readable',
      () async {
        final folderId = await contentService.documentsService.createFolder(
          type: documentTypeLore,
          title: '魔法系统',
        );
        await contentService.documentsService.createDocument(
          type: documentTypeLore,
          parentId: folderId,
          title: '火系魔法',
          content: '火焰规则',
        );

        final result = await toolManager.executeTool(
          name: 'Remove',
          input: {'path': 'lore/魔法系统'},
        );

        expect(result['ok'], isFalse);
        expect(result['error_code'], 'failed_precondition');
        expect(result['operation'], 'delete');

        final readFolder = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'lore/魔法系统'},
        );
        final readChild = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'lore/魔法系统/火系魔法'},
        );
        expect(readFolder['is_folder'], isTrue);
        expect(readChild['content'], '火焰规则');
      },
    );

    test('recursive deletes a folder so Read can no longer see it', () async {
      final folderId = await contentService.documentsService.createFolder(
        type: documentTypeLore,
        title: '魔法系统',
      );
      await contentService.documentsService.createDocument(
        type: documentTypeLore,
        parentId: folderId,
        title: '火系魔法',
        content: '火焰规则',
      );

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'lore/魔法系统', 'recursive': true},
      );

      expect(result['removed'], isTrue);
      expect(result.containsKey('title'), isFalse);

      final readFolder = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'lore/魔法系统'},
      );
      final readChild = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'lore/魔法系统/火系魔法'},
      );
      expect(readFolder['error_code'], 'not_found');
      expect(readChild['error_code'], 'not_found');
    });

    test('removes an ID-addressed entry from an item collection', () async {
      final entryId = await contentService.createItem(
        type: 'skill',
        title: '测试技能二',
        content: '技能说明',
      );

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'skills/$entryId'},
      );

      expect(result['ok'], isTrue);
      expect(result['removed'], isTrue);
      expect(result['path'], 'skills/$entryId');
      expect(await contentService.getItemById(entryId), isNull);
    });

    test('rejects an old title path without deleting the entry', () async {
      final entryId = await contentService.createItem(
        type: 'skill',
        title: '测试技能二',
      );

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'skills/测试技能二'},
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'not_found');
      expect(result['hint'], contains('resource ids'));
      expect(await contentService.getItemById(entryId), isNotNull);
    });

    test('Create reports a path that Remove accepts', () async {
      final created = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'skills',
          'fields': {'title': '御风术', 'content': '踏风而行'},
        },
      );
      expect(created['created'], isTrue);

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': created['path']},
      );

      expect(result['ok'], isTrue);
      expect(result['removed'], isTrue);
      expect(await contentService.getItemsByType('skill'), isEmpty);
    });

    test('force cannot skip recursive on a folder', () async {
      final folderId = await contentService.documentsService.createFolder(
        type: documentTypeLore,
        title: '魔法系统',
      );
      await contentService.documentsService.createDocument(
        type: documentTypeLore,
        parentId: folderId,
        title: '火系魔法',
        content: '火焰规则',
      );

      final result = await toolManager.executeTool(
        name: 'Remove',
        input: {'path': 'lore/魔法系统', 'force': true},
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'failed_precondition');
      expect(
        await contentService.documentsService.getDocumentById(folderId),
        isNotNull,
      );
    });
  });
}
