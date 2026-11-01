// 职责: 测试 AI 创建/写入工具在唯一标题约束前返回结构化错误
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_create.dart
//   lib/shared/services/ai/tools_write.dart
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
  group('AI tools unique title validation', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late AiToolManager toolManager;

    setUp(() async {
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

    test(
      'Create foreshadowing uses final title when empty title exists',
      () async {
        await contentService.createForeshadowing();

        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'foreshadowing',
            'fields': {'title': '遗失的钥匙', 'setup': '第一章出现'},
          },
        );

        expect(created['created'], isTrue);
        final foreshadowings = await contentService.getForeshadowings();
        expect(foreshadowings.map((entry) => entry.title), {'', '遗失的钥匙'});
      },
    );

    test(
      'Create foreshadowing rejects duplicate title before insert',
      () async {
        await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'foreshadowing',
            'fields': {'title': '遗失的钥匙', 'setup': '第一章出现'},
          },
        );

        final duplicate = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'foreshadowing',
            'fields': {'title': '遗失的钥匙', 'setup': '第二章重复'},
          },
        );

        expect(duplicate['ok'], isFalse);
        expect(duplicate['error_code'], 'already_exists');
        expect(duplicate['operation'], 'create');
        expect(await contentService.getForeshadowings(), hasLength(1));
      },
    );

    test(
      'Create-created item uses final title when empty title exists',
      () async {
        await contentService.createItem(type: 'item');

        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'items',
            'fields': {'title': '青铜罗盘', 'content': '指向旧都'},
          },
        );

        expect(created['created'], isTrue);
        final items = await contentService.getItemsByType('item');
        expect(items.map((entry) => entry.title), {'', '青铜罗盘'});
      },
    );

    test('Create-created item rejects duplicate title before insert', () async {
      await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'items',
          'fields': {'title': '青铜罗盘', 'content': '指向旧都'},
        },
      );

      final duplicate = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'items',
          'fields': {'title': '青铜罗盘', 'content': '重复物品'},
        },
      );

      expect(duplicate['ok'], isFalse);
      expect(duplicate['error_code'], 'already_exists');
      expect(duplicate['operation'], 'create');
      expect(await contentService.getItemsByType('item'), hasLength(1));
    });

    test(
      'Write-created document uses final title when empty title exists',
      () async {
        await contentService.documentsService.createDocument(type: 'lore');

        final created = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'lore/魔法系统',
            'fields': {'content': '行政结构'},
          },
        );

        expect(created['created'], isTrue);
        final documents = await contentService.documentsService
            .getDocumentsInPath(type: 'lore', namePath: const []);
        expect(documents.map((document) => document.title), {'', '魔法系统'});
      },
    );
  });
}
